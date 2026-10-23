const std = @import("std");
const builtin = @import("builtin");
const slack = @import("slack.zig");
const slack_send = @import("slack_send.zig");
const deepgram_key = @import("deepgram_key.zig");
const attachments = @import("attachments.zig");

pub const enabled = builtin.os.tag == .windows;

const win = if (enabled)
    @cImport({
        @cDefine("WIN32_LEAN_AND_MEAN", "1");
        @cDefine("NOMINMAX", "1");
        @cInclude("windows.h");
        @cInclude("winhttp.h");
        @cInclude("dpapi.h");
    })
else
    struct {};

const option_upgrade_to_web_socket = 114;
const web_socket_utf8_message: c_int = 0;
const web_socket_utf8_fragment: c_int = 1;
const web_socket_binary_message: c_int = 2;
const web_socket_binary_fragment: c_int = 3;
const web_socket_close: c_int = 4;
const web_socket_success_close_status: c_ushort = 1000;

pub const Tokens = struct {
    user: []u8,
    app: []u8,
};

pub const Bridge = struct {
    host: []u8,
    key: []u8,
};

pub const max_download_bytes: u64 = 100 * 1024 * 1024;

pub fn isUserToken(token: []const u8) bool {
    return (std.mem.startsWith(u8, token, "xoxp-") or std.mem.startsWith(u8, token, "xoxe.xoxp-")) and token.len >= 20 and token.len <= 4096;
}

pub fn isAppToken(token: []const u8) bool {
    return std.mem.startsWith(u8, token, "xapp-") and token.len >= 20 and token.len <= 512;
}

const DATA_BLOB = extern struct {
    cbData: win.DWORD,
    pbData: ?[*]u8,
};

extern "crypt32" fn CryptProtectData(data_in: *const DATA_BLOB, name: ?[*:0]const u16, entropy: ?*const DATA_BLOB, reserved: ?*anyopaque, prompt: ?*anyopaque, flags: win.DWORD, data_out: *DATA_BLOB) win.BOOL;
extern "crypt32" fn CryptUnprotectData(data_in: *const DATA_BLOB, name: ?*?[*:0]u16, entropy: ?*const DATA_BLOB, reserved: ?*anyopaque, prompt: ?*anyopaque, flags: win.DWORD, data_out: *DATA_BLOB) win.BOOL;

fn wideLiteral(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

fn protect(allocator: std.mem.Allocator, plain: []const u8) ?[]u8 {
    if (!enabled) return null;
    var in = DATA_BLOB{ .cbData = @intCast(plain.len), .pbData = @constCast(plain.ptr) };
    var out = DATA_BLOB{ .cbData = 0, .pbData = null };
    if (CryptProtectData(&in, null, null, null, null, 0, &out) == 0) return null;
    const bytes = allocator.dupe(u8, out.pbData.?[0..out.cbData]) catch null;
    _ = win.LocalFree(out.pbData);
    return bytes;
}

fn unprotect(allocator: std.mem.Allocator, blob: []const u8) ?[]u8 {
    if (!enabled) return null;
    var in = DATA_BLOB{ .cbData = @intCast(blob.len), .pbData = @constCast(blob.ptr) };
    var out = DATA_BLOB{ .cbData = 0, .pbData = null };
    if (CryptUnprotectData(&in, null, null, null, null, 0, &out) == 0) return null;
    const bytes = allocator.dupe(u8, out.pbData.?[0..out.cbData]) catch null;
    _ = win.LocalFree(out.pbData);
    return bytes;
}

fn regSetBinary(name: [*:0]const u16, blob: []const u8) bool {
    var key: win.HKEY = null;
    if (win.RegCreateKeyExW(winHandleHkey(0x80000001), wideLiteral("Software\\Messages"), 0, null, 0, win.KEY_SET_VALUE, null, &key, null) != win.ERROR_SUCCESS) return false;
    defer _ = win.RegCloseKey(key);
    return win.RegSetValueExW(key, name, 0, win.REG_BINARY, @ptrCast(@constCast(blob.ptr)), @intCast(blob.len)) == win.ERROR_SUCCESS;
}

fn regSetString(name: [*:0]const u16, text: []const u8) bool {
    const wide = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, text) catch return false;
    defer std.heap.page_allocator.free(wide);
    var key: win.HKEY = null;
    if (win.RegCreateKeyExW(winHandleHkey(0x80000001), wideLiteral("Software\\Messages"), 0, null, 0, win.KEY_SET_VALUE, null, &key, null) != win.ERROR_SUCCESS) return false;
    defer _ = win.RegCloseKey(key);
    const bytes: win.DWORD = @intCast((wide.len + 1) * 2);
    return win.RegSetValueExW(key, name, 0, win.REG_SZ, @ptrCast(@constCast(wide.ptr)), bytes) == win.ERROR_SUCCESS;
}

fn regGetBinary(allocator: std.mem.Allocator, name: [*:0]const u16) ?[]u8 {
    var size: win.DWORD = 0;
    if (win.RegGetValueW(winHandleHkey(0x80000001), wideLiteral("Software\\Messages"), name, win.RRF_RT_REG_BINARY, null, null, &size) != win.ERROR_SUCCESS or size == 0 or size > 64 * 1024) return null;
    const blob = allocator.alloc(u8, size) catch return null;
    var real_size = size;
    if (win.RegGetValueW(winHandleHkey(0x80000001), wideLiteral("Software\\Messages"), name, win.RRF_RT_REG_BINARY, null, blob.ptr, &real_size) != win.ERROR_SUCCESS) {
        allocator.free(blob);
        return null;
    }
    const shrunk = allocator.realloc(blob, real_size) catch return blob[0..real_size];
    return shrunk;
}

fn regGetString(allocator: std.mem.Allocator, name: [*:0]const u16) ?[]u8 {
    var size: win.DWORD = 0;
    if (win.RegGetValueW(winHandleHkey(0x80000001), wideLiteral("Software\\Messages"), name, win.RRF_RT_REG_SZ, null, null, &size) != win.ERROR_SUCCESS or size == 0 or size > 64 * 1024) return null;
    const wide = allocator.alloc(u16, (size + 1) / 2) catch return null;
    defer allocator.free(wide);
    var real_size = size;
    if (win.RegGetValueW(winHandleHkey(0x80000001), wideLiteral("Software\\Messages"), name, win.RRF_RT_REG_SZ, null, wide.ptr, &real_size) != win.ERROR_SUCCESS) return null;
    var text = std.unicode.utf16LeToUtf8Alloc(allocator, wide[0 .. real_size / 2]) catch return null;
    if (text.len > 0 and text[text.len - 1] == 0) {
        text = allocator.realloc(text, text.len - 1) catch text[0 .. text.len - 1];
    }
    return text;
}

pub fn loadUserEnvironment(allocator: std.mem.Allocator, name: [*:0]const u16) ?[]u8 {
    if (!enabled) return null;
    const flags = win.RRF_RT_REG_SZ | win.RRF_RT_REG_EXPAND_SZ;
    var size: win.DWORD = 0;
    if (win.RegGetValueW(winHandleHkey(0x80000001), wideLiteral("Environment"), name, flags, null, null, &size) != win.ERROR_SUCCESS or size == 0 or size > 64 * 1024 or size % 2 != 0) return null;
    const wide = allocator.alloc(u16, size / 2) catch return null;
    defer allocator.free(wide);
    var real_size = size;
    if (win.RegGetValueW(winHandleHkey(0x80000001), wideLiteral("Environment"), name, flags, null, wide.ptr, &real_size) != win.ERROR_SUCCESS or real_size > size or real_size % 2 != 0) return null;
    const value = wide[0 .. real_size / 2];
    const end = std.mem.indexOfScalar(u16, value, 0) orelse value.len;
    const text = std.unicode.utf16LeToUtf8Alloc(allocator, value[0..end]) catch return null;
    defer allocator.free(text);
    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    return allocator.dupe(u8, trimmed) catch null;
}

fn regDelete(name: [*:0]const u16) void {
    var key: win.HKEY = null;
    if (win.RegCreateKeyExW(winHandleHkey(0x80000001), wideLiteral("Software\\Messages"), 0, null, 0, win.KEY_SET_VALUE, null, &key, null) != win.ERROR_SUCCESS) return;
    defer _ = win.RegCloseKey(key);
    _ = win.RegDeleteValueW(key, name);
}

fn winHandleHkey(value: usize) win.HKEY {
    @setRuntimeSafety(false);
    return @ptrFromInt(value);
}

pub const SecretLoad = struct {
    value: []u8,
    outcome: enum { encrypted, migrated, migration_failed },
};

pub fn saveSecret(name: [*:0]const u16, value: []const u8) bool {
    if (!enabled) return false;
    const allocator = std.heap.page_allocator;
    const blob = protect(allocator, value) orelse return false;
    defer allocator.free(blob);
    return regSetBinary(name, blob);
}

pub fn loadSecret(allocator: std.mem.Allocator, name: [*:0]const u16) ?SecretLoad {
    if (!enabled) return null;
    if (regGetBinary(allocator, name)) |blob| {
        defer allocator.free(blob);
        if (unprotect(allocator, blob)) |plain| {
            if (plain.len > 0) return .{ .value = plain, .outcome = .encrypted };
            allocator.free(plain);
        }
    }
    const plain = regGetString(allocator, name) orelse return null;
    if (plain.len == 0) {
        allocator.free(plain);
        return null;
    }
    const failed = SecretLoad{ .value = plain, .outcome = .migration_failed };
    const blob = protect(allocator, plain) orelse return failed;
    defer allocator.free(blob);
    const verified = unprotect(allocator, blob) orelse return failed;
    defer allocator.free(verified);
    if (!std.mem.eql(u8, verified, plain)) return failed;
    if (!regSetBinary(name, blob)) return failed;
    return .{ .value = plain, .outcome = .migrated };
}

pub const DeepgramKey = struct {
    key: []u8,
    action: deepgram_key.Action,
    stored_outcome: ?@FieldType(SecretLoad, "outcome"),
    seed_saved: bool,
};

pub fn loadDeepgramKey(allocator: std.mem.Allocator) !DeepgramKey {
    const stored = loadSecret(allocator, wideLiteral("DeepgramApiKey"));
    defer if (stored) |previous| allocator.free(previous.value);
    const seed = loadUserEnvironment(allocator, wideLiteral("DEEPGRAM_API_KEY"));
    defer if (seed) |value| allocator.free(value);
    const decision = deepgram_key.decide(if (stored) |previous| previous.value else null, seed);
    const key = try allocator.dupe(u8, decision.key);
    const saved = switch (decision.action) {
        .save, .update => saveSecret(wideLiteral("DeepgramApiKey"), key),
        .none, .load => false,
    };
    return .{
        .key = key,
        .action = decision.action,
        .stored_outcome = if (stored) |previous| previous.outcome else null,
        .seed_saved = saved,
    };
}

pub const Installation = struct {
    team_id: []const u8,
    team_name: []const u8,
    user_id: []const u8,
    user_token: []const u8,
    refresh_token: []const u8 = "",
    expires_at: i64 = 0,
};

pub fn deleteSecret(name: [*:0]const u16) void {
    if (enabled) regDelete(name);
}

pub fn saveInstallation(installation: Installation) bool {
    if (!slack.validTeamId(installation.team_id) or !isUserToken(installation.user_token)) return false;
    const allocator = std.heap.page_allocator;
    const name = std.fmt.allocPrintSentinel(allocator, "SlackInstallation-{s}", .{installation.team_id}, 0) catch return false;
    defer allocator.free(name);
    const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, name) catch return false;
    defer allocator.free(wide);
    const json = std.json.Stringify.valueAlloc(allocator, installation, .{}) catch return false;
    defer allocator.free(json);
    return saveSecret(wide, json);
}

pub fn loadInstallation(allocator: std.mem.Allocator, team_id: []const u8) ?std.json.Parsed(Installation) {
    if (!slack.validTeamId(team_id)) return null;
    const name = std.fmt.allocPrint(allocator, "SlackInstallation-{s}", .{team_id}) catch return null;
    defer allocator.free(name);
    const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, name) catch return null;
    defer allocator.free(wide);
    const stored = loadSecret(allocator, wide) orelse return null;
    defer allocator.free(stored.value);
    const parsed = std.json.parseFromSlice(Installation, allocator, stored.value, .{ .allocate = .alloc_always }) catch return null;
    if (!std.mem.eql(u8, parsed.value.team_id, team_id) or !isUserToken(parsed.value.user_token)) {
        parsed.deinit();
        return null;
    }
    return parsed;
}

pub fn deleteInstallation(team_id: []const u8) void {
    if (!slack.validTeamId(team_id)) return;
    const allocator = std.heap.page_allocator;
    const name = std.fmt.allocPrint(allocator, "SlackInstallation-{s}", .{team_id}) catch return;
    defer allocator.free(name);
    const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, name) catch return;
    defer allocator.free(wide);
    deleteSecret(wide);
}

pub fn validClientId(value: []const u8) bool {
    if (value.len == 0 or value.len > 128) return false;
    for (value) |c| if (!std.ascii.isDigit(c) and c != '.') return false;
    return true;
}

pub fn saveClientId(value: []const u8) bool {
    return validClientId(value) and regSetString(wideLiteral("SlackClientId"), value);
}

pub fn loadClientId(allocator: std.mem.Allocator) ?[]u8 {
    return regGetString(allocator, wideLiteral("SlackClientId"));
}

pub fn saveTokens(user: []const u8, app: []const u8) bool {
    const allocator = std.heap.page_allocator;
    const user_blob = protect(allocator, user) orelse return false;
    defer allocator.free(user_blob);
    const app_blob = protect(allocator, app) orelse return false;
    defer allocator.free(app_blob);
    return regSetBinary(wideLiteral("SlackUserToken"), user_blob) and regSetBinary(wideLiteral("SlackAppToken"), app_blob);
}

pub fn clearTokens() void {
    regDelete(wideLiteral("SlackUserToken"));
    regDelete(wideLiteral("SlackAppToken"));
}

pub fn loadTokens(allocator: std.mem.Allocator) ?Tokens {
    if (!enabled) return null;
    const user_blob = regGetBinary(allocator, wideLiteral("SlackUserToken")) orelse return null;
    defer allocator.free(user_blob);
    const app_blob = regGetBinary(allocator, wideLiteral("SlackAppToken")) orelse return null;
    defer allocator.free(app_blob);
    const user = unprotect(allocator, user_blob) orelse return null;
    const app = unprotect(allocator, app_blob) orelse {
        allocator.free(user);
        return null;
    };
    if (!isUserToken(user) or !isAppToken(app)) {
        allocator.free(user);
        allocator.free(app);
        return null;
    }
    return .{ .user = user, .app = app };
}

pub fn saveBridge(host: []const u8, key: []const u8) bool {
    if (!slack.isValidBridgeHost(host) or !slack.isValidBridgeKey(key)) return false;
    const allocator = std.heap.page_allocator;
    const key_blob = protect(allocator, key) orelse return false;
    defer allocator.free(key_blob);
    return regSetString(wideLiteral("BridgeHost"), host) and regSetBinary(wideLiteral("BridgeKey"), key_blob);
}

pub fn clearBridge() void {
    regDelete(wideLiteral("BridgeHost"));
    regDelete(wideLiteral("BridgeKey"));
}

pub fn loadBridge(allocator: std.mem.Allocator) ?Bridge {
    if (!enabled) return null;
    const host = regGetString(allocator, wideLiteral("BridgeHost")) orelse return null;
    const key_blob = regGetBinary(allocator, wideLiteral("BridgeKey")) orelse {
        allocator.free(host);
        return null;
    };
    defer allocator.free(key_blob);
    const key = unprotect(allocator, key_blob) orelse {
        allocator.free(host);
        return null;
    };
    if (!slack.isValidBridgeHost(host) or !slack.isValidBridgeKey(key)) {
        allocator.free(host);
        allocator.free(key);
        return null;
    }
    return .{ .host = host, .key = key };
}

pub const Response = struct {
    status: u32 = 0,
    body: []u8 = &.{},
    headers: []u8 = &.{},

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        if (self.body.len > 0) allocator.free(self.body);
        if (self.headers.len > 0) allocator.free(self.headers);
        self.body = &.{};
        self.headers = &.{};
    }
};

fn toWide(allocator: std.mem.Allocator, text: []const u8) ![:0]u16 {
    return std.unicode.utf8ToUtf16LeAllocZ(allocator, text);
}

fn urlHost(url: []const u8) []const u8 {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return "";
    const host_start = scheme_end + 3;
    const path_start = std.mem.indexOfScalarPos(u8, url, host_start, '/') orelse url.len;
    var host = url[host_start..path_start];
    if (std.mem.indexOfScalar(u8, host, '@')) |at| host = host[at + 1 ..];
    if (std.mem.indexOfScalar(u8, host, ':')) |colon| host = host[0..colon];
    return host;
}

fn readResponse(allocator: std.mem.Allocator, request: win.HINTERNET, max_bytes: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    while (true) {
        var available: win.DWORD = 0;
        if (win.WinHttpQueryDataAvailable(request, &available) == 0) return error.NetworkFailed;
        if (available == 0) break;
        if (out.items.len + available > max_bytes) return error.ResponseTooLarge;
        const old_len = out.items.len;
        try out.resize(allocator, old_len + available);
        var read: win.DWORD = 0;
        if (win.WinHttpReadData(request, out.items.ptr + old_len, available, &read) == 0) return error.NetworkFailed;
        if (read == 0) {
            out.shrinkRetainingCapacity(old_len);
            break;
        }
        out.shrinkRetainingCapacity(old_len + read);
    }
    return out.toOwnedSlice(allocator);
}

var api_session: ?win.HINTERNET = null;
var api_connection: ?win.HINTERNET = null;
var api_host: ?[]u8 = null;
var api_lock: win.SRWLOCK = .{};

fn sharedApiHandles(host: []const u8) ?win.HINTERNET {
    win.AcquireSRWLockExclusive(&api_lock);
    defer win.ReleaseSRWLockExclusive(&api_lock);
    if (api_connection) |connection| {
        if (api_host) |cached_host| {
            if (std.mem.eql(u8, cached_host, host)) return connection;
        }
    }
    const session = api_session orelse blk: {
        const opened = win.WinHttpOpen(wideLiteral("Wazig Messages/1.0"), win.WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, null, null, 0) orelse return null;
        _ = win.WinHttpSetTimeouts(opened, 10_000, 10_000, 30_000, 60_000);
        api_session = opened;
        break :blk opened;
    };
    const wide_host = toWide(std.heap.page_allocator, host) catch return null;
    defer std.heap.page_allocator.free(wide_host);
    const owned_host = std.heap.page_allocator.dupe(u8, host) catch return null;
    const connection = win.WinHttpConnect(session, wide_host.ptr, win.INTERNET_DEFAULT_HTTPS_PORT, 0) orelse {
        std.heap.page_allocator.free(owned_host);
        return null;
    };
    if (api_host) |old_host| std.heap.page_allocator.free(old_host);
    api_connection = connection;
    api_host = owned_host;
    return connection;
}

pub threadlocal var last_status: u32 = 0;
pub threadlocal var last_error: [64]u8 = [_]u8{0} ** 64;

pub fn callApi(allocator: std.mem.Allocator, host: []const u8, token: []const u8, method: []const u8, path_query: []const u8, body: ?[]const u8) !Response {
    last_status = 0;
    last_error = [_]u8{0} ** 64;
    if (!enabled) return error.Unsupported;
    const wide_path = try toWide(allocator, path_query);
    defer allocator.free(wide_path);
    const wide_method = try toWide(allocator, if (std.mem.eql(u8, method, "GET")) "GET" else "POST");
    defer allocator.free(wide_method);

    const connection = sharedApiHandles(host) orelse return error.NetworkFailed;
    const request = win.WinHttpOpenRequest(connection, wide_method.ptr, wide_path.ptr, null, null, null, win.WINHTTP_FLAG_SECURE) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(request);

    var headers = std.ArrayList(u16).empty;
    defer headers.deinit(allocator);
    try headers.appendSlice(allocator, std.unicode.utf8ToUtf16LeStringLiteral("Authorization: Bearer "));
    for (token) |char| try headers.append(allocator, char);
    try headers.appendSlice(allocator, std.unicode.utf8ToUtf16LeStringLiteral("\r\nContent-Type: application/json; charset=utf-8\r\n"));
    try headers.append(allocator, 0);
    if (body) |payload| {
        if (win.WinHttpSendRequest(request, headers.items.ptr, @intCast(headers.items.len - 1), @constCast(payload.ptr), @intCast(payload.len), @intCast(payload.len), 0) == 0) return error.NetworkFailed;
    } else {
        if (win.WinHttpSendRequest(request, headers.items.ptr, @intCast(headers.items.len - 1), null, 0, 0, 0) == 0) return error.NetworkFailed;
    }
    if (win.WinHttpReceiveResponse(request, null) == 0) return error.NetworkFailed;
    var status: win.DWORD = 0;
    var status_size: win.DWORD = @sizeOf(win.DWORD);
    _ = win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_STATUS_CODE | win.WINHTTP_QUERY_FLAG_NUMBER, null, &status, &status_size, null);
    last_status = status;
    const data = try readResponse(allocator, request, 32 * 1024 * 1024);
    var header_size: win.DWORD = 0;
    _ = win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_RAW_HEADERS_CRLF, null, null, &header_size, 0);
    var raw_headers: []u8 = &.{};
    if (header_size > 0) {
        const wide_headers = allocator.alloc(u16, header_size) catch null;
        if (wide_headers) |wh| {
            var real = header_size;
            if (win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_RAW_HEADERS_CRLF, null, wh.ptr, &real, 0) != 0) {
                if (std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.span(@as([*:0]const u16, @ptrCast(wh))))) |narrow| {
                    raw_headers = narrow;
                } else |_| {}
            }
            allocator.free(wh);
        }
    }
    return .{ .status = status, .body = data, .headers = raw_headers };
}

pub fn exchangeOAuth(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    return exchangeOAuthAt(allocator, "slack.com", win.INTERNET_DEFAULT_HTTPS_PORT, true, body);
}

pub fn exchangeOAuthAt(allocator: std.mem.Allocator, host: []const u8, port: u16, secure: bool, body: []const u8) ![]u8 {
    if (!enabled) return error.Unsupported;
    const wide_host = try toWide(allocator, host);
    defer allocator.free(wide_host);
    const session = win.WinHttpOpen(wideLiteral("Wazig Messages/1.0"), if (secure) win.WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY else win.WINHTTP_ACCESS_TYPE_NO_PROXY, null, null, 0) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(session);
    _ = win.WinHttpSetTimeouts(session, 10_000, 10_000, 15_000, 15_000);
    const connection = win.WinHttpConnect(session, wide_host, port, 0) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(connection);
    const request = win.WinHttpOpenRequest(connection, wideLiteral("POST"), wideLiteral("/api/oauth.v2.access"), null, null, null, if (secure) win.WINHTTP_FLAG_SECURE else 0) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(request);
    var redirect_policy: win.DWORD = win.WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    if (win.WinHttpSetOption(request, win.WINHTTP_OPTION_REDIRECT_POLICY, &redirect_policy, @sizeOf(win.DWORD)) == 0) return error.NetworkFailed;
    const headers = std.unicode.utf8ToUtf16LeStringLiteral("Content-Type: application/x-www-form-urlencoded\r\n");
    if (win.WinHttpSendRequest(request, headers, @intCast(headers.len), @constCast(body.ptr), @intCast(body.len), @intCast(body.len), 0) == 0 or win.WinHttpReceiveResponse(request, null) == 0) return error.NetworkFailed;
    var status: win.DWORD = 0;
    var size: win.DWORD = @sizeOf(win.DWORD);
    if (win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_STATUS_CODE | win.WINHTTP_QUERY_FLAG_NUMBER, null, &status, &size, null) == 0 or status != 200) return error.OAuthHttpFailed;
    return readResponse(allocator, request, 64 * 1024);
}

pub fn putFile(allocator: std.mem.Allocator, url: []const u8, bytes: []const u8) !void {
    last_status = 0;
    last_error = [_]u8{0} ** 64;
    if (!enabled) return error.Unsupported;
    if (!std.mem.startsWith(u8, url, "https://")) return error.UntrustedUrl;
    const scheme_end = std.mem.indexOf(u8, url, "://").?;
    const host_start = scheme_end + 3;
    const path_start = std.mem.indexOfScalarPos(u8, url, host_start, '/') orelse return error.UntrustedUrl;
    const wide_host = try toWide(allocator, url[host_start..path_start]);
    defer allocator.free(wide_host);
    const wide_path = try toWide(allocator, url[path_start..]);
    defer allocator.free(wide_path);

    const session = win.WinHttpOpen(wideLiteral("Wazig Messages/1.0"), win.WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, null, null, 0) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(session);
    _ = win.WinHttpSetTimeouts(session, 10_000, 10_000, 60_000, 300_000);
    const connection = win.WinHttpConnect(session, wide_host.ptr, win.INTERNET_DEFAULT_HTTPS_PORT, 0) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(connection);
    const request = win.WinHttpOpenRequest(connection, wideLiteral("PUT"), wide_path.ptr, null, null, null, win.WINHTTP_FLAG_SECURE) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(request);
    const content_type = std.unicode.utf8ToUtf16LeStringLiteral("Content-Type: application/octet-stream\r\n");
    if (win.WinHttpSendRequest(request, content_type.ptr, @intCast(content_type.len), @constCast(bytes.ptr), @intCast(bytes.len), @intCast(bytes.len), 0) == 0) return error.NetworkFailed;
    if (win.WinHttpReceiveResponse(request, null) == 0) return error.NetworkFailed;
    var status: win.DWORD = 0;
    var status_size: win.DWORD = @sizeOf(win.DWORD);
    _ = win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_STATUS_CODE | win.WINHTTP_QUERY_FLAG_NUMBER, null, &status, &status_size, null);
    last_status = status;
    if (status < 200 or status >= 300) return error.UploadRejected;
}

pub fn markDownloaded(allocator: std.mem.Allocator, path: []const u8) void {
    if (!enabled) return;
    const wide = toWide(allocator, path) catch return;
    defer allocator.free(wide);
    const stream = attachments.zoneStreamName(allocator, wide) catch return;
    defer allocator.free(stream);
    const file = win.CreateFileW(stream.ptr, win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    if (file == win.INVALID_HANDLE_VALUE or file == null) return;
    defer _ = win.CloseHandle(file);
    var written: win.DWORD = 0;
    _ = win.WriteFile(file, attachments.zone_stream_body.ptr, @intCast(attachments.zone_stream_body.len), &written, null);
}

pub fn downloadTo(allocator: std.mem.Allocator, token: []const u8, url: []const u8, dest_path: []const u8, bridge_host: ?[]const u8) !void {
    if (!enabled) return error.Unsupported;
    if (!std.mem.startsWith(u8, url, "https://")) return error.UntrustedUrl;
    const host = urlHost(url);
    var connect_host: []const u8 = host;
    var connect_path: []const u8 = url;
    var owned_path: ?[]u8 = null;
    defer if (owned_path) |p| allocator.free(p);
    if (bridge_host) |bh| {
        if (!slack.isSlackFileHost(host)) return error.UntrustedUrl;
        const rewritten = try slack.bridgeFilePath(allocator, url);
        owned_path = rewritten;
        connect_host = bh;
        connect_path = rewritten;
    } else {
        if (!slack.isSlackFileHost(host)) return error.UntrustedUrl;
        const scheme_end = std.mem.indexOf(u8, url, "://").?;
        const host_start = scheme_end + 3;
        const path_start = std.mem.indexOfScalarPos(u8, url, host_start, '/') orelse return error.UntrustedUrl;
        connect_host = url[host_start..path_start];
        connect_path = url[path_start..];
    }
    const wide_host = try toWide(allocator, connect_host);
    defer allocator.free(wide_host);
    const wide_path = try toWide(allocator, connect_path);
    defer allocator.free(wide_path);
    const wide_dest = try toWide(allocator, dest_path);
    defer allocator.free(wide_dest);

    const session = win.WinHttpOpen(wideLiteral("Wazig Messages/1.0"), win.WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, null, null, 0) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(session);
    _ = win.WinHttpSetTimeouts(session, 10_000, 10_000, 30_000, 600_000);
    const connection = win.WinHttpConnect(session, wide_host.ptr, win.INTERNET_DEFAULT_HTTPS_PORT, 0) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(connection);
    const request = win.WinHttpOpenRequest(connection, wideLiteral("GET"), wide_path.ptr, null, null, null, win.WINHTTP_FLAG_SECURE) orelse return error.NetworkFailed;
    defer _ = win.WinHttpCloseHandle(request);
    var headers = std.ArrayList(u16).empty;
    defer headers.deinit(allocator);
    try headers.appendSlice(allocator, std.unicode.utf8ToUtf16LeStringLiteral("Authorization: Bearer "));
    for (token) |char| try headers.append(allocator, char);
    try headers.appendSlice(allocator, std.unicode.utf8ToUtf16LeStringLiteral("\r\n"));
    try headers.append(allocator, 0);
    if (win.WinHttpSendRequest(request, headers.items.ptr, @intCast(headers.items.len - 1), null, 0, 0, 0) == 0) return error.NetworkFailed;
    if (win.WinHttpReceiveResponse(request, null) == 0) return error.NetworkFailed;
    var status: win.DWORD = 0;
    var status_size: win.DWORD = @sizeOf(win.DWORD);
    _ = win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_STATUS_CODE | win.WINHTTP_QUERY_FLAG_NUMBER, null, &status, &status_size, null);
    if (status != 200) return error.DownloadRejected;

    const file = win.CreateFileW(wide_dest.ptr, win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    if (file == win.INVALID_HANDLE_VALUE or file == null) return error.WriteFailed;
    defer {
        _ = win.CloseHandle(file);
        markDownloaded(allocator, dest_path);
    }
    var total: u64 = 0;
    var buffer: [256 * 1024]u8 = undefined;
    while (true) {
        var read: win.DWORD = 0;
        if (win.WinHttpReadData(request, &buffer, buffer.len, &read) == 0) return error.NetworkFailed;
        if (read == 0) break;
        total += read;
        if (total > max_download_bytes) return error.TooLarge;
        var written: win.DWORD = 0;
        if (win.WriteFile(file, &buffer, read, &written, null) == 0) return error.WriteFailed;
    }
}

pub const Socket = struct {
    session: win.HINTERNET,
    connection: win.HINTERNET,
    request: win.HINTERNET,
    socket: win.HINTERNET,
};

pub fn socketConnect(allocator: std.mem.Allocator, endpoint: slack.WsEndpoint) !Socket {
    if (!enabled) return error.Unsupported;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const wide_host = try toWide(arena.allocator(), endpoint.host);
    const wide_path = try toWide(arena.allocator(), endpoint.path_query);

    const session = win.WinHttpOpen(wideLiteral("Wazig Messages/1.0"), win.WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, null, null, 0) orelse return error.NetworkFailed;
    errdefer _ = win.WinHttpCloseHandle(session);
    _ = win.WinHttpSetTimeouts(session, 10_000, 10_000, 30_000, 15_000);
    const connection = win.WinHttpConnect(session, wide_host.ptr, win.INTERNET_DEFAULT_HTTPS_PORT, 0) orelse return error.NetworkFailed;
    errdefer _ = win.WinHttpCloseHandle(connection);
    const request = win.WinHttpOpenRequest(connection, wideLiteral("GET"), wide_path.ptr, null, null, null, win.WINHTTP_FLAG_SECURE) orelse return error.NetworkFailed;
    errdefer _ = win.WinHttpCloseHandle(request);
    var upgrade: win.BOOL = 1;
    if (win.WinHttpSetOption(request, option_upgrade_to_web_socket, &upgrade, @sizeOf(win.BOOL)) == 0) return error.WebSocketUnsupported;
    if (win.WinHttpSendRequest(request, null, 0, null, 0, 0, 0) == 0) return error.NetworkFailed;
    if (win.WinHttpReceiveResponse(request, null) == 0) return error.NetworkFailed;
    var status: win.DWORD = 0;
    var status_size: win.DWORD = @sizeOf(win.DWORD);
    _ = win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_STATUS_CODE | win.WINHTTP_QUERY_FLAG_NUMBER, null, &status, &status_size, null);
    if (status != 101 and status != 200) return error.WebSocketRejected;
    const socket = win.WinHttpWebSocketCompleteUpgrade(request, 0) orelse return error.NetworkFailed;
    var receive_timeout: win.DWORD = 1000;
    _ = win.WinHttpSetOption(socket, win.WINHTTP_OPTION_RECEIVE_TIMEOUT, &receive_timeout, @sizeOf(win.DWORD));
    return .{ .session = session, .connection = connection, .request = request, .socket = socket };
}

pub fn socketClose(sock: Socket) void {
    if (enabled) {
        _ = win.WinHttpWebSocketClose(sock.socket, web_socket_success_close_status, null, 0);
        _ = win.WinHttpCloseHandle(sock.socket);
        _ = win.WinHttpCloseHandle(sock.request);
        _ = win.WinHttpCloseHandle(sock.connection);
        _ = win.WinHttpCloseHandle(sock.session);
    }
}

pub fn socketSend(allocator: std.mem.Allocator, sock: Socket, bytes: []const u8) !void {
    if (!enabled) return error.Unsupported;
    const wide_free = false;
    _ = allocator;
    _ = wide_free;
    if (win.WinHttpWebSocketSend(sock.socket, web_socket_utf8_message, @constCast(bytes.ptr), @intCast(bytes.len)) != 0) return error.NetworkFailed;
}

pub fn socketReceive(sock: Socket, buf: []u8, stop: *std.atomic.Value(bool)) ![]u8 {
    if (!enabled) return error.Unsupported;
    var offset: usize = 0;
    while (true) {
        if (offset >= buf.len) return error.TooLarge;
        var kind: c_int = 0;
        var read: win.DWORD = 0;
        if (stop.load(.acquire)) return error.Closed;
        const status = win.WinHttpWebSocketReceive(sock.socket, buf.ptr + offset, @intCast(buf.len - offset), &read, @ptrCast(&kind));
        if (status == win.ERROR_WINHTTP_TIMEOUT) continue;
        if (status != 0) return error.NetworkFailed;
        offset += read;
        if (kind == web_socket_close) return error.Closed;
        if (kind == web_socket_utf8_message or kind == web_socket_binary_message) return buf[0..offset];
        if (kind != web_socket_utf8_fragment and kind != web_socket_binary_fragment) return error.Closed;
    }
}

pub const Event = struct {
    team_id: [32]u8 = undefined,
    team_id_len: u8 = 0,
    event_type: [32]u8 = undefined,
    event_type_len: u8 = 0,
    reaction: [96]u8 = undefined,
    reaction_len: u8 = 0,
    channel: [slack.max_channel_id + 1]u8 = undefined,
    channel_len: u8 = 0,
    ts: [40]u8 = undefined,
    ts_len: u8 = 0,
    thread_ts: [40]u8 = undefined,
    thread_ts_len: u8 = 0,
    user: [slack.max_user_id + 1]u8 = undefined,
    user_len: u8 = 0,
    client_msg_id: [63]u8 = undefined,
    client_msg_id_len: u8 = 0,
    text: [slack.max_text + 1]u8 = undefined,
    text_len: u16 = 0,
    file_id: [32]u8 = undefined,
    file_id_len: u8 = 0,
    file_url: [512]u8 = undefined,
    file_url_len: u16 = 0,
    file_name: [259]u8 = undefined,
    file_name_len: u16 = 0,
    file_mime: [95]u8 = undefined,
    file_mime_len: u8 = 0,
    file_size: i64 = 0,

    pub fn teamIdSlice(self: *const Event) []const u8 {
        return self.team_id[0..self.team_id_len];
    }
    pub fn eventTypeSlice(self: *const Event) []const u8 {
        return self.event_type[0..self.event_type_len];
    }
    pub fn channelSlice(self: *const Event) []const u8 {
        return self.channel[0..self.channel_len];
    }
    pub fn tsSlice(self: *const Event) []const u8 {
        return self.ts[0..self.ts_len];
    }
    pub fn threadTsSlice(self: *const Event) []const u8 {
        return self.thread_ts[0..self.thread_ts_len];
    }
    pub fn userSlice(self: *const Event) []const u8 {
        return self.user[0..self.user_len];
    }
    pub fn clientMsgIdSlice(self: *const Event) []const u8 {
        return self.client_msg_id[0..self.client_msg_id_len];
    }
    pub fn textSlice(self: *const Event) []const u8 {
        return self.text[0..self.text_len];
    }
    pub fn fileIdSlice(self: *const Event) []const u8 {
        return self.file_id[0..self.file_id_len];
    }
    pub fn fileUrlSlice(self: *const Event) []const u8 {
        return self.file_url[0..self.file_url_len];
    }
    pub fn fileNameSlice(self: *const Event) []const u8 {
        return self.file_name[0..self.file_name_len];
    }
    pub fn fileMimeSlice(self: *const Event) []const u8 {
        return self.file_mime[0..self.file_mime_len];
    }
};

fn copyInto(dest: anytype, dest_len: anytype, source: []const u8) void {
    if (@TypeOf(dest_len.*) == u8) {
        const taken = @min(source.len, dest.len);
        @memcpy(dest[0..taken], source[0..taken]);
        dest_len.* = @intCast(taken);
        return;
    }
    const taken = @min(source.len, dest.len);
    @memcpy(dest[0..taken], source[0..taken]);
    dest_len.* = @intCast(taken);
}

pub const EventSink = struct {
    hwnd: *anyopaque,
    message_id: u32,
    queue: *std.atomic.Value(usize),
};

pub fn buildEvent(envelope: slack.Envelope) ?*Event {
    if (envelope.channel.len == 0 or envelope.ts.len == 0) return null;
    if (envelope.ts.len != envelope.thread_ts.len or !std.mem.eql(u8, envelope.ts, envelope.thread_ts)) {}
    const event = std.heap.page_allocator.create(Event) catch return null;
    event.* = .{};
    copyInto(&event.team_id, &event.team_id_len, envelope.team_id);
    copyInto(&event.event_type, &event.event_type_len, envelope.event_type);
    copyInto(&event.reaction, &event.reaction_len, envelope.reaction);
    copyInto(&event.channel, &event.channel_len, envelope.channel);
    copyInto(&event.ts, &event.ts_len, envelope.ts);
    copyInto(&event.thread_ts, &event.thread_ts_len, envelope.thread_ts);
    copyInto(&event.user, &event.user_len, envelope.user);
    copyInto(&event.client_msg_id, &event.client_msg_id_len, envelope.client_msg_id);
    copyInto(&event.text, &event.text_len, envelope.text);
    copyInto(&event.file_id, &event.file_id_len, envelope.file_id);
    copyInto(&event.file_url, &event.file_url_len, envelope.file_url);
    copyInto(&event.file_name, &event.file_name_len, envelope.file_name);
    copyInto(&event.file_mime, &event.file_mime_len, envelope.file_mime);
    event.file_size = envelope.file_size;
    return event;
}

pub fn destroyEvent(event: *Event) void {
    std.heap.page_allocator.destroy(event);
}

pub const SocketConfig = struct {
    user_token: []const u8,
    app_token: []const u8,
    stop: *std.atomic.Value(bool),
    sink: EventSink,
    connected: *std.atomic.Value(bool),
};

pub fn socketThreadMain(config: SocketConfig) void {
    var backoff_seconds: u64 = 1;
    while (!config.stop.load(.acquire)) {
        var connected_here = false;
        runOneSession(config, &connected_here) catch {};
        _ = config.connected.swap(false, .acq_rel);
        if (config.stop.load(.acquire)) return;
        const delay = if (connected_here) 1000 else backoff_seconds * 1000;
        var waited: u64 = 0;
        while (waited < delay and !config.stop.load(.acquire)) : (waited += 250) win.Sleep(250);
        backoff_seconds = @min(if (connected_here) @as(u64, 1) else backoff_seconds * 2, 30);
    }
}

fn runOneSession(config: SocketConfig, connected_here: *bool) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const response = try callApi(arena, "slack.com", config.app_token, "POST", "/api/apps.connections.open", null);
    if (response.status != 200) return error.HttpFailed;
    const endpoint = slack.parseWsUrl(arena, response.body) orelse return error.BadHandshake;
    const sock = try socketConnect(arena, endpoint);
    defer socketClose(sock);
    connected_here.* = true;
    _ = config.connected.swap(true, .acq_rel);

    var buffer: [128 * 1024]u8 = undefined;
    while (!config.stop.load(.acquire)) {
        const message = socketReceive(sock, &buffer, config.stop) catch |err| return err;
        var classify_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer classify_arena.deinit();
        const envelope = (slack.classifyEnvelope(classify_arena.allocator(), message) catch return error.BadEnvelope) orelse continue;
        if (envelope.envelope_id.len > 0) {
            const ack = slack.buildAckBody(classify_arena.allocator(), envelope.envelope_id) catch return error.OutOfMemory;
            socketSend(classify_arena.allocator(), sock, ack) catch return error.NetworkFailed;
        }
        if (envelope.kind != .events) continue;
        if (!std.mem.eql(u8, envelope.event_type, "message") and !std.mem.eql(u8, envelope.event_type, "reaction_added") and !std.mem.eql(u8, envelope.event_type, "reaction_removed")) continue;
        for (envelope.teams[0..envelope.team_count]) |team| {
            var routed = envelope;
            routed.team_id = team;
            const event = buildEvent(routed) orelse continue;
            _ = config.sink.queue.fetchAdd(1, .acq_rel);
            const hwnd: win.HWND = @ptrFromInt(@intFromPtr(config.sink.hwnd));
            if (win.PostMessageW(hwnd, config.sink.message_id, 0, @bitCast(@intFromPtr(event))) == 0) {
                _ = config.sink.queue.fetchSub(1, .acq_rel);
                destroyEvent(event);
            }
        }
    }
}

pub const JobKind = enum(u8) {
    workspace,
    users,
    history,
    replies,
    send_text,
    upload_image,
    share_image,
    download,
    auth,
    mark,
};

pub const JobContext = struct {
    user_token: []const u8,
    host: []const u8,
    is_bridge: bool,
    media_dir: []const u8,
    io: std.Io,
};

fn ensureMediaDir(dir: []const u8) !void {
    const wide = try toWide(std.heap.page_allocator, dir);
    defer std.heap.page_allocator.free(wide);
    _ = win.CreateDirectoryW(wide.ptr, null);
}

fn httpOk(allocator: std.mem.Allocator, body: []const u8) bool {
    return slack.responseIsOk(allocator, body);
}

fn workspaceReadState(allocator: std.mem.Allocator, ctx: JobContext, page: []const u8) ![]u8 {
    if (ctx.is_bridge) return allocator.dupe(u8, page);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, page, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const root = &parsed.value.object;
    if (root.getPtr("channels")) |channels| {
        if (channels.* == .array) for (channels.array.items) |*channel| {
            if (channel.* != .object) continue;
            if (slack.workspaceChannel(channel.object) == null) continue;
            const id = slack.objectStringField(channel.object, "id");
            if (id.len == 0) continue;
            const path = try std.fmt.allocPrint(allocator, "/api/conversations.info?channel={s}", .{id});
            defer allocator.free(path);
            var response = try callWithRetry(allocator, ctx.host, ctx.user_token, path, null);
            defer response.deinit(allocator);
            if (response.status != 200 or !httpOk(allocator, response.body)) return error.SlackReadStateFailed;
            const info = try std.json.parseFromSliceLeaky(std.json.Value, parsed.arena.allocator(), response.body, .{ .allocate = .alloc_always });
            if (info != .object) return error.BadResponse;
            const details = info.object.get("channel") orelse return error.BadResponse;
            if (details != .object) return error.BadResponse;
            for ([_][]const u8{ "last_read", "unread_count", "unread_count_display", "latest" }) |field| {
                if (details.object.get(field)) |value| try channel.object.put(parsed.arena.allocator(), field, value);
            }
        };
    }
    return std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
}

pub fn runJob(allocator: std.mem.Allocator, ctx: JobContext, kind: JobKind, args: []const []const u8) ![]u8 {
    switch (kind) {
        .workspace => {
            var path = std.ArrayList(u8).empty;
            defer path.deinit(allocator);
            try path.appendSlice(allocator, "/api/conversations.list?limit=200&types=");
            try path.appendSlice(allocator, if (args.len > 0) args[0] else "public_channel,private_channel,im");
            if (args.len > 1 and args[1].len > 0) {
                const encoded = try slack.percentEncode(allocator, args[1]);
                defer allocator.free(encoded);
                try path.appendSlice(allocator, "&cursor=");
                try path.appendSlice(allocator, encoded);
            }
            const page = try listPage(allocator, try callWithRetry(allocator, ctx.host, ctx.user_token, path.items, null));
            defer allocator.free(page);
            return workspaceReadState(allocator, ctx, page);
        },
        .users => {
            var path = std.ArrayList(u8).empty;
            defer path.deinit(allocator);
            try path.appendSlice(allocator, "/api/users.list?limit=200");
            if (args.len > 0 and args[0].len > 0) {
                const encoded = try slack.percentEncode(allocator, args[0]);
                defer allocator.free(encoded);
                try path.appendSlice(allocator, "&cursor=");
                try path.appendSlice(allocator, encoded);
            }
            return listPage(allocator, try callWithRetry(allocator, ctx.host, ctx.user_token, path.items, null));
        },
        .history => {
            var path = std.ArrayList(u8).empty;
            defer path.deinit(allocator);
            try path.appendSlice(allocator, "/api/conversations.history?limit=80&channel=");
            try path.appendSlice(allocator, if (args.len > 0) args[0] else "");
            return bodyOnly(allocator, try callWithRetry(allocator, ctx.host, ctx.user_token, path.items, null));
        },
        .replies => {
            var path = std.ArrayList(u8).empty;
            defer path.deinit(allocator);
            try path.appendSlice(allocator, "/api/conversations.replies?limit=100&channel=");
            try path.appendSlice(allocator, if (args.len > 0) args[0] else "");
            if (args.len > 1) {
                try path.appendSlice(allocator, "&ts=");
                try path.appendSlice(allocator, args[1]);
            }
            return bodyOnly(allocator, try callWithRetry(allocator, ctx.host, ctx.user_token, path.items, null));
        },
        .send_text => {
            if (args.len < 3) return error.BadArguments;
            const body = try slack.buildPostMessageBody(allocator, .{ .channel_id = args[0], .text = args[1], .thread_ts = args[2], .client_msg_id = if (args.len > 3) args[3] else "" });
            defer allocator.free(body);
            var response = try callWithRetry(allocator, ctx.host, ctx.user_token, "/api/chat.postMessage", body);
            errdefer response.deinit(allocator);
            if (response.status == 200 and !httpOk(allocator, response.body)) return error.SlackRejected;
            if (response.status != 200) return error.HttpFailed;
            return bodyOnly(allocator, response);
        },
        .upload_image => {
            if (ctx.is_bridge) return error.UploadNotSupported;
            if (args.len < 4) return error.BadArguments;
            return uploadImage(allocator, ctx, args[2]);
        },
        .share_image => {
            if (ctx.is_bridge) return error.UploadNotSupported;
            if (args.len < 4) return error.BadArguments;
            return shareImage(allocator, ctx, args[0], args[1], args[2], args[3]);
        },
        .auth => {
            var response = try callWithRetry(allocator, ctx.host, ctx.user_token, "/api/auth.test", null);
            errdefer response.deinit(allocator);
            if (response.status != 200) return error.HttpFailed;
            if (!httpOk(allocator, response.body)) return error.SlackRejected;
            return bodyOnly(allocator, response);
        },
        .mark => {
            if (args.len < 2) return error.BadArguments;
            const body = try slack.buildMarkBody(allocator, args[0], args[1]);
            defer allocator.free(body);
            var response = try callWithRetry(allocator, ctx.host, ctx.user_token, "/api/conversations.mark", body);
            errdefer response.deinit(allocator);
            if (response.status != 200) return error.HttpFailed;
            if (!httpOk(allocator, response.body)) return error.SlackRejected;
            return bodyOnly(allocator, response);
        },
        .download => {
            if (args.len < 5) return error.BadArguments;
            const dest = try slack.downloadPath(allocator, ctx.media_dir, args[1], args[2], args[3], args[4]);
            defer allocator.free(dest);
            try ensureMediaDir(ctx.media_dir);
            try downloadTo(allocator, ctx.user_token, args[0], dest, if (ctx.is_bridge) ctx.host else null);
            return allocator.dupe(u8, dest);
        },
    }
}

fn listPage(allocator: std.mem.Allocator, response: Response) ![]u8 {
    var owned = response;
    errdefer owned.deinit(allocator);
    if (owned.status != 200) return error.HttpFailed;
    if (!httpOk(allocator, owned.body)) return error.SlackRejected;
    return bodyOnly(allocator, owned);
}

fn bodyOnly(allocator: std.mem.Allocator, response: Response) []u8 {
    if (response.headers.len > 0) allocator.free(response.headers);
    return response.body;
}

fn callWithRetry(allocator: std.mem.Allocator, host: []const u8, token: []const u8, path: []const u8, body: ?[]const u8) !Response {
    var response = try callApi(allocator, host, token, if (body == null) "GET" else "POST", path, body);
    if (response.status == 429) {
        const wait_seconds = slack.parseRetryAfter(response.headers) orelse 5;
        response.deinit(allocator);
        win.Sleep(@intCast(@as(u64, @min(wait_seconds, 30)) * 1000));
        response = try callApi(allocator, host, token, if (body == null) "GET" else "POST", path, body);
    }
    var parsed = std.json.parseFromSlice(struct { @"error": []const u8 = "" }, allocator, response.body, .{ .ignore_unknown_fields = true }) catch return response;
    defer parsed.deinit();
    const len = @min(parsed.value.@"error".len, last_error.len - 1);
    @memcpy(last_error[0..len], parsed.value.@"error"[0..len]);
    return response;
}

fn uploadImage(allocator: std.mem.Allocator, ctx: JobContext, file_path: []const u8) ![]u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(ctx.io, file_path, allocator, .limited(max_download_bytes)) catch return error.ReadFailed;
    defer allocator.free(bytes);
    const base = std.fs.path.basename(file_path);
    var name_buffer: [128]u8 = undefined;
    const safe_name = slack.sanitizeFilename(&name_buffer, base);
    const safe = if (safe_name.len > 0) safe_name else "image";

    var start_path = std.ArrayList(u8).empty;
    defer start_path.deinit(allocator);
    try start_path.appendSlice(allocator, "/api/files.getUploadURLExternal");
    var start_body = std.ArrayList(u8).empty;
    defer start_body.deinit(allocator);
    const escaped_name = try slack.escapeJson(allocator, safe);
    defer allocator.free(escaped_name);
    const body = try std.fmt.allocPrint(allocator, "{{\"filename\":\"{s}\",\"length\":{d}}}", .{ escaped_name, bytes.len });
    defer allocator.free(body);
    var grant_response = try callWithRetry(allocator, ctx.host, ctx.user_token, start_path.items, body);
    defer grant_response.deinit(allocator);
    if (grant_response.status != 200) return error.HttpFailed;
    const grant = slack.parseUploadGrant(allocator, grant_response.body) orelse return error.SlackRejected;
    defer allocator.free(grant.upload_url);
    defer allocator.free(grant.file_id);

    try putFile(allocator, grant.upload_url, bytes);
    if (grant.file_id.len == 0 or grant.file_id.len > 63 or std.mem.indexOfScalar(u8, grant.file_id, 0) != null) return error.HttpFailed;
    return allocator.dupe(u8, grant.file_id);
}

test "singleton credentials migrate through auth identity into isolated DPAPI workspace records" {
    if (!enabled) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const user_token = "xoxp-00000000000000000001";
    const app_token = "xapp-00000000000000000001";
    try std.testing.expect(saveTokens(user_token, app_token));
    defer clearTokens();
    const singleton = loadTokens(allocator).?;
    defer allocator.free(singleton.user);
    defer allocator.free(singleton.app);
    const auth = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"ok":true,"team_id":"T0000000001","team":"Example workspace","user_id":"U0000000001"}
    , .{});
    defer auth.deinit();
    const identity = slack.installationIdentity(auth.value.object).?;
    const installation = Installation{ .team_id = identity.team_id, .team_name = identity.team_name, .user_id = identity.user_id, .user_token = singleton.user, .refresh_token = "example-refresh-token", .expires_at = 1740000000 };
    try std.testing.expect(saveInstallation(installation));
    defer deleteInstallation(identity.team_id);
    const saved = loadInstallation(allocator, identity.team_id).?;
    defer saved.deinit();
    try std.testing.expectEqualStrings(user_token, saved.value.user_token);
    try std.testing.expectEqualStrings("example-refresh-token", saved.value.refresh_token);
    try std.testing.expectEqual(@as(i64, 1740000000), saved.value.expires_at);
    deleteSecret(wideLiteral("SlackUserToken"));
    try std.testing.expect(loadTokens(allocator) == null);
    const shared_app = loadSecret(allocator, wideLiteral("SlackAppToken")).?;
    defer allocator.free(shared_app.value);
    try std.testing.expectEqualStrings(app_token, shared_app.value);
    try std.testing.expect(saveInstallation(.{ .team_id = "T0000000002", .team_name = "Second workspace", .user_id = "U0000000002", .user_token = "xoxp-00000000000000000002" }));
    defer deleteInstallation("T0000000002");
    const second = loadInstallation(allocator, "T0000000002").?;
    defer second.deinit();
    try std.testing.expectEqualStrings("xoxp-00000000000000000002", second.value.user_token);
    const first = loadInstallation(allocator, identity.team_id).?;
    defer first.deinit();
    try std.testing.expectEqualStrings(user_token, first.value.user_token);
}

pub const HttpCancel = struct {
    lock: win.SRWLOCK = .{},
    request: win.HINTERNET = null,
    stopped: bool = false,

    pub fn stop(self: *HttpCancel) void {
        win.AcquireSRWLockExclusive(&self.lock);
        defer win.ReleaseSRWLockExclusive(&self.lock);
        self.stopped = true;
        if (self.request) |request| _ = win.WinHttpCloseHandle(request);
        self.request = null;
    }

    fn attach(self: *HttpCancel, request: win.HINTERNET) bool {
        win.AcquireSRWLockExclusive(&self.lock);
        defer win.ReleaseSRWLockExclusive(&self.lock);
        if (self.stopped) return false;
        self.request = request;
        return true;
    }

    fn close(self: *HttpCancel, request: win.HINTERNET) void {
        win.AcquireSRWLockExclusive(&self.lock);
        defer win.ReleaseSRWLockExclusive(&self.lock);
        if (self.request == request) {
            _ = win.WinHttpCloseHandle(request);
            self.request = null;
        }
    }
};

pub const HttpStream = struct {
    session: win.HINTERNET,
    connection: win.HINTERNET,
    request: win.HINTERNET,
    cancel: ?*HttpCancel,
    status: u32,

    pub fn deinit(self: HttpStream) void {
        if (self.cancel) |cancel| cancel.close(self.request) else _ = win.WinHttpCloseHandle(self.request);
        _ = win.WinHttpCloseHandle(self.connection);
        _ = win.WinHttpCloseHandle(self.session);
    }

    pub fn read(self: HttpStream, buffer: []u8) !usize {
        var got: win.DWORD = 0;
        if (win.WinHttpReadData(self.request, buffer.ptr, @intCast(buffer.len), &got) == 0) return error.NetworkFailed;
        return got;
    }

    pub fn response(self: HttpStream, allocator: std.mem.Allocator, max_bytes: usize) !Response {
        return .{ .status = self.status, .body = try readResponse(allocator, self.request, max_bytes) };
    }
};

pub fn openHttp(allocator: std.mem.Allocator, host: []const u8, port: u16, secure: bool, token: []const u8, method: []const u8, path: []const u8, content_type: []const u8, payload: []const u8, last_event_id: []const u8, cancel: ?*HttpCancel) !HttpStream {
    if (!enabled) return error.Unsupported;
    for (token) |byte| if (byte < 0x21 or byte > 0x7e) return error.InvalidToken;
    for (last_event_id) |byte| if (!std.ascii.isDigit(byte)) return error.InvalidEventId;
    const wide_host = try toWide(allocator, host);
    defer allocator.free(wide_host);
    const wide_path = try toWide(allocator, path);
    defer allocator.free(wide_path);
    const wide_method = try toWide(allocator, method);
    defer allocator.free(wide_method);
    const session = win.WinHttpOpen(wideLiteral("Wazig Messages/1.0"), if (secure) win.WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY else win.WINHTTP_ACCESS_TYPE_NO_PROXY, null, null, 0) orelse return error.NetworkFailed;
    errdefer _ = win.WinHttpCloseHandle(session);
    _ = win.WinHttpSetTimeouts(session, 10_000, 10_000, 30_000, 30_000);
    const connection = win.WinHttpConnect(session, wide_host.ptr, port, 0) orelse return error.NetworkFailed;
    errdefer _ = win.WinHttpCloseHandle(connection);
    const request = win.WinHttpOpenRequest(connection, wide_method.ptr, wide_path.ptr, null, null, null, if (secure) win.WINHTTP_FLAG_SECURE else 0) orelse return error.NetworkFailed;
    if (cancel) |control| {
        if (!control.attach(request)) {
            _ = win.WinHttpCloseHandle(request);
            return error.Cancelled;
        }
    }
    errdefer if (cancel) |control| control.close(request) else {
        _ = win.WinHttpCloseHandle(request);
    };
    var redirect_policy: win.DWORD = win.WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    if (win.WinHttpSetOption(request, win.WINHTTP_OPTION_REDIRECT_POLICY, &redirect_policy, @sizeOf(win.DWORD)) == 0) return error.NetworkFailed;
    const headers = try std.fmt.allocPrint(allocator, "Authorization: Bearer {s}\r\nContent-Type: {s}\r\nAccept: */*\r\n{s}{s}{s}", .{ token, content_type, if (last_event_id.len > 0) "Last-Event-ID: " else "", last_event_id, if (last_event_id.len > 0) "\r\n" else "" });
    defer allocator.free(headers);
    const wide_headers = try toWide(allocator, headers);
    defer allocator.free(wide_headers);
    if (win.WinHttpSendRequest(request, wide_headers.ptr, @intCast(wide_headers.len), if (payload.len > 0) @constCast(payload.ptr) else null, @intCast(payload.len), @intCast(payload.len), 0) == 0 or win.WinHttpReceiveResponse(request, null) == 0) return error.NetworkFailed;
    var status: win.DWORD = 0;
    var size: win.DWORD = @sizeOf(win.DWORD);
    if (win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_STATUS_CODE | win.WINHTTP_QUERY_FLAG_NUMBER, null, &status, &size, null) == 0) return error.NetworkFailed;
    return .{ .session = session, .connection = connection, .request = request, .cancel = cancel, .status = status };
}

fn shareImage(allocator: std.mem.Allocator, ctx: JobContext, channel: []const u8, thread_ts: []const u8, file_id: []const u8, caption: []const u8) ![]u8 {
    const encoded = try slack.percentEncode(allocator, file_id);
    defer allocator.free(encoded);
    const path = try std.fmt.allocPrint(allocator, "/api/files.info?file={s}", .{encoded});
    defer allocator.free(path);
    var info = try callWithRetry(allocator, ctx.host, ctx.user_token, path, null);
    defer info.deinit(allocator);
    if (info.status != 200) return error.HttpFailed;
    switch (slack_send.sharedIn(allocator, info.body, channel)) {
        .shared => return allocator.dupe(u8, "{\"ok\":true,\"already_shared\":true}"),
        .not_shared => {},
        .missing => return error.FileMissing,
        .unknown => return error.HttpFailed,
    }
    const complete_body = try slack.buildCompleteUploadBody(allocator, file_id, channel, thread_ts, caption);
    defer allocator.free(complete_body);
    var complete = try callWithRetry(allocator, ctx.host, ctx.user_token, "/api/files.completeUploadExternal", complete_body);
    errdefer complete.deinit(allocator);
    if (complete.status != 200 or !httpOk(allocator, complete.body)) return error.UploadRejected;
    return bodyOnly(allocator, complete);
}

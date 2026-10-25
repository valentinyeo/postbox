const std = @import("std");
const builtin = @import("builtin");
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

pub const max_download_bytes: u64 = 100 * 1024 * 1024;

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

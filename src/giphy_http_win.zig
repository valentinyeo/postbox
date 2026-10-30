const std = @import("std");
const builtin = @import("builtin");
const catalogue = @import("giphy_catalogue.zig");

const win = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
    @cInclude("winhttp.h");
});

pub const Cancel = struct {
    stopped: std.atomic.Value(bool) = .init(false),

    pub fn stop(self: *Cancel) void {
        self.stopped.store(true, .release);
    }
};

pub const Result = union(enum) {
    page: catalogue.Page,
    needs_key,
    invalid_request,
    cancelled,
    transport,
    unauthorized,
    forbidden,
    rate_limited: ?u32,
    http_error: u32,
    oversized,
    malformed,
};

fn wide(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

fn cancelled(cancel: *const Cancel, deadline: u64) bool {
    return cancel.stopped.load(.acquire) or win.GetTickCount64() >= deadline;
}

fn retryAfter(request: win.HINTERNET) ?u32 {
    var buffer: [64]u16 = undefined;
    var size: win.DWORD = @sizeOf(@TypeOf(buffer));
    if (win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_RETRY_AFTER, null, &buffer, &size, null) == 0) return null;
    const count = size / @sizeOf(u16);
    if (count == 0 or count > 5) return null;
    var seconds: u32 = 0;
    for (buffer[0..count]) |c| {
        if (c < '0' or c > '9') return null;
        seconds = seconds * 10 + c - '0';
    }
    return if (seconds <= 86400) seconds else null;
}

pub fn fetch(allocator: std.mem.Allocator, key: []const u8, query: []const u8, offset: usize, limit: usize, cancel: *const Cancel) Result {
    if (builtin.is_test) return .transport;
    return fetchAt(allocator, wide("api.giphy.com"), 443, true, key, query, offset, limit, cancel);
}

fn fetchAt(allocator: std.mem.Allocator, host: [*:0]const u16, port: u16, secure: bool, key: []const u8, query: []const u8, offset: usize, limit: usize, cancel: *const Cancel) Result {
    const request_url = catalogue.request(key, query, offset, limit) catch |err| return switch (err) {
        error.NeedsKey => .needs_key,
        else => .invalid_request,
    };
    if (cancel.stopped.load(.acquire)) return .cancelled;
    const deadline = win.GetTickCount64() + 20_000;
    const path = request_url.url()["https://api.giphy.com".len..];
    const wide_path = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return .transport;
    defer allocator.free(wide_path);
    const session = win.WinHttpOpen(wide("Postbox/1.0"), if (secure) win.WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY else win.WINHTTP_ACCESS_TYPE_NO_PROXY, null, null, 0) orelse return .transport;
    defer _ = win.WinHttpCloseHandle(session);
    if (win.WinHttpSetTimeouts(session, 5000, 5000, 5000, 5000) == 0) return .transport;
    const connection = win.WinHttpConnect(session, host, port, 0) orelse return .transport;
    defer _ = win.WinHttpCloseHandle(connection);
    const request = win.WinHttpOpenRequest(connection, wide("GET"), wide_path.ptr, null, null, null, if (secure) win.WINHTTP_FLAG_SECURE else 0) orelse return .transport;
    defer _ = win.WinHttpCloseHandle(request);
    var policy: win.DWORD = win.WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    if (win.WinHttpSetOption(request, win.WINHTTP_OPTION_REDIRECT_POLICY, &policy, @sizeOf(win.DWORD)) == 0) return .transport;
    if (cancelled(cancel, deadline)) return .cancelled;
    if (win.WinHttpSendRequest(request, wide("Accept: application/json\r\n"), 0xffffffff, null, 0, 0, 0) == 0) return if (cancelled(cancel, deadline)) .cancelled else .transport;
    if (win.WinHttpReceiveResponse(request, null) == 0) return if (cancelled(cancel, deadline)) .cancelled else .transport;
    if (cancelled(cancel, deadline)) return .cancelled;
    var status: win.DWORD = 0;
    var size: win.DWORD = @sizeOf(win.DWORD);
    if (win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_STATUS_CODE | win.WINHTTP_QUERY_FLAG_NUMBER, null, &status, &size, null) == 0) return .transport;
    switch (status) {
        200 => {},
        401 => return .unauthorized,
        403 => return .forbidden,
        429 => return .{ .rate_limited = retryAfter(request) },
        else => return .{ .http_error = status },
    }
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);
    var buffer: [8192]u8 = undefined;
    while (true) {
        if (cancelled(cancel, deadline)) return .cancelled;
        var read: win.DWORD = 0;
        if (win.WinHttpReadData(request, &buffer, buffer.len, &read) == 0) return if (cancelled(cancel, deadline)) .cancelled else .transport;
        if (read == 0) break;
        if (read > catalogue.max_response_bytes - body.items.len) return .oversized;
        body.appendSlice(allocator, buffer[0..read]) catch return .transport;
    }
    if (cancelled(cancel, deadline)) return .cancelled;
    const page = catalogue.parse(allocator, body.items, offset, limit) catch return .malformed;
    if (cancelled(cancel, deadline)) return .cancelled;
    return .{ .page = page };
}

fn fixturePort() !u16 {
    if (!builtin.is_test) return error.FixtureMissing;
    var ready: [32]u16 = undefined;
    const ready_len = win.GetEnvironmentVariableW(wide("POSTBOX_GIPHY_FIXTURE"), &ready, ready.len);
    if (ready_len == 0 or ready_len >= ready.len) return error.FixtureMissing;
    const marker = std.unicode.utf16LeToUtf8Alloc(std.testing.allocator, ready[0..ready_len]) catch return error.FixtureMissing;
    defer std.testing.allocator.free(marker);
    if (!std.mem.eql(u8, marker, "loopback-only")) return error.FixtureMissing;
    var port: [8]u16 = undefined;
    const port_len = win.GetEnvironmentVariableW(wide("POSTBOX_GIPHY_PORT"), &port, port.len);
    if (port_len == 0 or port_len >= port.len) return error.FixtureMissing;
    const digits = std.unicode.utf16LeToUtf8Alloc(std.testing.allocator, port[0..port_len]) catch return error.FixtureMissing;
    defer std.testing.allocator.free(digits);
    const value = std.fmt.parseUnsigned(u16, digits, 10) catch return error.FixtureMissing;
    if (value == 0) return error.FixtureMissing;
    return value;
}

fn fixtureFetch(port: u16, query: []const u8, cancel: *const Cancel) Result {
    if (!builtin.is_test) return .transport;
    return fetchAt(std.testing.allocator, wide("127.0.0.1"), port, false, "fixture-key", query, 0, 1, cancel);
}

test "GIPHY_LOOPBACK native status, size and redirect behavior" {
    const port = try fixturePort();
    var cancel = Cancel{};
    const success = fixtureFetch(port, "cat & dog", &cancel);
    try std.testing.expect(success == .page);
    try std.testing.expectEqual(@as(usize, 1), success.page.count);
    try std.testing.expect(fixtureFetch(port, "unauthorized", &cancel) == .unauthorized);
    try std.testing.expect(fixtureFetch(port, "forbidden", &cancel) == .forbidden);
    const limited = fixtureFetch(port, "limited", &cancel);
    try std.testing.expect(limited == .rate_limited);
    try std.testing.expectEqual(@as(?u32, 17), limited.rate_limited);
    try std.testing.expect(fixtureFetch(port, "malformed", &cancel) == .malformed);
    try std.testing.expect(fixtureFetch(port, "oversized", &cancel) == .oversized);
    try std.testing.expect(fixtureFetch(port, "lying", &cancel) == .oversized);
    const redirect = fixtureFetch(port, "redirect", &cancel);
    try std.testing.expect(redirect == .http_error);
    try std.testing.expectEqual(@as(u32, 302), redirect.http_error);
}

fn stopSoon(cancel: *Cancel) void {
    win.Sleep(150);
    cancel.stop();
}

test "GIPHY_LOOPBACK cancellation prevents slow response publication" {
    const port = try fixturePort();
    var cancel = Cancel{};
    const thread = try std.Thread.spawn(.{}, stopSoon, .{&cancel});
    defer thread.join();
    try std.testing.expect(fixtureFetch(port, "slow", &cancel) == .cancelled);
}

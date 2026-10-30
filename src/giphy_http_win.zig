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
    timeout,
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

fn stopReason(cancel: *const Cancel, deadline: u64) ?Result {
    if (cancel.stopped.load(.acquire)) return .cancelled;
    if (win.GetTickCount64() >= deadline) return .timeout;
    return null;
}

fn retryAfter(request: win.HINTERNET) ?u32 {
    var buffer: [256]u16 = undefined;
    var size: win.DWORD = @sizeOf(@TypeOf(buffer));
    if (win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_RETRY_AFTER, null, &buffer, &size, null) == 0) return null;
    const count = size / @sizeOf(u16);
    if (count == 0 or count > buffer.len) return null;
    var seconds: u32 = 0;
    for (buffer[0..count]) |c| {
        if (c < '0' or c > '9') return null;
        seconds = @min(86400, seconds * 10 + c - '0');
    }
    return seconds;
}

const CallbackContext = struct {
    wake: win.HANDLE,
    completion: std.atomic.Value(u64) = .init(0),
    close_ack: std.atomic.Value(bool) = .init(false),
    read_buffer: [8192]u8 = undefined,
};

const sent: u32 = 1;
const headers: u32 = 2;
const read_done: u32 = 3;
const failed: u32 = 4;

fn statusCallback(_: win.HINTERNET, context_value: win.DWORD_PTR, status: win.DWORD, info: win.LPVOID, length: win.DWORD) callconv(.winapi) void {
    if (context_value == 0) return;
    const ctx: *CallbackContext = @ptrFromInt(context_value);
    if (status == win.WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING) {
        _ = win.SetEvent(ctx.wake);
        ctx.close_ack.store(true, .release);
        return;
    }
    var kind: u32 = 0;
    var value: u32 = 0;
    switch (status) {
        win.WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE => kind = sent,
        win.WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE => kind = headers,
        win.WINHTTP_CALLBACK_STATUS_READ_COMPLETE => {
            kind = read_done;
            value = length;
        },
        win.WINHTTP_CALLBACK_STATUS_REQUEST_ERROR => {
            kind = failed;
            if (info != null and length == @sizeOf(win.WINHTTP_ASYNC_RESULT)) {
                const detail: *const win.WINHTTP_ASYNC_RESULT = @ptrCast(@alignCast(info.?));
                value = detail.dwError;
            }
        },
        else => return,
    }
    ctx.completion.store((@as(u64, kind) << 32) | value, .release);
    _ = win.SetEvent(ctx.wake);
}

const Completion = union(enum) { value: u32, stopped: Result };

fn waitCompletion(ctx: *CallbackContext, expected: u32, cancel: *const Cancel, deadline: u64) Completion {
    while (true) {
        if (stopReason(cancel, deadline)) |reason| return .{ .stopped = reason };
        const completion = ctx.completion.swap(0, .acq_rel);
        if (completion != 0) {
            if (stopReason(cancel, deadline)) |reason| return .{ .stopped = reason };
            if (@as(u32, @intCast(completion >> 32)) != expected) return .{ .stopped = .transport };
            return .{ .value = @truncate(completion) };
        }
        const now = win.GetTickCount64();
        if (now >= deadline) return .{ .stopped = .timeout };
        const wait_ms: win.DWORD = @intCast(@min(10, deadline - now));
        const wait = win.WaitForSingleObject(ctx.wake, wait_ms);
        if (wait != win.WAIT_OBJECT_0 and wait != win.WAIT_TIMEOUT) return .{ .stopped = .transport };
    }
}

const FixtureProbe = struct {
    pending: win.HANDLE = null,
    pending_kind: u32 = 0,
    before_send: bool = false,
    close_attempts: u32 = 0,
    close_ack: u32 = 0,
};

fn closeAndDrain(request_slot: *win.HINTERNET, ctx: *CallbackContext, armed: bool, probe: ?*FixtureProbe) void {
    const request = request_slot.* orelse return;
    request_slot.* = null;
    if (builtin.is_test) if (probe) |p| {
        p.close_attempts += 1;
    };
    const closed = win.WinHttpCloseHandle(request);
    if (!armed) return;
    if (closed == 0) {
        while (true) _ = win.WaitForSingleObject(ctx.wake, 1000);
    }
    while (!ctx.close_ack.load(.acquire)) {
        _ = win.WaitForSingleObject(ctx.wake, 10);
    }
    if (builtin.is_test) if (probe) |p| {
        p.close_ack += 1;
    };
}

fn signalPending(ctx: *CallbackContext, probe: ?*FixtureProbe, kind: u32) void {
    if (builtin.is_test) if (probe) |p| {
        if (p.pending_kind == kind and ctx.completion.load(.acquire) == 0 and p.pending != null) _ = win.SetEvent(p.pending);
    };
}

pub fn fetch(allocator: std.mem.Allocator, key: []const u8, query: []const u8, offset: usize, limit: usize, cancel: *const Cancel) Result {
    if (builtin.is_test) return .transport;
    return fetchAt(allocator, wide("api.giphy.com"), 443, true, key, query, offset, limit, cancel, 20_000, null);
}

fn fetchAt(allocator: std.mem.Allocator, host: [*:0]const u16, port: u16, secure: bool, key: []const u8, query: []const u8, offset: usize, limit: usize, cancel: *const Cancel, budget_ms: u32, probe: ?*FixtureProbe) Result {
    const request_url = catalogue.request(key, query, offset, limit) catch |err| return switch (err) {
        error.NeedsKey => .needs_key,
        else => .invalid_request,
    };
    if (cancel.stopped.load(.acquire)) return .cancelled;
    const deadline = win.GetTickCount64() + budget_ms;
    const path = request_url.url()["https://api.giphy.com".len..];
    const wide_path = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return .transport;
    defer allocator.free(wide_path);
    if (stopReason(cancel, deadline)) |reason| return reason;
    const session = win.WinHttpOpen(wide("Postbox/1.0"), if (secure) win.WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY else win.WINHTTP_ACCESS_TYPE_NO_PROXY, null, null, win.WINHTTP_FLAG_ASYNC) orelse return .transport;
    defer _ = win.WinHttpCloseHandle(session);
    if (stopReason(cancel, deadline)) |reason| return reason;
    if (win.WinHttpSetTimeouts(session, 5000, 5000, 5000, 5000) == 0) return .transport;
    if (stopReason(cancel, deadline)) |reason| return reason;
    const connection = win.WinHttpConnect(session, host, port, 0) orelse return .transport;
    defer _ = win.WinHttpCloseHandle(connection);
    if (stopReason(cancel, deadline)) |reason| return reason;
    const event = win.CreateEventW(null, 0, 0, null) orelse return .transport;
    defer _ = win.CloseHandle(event);
    var ctx = CallbackContext{ .wake = event };
    var request: win.HINTERNET = win.WinHttpOpenRequest(connection, wide("GET"), wide_path.ptr, null, null, null, if (secure) win.WINHTTP_FLAG_SECURE else 0) orelse return .transport;
    var armed = false;
    defer closeAndDrain(&request, &ctx, armed, probe);
    if (stopReason(cancel, deadline)) |reason| return reason;
    var policy: win.DWORD = win.WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    if (win.WinHttpSetOption(request, win.WINHTTP_OPTION_REDIRECT_POLICY, &policy, @sizeOf(win.DWORD)) == 0) return .transport;
    var context: win.DWORD_PTR = @intFromPtr(&ctx);
    if (win.WinHttpSetOption(request, win.WINHTTP_OPTION_CONTEXT_VALUE, &context, @sizeOf(win.DWORD_PTR)) == 0) return .transport;
    const flags = win.WINHTTP_CALLBACK_FLAG_SENDREQUEST_COMPLETE | win.WINHTTP_CALLBACK_FLAG_HEADERS_AVAILABLE | win.WINHTTP_CALLBACK_FLAG_READ_COMPLETE | win.WINHTTP_CALLBACK_FLAG_REQUEST_ERROR | win.WINHTTP_CALLBACK_FLAG_HANDLES;
    const old = win.WinHttpSetStatusCallback(request, statusCallback, flags, 0);
    if (old != null and @intFromPtr(old.?) == std.math.maxInt(usize)) return .transport;
    armed = true;
    if (builtin.is_test) if (probe) |p| {
        if (p.before_send) return .cancelled;
    };
    if (stopReason(cancel, deadline)) |reason| return reason;
    if (win.WinHttpSendRequest(request, wide("Accept: application/json\r\n"), 0xffffffff, null, 0, 0, context) == 0) return stopReason(cancel, deadline) orelse .transport;
    switch (waitCompletion(&ctx, sent, cancel, deadline)) {
        .stopped => |reason| return reason,
        .value => {},
    }
    if (stopReason(cancel, deadline)) |reason| return reason;
    if (win.WinHttpReceiveResponse(request, null) == 0) return stopReason(cancel, deadline) orelse .transport;
    signalPending(&ctx, probe, headers);
    switch (waitCompletion(&ctx, headers, cancel, deadline)) {
        .stopped => |reason| return reason,
        .value => {},
    }
    if (stopReason(cancel, deadline)) |reason| return reason;
    var status: win.DWORD = 0;
    var size: win.DWORD = @sizeOf(win.DWORD);
    if (win.WinHttpQueryHeaders(request, win.WINHTTP_QUERY_STATUS_CODE | win.WINHTTP_QUERY_FLAG_NUMBER, null, &status, &size, null) == 0) return stopReason(cancel, deadline) orelse .transport;
    if (stopReason(cancel, deadline)) |reason| return reason;
    switch (status) {
        200 => {},
        401 => return .unauthorized,
        403 => return .forbidden,
        429 => {
            const delay = retryAfter(request);
            if (stopReason(cancel, deadline)) |reason| return reason;
            return .{ .rate_limited = delay };
        },
        else => return .{ .http_error = status },
    }
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);
    while (true) {
        if (stopReason(cancel, deadline)) |reason| return reason;
        if (win.WinHttpReadData(request, &ctx.read_buffer, ctx.read_buffer.len, null) == 0) return stopReason(cancel, deadline) orelse .transport;
        signalPending(&ctx, probe, read_done);
        const read = switch (waitCompletion(&ctx, read_done, cancel, deadline)) {
            .stopped => |reason| return reason,
            .value => |count| count,
        };
        if (read > ctx.read_buffer.len) return .transport;
        if (read == 0) break;
        if (read > catalogue.max_response_bytes - body.items.len) return .oversized;
        body.appendSlice(allocator, ctx.read_buffer[0..read]) catch return .transport;
    }
    if (stopReason(cancel, deadline)) |reason| return reason;
    const page = catalogue.parse(allocator, body.items, offset, limit) catch return .malformed;
    if (stopReason(cancel, deadline)) |reason| return reason;
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

fn fixtureFetch(port: u16, query: []const u8, cancel: *const Cancel, budget_ms: u32) Result {
    return fixtureFetchProbed(port, query, cancel, budget_ms, null);
}

fn fixtureFetchProbed(port: u16, query: []const u8, cancel: *const Cancel, budget_ms: u32, probe: ?*FixtureProbe) Result {
    if (!builtin.is_test) return .transport;
    return fetchAt(std.testing.allocator, wide("127.0.0.1"), port, false, "fixture-key", query, 0, 1, cancel, budget_ms, probe);
}

test "GIPHY_LOOPBACK native status, size and redirect behavior" {
    const port = try fixturePort();
    var cancel = Cancel{};
    const success = fixtureFetch(port, "cat & dog", &cancel, 20_000);
    try std.testing.expect(success == .page);
    try std.testing.expectEqual(@as(usize, 1), success.page.count);
    try std.testing.expect(fixtureFetch(port, "unauthorized", &cancel, 20_000) == .unauthorized);
    try std.testing.expect(fixtureFetch(port, "forbidden", &cancel, 20_000) == .forbidden);
    const limited = fixtureFetch(port, "limited", &cancel, 20_000);
    try std.testing.expect(limited == .rate_limited);
    try std.testing.expectEqual(@as(?u32, 17), limited.rate_limited);
    for ([_][]const u8{ "limited-over", "limited-six", "limited-huge" }) |query| {
        const result = fixtureFetch(port, query, &cancel, 20_000);
        try std.testing.expect(result == .rate_limited);
        try std.testing.expectEqual(@as(?u32, 86400), result.rate_limited);
    }
    for ([_][]const u8{ "limited-invalid", "limited-date", "limited-missing" }) |query| {
        const result = fixtureFetch(port, query, &cancel, 20_000);
        try std.testing.expect(result == .rate_limited);
        try std.testing.expectEqual(@as(?u32, null), result.rate_limited);
    }
    try std.testing.expect(fixtureFetch(port, "malformed", &cancel, 20_000) == .malformed);
    try std.testing.expect(fixtureFetch(port, "oversized", &cancel, 20_000) == .oversized);
    try std.testing.expect(fixtureFetch(port, "lying", &cancel, 20_000) == .oversized);
    const redirect = fixtureFetch(port, "redirect", &cancel, 20_000);
    try std.testing.expect(redirect == .http_error);
    try std.testing.expectEqual(@as(u32, 302), redirect.http_error);
}

fn fixtureEvent(name: [*:0]const u16) !win.HANDLE {
    var buffer: [128]u16 = undefined;
    const len = win.GetEnvironmentVariableW(name, &buffer, buffer.len);
    if (len == 0 or len >= buffer.len) return error.FixtureMissing;
    return win.OpenEventW(win.SYNCHRONIZE | win.EVENT_MODIFY_STATE, 0, &buffer) orelse error.FixtureMissing;
}

const StopOnPending = struct {
    arrived: win.HANDLE,
    pending: win.HANDLE,
    cancel: *Cancel,

    fn run(self: StopOnPending) void {
        if (win.WaitForSingleObject(self.arrived, 5000) != win.WAIT_OBJECT_0) return;
        if (win.WaitForSingleObject(self.pending, 5000) == win.WAIT_OBJECT_0) self.cancel.stop();
    }
};

fn stallCase(query: []const u8, arrived_name: [*:0]const u16, pending_name: [*:0]const u16, done_name: [*:0]const u16, kind: u32, deadline_case: bool) !void {
    const port = try fixturePort();
    const arrived = try fixtureEvent(arrived_name);
    defer _ = win.CloseHandle(arrived);
    const pending = try fixtureEvent(pending_name);
    defer _ = win.CloseHandle(pending);
    const completed = try fixtureEvent(done_name);
    defer _ = win.CloseHandle(completed);
    var cancel = Cancel{};
    var probe = FixtureProbe{ .pending = pending, .pending_kind = kind };
    var thread: ?std.Thread = null;
    if (!deadline_case) thread = try std.Thread.spawn(.{}, StopOnPending.run, .{StopOnPending{ .arrived = arrived, .pending = pending, .cancel = &cancel }});
    defer if (thread) |t| t.join();
    const result = fixtureFetchProbed(port, query, &cancel, if (deadline_case) 1500 else 20_000, &probe);
    try std.testing.expect(if (deadline_case) result == .timeout else result == .cancelled);
    try std.testing.expect(win.WaitForSingleObject(arrived, 0) == win.WAIT_OBJECT_0);
    try std.testing.expect(win.WaitForSingleObject(pending, 0) == win.WAIT_OBJECT_0);
    try std.testing.expectEqual(@as(u32, 1), probe.close_attempts);
    try std.testing.expectEqual(@as(u32, 1), probe.close_ack);
    try std.testing.expect(win.SetEvent(completed) != 0);
}

test "GIPHY_LOOPBACK pending headers cancellation" {
    try stallCase("cancelstall", wide("POSTBOX_GIPHY_CANCEL_ARRIVED"), wide("POSTBOX_GIPHY_CANCEL_PENDING"), wide("POSTBOX_GIPHY_CANCEL_DONE"), headers, false);
}

test "GIPHY_LOOPBACK pending headers deadline" {
    try stallCase("deadlinestall", wide("POSTBOX_GIPHY_DEADLINE_ARRIVED"), wide("POSTBOX_GIPHY_DEADLINE_PENDING"), wide("POSTBOX_GIPHY_DEADLINE_DONE"), headers, true);
}

test "GIPHY_LOOPBACK pending body cancellation" {
    try stallCase("bodycancel", wide("POSTBOX_GIPHY_BODY_CANCEL_ARRIVED"), wide("POSTBOX_GIPHY_BODY_CANCEL_PENDING"), wide("POSTBOX_GIPHY_BODY_CANCEL_DONE"), read_done, false);
}

test "GIPHY_LOOPBACK pending body deadline" {
    try stallCase("bodydeadline", wide("POSTBOX_GIPHY_BODY_DEADLINE_ARRIVED"), wide("POSTBOX_GIPHY_BODY_DEADLINE_PENDING"), wide("POSTBOX_GIPHY_BODY_DEADLINE_DONE"), read_done, true);
}

test "GIPHY_LOOPBACK pre-cancel and armed close before send" {
    const port = try fixturePort();
    var cancel = Cancel{};
    cancel.stop();
    var pre = FixtureProbe{};
    try std.testing.expect(fixtureFetchProbed(port, "not-sent", &cancel, 20_000, &pre) == .cancelled);
    try std.testing.expectEqual(@as(u32, 0), pre.close_attempts);
    var active = Cancel{};
    var armed = FixtureProbe{ .before_send = true };
    try std.testing.expect(fixtureFetchProbed(port, "not-sent", &active, 20_000, &armed) == .cancelled);
    try std.testing.expectEqual(@as(u32, 1), armed.close_attempts);
    try std.testing.expectEqual(@as(u32, 1), armed.close_ack);
}

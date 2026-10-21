const std = @import("std");
const oauth = @import("slack_oauth.zig");
const win = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("winsock2.h");
    @cInclude("ws2tcpip.h");
    @cInclude("windows.h");
    @cInclude("shellapi.h");
});

fn wide(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

fn waitReadable(socket: win.SOCKET, deadline: u64, stop: *std.atomic.Value(bool)) !void {
    while (!stop.load(.acquire)) {
        const now = win.GetTickCount64();
        if (now >= deadline) return error.CallbackTimedOut;
        var sockets = std.mem.zeroes(win.fd_set);
        sockets.fd_count = 1;
        sockets.fd_array[0] = socket;
        var timeout = win.timeval{ .tv_sec = 0, .tv_usec = @intCast(@as(u64, @min(deadline - now, 250)) * 1000) };
        const result = win.select(0, &sockets, null, null, &timeout);
        if (result > 0) return;
        if (result < 0) return error.CallbackNetworkFailed;
    }
    return error.Cancelled;
}

pub const Callback = struct {
    socket: win.SOCKET,
    code: []const u8,
    attempt: oauth.Attempt,

    pub fn respond(self: Callback, success: bool, message: []const u8) void {
        var buffer: [2048]u8 = undefined;
        const page = std.fmt.bufPrint(&buffer, "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width\"><title>Messages - Slack</title><style>body{{background:#111;color:#eee;font:18px system-ui;max-width:40em;margin:15vh auto;padding:24px}}</style><h1>{s}</h1><p>{s}</p>", .{ if (success) "Slack connected, you can close this tab" else "Slack sign-in failed", message }) catch return;
        var header_buffer: [256]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buffer, "HTTP/1.1 {s}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\nConnection: close\r\n\r\n", .{ if (success) "200 OK" else "400 Bad Request", page.len }) catch return;
        const timeout: win.DWORD = 2000;
        _ = win.setsockopt(self.socket, win.SOL_SOCKET, win.SO_SNDTIMEO, @ptrCast(&timeout), @sizeOf(win.DWORD));
        for ([_][]const u8{ header, page }) |part| {
            var offset: usize = 0;
            while (offset < part.len) {
                const sent = win.send(self.socket, part.ptr + offset, @intCast(part.len - offset), 0);
                if (sent <= 0) return;
                offset += @intCast(sent);
            }
        }
    }

    pub fn close(self: Callback) void {
        _ = win.closesocket(self.socket);
        _ = win.WSACleanup();
    }
};

pub fn authorize(allocator: std.mem.Allocator, io: std.Io, client_id: []const u8, stop: *std.atomic.Value(bool)) !Callback {
    var data: win.WSADATA = undefined;
    if (win.WSAStartup(0x0202, &data) != 0) return error.CallbackNetworkFailed;
    errdefer _ = win.WSACleanup();
    const listener = win.socket(win.AF_INET, win.SOCK_STREAM, win.IPPROTO_TCP);
    if (listener == win.INVALID_SOCKET) return error.CallbackNetworkFailed;
    var listener_open = true;
    defer if (listener_open) {
        _ = win.closesocket(listener);
    };
    const exclusive: win.BOOL = 1;
    if (win.setsockopt(listener, win.SOL_SOCKET, win.SO_EXCLUSIVEADDRUSE, @ptrCast(&exclusive), @sizeOf(win.BOOL)) != 0) return error.CallbackNetworkFailed;
    var address = std.mem.zeroes(win.sockaddr_in);
    address.sin_family = win.AF_INET;
    address.sin_port = win.htons(53682);
    address.sin_addr.S_un.S_addr = win.htonl(0x7f000001);
    if (win.bind(listener, @ptrCast(&address), @sizeOf(win.sockaddr_in)) != 0) return error.CallbackPortBusy;
    if (win.listen(listener, 1) != 0) return error.CallbackNetworkFailed;
    const attempt = try oauth.generate(io);
    const url = try oauth.buildAuthorizeUrl(allocator, client_id, attempt);
    const wide_url = try std.unicode.utf8ToUtf16LeAllocZ(allocator, url);
    const shell = win.LoadLibraryW(wide("shell32.dll")) orelse return error.BrowserFailed;
    defer _ = win.FreeLibrary(shell);
    const execute: *const @TypeOf(win.ShellExecuteW) = @ptrCast(win.GetProcAddress(shell, "ShellExecuteW") orelse return error.BrowserFailed);
    if (@intFromPtr(execute(null, wide("open"), wide_url, null, null, win.SW_SHOWNORMAL)) <= 32) return error.BrowserFailed;
    const deadline = win.GetTickCount64() + 300_000;
    try waitReadable(listener, deadline, stop);
    const socket = win.accept(listener, null, null);
    if (socket == win.INVALID_SOCKET) return error.CallbackNetworkFailed;
    _ = win.closesocket(listener);
    listener_open = false;
    errdefer _ = win.closesocket(socket);
    var callback = Callback{ .socket = socket, .code = "", .attempt = attempt };
    var request: [8192]u8 = undefined;
    var length: usize = 0;
    while (std.mem.indexOf(u8, request[0..length], "\r\n\r\n") == null) {
        waitReadable(socket, deadline, stop) catch |err| {
            callback.respond(false, "Callback timed out or was cancelled. Return to Messages and try again.");
            return err;
        };
        if (length == request.len) {
            callback.respond(false, "Invalid callback request.");
            return error.InvalidCallback;
        }
        const count = win.recv(socket, request[length..].ptr, @intCast(request.len - length), 0);
        if (count <= 0) return error.CallbackNetworkFailed;
        length += @intCast(count);
    }
    callback.code = oauth.parseRequest(allocator, request[0..length], &attempt.state) catch |err| {
        callback.respond(false, "Invalid or denied authorization. Return to Messages and try again.");
        return err;
    };
    return callback;
}

test "exclusive loopback port conflict fails before browser launch" {
    var data: win.WSADATA = undefined;
    try std.testing.expectEqual(@as(c_int, 0), win.WSAStartup(0x0202, &data));
    defer _ = win.WSACleanup();
    const listener = win.socket(win.AF_INET, win.SOCK_STREAM, win.IPPROTO_TCP);
    try std.testing.expect(listener != win.INVALID_SOCKET);
    defer _ = win.closesocket(listener);
    const exclusive: win.BOOL = 1;
    try std.testing.expectEqual(@as(c_int, 0), win.setsockopt(listener, win.SOL_SOCKET, win.SO_EXCLUSIVEADDRUSE, @ptrCast(&exclusive), @sizeOf(win.BOOL)));
    var address = std.mem.zeroes(win.sockaddr_in);
    address.sin_family = win.AF_INET;
    address.sin_port = win.htons(53682);
    address.sin_addr.S_un.S_addr = win.htonl(0x7f000001);
    try std.testing.expectEqual(@as(c_int, 0), win.bind(listener, @ptrCast(&address), @sizeOf(win.sockaddr_in)));
    var stop: std.atomic.Value(bool) = .init(false);
    try std.testing.expectError(error.CallbackPortBusy, authorize(std.testing.allocator, std.testing.io, "0000000000.0000000000", &stop));
}

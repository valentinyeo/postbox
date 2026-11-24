const std = @import("std");
const win = @import("win32.zig").c;
const control = @import("control.zig");

pub const max_request_bytes: usize = 64 * 1024;
pub const max_response_bytes: usize = 16 * 1024 * 1024;

pub fn pipeName(buffer: *[200]u16) ?[:0]const u16 {
    return pipeNameWithPrefix(control.pipe_prefix, buffer);
}

pub fn pipeNameWithPrefix(comptime prefix_utf8: []const u8, buffer: *[200]u16) ?[:0]const u16 {
    const prefix = std.unicode.utf8ToUtf16LeStringLiteral(prefix_utf8);
    const rest = buffer[prefix.len..];
    const user_len = win.GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("USERNAME"), rest.ptr, @intCast(rest.len));
    if (user_len == 0 or user_len >= rest.len) return null;
    @memcpy(buffer[0..prefix.len], prefix);
    const len = prefix.len + user_len;
    buffer[len] = 0;
    return buffer[0..len :0];
}

pub const Handler = *const fn (context: *anyopaque, line: []const u8, out: *std.Io.Writer.Allocating) void;

pub fn serve(allocator: std.mem.Allocator, context: *anyopaque, handler: Handler) void {
    serveWithPrefix(control.pipe_prefix, allocator, context, handler);
}

pub fn serveWithPrefix(comptime prefix_utf8: []const u8, allocator: std.mem.Allocator, context: *anyopaque, handler: Handler) void {
    var name_buffer: [200]u16 = undefined;
    const name = pipeNameWithPrefix(prefix_utf8, &name_buffer) orelse return;
    while (true) {
        const pipe = win.CreateNamedPipeW(
            name.ptr,
            win.PIPE_ACCESS_DUPLEX,
            win.PIPE_TYPE_BYTE | win.PIPE_READMODE_BYTE | win.PIPE_WAIT | win.PIPE_REJECT_REMOTE_CLIENTS,
            win.PIPE_UNLIMITED_INSTANCES,
            64 * 1024,
            64 * 1024,
            0,
            null,
        );
        if (pipe == win.INVALID_HANDLE_VALUE or pipe == null) {
            win.Sleep(5000);
            continue;
        }
        const connected = win.ConnectNamedPipe(pipe, null) != 0 or win.GetLastError() == win.ERROR_PIPE_CONNECTED;
        if (!connected) {
            _ = win.CloseHandle(pipe);
            continue;
        }
        const job = Connection{ .allocator = allocator, .context = context, .handler = handler, .pipe = pipe.? };
        if (std.Thread.spawn(.{ .stack_size = 512 * 1024 }, Connection.run, .{job})) |thread| {
            thread.detach();
        } else |_| job.run();
    }
}

pub fn sendLineWithPrefix(comptime prefix_utf8: []const u8, text: []const u8, wait_ms: u32) bool {
    var name_buffer: [200]u16 = undefined;
    const name = pipeNameWithPrefix(prefix_utf8, &name_buffer) orelse return false;
    const deadline = win.GetTickCount64() + wait_ms;
    var handle: win.HANDLE = win.INVALID_HANDLE_VALUE;
    while (true) {
        const opened = win.CreateFileW(name.ptr, win.GENERIC_READ | win.GENERIC_WRITE, 0, null, win.OPEN_EXISTING, control.client_open_flags, null);
        if (opened != win.INVALID_HANDLE_VALUE and opened != null) {
            handle = opened;
            break;
        }
        const err = win.GetLastError();
        if (win.GetTickCount64() >= deadline) return false;
        if (err == win.ERROR_PIPE_BUSY) {
            _ = win.WaitNamedPipeW(name.ptr, 500);
        } else if (err == win.ERROR_FILE_NOT_FOUND) {
            win.Sleep(200);
        } else {
            return false;
        }
    }
    defer _ = win.CloseHandle(handle);
    writeAll(handle, text);
    writeAll(handle, "\n");
    var reply: [256]u8 = undefined;
    var got: win.DWORD = 0;
    _ = win.ReadFile(handle, &reply, reply.len, &got, null);
    return true;
}

const Connection = struct {
    allocator: std.mem.Allocator,
    context: *anyopaque,
    handler: Handler,
    pipe: win.HANDLE,

    fn run(self: Connection) void {
        defer {
            _ = win.FlushFileBuffers(self.pipe);
            _ = win.DisconnectNamedPipe(self.pipe);
            _ = win.CloseHandle(self.pipe);
        }
        var out = std.Io.Writer.Allocating.init(self.allocator);
        defer out.deinit();
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(self.allocator);
        if (readLine(self.allocator, self.pipe, &line)) {
            self.handler(self.context, line.items, &out);
        } else {
            control.writeError(&out.writer, "request must be one JSON line under 64 KB") catch {};
        }
        writeAll(self.pipe, out.written());
    }
};

fn readLine(allocator: std.mem.Allocator, pipe: win.HANDLE, line: *std.ArrayList(u8)) bool {
    var chunk: [4096]u8 = undefined;
    while (line.items.len <= max_request_bytes) {
        var got: win.DWORD = 0;
        if (win.ReadFile(pipe, &chunk, chunk.len, &got, null) == 0 or got == 0) return line.items.len > 0;
        const piece = chunk[0..got];
        if (std.mem.indexOfScalar(u8, piece, '\n')) |end| {
            line.appendSlice(allocator, piece[0..end]) catch return false;
            return true;
        }
        line.appendSlice(allocator, piece) catch return false;
    }
    return false;
}

pub fn writeAll(handle: win.HANDLE, bytes: []const u8) void {
    var sent: usize = 0;
    while (sent < bytes.len) {
        var wrote: win.DWORD = 0;
        const size: win.DWORD = @intCast(@min(bytes.len - sent, 64 * 1024));
        if (win.WriteFile(handle, bytes[sent..].ptr, size, &wrote, null) == 0 or wrote == 0) return;
        sent += wrote;
    }
}

pub const UiResult = enum { done, timeout, gone };

pub fn callUi(hwnd: win.HWND, message: win.UINT, payload: *anyopaque, event: win.HANDLE, timeout_ms: u32) UiResult {
    if (win.PostMessageW(hwnd, message, 0, @bitCast(@intFromPtr(payload))) == 0) return .gone;
    return if (win.WaitForSingleObject(event, timeout_ms) == win.WAIT_OBJECT_0) .done else .timeout;
}

pub fn waitForever(event: win.HANDLE) void {
    _ = win.WaitForSingleObject(event, win.INFINITE);
}

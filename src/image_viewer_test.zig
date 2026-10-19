const std = @import("std");
const viewer = @import("image_viewer.zig");
const win = @import("win32.zig").c;

const Text = struct {
    buf: [192]u8 = @splat(0),
    len: usize = 0,

    pub fn set(self: *@This(), text: []const u8) void {
        self.len = text.len;
        @memcpy(self.buf[0..text.len], text);
    }
    pub fn slice(self: *const @This()) []const u8 {
        return self.buf[0..self.len];
    }
};
const Path = struct {
    len: usize = 0,
    pub fn ptr(_: *const @This()) [*:0]const u16 {
        return wide(".zig-cache/gallery-smoke.bmp");
    }
};
const Message = struct { id: Text = .{}, image: bool = true, local_path: Path = .{} };
const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    instance: win.HINSTANCE = null,
    hwnd: ?win.HWND = null,
    image_viewer_window: ?win.HWND = null,
    viewer_bitmap: ?win.HBITMAP = null,
    viewer_width: i32 = 0,
    viewer_height: i32 = 0,
    viewer_opened_ms: u64 = 0,
    viewer_chat: Text = .{},
    viewer_id: Text = .{},
    viewer_failed: bool = false,
    displayed_jid: Text = .{},
    pending_download_jid: Text = .{},
    pending_download_id: Text = .{},
    send_child: ?u8 = null,
    selected_chat: usize = 0,
    chat_count: usize = 1,
    chats: [1]struct { jid: Text = .{}, provider: enum { whatsapp } = .whatsapp } = .{.{}},
    messages: [4]Message = @splat(.{}),
    message_count: usize = 4,
    wic_factory: [*c]win.IWICImagingFactory = null,
    font_small: ?win.HFONT = null,
    downloads: usize = 0,
};
fn wide(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
fn isImage(message: *const Message) bool {
    return message.image;
}
fn download(a: *App, _: usize, _: bool) bool {
    a.downloads += 1;
    return true;
}
fn downloading(_: *const App, _: []const u8, _: []const u8) bool {
    return true;
}
fn external(_: *App, _: *const Message) void {
    @panic("unexpected external viewer");
}
const actions = .{ .isImage = isImage, .download = download, .isDownloading = downloading, .openExternal = external };
var app_ptr: ?*App = null;
fn proc(hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    return viewer.windowProc(app_ptr.?, hwnd, message, wparam, lparam, actions);
}
fn key(a: *App, code: win.WPARAM) void {
    _ = win.SendMessageW(a.image_viewer_window.?, win.WM_KEYDOWN, code, 0);
}

test "real viewer keys, clicks, queued loading, refresh identity and close" {
    _ = win.CoInitializeEx(null, win.COINIT_APARTMENTTHREADED);
    defer win.CoUninitialize();
    var a = App{};
    a.instance = win.GetModuleHandleW(null);
    app_ptr = &a;
    defer app_ptr = null;
    try std.testing.expect(win.CoCreateInstance(&win.CLSID_WICImagingFactory, null, win.CLSCTX_INPROC_SERVER, &win.IID_IWICImagingFactory, @ptrCast(&a.wic_factory)) >= 0);
    defer _ = a.wic_factory.*.lpVtbl.*.Release.?(a.wic_factory);
    var class = win.WNDCLASSEXW{ .cbSize = @sizeOf(win.WNDCLASSEXW), .lpfnWndProc = proc, .hInstance = a.instance, .lpszClassName = wide("MessagesImageViewer") };
    try std.testing.expect(win.RegisterClassExW(&class) != 0);
    defer _ = win.UnregisterClassW(class.lpszClassName, a.instance);
    a.hwnd = win.CreateWindowExW(0, wide("STATIC"), wide("Gallery test"), win.WS_OVERLAPPEDWINDOW, 0, 0, 320, 240, null, null, a.instance, null);
    try std.testing.expect(a.hwnd != null);
    defer _ = win.DestroyWindow(a.hwnd.?);
    defer viewer.close(&a);
    a.chats[0].jid.set("synthetic-chat");
    a.displayed_jid.set("synthetic-chat");
    for (&a.messages, 0..) |*message, i| message.id.set((&[_][]const u8{ "older", "text", "middle", "newer" })[i]);
    a.messages[1].image = false;
    viewer.open(&a, &a.messages[2], actions);
    try std.testing.expect(a.image_viewer_window != null);
    try std.testing.expect(a.viewer_bitmap == null and !a.viewer_failed);
    key(&a, win.VK_LEFT);
    try std.testing.expectEqualStrings("older", a.viewer_id.slice());
    const downloads = a.downloads;
    key(&a, win.VK_LEFT);
    try std.testing.expectEqual(downloads, a.downloads);
    key(&a, win.VK_RIGHT);
    key(&a, win.VK_RIGHT);
    try std.testing.expectEqualStrings("newer", a.viewer_id.slice());
    key(&a, win.VK_RIGHT);
    try std.testing.expectEqualStrings("newer", a.viewer_id.slice());
    std.mem.swap(Message, &a.messages[0], &a.messages[3]);
    viewer.downloadFinished(&a, "other-chat", "newer", false);
    viewer.downloadFinished(&a, "synthetic-chat", "older", false);
    try std.testing.expect(!a.viewer_failed);
    viewer.downloadFinished(&a, "synthetic-chat", "newer", false);
    try std.testing.expect(a.viewer_failed);
    viewer.downloadFinished(&a, "synthetic-chat", "newer", true);
    try std.testing.expect(!a.viewer_failed);

    const bmp = [_]u8{ 0x42, 0x4d, 58, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0 };
    const file = win.CreateFileW(Path.ptr(&.{}), win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    try std.testing.expect(file != win.INVALID_HANDLE_VALUE);
    var written: win.DWORD = 0;
    const write_ok = win.WriteFile(file, &bmp, bmp.len, &written, null);
    _ = win.CloseHandle(file);
    defer _ = win.DeleteFileW(Path.ptr(&.{}));
    try std.testing.expect(write_ok != 0 and written == bmp.len);
    a.messages[0].local_path.len = 1;
    viewer.refresh(&a, actions);
    try std.testing.expect(a.viewer_bitmap != null and !a.viewer_failed);
    const bitmap = a.viewer_bitmap;
    viewer.refresh(&a, actions);
    try std.testing.expectEqual(bitmap, a.viewer_bitmap);
    _ = win.UpdateWindow(a.image_viewer_window.?);
    var client = std.mem.zeroes(win.RECT);
    _ = win.GetClientRect(a.image_viewer_window.?, &client);
    const y: usize = @intCast(@divTrunc(client.bottom, 2));
    const x: usize = @intCast(client.right - 28);
    _ = win.SendMessageW(a.image_viewer_window.?, win.WM_LBUTTONUP, 0, @intCast((y << 16) | x));
    try std.testing.expectEqualStrings("middle", a.viewer_id.slice());
    try std.testing.expect(a.viewer_bitmap == null);
    _ = win.SendMessageW(a.image_viewer_window.?, win.WM_LBUTTONUP, 0, @intCast((y << 16) | 28));
    try std.testing.expectEqualStrings("newer", a.viewer_id.slice());
    const end_downloads = a.downloads;
    _ = win.SendMessageW(a.image_viewer_window.?, win.WM_LBUTTONUP, 0, @intCast((y << 16) | 28));
    try std.testing.expectEqualStrings("newer", a.viewer_id.slice());
    try std.testing.expectEqual(end_downloads, a.downloads);
    key(&a, win.VK_ESCAPE);
    try std.testing.expect(a.image_viewer_window == null and a.viewer_bitmap == null);
    viewer.downloadFinished(&a, "synthetic-chat", "middle", true);
    viewer.refresh(&a, actions);
    try std.testing.expect(a.image_viewer_window == null);
    a.send_child = 1;
    const before_queue = a.downloads;
    viewer.open(&a, &a.messages[2], actions);
    try std.testing.expectEqualStrings("middle", a.pending_download_id.slice());
    try std.testing.expectEqualStrings("synthetic-chat", a.pending_download_jid.slice());
    try std.testing.expectEqual(before_queue, a.downloads);
    a.chats[0].jid.set("different-chat");
    viewer.refresh(&a, actions);
    try std.testing.expect(a.image_viewer_window == null);
}

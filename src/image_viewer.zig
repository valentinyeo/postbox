const std = @import("std");
const win = @import("win32.zig").c;
const webp_detect = @import("webp.zig");
const gallery = @import("image_gallery.zig");

fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

pub fn close(a: anytype) void {
    // Drop the handle first so a re-entrant paint never sees a destroyed
    // window, then free the decoded bitmap.
    if (a.image_viewer_window) |hwnd| {
        a.image_viewer_window = null;
        _ = win.DestroyWindow(hwnd);
    }
    if (a.viewer_bitmap) |bitmap| {
        a.viewer_bitmap = null;
        _ = win.DeleteObject(bitmap);
    }
    a.viewer_chat.set("");
    a.viewer_id.set("");
    a.viewer_width = 0;
    a.viewer_height = 0;
    if (a.hwnd) |main_hwnd| _ = win.SetFocus(main_hwnd);
}

// Fit the source into the work area: shrink to fit, but never grow a small
// image past 2x. Aspect ratio is preserved.
fn viewerTargetSize(source_width: u32, source_height: u32, max_width: i32, max_height: i32) webp_detect.FitBox {
    if (source_width == 0 or source_height == 0) return .{ .width = 1, .height = 1 };
    if (max_width <= 0 or max_height <= 0) return .{ .width = source_width, .height = source_height };
    const sw: f32 = @floatFromInt(source_width);
    const sh: f32 = @floatFromInt(source_height);
    var scale: f32 = @min(@as(f32, @floatFromInt(max_width)) / sw, @as(f32, @floatFromInt(max_height)) / sh);
    if (scale > 2.0) scale = 2.0;
    if (scale <= 0.0) scale = 1.0;
    return .{
        .width = @max(1, @as(u32, @intFromFloat(sw * scale))),
        .height = @max(1, @as(u32, @intFromFloat(sh * scale))),
    };
}

// Decode the attachment's first frame at viewer size into a top-down 32bpp
// DIB. Fills out_width/out_height with the bitmap's pixel size.
fn decodeImageViewerBitmap(a: anytype, message: anytype, max_width: i32, max_height: i32, out_width: *i32, out_height: *i32) ?win.HBITMAP {
    if (a.wic_factory == null or message.local_path.len == 0) return null;
    var decoder: [*c]win.IWICBitmapDecoder = null;
    if (a.wic_factory.*.lpVtbl.*.CreateDecoderFromFilename.?(
        a.wic_factory,
        message.local_path.ptr(),
        null,
        win.GENERIC_READ,
        win.WICDecodeMetadataCacheOnLoad,
        &decoder,
    ) < 0 or decoder == null) return null;
    defer _ = decoder.*.lpVtbl.*.Release.?(decoder);

    var frame: [*c]win.IWICBitmapFrameDecode = null;
    if (decoder.*.lpVtbl.*.GetFrame.?(decoder, 0, &frame) < 0 or frame == null) return null;
    defer _ = frame.*.lpVtbl.*.Release.?(frame);
    var source_width: win.UINT = 0;
    var source_height: win.UINT = 0;
    if (frame.*.lpVtbl.*.GetSize.?(@ptrCast(frame), &source_width, &source_height) < 0 or source_width == 0 or source_height == 0) return null;

    const target = viewerTargetSize(source_width, source_height, max_width, max_height);
    var converter: [*c]win.IWICFormatConverter = null;
    if (a.wic_factory.*.lpVtbl.*.CreateFormatConverter.?(a.wic_factory, &converter) < 0 or converter == null) return null;
    defer _ = converter.*.lpVtbl.*.Release.?(converter);
    if (converter.*.lpVtbl.*.Initialize.?(
        converter,
        @ptrCast(frame),
        &win.GUID_WICPixelFormat32bppPBGRA,
        win.WICBitmapDitherTypeNone,
        null,
        0,
        win.WICBitmapPaletteTypeCustom,
    ) < 0) return null;

    var source: *win.IWICBitmapSource = @ptrCast(converter);
    var scaler: [*c]win.IWICBitmapScaler = null;
    defer {
        if (scaler != null) _ = scaler.*.lpVtbl.*.Release.?(scaler);
    }
    if (source_width != target.width or source_height != target.height) {
        if (a.wic_factory.*.lpVtbl.*.CreateBitmapScaler.?(a.wic_factory, &scaler) < 0 or scaler == null) return null;
        // Fant = high quality downscaling; small images grow cleanly too.
        if (scaler.*.lpVtbl.*.Initialize.?(scaler, @ptrCast(converter), target.width, target.height, win.WICBitmapInterpolationModeFant) < 0) return null;
        source = @ptrCast(scaler);
    }

    const stride: win.UINT = target.width * 4;
    const byte_count: usize = @as(usize, stride) * target.height;
    const pixels = a.allocator.alloc(u8, byte_count) catch return null;
    defer a.allocator.free(pixels);
    if (source.*.lpVtbl.*.CopyPixels.?(source, null, stride, @intCast(byte_count), pixels.ptr) < 0) return null;

    var info = std.mem.zeroes(win.BITMAPINFO);
    info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    info.bmiHeader.biWidth = @intCast(target.width);
    info.bmiHeader.biHeight = -@as(win.LONG, @intCast(target.height));
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = win.BI_RGB;
    var bits: ?*anyopaque = null;
    const bitmap = win.CreateDIBSection(null, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse return null;
    if (bits == null) {
        _ = win.DeleteObject(bitmap);
        return null;
    }
    @memcpy(@as([*]u8, @ptrCast(bits.?))[0..byte_count], pixels);
    out_width.* = @intCast(target.width);
    out_height.* = @intCast(target.height);
    return bitmap;
}

fn selection(a: anytype, comptime actions: anytype) ?gallery.Selection {
    if (a.selected_chat >= a.chat_count or
        !std.mem.eql(u8, a.viewer_chat.slice(), a.chats[a.selected_chat].jid.slice()) or
        !std.mem.eql(u8, a.viewer_chat.slice(), a.displayed_jid.slice())) return null;
    for (a.messages[0..a.message_count], 0..) |*message, index| {
        if (std.mem.eql(u8, a.viewer_id.slice(), message.id.slice()))
            return gallery.select(a.messages[0..a.message_count], index, actions.isImage);
    }
    return null;
}

fn clearBitmap(a: anytype) void {
    if (a.viewer_bitmap) |bitmap| _ = win.DeleteObject(bitmap);
    a.viewer_bitmap = null;
    a.viewer_width = 0;
    a.viewer_height = 0;
}

fn show(a: anytype, index: usize, comptime actions: anytype) void {
    const hwnd = a.image_viewer_window orelse return;
    clearBitmap(a);
    const message = &a.messages[index];
    a.viewer_id.set(message.id.slice());
    a.viewer_failed = false;
    if (message.local_path.len == 0) {
        if (a.send_child != null) {
            a.pending_download_jid.set(a.viewer_chat.slice());
            a.pending_download_id.set(message.id.slice());
        } else {
            const queued = actions.download(a, index, false);
            if (a.chats[a.selected_chat].provider == .whatsapp and !queued and !actions.isDownloading(a, a.chats[a.selected_chat].jid.slice(), message.id.slice())) a.viewer_failed = true;
        }
    }
    refresh(a, actions);
    _ = win.InvalidateRect(hwnd, null, win.TRUE);
}

pub fn refresh(a: anytype, comptime actions: anytype) void {
    const hwnd = a.image_viewer_window orelse return;
    if (a.selected_chat >= a.chat_count or
        !std.mem.eql(u8, a.viewer_chat.slice(), a.chats[a.selected_chat].jid.slice()))
    {
        close(a);
        return;
    }
    if (selection(a, actions)) |selected| {
        const message = &a.messages[selected.index];
        if (a.viewer_bitmap == null and message.local_path.len > 0 and !a.viewer_failed) {
            var client = std.mem.zeroes(win.RECT);
            _ = win.GetClientRect(hwnd, &client);
            a.viewer_bitmap = decodeImageViewerBitmap(a, message, @max(1, client.right - 112), @max(1, client.bottom - 64), &a.viewer_width, &a.viewer_height);
            a.viewer_failed = a.viewer_bitmap == null;
        }
    }
    _ = win.InvalidateRect(hwnd, null, win.FALSE);
}

pub fn downloadFinished(a: anytype, jid: []const u8, id: []const u8, ok: bool) void {
    if (a.image_viewer_window != null and std.mem.eql(u8, a.viewer_chat.slice(), jid) and
        std.mem.eql(u8, a.viewer_id.slice(), id))
    {
        a.viewer_failed = !ok;
        _ = win.InvalidateRect(a.image_viewer_window.?, null, win.FALSE);
    }
}

pub fn open(a: anytype, message: anytype, comptime actions: anytype) void {
    if (a.selected_chat >= a.chat_count) return;
    var index: ?usize = null;
    for (a.messages[0..a.message_count], 0..) |*item, i| {
        if (std.mem.eql(u8, item.id.slice(), message.id.slice())) {
            index = i;
            break;
        }
    }
    const current = index orelse return;
    if (a.image_viewer_window != null) close(a);
    const owner = a.hwnd orelse return;
    const monitor = win.MonitorFromWindow(owner, win.MONITOR_DEFAULTTONEAREST);
    var info = std.mem.zeroes(win.MONITORINFO);
    info.cbSize = @sizeOf(win.MONITORINFO);
    if (win.GetMonitorInfoW(monitor, &info) == 0) return;
    const work = info.rcWork;
    const hwnd = win.CreateWindowExW(0, lit("MessagesImageViewer"), lit("Messages · Image"), win.WS_POPUP, work.left, work.top, @max(1, work.right - work.left), @max(1, work.bottom - work.top), owner, null, a.instance, null) orelse return;
    a.image_viewer_window = hwnd;
    a.viewer_chat.set(a.chats[a.selected_chat].jid.slice());
    a.viewer_opened_ms = win.GetTickCount64();
    show(a, current, actions);
    if (a.viewer_failed and message.local_path.len > 0) {
        close(a);
        actions.openExternal(a, message);
        return;
    }
    _ = win.ShowWindow(hwnd, win.SW_SHOW);
    _ = win.SetForegroundWindow(hwnd);
    _ = win.SetFocus(hwnd);
}

fn navigate(a: anytype, direction: gallery.Direction, comptime actions: anytype) void {
    const selected = selection(a, actions) orelse return;
    const index = gallery.neighbour(selected, direction) orelse return;
    show(a, index, actions);
}

fn arrowRect(client: win.RECT, direction: gallery.Direction) win.RECT {
    const left = if (direction == .previous) 8 else client.right - 48;
    const top = @divTrunc(client.bottom, 2) - 24;
    return .{ .left = left, .top = top, .right = left + 40, .bottom = top + 48 };
}

fn contains(rect: win.RECT, x: i32, y: i32) bool {
    return x >= rect.left and x < rect.right and y >= rect.top and y < rect.bottom;
}

fn label(hdc: win.HDC, text: [*:0]const u16, rect: *win.RECT, enabled: bool) void {
    _ = win.SetTextColor(hdc, if (enabled) 0x00eeeeee else 0x00666666);
    _ = win.DrawTextW(hdc, text, -1, rect, win.DT_CENTER | win.DT_VCENTER | win.DT_SINGLELINE);
}

pub fn windowProc(a: anytype, hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, comptime actions: anytype) win.LRESULT {
    switch (message) {
        win.WM_ERASEBKGND => return 1,
        win.WM_PAINT => {
            var ps = win.PAINTSTRUCT{};
            const hdc = win.BeginPaint(hwnd, &ps);
            defer _ = win.EndPaint(hwnd, &ps);
            var client = std.mem.zeroes(win.RECT);
            _ = win.GetClientRect(hwnd, &client);
            if (win.CreateSolidBrush(0x00090909)) |brush| {
                _ = win.FillRect(hdc, &client, brush);
                _ = win.DeleteObject(brush);
            }
            if (a.viewer_bitmap) |bitmap| {
                if (win.CreateCompatibleDC(hdc)) |memory| {
                    const old = win.SelectObject(memory, bitmap);
                    _ = win.BitBlt(hdc, @divTrunc(client.right - a.viewer_width, 2), @divTrunc(client.bottom - a.viewer_height, 2), a.viewer_width, a.viewer_height, memory, 0, 0, win.SRCCOPY);
                    _ = win.SelectObject(memory, old);
                    _ = win.DeleteDC(memory);
                }
            }
            const old_font = if (a.font_small) |font| win.SelectObject(hdc, @ptrCast(font)) else null;
            defer {
                if (old_font) |font| _ = win.SelectObject(hdc, font);
            }
            _ = win.SetBkMode(hdc, win.TRANSPARENT);
            const selected = selection(a, actions);
            if (a.viewer_bitmap == null) {
                var status = client;
                label(hdc, if (a.viewer_failed) lit("Could not load image") else if (selected == null) lit("Image no longer in chat") else lit("Loading..."), &status, true);
            }
            if (selected) |item| {
                var left = arrowRect(client, .previous);
                var right = arrowRect(client, .next);
                label(hdc, lit("<"), &left, item.previous != null);
                label(hdc, lit(">"), &right, item.next != null);
                var buffer: [48]u8 = undefined;
                const counter = std.fmt.bufPrint(&buffer, "{d} / {d}", .{ item.position, item.total }) catch unreachable;
                var wide: [48:0]u16 = undefined;
                const length = std.unicode.utf8ToUtf16Le(&wide, counter) catch unreachable;
                wide[length] = 0;
                var rect = win.RECT{ .left = 56, .top = client.bottom - 40, .right = client.right - 56, .bottom = client.bottom - 8 };
                label(hdc, &wide, &rect, true);
            }
            return 0;
        },
        win.WM_LBUTTONDOWN, win.WM_LBUTTONDBLCLK => return 0,
        win.WM_LBUTTONUP => {
            var client = std.mem.zeroes(win.RECT);
            _ = win.GetClientRect(hwnd, &client);
            const x: i32 = @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lparam))))));
            const y: i32 = @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lparam)) >> 16))));
            inline for (.{ gallery.Direction.previous, gallery.Direction.next }) |direction| {
                if (contains(arrowRect(client, direction), x, y)) {
                    navigate(a, direction, actions);
                    return 0;
                }
            }
            // Do not let the opening double-click immediately close the popup.
            if (win.GetTickCount64() - a.viewer_opened_ms >= win.GetDoubleClickTime()) close(a);
            return 0;
        },
        win.WM_KEYDOWN => {
            if (wparam == win.VK_LEFT or wparam == win.VK_RIGHT) {
                navigate(a, if (wparam == win.VK_LEFT) .previous else .next, actions);
                return 0;
            }
            if (wparam == win.VK_ESCAPE or wparam == win.VK_SPACE or wparam == win.VK_RETURN) {
                close(a);
                return 0;
            }
        },
        win.WM_CLOSE => {
            close(a);
            return 0;
        },
        win.WM_DESTROY => {
            if (a.image_viewer_window != null and a.image_viewer_window.? == hwnd) {
                a.image_viewer_window = null;
                clearBitmap(a);
            }
            return 0;
        },
        else => {},
    }
    return win.DefWindowProcW(hwnd, message, wparam, lparam);
}

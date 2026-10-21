const std = @import("std");
const win = @import("win32.zig").c;
const text_draw = @import("text_draw.zig");
const theme = @import("theme.zig");

pub const class_name = std.unicode.utf8ToUtf16LeStringLiteral("RICHEDIT50W");
const property_name = std.unicode.utf8ToUtf16LeStringLiteral("Messages.DirectWriteEdit");
var module: win.HMODULE = null;

pub fn create(instance: win.HINSTANCE, parent: win.HWND, id: win.HMENU, style: u32, x: i32, y: i32, width: i32, height: i32) ?win.HWND {
    if (module == null) module = win.LoadLibraryExW(std.unicode.utf8ToUtf16LeStringLiteral("msftedit.dll"), null, win.LOAD_LIBRARY_SEARCH_SYSTEM32) orelse return null;
    const hwnd = win.CreateWindowExW(0, class_name, null, style, x, y, width, height, parent, id, instance, null) orelse return null;
    const host = std.heap.page_allocator.create(Host) catch {
        _ = win.DestroyWindow(hwnd);
        return null;
    };
    host.* = .{ .hwnd = hwnd };
    if (win.SetPropW(hwnd, property_name, host) == 0) {
        std.heap.page_allocator.destroy(host);
        _ = win.DestroyWindow(hwnd);
        return null;
    }
    const previous = win.SetWindowLongPtrW(hwnd, win.GWLP_WNDPROC, @bitCast(@intFromPtr(&windowProc)));
    host.previous = @ptrFromInt(@as(usize, @bitCast(previous)));
    _ = host.send(win.EM_SETTEXTMODE, win.TM_PLAINTEXT | win.TM_MULTILEVELUNDO, 0);
    _ = host.send(win.EM_SETEVENTMASK, 0, win.ENM_CHANGE | win.ENM_UPDATE);
    _ = host.send(win.EM_SETEDITSTYLE, win.SES_LOGICALCARET, win.SES_LOGICALCARET);
    return hwnd;
}

pub fn isComposing(hwnd: ?win.HWND) bool {
    const host = fromWindow(hwnd orelse return false) orelse return false;
    return host.composing;
}

pub fn contentHeight(hwnd: win.HWND, minimum: i32) i32 {
    const host = fromWindow(hwnd) orelse return minimum;
    const dc = win.GetDC(hwnd);
    defer _ = win.ReleaseDC(hwnd, dc);
    const saved = win.SaveDC(dc);
    defer _ = win.RestoreDC(dc, saved);
    _ = win.SelectObject(dc, host.font());
    const rect = host.textRect();
    var client: win.RECT = undefined;
    _ = win.GetClientRect(hwnd, &client);
    const lines = @max(1, host.send(win.EM_GETLINECOUNT, 0, 0));
    return @max(minimum, @as(i32, @intCast(lines)) * host.lineHeight(dc) + rect.top + client.bottom - rect.bottom);
}

const Host = struct {
    hwnd: win.HWND,
    previous: win.WNDPROC = null,
    composing: bool = false,
    cue: [256:0]u16 = @splat(0),
    cue_focused: bool = false,

    fn send(self: *Host, message: u32, wparam: usize, lparam: isize) win.LRESULT {
        return win.CallWindowProcW(self.previous, self.hwnd, message, wparam, lparam);
    }

    fn font(self: *Host) win.HFONT {
        return @ptrFromInt(@as(usize, @bitCast(self.send(win.WM_GETFONT, 0, 0))));
    }

    fn textRect(self: *Host) win.RECT {
        var rect: win.RECT = undefined;
        _ = self.send(win.EM_GETRECT, 0, @bitCast(@intFromPtr(&rect)));
        return rect;
    }

    fn position(self: *Host, index: usize) win.POINTL {
        var point = win.POINTL{ .x = 0, .y = 0 };
        _ = self.send(win.WM_USER + 38, @intFromPtr(&point), @intCast(index));
        return point;
    }

    fn lineHeight(self: *Host, dc: win.HDC) i32 {
        if (self.send(win.EM_GETLINECOUNT, 0, 0) > 1) {
            const next: usize = @intCast(self.send(win.EM_LINEINDEX, 1, 0));
            const delta = self.position(next).y - self.position(0).y;
            if (delta > 0) return delta;
        }
        var metrics: win.TEXTMETRICW = undefined;
        if (win.GetTextMetricsW(dc, &metrics) == 0) return 1;
        return @max(1, metrics.tmHeight);
    }

    fn setFont(self: *Host, wparam: usize, lparam: isize) win.LRESULT {
        const mask = self.send(win.EM_SETEVENTMASK, 0, 0);
        defer _ = self.send(win.EM_SETEVENTMASK, 0, mask);
        var ole: ?*Object = null;
        _ = self.send(win.EM_GETOLEINTERFACE, 0, @bitCast(@intFromPtr(&ole)));
        defer if (ole) |object| object.release();
        var document: ?*Object = null;
        if (ole) |object| _ = object.query(&iid_document, &document);
        defer if (document) |object| object.release();
        if (document) |object| object.undo(-9999995);
        defer if (document) |object| object.undo(-9999994);
        const modified = self.send(win.EM_GETMODIFY, 0, 0);
        const result = self.send(win.WM_SETFONT, wparam, lparam);
        _ = self.send(win.EM_SETMODIFY, @intCast(modified), 0);
        return result;
    }

    fn paint(self: *Host, dc: win.HDC) void {
        const saved = win.SaveDC(dc);
        defer _ = win.RestoreDC(dc, saved);
        _ = win.SetTextColor(dc, theme.current.on_surface);
        _ = win.SetBkColor(dc, theme.current.surface_container_high);
        _ = win.SendMessageW(win.GetParent(self.hwnd), win.WM_CTLCOLOREDIT, @intFromPtr(dc), @bitCast(@intFromPtr(self.hwnd)));
        const foreground = win.GetTextColor(dc);
        var client: win.RECT = undefined;
        _ = win.GetClientRect(self.hwnd, &client);
        _ = win.SetDCBrushColor(dc, win.GetBkColor(dc));
        _ = win.FillRect(dc, &client, @ptrCast(@alignCast(win.GetStockObject(win.DC_BRUSH))));
        _ = win.SelectObject(dc, self.font());
        _ = win.SetBkMode(dc, win.TRANSPARENT);
        const rect = self.textRect();
        _ = win.IntersectClipRect(dc, rect.left, rect.top, rect.right, rect.bottom);
        const length: usize = @intCast(self.send(win.WM_GETTEXTLENGTH, 0, 0));
        if (length == 0) {
            if (self.cue[0] != 0 and (self.cue_focused or win.GetFocus() != self.hwnd)) {
                _ = win.SetTextColor(dc, theme.current.on_surface_variant);
                var cue_rect = rect;
                _ = text_draw.drawText(dc, &self.cue, -1, &cue_rect, win.DT_SINGLELINE | win.DT_NOPREFIX | win.DT_END_ELLIPSIS);
            }
            return;
        }
        const text = std.heap.page_allocator.alloc(u16, length + 1) catch return;
        defer std.heap.page_allocator.free(text);
        const request = win.GETTEXTEX{ .cb = @intCast(text.len * 2), .flags = win.GT_DEFAULT, .codepage = 1200, .lpDefaultChar = null, .lpUsedDefChar = null };
        const count: usize = @intCast(self.send(win.EM_GETTEXTEX, @intFromPtr(&request), @bitCast(@intFromPtr(text.ptr))));
        var selection = win.CHARRANGE{ .cpMin = 0, .cpMax = 0 };
        _ = self.send(win.EM_EXGETSEL, 0, @bitCast(@intFromPtr(&selection)));
        const height = self.lineHeight(dc);
        const lines: usize = @intCast(self.send(win.EM_GETLINECOUNT, 0, 0));
        for (0..lines) |line| {
            const first: usize = @intCast(self.send(win.EM_LINEINDEX, line, 0));
            if (first > count) break;
            const size: usize = @intCast(self.send(win.EM_LINELENGTH, first, 0));
            const last = @min(count, first + size);
            const point = self.position(first);
            if (point.y + height <= rect.top) continue;
            if (point.y >= rect.bottom) break;
            var line_rect = win.RECT{ .left = point.x, .top = point.y, .right = @max(rect.right, point.x + 1), .bottom = point.y + height };
            _ = text_draw.drawText(dc, text.ptr + first, @intCast(last - first), &line_rect, win.DT_SINGLELINE | win.DT_NOPREFIX | win.DT_NOCLIP);
            const start = @max(first, @as(usize, @intCast(@max(0, selection.cpMin))));
            const end = @min(last, @as(usize, @intCast(@max(0, selection.cpMax))));
            if (end > start and (win.GetFocus() == self.hwnd or win.GetWindowLongPtrW(self.hwnd, win.GWL_STYLE) & win.ES_NOHIDESEL != 0)) {
                const left = self.position(start).x;
                const end_point = self.position(end);
                var measured = line_rect;
                _ = text_draw.drawText(dc, text.ptr + first, @intCast(last - first), &measured, win.DT_SINGLELINE | win.DT_NOPREFIX | win.DT_CALCRECT);
                const right = if (end_point.y == point.y) end_point.x else measured.right;
                const selected = win.RECT{ .left = left, .top = point.y, .right = @max(left + 1, right), .bottom = point.y + height };
                _ = win.SetDCBrushColor(dc, theme.current.primary_container);
                _ = win.FillRect(dc, &selected, @ptrCast(@alignCast(win.GetStockObject(win.DC_BRUSH))));
                const selection_dc = win.SaveDC(dc);
                _ = win.IntersectClipRect(dc, selected.left, selected.top, selected.right, selected.bottom);
                _ = win.SetTextColor(dc, theme.current.on_primary_container);
                _ = text_draw.drawText(dc, text.ptr + first, @intCast(last - first), &line_rect, win.DT_SINGLELINE | win.DT_NOPREFIX | win.DT_NOCLIP);
                _ = win.RestoreDC(dc, selection_dc);
                _ = win.SetTextColor(dc, foreground);
            }
        }
    }

    fn contextMenu(self: *Host, lparam: isize) void {
        _ = win.SetFocus(self.hwnd);
        var point = win.POINT{ .x = @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lparam)))))), .y = @as(i16, @bitCast(@as(u16, @truncate(@as(usize, @bitCast(lparam)) >> 16)))) };
        if (lparam == -1) {
            _ = win.GetCaretPos(&point);
            _ = win.ClientToScreen(self.hwnd, &point);
        }
        const menu = win.CreatePopupMenu() orelse return;
        defer _ = win.DestroyMenu(menu);
        var selection = win.CHARRANGE{ .cpMin = 0, .cpMax = 0 };
        _ = self.send(win.EM_EXGETSEL, 0, @bitCast(@intFromPtr(&selection)));
        const selected = selection.cpMin != selection.cpMax;
        const editable = win.IsWindowEnabled(self.hwnd) != 0 and self.send(win.EM_GETOPTIONS, 0, 0) & win.ECO_READONLY == 0;
        const items = .{
            .{ "Undo", win.EM_UNDO, editable and self.send(win.EM_CANUNDO, 0, 0) != 0 },
            .{ "Cut", win.WM_CUT, editable and selected },
            .{ "Copy", win.WM_COPY, selected },
            .{ "Paste", win.WM_PASTE, editable and self.send(win.EM_CANPASTE, win.CF_UNICODETEXT, 0) != 0 },
            .{ "Select all", win.EM_SETSEL, self.send(win.WM_GETTEXTLENGTH, 0, 0) > 0 },
        };
        inline for (items) |item| _ = win.AppendMenuW(menu, win.MF_STRING | @as(u32, if (item[2]) win.MF_ENABLED else win.MF_GRAYED), item[1], std.unicode.utf8ToUtf16LeStringLiteral(item[0]));
        const choice = win.TrackPopupMenu(menu, win.TPM_RETURNCMD | win.TPM_NONOTIFY | win.TPM_RIGHTBUTTON, point.x, point.y, 0, self.hwnd, null);
        if (choice != 0) _ = win.SendMessageW(self.hwnd, @intCast(choice), 0, if (choice == win.EM_SETSEL) -1 else 0);
    }
};

fn fromWindow(hwnd: win.HWND) ?*Host {
    return @ptrCast(@alignCast(win.GetPropW(hwnd, property_name)));
}

fn windowProc(hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    const host = fromWindow(hwnd) orelse return win.DefWindowProcW(hwnd, message, wparam, lparam);
    switch (message) {
        win.WM_NCDESTROY => {
            const previous = host.previous;
            _ = win.RemovePropW(hwnd, property_name);
            std.heap.page_allocator.destroy(host);
            return win.CallWindowProcW(previous, hwnd, message, wparam, lparam);
        },
        win.WM_PAINT => {
            var ps: win.PAINTSTRUCT = undefined;
            const dc = win.BeginPaint(hwnd, &ps);
            defer _ = win.EndPaint(hwnd, &ps);
            _ = win.HideCaret(hwnd);
            defer _ = win.ShowCaret(hwnd);
            host.paint(dc);
            return 0;
        },
        win.WM_PRINTCLIENT => {
            host.paint(@ptrFromInt(wparam));
            return 0;
        },
        win.WM_ERASEBKGND => return 1,
        win.WM_CONTEXTMENU => {
            host.contextMenu(lparam);
            return 0;
        },
        win.WM_SETFONT => return host.setFont(wparam, lparam),
        win.WM_IME_STARTCOMPOSITION => host.composing = true,
        win.WM_IME_ENDCOMPOSITION, win.WM_KILLFOCUS => host.composing = false,
        win.EM_SETCUEBANNER => {
            const input: [*:0]const u16 = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const count = @min(std.mem.len(input), host.cue.len - 1);
            @memcpy(host.cue[0..count], input[0..count]);
            host.cue[count] = 0;
            host.cue_focused = wparam != 0;
            _ = win.InvalidateRect(hwnd, null, win.FALSE);
            return 1;
        },
        win.EM_POSFROMCHAR => {
            const point = host.position(wparam);
            const x: u16 = @bitCast(@as(i16, @intCast(std.math.clamp(point.x, -32768, 32767))));
            const y: u16 = @bitCast(@as(i16, @intCast(std.math.clamp(point.y, -32768, 32767))));
            return @as(isize, x) | (@as(isize, y) << 16);
        },
        win.WM_GETTEXTLENGTH => {
            const request = win.GETTEXTLENGTHEX{ .flags = win.GTL_PRECISE | win.GTL_NUMCHARS, .codepage = 1200 };
            return host.send(win.EM_GETTEXTLENGTHEX, @intFromPtr(&request), 0);
        },
        win.WM_GETTEXT => {
            if (wparam == 0) return 0;
            const request = win.GETTEXTEX{ .cb = @intCast(@min(wparam, 0x7fffffff) * 2), .flags = win.GT_DEFAULT, .codepage = 1200, .lpDefaultChar = null, .lpUsedDefChar = null };
            const count = host.send(win.EM_GETTEXTEX, @intFromPtr(&request), lparam);
            if (count > 0) {
                const text: [*]u16 = @ptrFromInt(@as(usize, @bitCast(lparam)));
                for (text[0..@intCast(count)]) |*unit| if (unit.* == '\r') {
                    unit.* = '\n';
                };
            }
            return count;
        },
        else => {},
    }
    return host.send(message, wparam, lparam);
}

const iid_document = win.GUID{ .Data1 = 0x8cc497c0, .Data2 = 0xa1df, .Data3 = 0x11ce, .Data4 = .{ 0x80, 0x98, 0, 0xaa, 0, 0x47, 0xbe, 0x5d } };
const Object = extern struct {
    vtable: [*]const *const anyopaque,

    fn release(self: *Object) void {
        const call: *const fn (*Object) callconv(.winapi) u32 = @ptrCast(self.vtable[2]);
        _ = call(self);
    }
    fn query(self: *Object, iid: *const win.GUID, out: *?*Object) win.HRESULT {
        const call: *const fn (*Object, *const win.GUID, *?*Object) callconv(.winapi) win.HRESULT = @ptrCast(self.vtable[0]);
        return call(self, iid, out);
    }
    fn undo(self: *Object, count: i32) void {
        const call: *const fn (*Object, i32, ?*i32) callconv(.winapi) win.HRESULT = @ptrCast(self.vtable[22]);
        _ = call(self, count, null);
    }
};

test "IGSH-466 native DirectWrite host maps text selection undo rectangles limits and rendering" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    if (win.OleInitialize(null) < 0) return error.OleInitializeFailed;
    defer win.OleUninitialize();
    const instance = win.GetModuleHandleW(null);
    const font_files = @import("font_config.zig").files;
    var paths: [font_files.len][1024:0]u16 = undefined;
    var pointers: [font_files.len][*:0]const u16 = undefined;
    inline for (font_files, 0..) |file, i| {
        const count = win.GetFullPathNameW(std.unicode.utf8ToUtf16LeStringLiteral("assets\\" ++ file), paths[i].len, &paths[i], null);
        try std.testing.expect(count > 0 and count < paths[i].len);
        try std.testing.expect(win.AddFontResourceExW(&paths[i], win.FR_PRIVATE, null) > 0);
        pointers[i] = &paths[i];
    }
    defer {
        text_draw.reset();
        for (&paths) |*path| _ = win.RemoveFontResourceExW(path, win.FR_PRIVATE, null);
    }
    text_draw.setBundledFontPaths(&pointers);
    const parent = win.CreateWindowExW(0, std.unicode.utf8ToUtf16LeStringLiteral("STATIC"), null, win.WS_POPUP | win.WS_VISIBLE, 0, 0, 320, 200, null, null, instance, null) orelse return error.CreateWindowFailed;
    defer _ = win.DestroyWindow(parent);
    _ = win.SetWindowLongPtrW(parent, win.GWLP_WNDPROC, @bitCast(@intFromPtr(&testParentProc)));
    const edit = create(instance, parent, null, win.WS_CHILD | win.WS_VISIBLE | win.ES_MULTILINE | win.ES_AUTOVSCROLL, 0, 0, 200, 80) orelse return error.CreateEditFailed;
    defer _ = win.DestroyWindow(edit);
    const host = fromWindow(edit).?;
    _ = win.SetWindowLongPtrW(edit, win.GWLP_ID, 1);
    try std.testing.expect(!isComposing(parent));
    try std.testing.expect(!isComposing(null));
    var name: [64]u16 = undefined;
    const name_len: usize = @intCast(win.GetClassNameW(edit, &name, name.len));
    try std.testing.expectEqualSlices(u16, class_name, name[0..name_len]);
    const font = win.CreateFontW(-17, 0, 0, 0, @import("font_config.zig").body_weight, 0, 0, 0, win.DEFAULT_CHARSET, win.OUT_DEFAULT_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_NATURAL_QUALITY, win.DEFAULT_PITCH, std.unicode.utf8ToUtf16LeStringLiteral("IBM Plex Sans")) orelse return error.CreateFontFailed;
    defer _ = win.DeleteObject(font);
    _ = win.SendMessageW(edit, win.WM_SETFONT, @intFromPtr(font), 1);
    try std.testing.expectEqual(@as(win.LRESULT, @bitCast(@intFromPtr(font))), win.SendMessageW(edit, win.WM_GETFONT, 0, 0));
    var format = std.mem.zeroes(win.CHARFORMAT2W);
    format.cbSize = @sizeOf(win.CHARFORMAT2W);
    _ = host.send(win.EM_GETCHARFORMAT, win.SCF_DEFAULT, @bitCast(@intFromPtr(&format)));
    try std.testing.expectEqual(@as(u16, 500), format.wWeight);
    try std.testing.expectEqual(@as(i32, 255), format.yHeight);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("IBM Plex Sans"), std.mem.sliceTo(&format.szFaceName, 0));
    const text = std.unicode.utf8ToUtf16LeStringLiteral("one\r\ntwo😀");
    _ = win.SetWindowTextW(edit, text);
    var buffer: [256]u16 = undefined;
    const count: usize = @intCast(win.GetWindowTextW(edit, &buffer, buffer.len));
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("one\ntwo😀"), buffer[0..count]);
    try std.testing.expectEqual(@as(i32, @intCast(count)), win.GetWindowTextLengthW(edit));
    _ = win.SendMessageW(edit, win.EM_SETSEL, 4, 7);
    const replacement = std.unicode.utf8ToUtf16LeStringLiteral("more");
    _ = win.SendMessageW(edit, win.EM_REPLACESEL, 1, @bitCast(@intFromPtr(replacement)));
    var start: u32 = 0;
    var end: u32 = 0;
    _ = win.SendMessageW(edit, win.EM_GETSEL, @intFromPtr(&start), @bitCast(@intFromPtr(&end)));
    try std.testing.expectEqual(@as(u32, 8), start);
    try std.testing.expectEqual(start, end);
    try std.testing.expect(win.SendMessageW(edit, win.EM_UNDO, 0, 0) != 0);
    try std.testing.expect(win.SendMessageW(edit, win.EM_REDO, 0, 0) != 0);
    _ = win.SendMessageW(edit, win.EM_EMPTYUNDOBUFFER, 0, 0);
    try std.testing.expectEqual(@as(isize, 0), win.SendMessageW(edit, win.EM_CANUNDO, 0, 0));
    _ = win.SendMessageW(edit, win.EM_SETSEL, 0, -1);
    _ = win.SendMessageW(edit, win.WM_COPY, 0, 0);
    try std.testing.expect(win.SendMessageW(edit, win.EM_CANPASTE, win.CF_UNICODETEXT, 0) != 0);
    _ = win.SendMessageW(edit, win.WM_CUT, 0, 0);
    try std.testing.expectEqual(@as(i32, 0), win.GetWindowTextLengthW(edit));
    _ = win.SendMessageW(edit, win.WM_PASTE, 0, 0);
    const pasted: usize = @intCast(win.GetWindowTextW(edit, &buffer, buffer.len));
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("one\nmore😀"), buffer[0..pasted]);
    var rect = win.RECT{ .left = 2, .top = 8, .right = 198, .bottom = 72 };
    _ = win.SendMessageW(edit, win.EM_SETRECTNP, 0, @bitCast(@intFromPtr(&rect)));
    var actual: win.RECT = undefined;
    _ = win.SendMessageW(edit, win.EM_GETRECT, 0, @bitCast(@intFromPtr(&actual)));
    try std.testing.expectEqualDeep(rect, actual);
    const position: usize = @bitCast(win.SendMessageW(edit, win.EM_POSFROMCHAR, 4, 0));
    try std.testing.expect(@as(i16, @bitCast(@as(u16, @truncate(position)))) >= rect.left);
    try std.testing.expect(@as(i16, @bitCast(@as(u16, @truncate(position >> 16)))) >= rect.top);
    try std.testing.expect(win.SendMessageW(edit, win.EM_GETLINECOUNT, 0, 0) >= 2);
    _ = win.SendMessageW(edit, win.EM_LINESCROLL, 0, 1);
    try std.testing.expect(win.SendMessageW(edit, win.EM_GETFIRSTVISIBLELINE, 0, 0) >= 0);
    _ = win.SendMessageW(edit, win.EM_SCROLLCARET, 0, 0);
    _ = win.SendMessageW(edit, win.EM_SETMARGINS, win.EC_LEFTMARGIN | win.EC_RIGHTMARGIN, 4 | (6 << 16));
    try std.testing.expectEqual(@as(isize, 4 | (6 << 16)), win.SendMessageW(edit, win.EM_GETMARGINS, 0, 0));
    _ = win.SendMessageW(edit, win.EM_SETRECTNP, 0, @bitCast(@intFromPtr(&rect)));
    _ = win.SendMessageW(edit, win.EM_SETLIMITTEXT, 128, 0);
    try std.testing.expectEqual(@as(isize, 128), host.send(win.EM_GETLIMITTEXT, 0, 0));
    const cue = std.unicode.utf8ToUtf16LeStringLiteral("Filter");
    _ = win.SendMessageW(edit, win.EM_SETCUEBANNER, 1, @bitCast(@intFromPtr(cue)));
    try std.testing.expectEqualSlices(u16, cue, std.mem.sliceTo(&host.cue, 0));
    _ = win.SetWindowTextW(edit, std.unicode.utf8ToUtf16LeStringLiteral("one two three four five six seven eight nine ten"));
    const wide_height = contentHeight(edit, 1);
    _ = win.MoveWindow(edit, 0, 0, 70, 80, 0);
    const narrow_height = contentHeight(edit, 1);
    try std.testing.expect(narrow_height > wide_height);
    _ = win.MoveWindow(edit, 0, 0, 200, 80, 0);
    try std.testing.expectEqual(wide_height, contentHeight(edit, 1));
    const dc = win.CreateCompatibleDC(null) orelse return error.CreateDCFailed;
    defer _ = win.DeleteDC(dc);
    var info = std.mem.zeroes(win.BITMAPINFO);
    info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    info.bmiHeader.biWidth = 200;
    info.bmiHeader.biHeight = -80;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    var bits: ?*anyopaque = null;
    const bitmap = win.CreateDIBSection(dc, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse return error.CreateBitmapFailed;
    defer _ = win.DeleteObject(bitmap);
    const old = win.SelectObject(dc, bitmap);
    defer _ = win.SelectObject(dc, old);
    const pixels = @as([*]u32, @ptrCast(@alignCast(bits.?)))[0 .. 200 * 80];
    @memset(pixels, 0xffffffff);
    _ = win.SendMessageW(edit, win.WM_PRINTCLIENT, @intFromPtr(dc), win.PRF_CLIENT);
    _ = win.GdiFlush();
    try std.testing.expect(text_draw.directwrite);
    const colour = theme.current.surface_container_high;
    const background = ((colour & 255) << 16) | (colour & 0xff00) | ((colour >> 16) & 255);
    try std.testing.expectEqual(background, pixels[0] & 0xffffff);
    var ink: usize = 0;
    for (pixels) |pixel| {
        if (pixel & 0xffffff != background) ink += 1;
    }
    try std.testing.expect(ink > 100);

    _ = win.SetWindowTextW(edit, std.unicode.utf8ToUtf16LeStringLiteral("before"));
    _ = win.SendMessageW(edit, win.EM_SETSEL, 6, 6);
    _ = win.SendMessageW(edit, win.EM_REPLACESEL, 1, @bitCast(@intFromPtr(std.unicode.utf8ToUtf16LeStringLiteral(" after"))));
    const changes_before_style = test_changes;
    _ = win.SendMessageW(edit, win.WM_SETFONT, @intFromPtr(font), 1);
    theme.set(.green);
    _ = win.SendMessageW(edit, win.WM_PRINTCLIENT, @intFromPtr(dc), win.PRF_CLIENT);
    try std.testing.expectEqual(changes_before_style, test_changes);
    try std.testing.expect(win.SendMessageW(edit, win.EM_UNDO, 0, 0) != 0);
    const undone: usize = @intCast(win.GetWindowTextW(edit, &buffer, buffer.len));
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("before"), buffer[0..undone]);
    const changes_before_set = test_changes;
    _ = win.SetWindowTextW(edit, std.unicode.utf8ToUtf16LeStringLiteral("accessible value"));
    try std.testing.expectEqual(changes_before_set + 1, test_changes);
    test_revert = true;
    _ = win.SetWindowTextW(edit, std.unicode.utf8ToUtf16LeStringLiteral("rejected"));
    try std.testing.expectEqual(changes_before_set + 3, test_changes);
    const reverted: usize = @intCast(win.GetWindowTextW(edit, &buffer, buffer.len));
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("accessible value"), buffer[0..reverted]);
    const iid_accessible = win.GUID{ .Data1 = 0x618736e0, .Data2 = 0x3c3d, .Data3 = 0x11cf, .Data4 = .{ 0x81, 0x0c, 0, 0xaa, 0, 0x38, 0x9b, 0x71 } };
    var accessible: ?*Object = null;
    try std.testing.expect(win.AccessibleObjectFromWindow(edit, @bitCast(@as(i32, -4)), &iid_accessible, @ptrCast(&accessible)) >= 0);
    const provider = accessible orelse return error.MissingAccessibleProvider;
    defer provider.release();
    var child = std.mem.zeroes(win.VARIANT);
    @as(*u16, @ptrCast(&child)).* = win.VT_I4;
    var value: win.BSTR = null;
    const get_value: *const fn (*Object, win.VARIANT, *win.BSTR) callconv(.winapi) win.HRESULT = @ptrCast(provider.vtable[11]);
    try std.testing.expect(get_value(provider, child, &value) >= 0);
    defer win.SysFreeString(value);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("accessible value"), std.mem.span(value));
    _ = win.SetFocus(edit);
    var gui = std.mem.zeroes(win.GUITHREADINFO);
    gui.cbSize = @sizeOf(win.GUITHREADINFO);
    try std.testing.expect(win.GetGUIThreadInfo(0, &gui) != 0);
    try std.testing.expectEqual(edit, gui.hwndCaret);
    _ = win.InvalidateRect(edit, null, win.FALSE);
    _ = win.UpdateWindow(edit);
    try std.testing.expectEqual(@as(win.BOOL, 0), win.GetUpdateRect(edit, null, win.FALSE));

    const sample = std.unicode.utf8ToUtf16LeStringLiteral("Plex agQW 0123");
    const rendered = try std.testing.allocator.alloc(u32, pixels.len);
    defer std.testing.allocator.free(rendered);
    for ([_]i32{ 96, 144 }) |dpi| {
        const scaled_font = win.CreateFontW(-@divTrunc(17 * dpi + 48, 96), 0, 0, 0, @import("font_config.zig").body_weight, 0, 0, 0, win.DEFAULT_CHARSET, win.OUT_DEFAULT_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_NATURAL_QUALITY, win.DEFAULT_PITCH, std.unicode.utf8ToUtf16LeStringLiteral("IBM Plex Sans")) orelse return error.CreateFontFailed;
        defer _ = win.DeleteObject(scaled_font);
        _ = win.SendMessageW(edit, win.WM_SETFONT, @intFromPtr(scaled_font), 1);
        _ = win.SetWindowTextW(edit, sample);
        _ = win.SendMessageW(edit, win.EM_SETSEL, 0, 0);
        _ = win.SendMessageW(edit, win.EM_LINESCROLL, 0, -100);
        const origin = host.position(0);
        for ([_]theme.Choice{ .green, .amoled }) |choice| {
            theme.set(choice);
            _ = win.SendMessageW(edit, win.WM_PRINTCLIENT, @intFromPtr(dc), win.PRF_CLIENT);
            _ = win.GdiFlush();
            @memcpy(rendered, pixels);
            const saved = win.SaveDC(dc);
            _ = win.SelectObject(dc, scaled_font);
            _ = win.SetBkMode(dc, win.TRANSPARENT);
            _ = win.SetTextColor(dc, theme.current.on_surface);
            _ = win.SetDCBrushColor(dc, theme.current.surface_container_high);
            const client = win.RECT{ .left = 0, .top = 0, .right = 200, .bottom = 80 };
            _ = win.FillRect(dc, &client, @ptrCast(@alignCast(win.GetStockObject(win.DC_BRUSH))));
            const clip = host.textRect();
            _ = win.IntersectClipRect(dc, clip.left, clip.top, clip.right, clip.bottom);
            var reference_rect = win.RECT{ .left = origin.x, .top = origin.y, .right = clip.right, .bottom = origin.y + host.lineHeight(dc) };
            _ = text_draw.drawText(dc, sample, sample.len, &reference_rect, win.DT_SINGLELINE | win.DT_NOPREFIX | win.DT_NOCLIP);
            _ = win.GdiFlush();
            try std.testing.expect(text_draw.directwrite);
            const bg = rgbPixel(theme.current.surface_container_high);
            var ink_count: usize = 0;
            var left: usize = 200;
            var right: usize = 0;
            for (rendered, pixels, 0..) |actual_pixel, reference_pixel, i| {
                try std.testing.expectEqual(reference_pixel & 0xffffff, actual_pixel & 0xffffff);
                if (actual_pixel & 0xffffff != bg) {
                    ink_count += 1;
                    left = @min(left, i % 200);
                    right = @max(right, i % 200);
                }
            }
            try std.testing.expect(ink_count > 100);
            try std.testing.expect(right - left > 70);
            const wrong_font = win.CreateFontW(-@divTrunc(17 * dpi + 48, 96), 0, 0, 0, 500, 0, 0, 0, win.DEFAULT_CHARSET, win.OUT_DEFAULT_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_NATURAL_QUALITY, win.DEFAULT_PITCH, std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI")) orelse return error.CreateFontFailed;
            _ = win.SelectObject(dc, wrong_font);
            _ = win.FillRect(dc, &client, @ptrCast(@alignCast(win.GetStockObject(win.DC_BRUSH))));
            _ = text_draw.drawText(dc, sample, sample.len, &reference_rect, win.DT_SINGLELINE | win.DT_NOPREFIX | win.DT_NOCLIP);
            _ = win.GdiFlush();
            var different: usize = 0;
            for (rendered, pixels) |actual_pixel, wrong_pixel| {
                if (actual_pixel & 0xffffff != wrong_pixel & 0xffffff) different += 1;
            }
            try std.testing.expect(different > 100);
            _ = win.RestoreDC(dc, saved);
            _ = win.DeleteObject(wrong_font);
        }
        _ = win.SetWindowTextW(edit, std.unicode.utf8ToUtf16LeStringLiteral("Plex\r\nPlex"));
        const next: usize = @intCast(host.send(win.EM_LINEINDEX, 1, 0));
        const line_height = host.position(next).y - host.position(0).y;
        try std.testing.expect(line_height >= @divTrunc(17 * dpi, 96));
        var client: win.RECT = undefined;
        _ = win.GetClientRect(edit, &client);
        const text_rect = host.textRect();
        try std.testing.expectEqual(2 * line_height + text_rect.top + client.bottom - text_rect.bottom, contentHeight(edit, 1));
        _ = win.SendMessageW(edit, win.WM_PRINTCLIENT, @intFromPtr(dc), win.PRF_CLIENT);
        _ = win.GdiFlush();
        var top: usize = 80;
        var bottom: usize = 0;
        for (pixels, 0..) |pixel, i| {
            if (pixel & 0xffffff != rgbPixel(theme.current.surface_container_high)) {
                top = @min(top, i / 200);
                bottom = @max(bottom, i / 200);
            }
        }
        try std.testing.expect(bottom - top > @as(usize, @intCast(line_height)));
        try std.testing.expect(bottom - top < @as(usize, @intCast(contentHeight(edit, 1))));
        _ = win.SendMessageW(edit, win.WM_SETFONT, @intFromPtr(font), 0);
    }
    std.debug.print("IGSH-466 font pixel equality, fallback negative control and 96/144 DPI ink/content-height passed\n", .{});
}

fn rgbPixel(colour: win.COLORREF) u32 {
    return ((colour & 255) << 16) | (colour & 0xff00) | ((colour >> 16) & 255);
}

var test_changes: usize = 0;
var test_revert = false;

fn testParentProc(hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    if (message == win.WM_COMMAND and (wparam >> 16) & 0xffff == win.EN_CHANGE) {
        test_changes += 1;
        if (test_revert) {
            test_revert = false;
            _ = win.SetWindowTextW(@ptrFromInt(@as(usize, @bitCast(lparam))), std.unicode.utf8ToUtf16LeStringLiteral("accessible value"));
        }
        return 0;
    }
    if (message == win.WM_CTLCOLOREDIT) {
        const dc: win.HDC = @ptrFromInt(wparam);
        _ = win.SetTextColor(dc, theme.current.on_surface);
        _ = win.SetBkColor(dc, theme.current.surface_container_high);
        return @bitCast(@intFromPtr(win.GetStockObject(win.BLACK_BRUSH)));
    }
    return win.DefWindowProcW(hwnd, message, wparam, lparam);
}

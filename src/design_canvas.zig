const win = @import("win32.zig").c;
const design = @import("design_tokens.zig");
const smooth = @import("smooth_shapes.zig");

hdc: win.HDC,
shapes: *const smooth.Context,

pub fn roundRect(self: *@This(), rect: design.Rect, radius: i32, color: u32) void {
    smooth.fillRoundRect(self.shapes, @bitCast(rect), radius * 2, radius * 2, color);
}

pub fn clip(self: *@This(), rect: design.Rect) i32 {
    const saved = win.SaveDC(self.hdc);
    _ = win.IntersectClipRect(self.hdc, rect.left, rect.top, rect.right, rect.bottom);
    return saved;
}

pub fn restore(self: *@This(), saved: i32) void {
    _ = win.RestoreDC(self.hdc, saved);
}

pub fn bubbleFill(self: *@This(), rect: design.Rect, radius: i32, color: u32, round_top: bool, round_bottom: bool) void {
    if (round_top and round_bottom) return self.roundRect(rect, radius, color);
    const saved = self.clip(rect);
    defer self.restore(saved);
    var extended = rect;
    if (!round_top) extended.top -= 2 * radius + 2;
    if (!round_bottom) extended.bottom += 2 * radius + 2;
    self.roundRect(extended, radius, color);
}

pub fn label(self: *@This(), rect: design.Rect, text: []const u16, height: i32, ink: u32) void {
    const face = @import("std").unicode.utf8ToUtf16LeStringLiteral(design.font_face);
    const font = win.CreateFontW(-height, 0, 0, 0, win.FW_MEDIUM, 0, 0, 0, win.DEFAULT_CHARSET, win.OUT_DEFAULT_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_NATURAL_QUALITY, win.DEFAULT_PITCH, face);
    const old_font = win.SelectObject(self.hdc, @ptrCast(font));
    defer {
        _ = win.SelectObject(self.hdc, old_font);
        _ = win.DeleteObject(@ptrCast(font));
    }
    _ = win.SetBkMode(self.hdc, win.TRANSPARENT);
    _ = win.SetTextColor(self.hdc, ink);
    var bounds: win.RECT = @bitCast(rect);
    _ = @import("text_draw.zig").drawText(self.hdc, text.ptr, @intCast(text.len), &bounds, win.DT_SINGLELINE | win.DT_VCENTER | win.DT_NOPREFIX);
}

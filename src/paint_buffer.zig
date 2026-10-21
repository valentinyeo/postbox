const win = @import("win32.zig").c;

pub const Buffer = struct {
    hdc: win.HDC,
    target: win.HDC,
    rect: win.RECT,
    bitmap: win.HBITMAP = null,
    previous: win.HGDIOBJ = null,

    pub fn init(target: win.HDC, client: win.RECT, dirty: win.RECT) Buffer {
        const rect = win.RECT{
            .left = @max(client.left, dirty.left),
            .top = @max(client.top, dirty.top),
            .right = @min(client.right, dirty.right),
            .bottom = @min(client.bottom, dirty.bottom),
        };
        var result = Buffer{ .hdc = target, .target = target, .rect = rect };
        if (rect.right <= rect.left or rect.bottom <= rect.top) return result;
        const memory = win.CreateCompatibleDC(target) orelse return result;
        const bitmap = win.CreateCompatibleBitmap(target, client.right, client.bottom) orelse {
            _ = win.DeleteDC(memory);
            return result;
        };
        const previous = win.SelectObject(memory, bitmap) orelse {
            _ = win.DeleteObject(bitmap);
            _ = win.DeleteDC(memory);
            return result;
        };
        if (win.IntersectClipRect(memory, rect.left, rect.top, rect.right, rect.bottom) == win.ERROR) {
            _ = win.SelectObject(memory, previous);
            _ = win.DeleteObject(bitmap);
            _ = win.DeleteDC(memory);
            return result;
        }
        result.hdc = memory;
        result.bitmap = bitmap;
        result.previous = previous;
        return result;
    }

    pub fn deinit(self: *Buffer) void {
        if (self.bitmap == null) return;
        const rect = self.rect;
        _ = win.BitBlt(self.target, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, self.hdc, rect.left, rect.top, win.SRCCOPY);
        _ = win.SelectObject(self.hdc, self.previous);
        _ = win.DeleteObject(self.bitmap);
        _ = win.DeleteDC(self.hdc);
        self.bitmap = null;
    }
};

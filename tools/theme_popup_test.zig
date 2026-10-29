const std = @import("std");
const theme = @import("theme.zig");

const win = struct {
    const HWND = usize;
    const RECT = struct { left: i32, top: i32, right: i32, bottom: i32 };
    var focus: ?HWND = null;

    fn GetFocus() ?HWND {
        return focus;
    }

    fn GetWindowRect(hwnd: HWND, rect: *RECT) i32 {
        std.debug.assert(hwnd == 2);
        rect.* = .{ .left = 110, .top = 220, .right = 210, .bottom = 248 };
        return 1;
    }

    fn MapWindowPoints(from: ?HWND, owner: HWND, rect: *RECT, count: u32) i32 {
        std.debug.assert(from == null and owner == 1 and count == 2);
        rect.left -= 100;
        rect.right -= 100;
        rect.top -= 200;
        rect.bottom -= 200;
        return 1;
    }

    fn InflateRect(rect: *RECT, x: i32, y: i32) i32 {
        rect.left -= x;
        rect.right += x;
        rect.top -= y;
        rect.bottom += y;
        return 1;
    }
};

const smooth = struct {
    const Context = struct {};
    var fill: ?u32 = null;
    var border: ?u32 = null;
    var bounds: ?win.RECT = null;

    fn fillRoundRect(_: *const Context, rect: win.RECT, width: i32, height: i32, color: u32) void {
        std.debug.assert(width == 8 and height == 8);
        fill = color;
        bounds = rect;
    }

    fn strokeRoundRect(_: *const Context, rect: win.RECT, width: i32, height: i32, color: u32, thickness: i32) void {
        std.debug.assert(width == 8 and height == 8 and thickness == 1);
        std.debug.assert(std.meta.eql(bounds.?, rect));
        border = color;
    }
};

test "IGSH-461 AMOLED popup input keeps its raised fill and follows focus in both directions" {
    theme.set(.amoled);
    defer theme.set(.amoled);
    const context = smooth.Context{};
    for ([_]?win.HWND{ null, 2, 3, 2, null }) |focus| {
        win.focus = focus;
        paintPopupInput(&context, 1, 2);
        try std.testing.expectEqual(theme.amoled.surface_container, smooth.fill.?);
        try std.testing.expectEqual(if (focus == 2) theme.amoled.primary else theme.amoled.outline, smooth.border.?);
        try std.testing.expectEqualDeep(win.RECT{ .left = 6, .top = 16, .right = 114, .bottom = 52 }, smooth.bounds.?);
    }
}

test "IGSH-461 missing popup input is not painted" {
    theme.set(.amoled);
    defer theme.set(.amoled);
    smooth.fill = null;
    smooth.border = null;
    const context = smooth.Context{};
    paintPopupInput(&context, 1, null);
    try std.testing.expectEqual(@as(?u32, null), smooth.fill);
    try std.testing.expectEqual(@as(?u32, null), smooth.border);
}

pub const height: i32 = 90;

pub const Rect = struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const Layout = struct {
    title: Rect,
    line: Rect,
    button: Rect,
    close: Rect,
    bar: Rect,
};

pub fn compute(card: Rect, dpi: i32) Layout {
    return .{
        .title = .{ .left = card.left + scale(12, dpi), .top = card.top + scale(8, dpi), .right = card.right - scale(32, dpi), .bottom = card.top + scale(30, dpi) },
        .line = .{ .left = card.left + scale(12, dpi), .top = card.top + scale(30, dpi), .right = card.right - scale(12, dpi), .bottom = card.top + scale(50, dpi) },
        .button = .{ .left = card.left + scale(12, dpi), .top = card.bottom - scale(36, dpi), .right = card.left + scale(124, dpi), .bottom = card.bottom - scale(10, dpi) },
        .close = .{ .left = card.right - scale(28, dpi), .top = card.top + scale(4, dpi), .right = card.right - scale(4, dpi), .bottom = card.top + scale(28, dpi) },
        .bar = .{ .left = card.left + scale(12, dpi), .top = card.bottom - scale(22, dpi), .right = card.right - scale(12, dpi), .bottom = card.bottom - scale(14, dpi) },
    };
}

pub fn scale(v: i32, dpi: i32) i32 {
    return @divTrunc(v * dpi + 48, 96);
}

fn overlaps(a: Rect, b: Rect) bool {
    return a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom;
}

fn inside(r: Rect, card: Rect) bool {
    return r.left >= card.left and r.right <= card.right and r.top >= card.top and r.bottom <= card.bottom;
}

test "IGSH-500 update card text never overlaps the button at any scale" {
    const std = @import("std");
    for ([_]i32{ 96, 120, 144, 168, 192 }) |dpi| {
        for ([_]i32{ 256, 300, 366 }) |width| {
            const card = Rect{ .left = scale(12, dpi), .top = 500, .right = scale(12, dpi) + scale(width, dpi), .bottom = 500 + scale(height, dpi) };
            const l = compute(card, dpi);
            const idle = [_]Rect{ l.title, l.line, l.button, l.close };
            for (idle, 0..) |r, i| {
                try std.testing.expect(inside(r, card));
                for (idle[i + 1 ..]) |other| try std.testing.expect(!overlaps(r, other));
            }
            const busy = [_]Rect{ l.title, l.line, l.bar };
            for (busy, 0..) |r, i| {
                try std.testing.expect(inside(r, card));
                for (busy[i + 1 ..]) |other| try std.testing.expect(!overlaps(r, other));
            }
        }
    }
}

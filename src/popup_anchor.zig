const std = @import("std");

pub const Rect = struct { left: i32, top: i32, right: i32, bottom: i32 };
pub const Spot = struct { x: i32, y: i32, above: bool };

pub fn place(anchor: Rect, width: i32, height: i32, work: Rect, gap: i32) Spot {
    const center = anchor.left + @divTrunc(anchor.right - anchor.left, 2);
    const max_x = @max(work.left, work.right - width);
    const x = std.math.clamp(center - @divTrunc(width, 2), work.left, max_x);
    const above_y = anchor.top - gap - height;
    if (above_y >= work.top) return .{ .x = x, .y = above_y, .above = true };
    const below_y = anchor.bottom + gap;
    const max_y = @max(work.top, work.bottom - height);
    return .{ .x = x, .y = std.math.clamp(below_y, work.top, max_y), .above = false };
}

const screen = Rect{ .left = 0, .top = 0, .right = 1920, .bottom = 1080 };

test "IGSH-1246 the picker sits right above the message and centred on it" {
    const spot = place(.{ .left = 800, .top = 500, .right = 1000, .bottom = 560 }, 252, 44, screen, 6);
    try std.testing.expect(spot.above);
    try std.testing.expectEqual(@as(i32, 900 - 126), spot.x);
    try std.testing.expectEqual(@as(i32, 500 - 6 - 44), spot.y);
}

test "IGSH-1246 near the top edge the picker flips below the message" {
    const spot = place(.{ .left = 800, .top = 20, .right = 1000, .bottom = 80 }, 252, 44, screen, 6);
    try std.testing.expect(!spot.above);
    try std.testing.expectEqual(@as(i32, 86), spot.y);
}

test "IGSH-1246 the picker stays inside the screen on every side" {
    const left = place(.{ .left = 0, .top = 500, .right = 40, .bottom = 560 }, 252, 44, screen, 6);
    try std.testing.expectEqual(@as(i32, 0), left.x);
    const right = place(.{ .left = 1880, .top = 500, .right = 1920, .bottom = 560 }, 252, 44, screen, 6);
    try std.testing.expectEqual(@as(i32, 1920 - 252), right.x);
    const bottom = place(.{ .left = 800, .top = 10, .right = 1000, .bottom = 1070 }, 252, 400, screen, 6);
    try std.testing.expect(!bottom.above);
    try std.testing.expectEqual(@as(i32, 1080 - 400), bottom.y);
}

test "IGSH-1246 a tall full picker flips below when it does not fit above" {
    const spot = place(.{ .left = 800, .top = 300, .right = 1000, .bottom = 360 }, 420, 480, screen, 6);
    try std.testing.expect(!spot.above);
    try std.testing.expectEqual(@as(i32, 366), spot.y);
}

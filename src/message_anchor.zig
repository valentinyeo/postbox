const std = @import("std");

pub const Anchor = struct {
    offset: i32 = 0,
    bottom: i32 = 0,
    valid: bool = false,
};

pub fn holdDelta(current_offset: i32, anchor: Anchor, current_bottom: i32, scrolled: bool) i32 {
    if (!anchor.valid or !scrolled or anchor.bottom != current_bottom) return 0;
    return anchor.offset - current_offset;
}

test "no anchor holds nothing" {
    try std.testing.expectEqual(@as(i32, 0), holdDelta(120, .{}, 900, true));
}

test "the bottom of the chat stays pinned" {
    try std.testing.expectEqual(@as(i32, 0), holdDelta(120, .{ .offset = 104, .bottom = 900, .valid = true }, 900, false));
}

test "a taller row below the reading position is added back to the scroll" {
    try std.testing.expectEqual(@as(i32, 16), holdDelta(104, .{ .offset = 120, .bottom = 900, .valid = true }, 900, true));
    try std.testing.expectEqual(@as(i32, -16), holdDelta(120, .{ .offset = 104, .bottom = 900, .valid = true }, 900, true));
}

test "a resized canvas starts a new anchor" {
    try std.testing.expectEqual(@as(i32, 0), holdDelta(104, .{ .offset = 120, .bottom = 900, .valid = true }, 940, true));
}

test "an unmoved reading position needs no correction" {
    try std.testing.expectEqual(@as(i32, 0), holdDelta(120, .{ .offset = 120, .bottom = 900, .valid = true }, 900, true));
}

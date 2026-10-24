const std = @import("std");

pub const Size = struct { width: i32, height: i32 };

pub fn fit(src_w: i32, src_h: i32, max_w: i32, max_h: i32) Size {
    if (src_w <= 0 or src_h <= 0 or max_w <= 0 or max_h <= 0) return .{ .width = 1, .height = 1 };
    const width: i64 = @min(src_w, max_w);
    const height: i64 = @min(src_h, max_h);
    if (width * src_h <= height * src_w) {
        return .{ .width = @intCast(width), .height = @intCast(@max(1, @divTrunc(width * src_h, src_w))) };
    }
    return .{ .width = @intCast(@max(1, @divTrunc(height * src_w, src_h))), .height = @intCast(height) };
}

pub fn needsTimeLine(last_line_right: i32, time_width_with_gap: i32, text_width: i32) bool {
    return @as(i64, last_line_right) + time_width_with_gap > text_width;
}

test "oversize landscape fits the height cap without upscaling" {
    try std.testing.expectEqual(Size{ .width = 343, .height = 250 }, fit(756, 550, 596, 250));
}

test "portrait keeps its aspect ratio at the height cap" {
    try std.testing.expectEqual(Size{ .width = 140, .height = 250 }, fit(720, 1280, 596, 250));
}

test "small bitmap stays unchanged" {
    try std.testing.expectEqual(Size{ .width = 100, .height = 80 }, fit(100, 80, 596, 250));
}

test "200 pixel bubble leaves the same horizontal padding as text" {
    try std.testing.expectEqual(Size{ .width = 176, .height = 128 }, fit(756, 550, 200 - 24, 250));
}

test "invalid source or bounds produce a one pixel fallback" {
    for ([_][4]i32{
        .{ 0, 550, 596, 250 },
        .{ 756, 0, 596, 250 },
        .{ -1, 550, 596, 250 },
        .{ 756, -1, 596, 250 },
        .{ 756, 550, 0, 250 },
        .{ 756, 550, 596, 0 },
        .{ 756, 550, -1, 250 },
        .{ 756, 550, 596, -1 },
    }) |input| {
        try std.testing.expectEqual(Size{ .width = 1, .height = 1 }, fit(input[0], input[1], input[2], input[3]));
    }
}

test "extreme aspect ratios and dimensions remain positive and bounded" {
    try std.testing.expectEqual(Size{ .width = 1, .height = 250 }, fit(1, std.math.maxInt(i32), 596, 250));
    try std.testing.expectEqual(Size{ .width = 596, .height = 1 }, fit(std.math.maxInt(i32), 1, 596, 250));
    try std.testing.expectEqual(Size{ .width = 596, .height = 596 }, fit(std.math.maxInt(i32), std.math.maxInt(i32), 596, std.math.maxInt(i32)));
}

test "time gets a separate line only when it overlaps the last text line" {
    try std.testing.expect(needsTimeLine(580, 46, 596));
    try std.testing.expect(!needsTimeLine(500, 46, 596));
    try std.testing.expect(!needsTimeLine(550, 46, 596));
    try std.testing.expect(needsTimeLine(551, 46, 596));
    try std.testing.expect(needsTimeLine(std.math.maxInt(i32), 46, std.math.maxInt(i32)));
}

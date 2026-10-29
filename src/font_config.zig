const std = @import("std");

pub const default_scale: i32 = 100;

pub fn savedScale(value: u32) i32 {
    if (value == 82) return default_scale;
    return @intCast(std.math.clamp(value, 60, 160));
}

pub const body_weight: i32 = 400;
pub const files = [_][]const u8{
    "IBMPlexSans-Regular.ttf",
    "IBMPlexSans-Medium.ttf",
    "IBMPlexSans-SemiBold.ttf",
    "IBMPlexSans-Bold.ttf",
    "IBMPlexSans-Italic.ttf",
    "IBMPlexMono-Regular.ttf",
};

test "WAZI-161 bundled font list includes all approved weights and code face" {
    const expected = [_][]const u8{ "IBMPlexSans-Regular.ttf", "IBMPlexSans-Medium.ttf", "IBMPlexSans-SemiBold.ttf", "IBMPlexSans-Bold.ttf", "IBMPlexSans-Italic.ttf", "IBMPlexMono-Regular.ttf" };
    try std.testing.expectEqual(expected.len, files.len);
    for (expected, files) |want, actual| try std.testing.expectEqualStrings(want, actual);
}

test "IGSH-829 body text uses Regular weight" {
    try std.testing.expectEqual(@as(i32, 400), body_weight);
}

test "IGSH-1195 approved size migrates only the legacy default" {
    try std.testing.expectEqual(@as(i32, 100), default_scale);
    try std.testing.expectEqual(default_scale, savedScale(82));
    for ([_]u32{ 60, 72, 92, 100, 110, 160 }) |scale| {
        try std.testing.expectEqual(@as(i32, @intCast(scale)), savedScale(scale));
    }
    try std.testing.expectEqual(@as(i32, 60), savedScale(0));
    try std.testing.expectEqual(@as(i32, 160), savedScale(std.math.maxInt(u32)));
}

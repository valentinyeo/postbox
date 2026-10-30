const std = @import("std");

pub const small_scale: i32 = 80;
pub const default_scale: i32 = 100;
pub const large_scale: i32 = 125;
pub const larger_scale: i32 = 150;

pub fn savedScale(value: u32) i32 {
    if (value == 82) return default_scale;
    return @intCast(std.math.clamp(value, 60, 160));
}

pub const body_weight: i32 = @import("design_tokens.zig").body_weight;
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

test "IGSH-1174 presets survive saved preference loading" {
    for ([_]i32{ small_scale, default_scale, large_scale, larger_scale }) |scale| {
        try std.testing.expectEqual(scale, savedScale(@intCast(scale)));
    }
    try std.testing.expectEqual(@as(i32, 80), small_scale);
    try std.testing.expectEqual(@as(i32, 100), default_scale);
    try std.testing.expectEqual(@as(i32, 125), large_scale);
    try std.testing.expectEqual(@as(i32, 150), larger_scale);
    try std.testing.expectEqual(default_scale, savedScale(82));
    try std.testing.expectEqual(@as(i32, 137), savedScale(137));
}

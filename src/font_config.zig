const std = @import("std");

pub const min_scale = 60;
pub const max_scale = 160;

pub const small_scale: i32 = 80;
pub const default_scale: i32 = 100;
pub const large_scale: i32 = 125;
pub const larger_scale: i32 = 150;

pub fn savedScale(value: u32) i32 {
    if (value == 82) return default_scale;
    return @intCast(std.math.clamp(value, min_scale, max_scale));
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
    try std.testing.expectEqual(default_scale, savedScale(82));
    try std.testing.expectEqual(@as(i32, 137), savedScale(137));
}

pub const RowGeometry = struct {
    name_top: i32,
    preview_top: i32,
    preview_bottom: i32,
    height: i32,
};

pub fn rowGeometry(dpi: i32, name_height: i32, preview_height: i32, time_height: i32) RowGeometry {
    const padding = @divTrunc(4 * dpi + 48, 96);
    const name_band = @max(@divTrunc(24 * dpi + 48, 96), @max(name_height, time_height));
    const preview_band = @max(@divTrunc(24 * dpi + 48, 96), preview_height);
    const preview_top = padding + name_band;
    const preview_bottom = preview_top + preview_band;
    return .{ .name_top = padding, .preview_top = preview_top, .preview_bottom = preview_bottom, .height = preview_bottom + padding };
}

test "chat row geometry fits measured fonts at any scale" {
    const normal = rowGeometry(96, 18, 16, 14);
    try std.testing.expectEqual(@as(i32, 56), normal.height);
    const large = rowGeometry(96, 33, 29, 25);
    try std.testing.expect(large.preview_top - large.name_top >= 33);
    try std.testing.expect(large.preview_bottom - large.preview_top >= 29);
    try std.testing.expect(large.height > normal.height);
    const high_dpi = rowGeometry(192, 60, 50, 56);
    try std.testing.expect(high_dpi.preview_top - high_dpi.name_top >= 60);
    try std.testing.expect(high_dpi.preview_bottom - high_dpi.preview_top >= 50);
}

pub const RowEdges = struct {
    highlight_right: i32,
    time_left: i32,
    time_right: i32,
    name_right: i32,
};

fn scaled(value: i32, dpi: i32) i32 {
    return @divTrunc(value * dpi + 48, 96);
}

pub fn rowEdges(item_right: i32, dpi: i32, is_pinned: bool) RowEdges {
    return .{
        .highlight_right = item_right - scaled(8, dpi),
        .time_left = item_right - scaled(60, dpi),
        .time_right = item_right - scaled(12, dpi),
        .name_right = item_right - scaled(if (is_pinned) 78 else 62, dpi),
    };
}

test "IGSH-1538 the row time sits inside the highlight with the avatar's padding" {
    for ([_]i32{ 96, 120, 144, 192 }) |dpi| {
        for ([_]bool{ false, true }) |is_pinned| {
            const edges = rowEdges(360, dpi, is_pinned);
            const avatar_inset = scaled(12, dpi) - scaled(8, dpi);
            try std.testing.expect(edges.time_right <= edges.highlight_right - avatar_inset);
            try std.testing.expect(edges.name_right <= edges.time_left);
        }
    }
}

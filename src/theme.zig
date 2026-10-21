const std = @import("std");

pub fn hex(rgb_value: u24) u32 {
    const value: u32 = rgb_value;
    return ((value & 0xff0000) >> 16) | (value & 0x00ff00) | ((value & 0x0000ff) << 16);
}

pub const Palette = struct {
    surface: u32,
    surface_container_low: u32,
    surface_container: u32,
    surface_container_high: u32,
    surface_container_highest: u32,
    on_surface: u32,
    on_surface_variant: u32,
    outline: u32,
    outline_variant: u32,
    primary: u32,
    on_primary: u32,
    primary_container: u32,
    on_primary_container: u32,
    secondary_container: u32,
    on_secondary_container: u32,
    @"error": u32,
};

pub const green: Palette = .{
    .surface = hex(0x0f1512),
    .surface_container_low = hex(0x171d1a),
    .surface_container = hex(0x1b211e),
    .surface_container_high = hex(0x252b28),
    .surface_container_highest = hex(0x303633),
    .on_surface = hex(0xdee4df),
    .on_surface_variant = hex(0xbfc9c3),
    .outline = hex(0x89938e),
    .outline_variant = hex(0x3f4944),
    .primary = hex(0x88d6ba),
    .on_primary = hex(0x00382a),
    .primary_container = hex(0x00513e),
    .on_primary_container = hex(0xa4f2d5),
    .secondary_container = hex(0x344c43),
    .on_secondary_container = hex(0xcee9dc),
    .@"error" = hex(0xffb4ab),
};

pub const amoled: Palette = .{
    .surface = hex(0x000000),
    .surface_container_low = hex(0x000000),
    .surface_container = hex(0x000000),
    .surface_container_high = hex(0x1a1a1a),
    .surface_container_highest = hex(0x262626),
    .on_surface = hex(0xffffff),
    .on_surface_variant = hex(0xcccccc),
    .outline = hex(0x999999),
    .outline_variant = hex(0x666666),
    .primary = hex(0xe6e6e6),
    .on_primary = hex(0x1a1a1a),
    .primary_container = hex(0x333333),
    .on_primary_container = hex(0xffffff),
    .secondary_container = hex(0xbfbfbf),
    .on_secondary_container = hex(0x181818),
    .@"error" = hex(0xffb4ab),
};

pub const Choice = enum(u32) { green = 0, amoled = 1 };

pub var current: *const Palette = &green;
pub var choice: Choice = .green;

pub fn choiceFromDword(value: u32) Choice {
    return std.enums.fromInt(Choice, value) orelse .green;
}

pub fn set(selected: Choice) void {
    choice = selected;
    current = switch (selected) {
        .green => &green,
        .amoled => &amoled,
    };
}

pub const unread_dot_px: i32 = 8;
pub const radius_bubble: i32 = 16;
pub const radius_field: i32 = 28;
pub const radius_row: i32 = 32;

fn linear(channel: u8) f64 {
    const value = @as(f64, @floatFromInt(channel)) / 255.0;
    return if (value <= 0.04045) value / 12.92 else std.math.pow(f64, (value + 0.055) / 1.055, 2.4);
}

fn luminance(color: u32) f64 {
    return 0.2126 * linear(@truncate(color)) + 0.7152 * linear(@truncate(color >> 8)) + 0.0722 * linear(@truncate(color >> 16));
}

test "COLORREF conversion" {
    try std.testing.expectEqual(@as(u32, 0x00563412), hex(0x123456));
}

test "Material 3 text contrast" {
    for ([_]Palette{ green, amoled }) |palette| {
        const pairs = [_][2]u32{
            .{ palette.on_surface, palette.surface },
            .{ palette.on_surface, palette.surface_container_low },
            .{ palette.on_surface, palette.surface_container },
            .{ palette.on_surface, palette.surface_container_high },
            .{ palette.on_surface, palette.surface_container_highest },
            .{ palette.on_surface_variant, palette.surface_container_low },
            .{ palette.on_surface_variant, palette.surface_container_high },
            .{ palette.on_surface_variant, palette.primary_container },
            .{ palette.on_primary_container, palette.primary_container },
            .{ palette.on_secondary_container, palette.secondary_container },
            .{ palette.on_primary, palette.primary },
        };
        for (pairs) |pair| {
            const a = luminance(pair[0]);
            const b = luminance(pair[1]);
            try std.testing.expect((@max(a, b) + 0.05) / (@min(a, b) + 0.05) >= 4.5);
        }
    }
}

test "unread dot size is between 6 and 10" {
    try std.testing.expect(unread_dot_px >= 6 and unread_dot_px <= 10);
}

test "green palette preserves every original COLORREF" {
    const expected = [_]u32{ hex(0x0f1512), hex(0x171d1a), hex(0x1b211e), hex(0x252b28), hex(0x303633), hex(0xdee4df), hex(0xbfc9c3), hex(0x89938e), hex(0x3f4944), hex(0x88d6ba), hex(0x00382a), hex(0x00513e), hex(0xa4f2d5), hex(0x344c43), hex(0xcee9dc), hex(0xffb4ab) };
    inline for (@typeInfo(Palette).@"struct".fields, 0..) |field, index| {
        try std.testing.expectEqual(expected[index], @field(green, field.name));
    }
}

test "AMOLED has pure black surfaces and distinct neutral bubbles" {
    try std.testing.expectEqual(hex(0x000000), amoled.surface);
    try std.testing.expectEqual(hex(0x000000), amoled.surface_container_low);
    try std.testing.expectEqual(hex(0x000000), amoled.surface_container);
    try std.testing.expect(amoled.surface_container_high != amoled.primary_container);
    try std.testing.expect(luminance(amoled.primary_container) > luminance(amoled.surface_container_high));
    inline for (@typeInfo(Palette).@"struct".fields) |field| {
        if (comptime !std.mem.eql(u8, field.name, "error")) {
            const color = @field(amoled, field.name);
            try std.testing.expectEqual(color & 0xff, (color >> 8) & 0xff);
            try std.testing.expectEqual(color & 0xff, (color >> 16) & 0xff);
        }
    }
}

test "theme DWORD selection defaults unknown values to green" {
    try std.testing.expectEqual(Choice.green, choiceFromDword(0));
    try std.testing.expectEqual(Choice.amoled, choiceFromDword(1));
    try std.testing.expectEqual(Choice.green, choiceFromDword(2));
    try std.testing.expectEqual(Choice.green, choiceFromDword(std.math.maxInt(u32)));
}

test "runtime selection updates every palette field" {
    defer set(.green);
    for ([_]Choice{ .amoled, .green }) |selected| {
        set(selected);
        try std.testing.expectEqual(selected, choice);
        const expected = if (selected == .amoled) amoled else green;
        try std.testing.expectEqualDeep(expected, current.*);
    }
}

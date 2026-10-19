const std = @import("std");

pub fn hex(rgb_value: u24) u32 {
    const value: u32 = rgb_value;
    return ((value & 0xff0000) >> 16) | (value & 0x00ff00) | ((value & 0x0000ff) << 16);
}

pub const surface = hex(0x0f1512);
pub const surface_container_low = hex(0x171d1a);
pub const surface_container = hex(0x1b211e);
pub const surface_container_high = hex(0x252b28);
pub const surface_container_highest = hex(0x303633);
pub const on_surface = hex(0xdee4df);
pub const on_surface_variant = hex(0xbfc9c3);
pub const outline = hex(0x89938e);
pub const outline_variant = hex(0x3f4944);
pub const primary = hex(0x88d6ba);
pub const on_primary = hex(0x00382a);
pub const primary_container = hex(0x00513e);
pub const on_primary_container = hex(0xa4f2d5);
pub const secondary_container = hex(0x344c43);
pub const on_secondary_container = hex(0xcee9dc);
pub const @"error" = hex(0xffb4ab);

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
    const pairs = [_][2]u32{
        .{ on_surface, surface },
        .{ on_surface, surface_container_low },
        .{ on_surface, surface_container_high },
        .{ on_surface_variant, surface_container_low },
        .{ on_primary_container, primary_container },
        .{ on_secondary_container, secondary_container },
        .{ on_primary, primary },
    };
    for (pairs) |pair| {
        const a = luminance(pair[0]);
        const b = luminance(pair[1]);
        try std.testing.expect((@max(a, b) + 0.05) / (@min(a, b) + 0.05) >= 4.5);
    }
}

test "unread dot size is between 6 and 10" {
    try std.testing.expect(unread_dot_px >= 6 and unread_dot_px <= 10);
}

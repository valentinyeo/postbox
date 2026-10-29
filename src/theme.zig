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
    sidebar_surface: u32,
    sidebar_divider: u32,
};

pub const amoled: Palette = .{
    .surface = hex(0x101010),
    .surface_container_low = hex(0x181818),
    .surface_container = hex(0x1f1f1f),
    .surface_container_high = hex(0x262626),
    .surface_container_highest = hex(0x353535),
    .on_surface = hex(0xf2f2f2),
    .on_surface_variant = hex(0x8a8a8a),
    .outline = hex(0x2e2e2e),
    .outline_variant = hex(0x2a2a2a),
    .primary = hex(0x89b4f8),
    .on_primary = hex(0x101010),
    .primary_container = hex(0x414141),
    .on_primary_container = hex(0xf2f2f2),
    .secondary_container = hex(0x353535),
    .on_secondary_container = hex(0xf2f2f2),
    .@"error" = hex(0xf28b82),
    .sidebar_surface = hex(0x181818),
    .sidebar_divider = hex(0x2a2a2a),
};

pub fn selectionColors(palette: Palette, from_me: bool) struct { fill: u32, text: u32 } {
    return if (from_me)
        .{ .fill = palette.primary, .text = palette.on_primary }
    else
        .{ .fill = palette.primary, .text = palette.on_primary };
}

pub const Choice = enum(u32) { amoled = 1 };

pub var current: *const Palette = &amoled;
pub var choice: Choice = .amoled;

pub fn choiceFromSaved(value: ?u32) Choice {
    return std.enums.fromInt(Choice, value orelse return .amoled) orelse .amoled;
}

pub const amoled_button = hex(0x1f1f1f);
pub const amoled_button_hover = hex(0x353535);
pub const amoled_button_pressed = hex(0x414141);
pub const amoled_send = hex(0xf2f2f2);
pub const amoled_send_hover = hex(0xdedede);
pub const amoled_send_pressed = hex(0xcacaca);
pub const amoled_button_text = hex(0xf2f2f2);
pub const send_text = hex(0x101010);
pub const bubble_other_bottom = hex(0x1e1e1e);
pub const bubble_own_bottom = hex(0x3a3a3a);
pub const bubble_own_outline = hex(0x4a4a4a);
pub const quote_bar = hex(0x4a4a4a);
pub const code_block = hex(0x1a1a1a);
pub const code_inline = hex(0x2a2a2a);
pub const online = hex(0x3ba55c);

pub fn set(selected: Choice) void {
    choice = selected;
    current = &amoled;
}

pub const unread_dot_px: i32 = 8;
pub const radius_bubble: i32 = 20;
pub const radius_dialog: i32 = 20;
pub const radius_card: i32 = 16;
pub const radius_field: i32 = 28;
pub const radius_code: i32 = 8;
pub const radius_inline: i32 = 4;
pub const selected_row_radius: i32 = 10;
pub const sidebar_width: i32 = 300;
pub const chat_column_width: i32 = 760;
pub const bubble_max_width: i32 = 660;
pub const chat_row_height: i32 = 56;
pub const avatar_size: i32 = 40;
pub const platform_badge_size: i32 = 16;
pub const mention_row_height: i32 = 40;
pub const type_title: i32 = 24;
pub const type_chat_name: i32 = 15;
pub const type_body: i32 = 15;
pub const type_row_name: i32 = 14;
pub const type_preview: i32 = 13;
pub const type_time: i32 = 12;
pub const type_label: i32 = 11;
pub const icon_size: i32 = 16;
pub const spacing = [_]i32{ 2, 4, 8, 12, 16, 24, 32 };

pub const archived_row_foreground_weight: u8 = 180;

pub fn archivedRowColor(color: u32) u32 {
    const weight: u32 = archived_row_foreground_weight;
    var result: u32 = 0;
    inline for ([_]u5{ 0, 8, 16 }) |shift| {
        const foreground = (color >> shift) & 0xff;
        const background = (current.surface_container_low >> shift) & 0xff;
        result |= ((foreground * weight + background * (255 - weight)) / 255) << shift;
    }
    return result;
}

fn linear(channel: u8) f64 {
    const value = @as(f64, @floatFromInt(channel)) / 255.0;
    return if (value <= 0.04045) value / 12.92 else std.math.pow(f64, (value + 0.055) / 1.055, 2.4);
}

fn luminance(color: u32) f64 {
    return 0.2126 * linear(@truncate(color)) + 0.7152 * linear(@truncate(color >> 8)) + 0.0722 * linear(@truncate(color >> 16));
}

pub fn contrastRatio(a: u32, b: u32) f64 {
    const la = luminance(a);
    const lb = luminance(b);
    return (@max(la, lb) + 0.05) / (@min(la, lb) + 0.05);
}

test "IGSH-461 WCAG contrast reference values" {
    try std.testing.expectApproxEqAbs(@as(f64, 21), contrastRatio(hex(0x000000), hex(0xffffff)), 0.000001);
    try std.testing.expectEqual(@as(f64, 1), contrastRatio(hex(0x252b28), hex(0x252b28)));
    try std.testing.expectApproxEqAbs(@as(f64, 4.478089), contrastRatio(hex(0x777777), hex(0xffffff)), 0.000001);
    try std.testing.expectEqual(contrastRatio(hex(0x123456), hex(0xabcdef)), contrastRatio(hex(0xabcdef), hex(0x123456)));
}

test "shared kit body text and selections remain readable" {
    for ([_]u32{ amoled.surface, amoled.surface_container_low, amoled.surface_container, amoled.surface_container_high, amoled.surface_container_highest, amoled.primary_container }) |background| {
        try std.testing.expect(contrastRatio(amoled.on_surface, background) >= 4.5);
    }
    try std.testing.expect(contrastRatio(amoled.on_surface_variant, amoled.sidebar_surface) >= 4.5);
    for ([_]bool{ false, true }) |from_me| {
        const selected = selectionColors(amoled, from_me);
        try std.testing.expect(contrastRatio(selected.text, selected.fill) >= 4.5);
    }
    try std.testing.expect(contrastRatio(send_text, amoled_send) >= 4.5);
}

test "saved green and unknown preferences migrate to the sole graphite design" {
    for ([_]?u32{ null, 0, 1, 2, std.math.maxInt(u32) }) |saved| {
        try std.testing.expectEqual(Choice.amoled, choiceFromSaved(saved));
    }
}

test "runtime selection uses the approved graphite palette" {
    set(.amoled);
    try std.testing.expectEqual(Choice.amoled, choice);
    try std.testing.expectEqual(&amoled, current);
    try std.testing.expectEqual(hex(0x101010), current.surface);
    try std.testing.expectEqual(hex(0x89b4f8), current.primary);
    try std.testing.expectEqual(@as(i32, 20), radius_bubble);
    try std.testing.expectEqual(@as(i32, 10), selected_row_radius);
}

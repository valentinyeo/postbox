const std = @import("std");
const design = @import("design_tokens.zig");

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
    .surface = design.ReaderBackground,
    .surface_container_low = design.ReaderPanel,
    .surface_container = design.ReaderControl,
    .surface_container_high = design.ReaderCard,
    .surface_container_highest = design.ReaderRaised,
    .on_surface = design.ReaderForeground,
    .on_surface_variant = design.ReaderHint,
    .outline = design.ReaderOutline,
    .outline_variant = design.ReaderOutline,
    .primary = design.ReaderForeground,
    .on_primary = design.ReaderBackground,
    .primary_container = design.ReaderUserCard,
    .on_primary_container = design.ReaderForeground,
    .secondary_container = design.ReaderRaised,
    .on_secondary_container = design.ReaderForeground,
    .@"error" = design.ReaderForeground,
    .sidebar_surface = design.ReaderPanel,
    .sidebar_divider = design.ReaderOutline,
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

pub const amoled_button = design.ReaderControl;
pub const amoled_button_hover = design.ReaderRaised;
pub const amoled_button_pressed = design.ReaderUserCard;
pub const amoled_send = design.ReaderForeground;
pub const amoled_send_hover = design.ReaderForeground;
pub const amoled_send_pressed = design.ReaderHint;
pub const amoled_button_text = design.ReaderForeground;
pub const send_text = design.ReaderBackground;
pub const bubble_other_bottom = design.ReaderCard;
pub const bubble_own_bottom = design.ReaderUserCard;
pub const bubble_own_outline = design.shift(design.ReaderUserCard, 16);
pub const quote_bar = design.shift(design.ReaderUserCard, 16);
pub const code_block = design.ReaderCard;
pub const code_inline = design.ReaderOutline;
pub const online = design.ReaderForeground;

pub fn set(selected: Choice) void {
    choice = selected;
    current = &amoled;
}

pub const unread_dot_px: i32 = 8;
pub const radius_bubble: i32 = design.bubble_radius;
pub const radius_dialog: i32 = design.bubble_radius;
pub const radius_card: i32 = design.menu_radius;
pub const radius_field: i32 = design.field_radius;
pub const radius_code: i32 = 8;
pub const radius_inline: i32 = 4;
pub const selected_row_radius: i32 = design.row_radius;
pub const sidebar_width: i32 = 300;
pub const chat_column_width: i32 = design.column_width;
pub const bubble_max_width: i32 = @divTrunc(design.column_width * 6, 10);
pub const chat_row_height: i32 = 56;
pub const avatar_size: i32 = 40;
pub const platform_badge_size: i32 = 16;
pub const mention_row_height: i32 = 40;
pub const type_title: i32 = 24;
pub const type_chat_name: i32 = 15;
pub const type_body: i32 = design.body_size;
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
    try std.testing.expectEqual(design.ReaderBackground, current.surface);
    try std.testing.expectEqual(design.ReaderForeground, current.primary);
    try std.testing.expectEqual(@as(i32, 20), radius_bubble);
    try std.testing.expectEqual(@as(i32, 10), selected_row_radius);
}

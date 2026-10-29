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
    .sidebar_surface = hex(0x1b211e),
    .sidebar_divider = hex(0x303633),
};

pub const amoled: Palette = .{
    .surface = hex(0x101010),
    .surface_container_low = hex(0x101010),
    .surface_container = hex(0x1f1f1f),
    .surface_container_high = hex(0x262626),
    .surface_container_highest = hex(0x303030),
    .on_surface = hex(0xf2f2f2),
    .on_surface_variant = hex(0xcccccc),
    .outline = hex(0x999999),
    .outline_variant = hex(0x666666),
    .primary = hex(0x89b4f8),
    .on_primary = hex(0x1a1a1a),
    .primary_container = hex(0x414141),
    .on_primary_container = hex(0xf2f2f2),
    .secondary_container = hex(0x333333),
    .on_secondary_container = hex(0xf2f2f2),
    .@"error" = hex(0xffb4ab),
    .sidebar_surface = hex(0x101010),
    .sidebar_divider = hex(0x242424),
};

pub fn selectionColors(palette: Palette, from_me: bool) struct { fill: u32, text: u32 } {
    return if (from_me)
        .{ .fill = palette.primary, .text = palette.on_primary }
    else
        .{ .fill = palette.secondary_container, .text = palette.on_secondary_container };
}

pub const Choice = enum(u32) { green = 0, amoled = 1 };

pub var current: *const Palette = &amoled;
pub var choice: Choice = .amoled;

pub fn choiceFromSaved(value: ?u32) Choice {
    return std.enums.fromInt(Choice, value orelse return .amoled) orelse .amoled;
}

pub const amoled_button = hex(0x262626);
pub const amoled_button_hover = hex(0x333333);
pub const amoled_button_pressed = hex(0x404040);
pub const amoled_send = hex(0x555555);
pub const amoled_send_hover = hex(0x606060);
pub const amoled_send_pressed = hex(0x666666);
pub const amoled_button_text = hex(0xffffff);

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
pub const selected_row_radius: i32 = 8;
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

test "IGSH-461 composer contrast on every theme" {
    const palettes = [_]Palette{ green, amoled };
    try std.testing.expectEqual(@typeInfo(Choice).@"enum".fields.len, palettes.len);
    for (palettes) |palette| {
        const composer_surface = palette.surface_container_high;
        const composer_border = palette.outline;
        try std.testing.expect(contrastRatio(composer_border, palette.surface) >= 3.0);
        try std.testing.expect(contrastRatio(palette.on_surface, composer_surface) >= 4.5);
        try std.testing.expect(contrastRatio(palette.on_surface_variant, composer_surface) >= 4.5);
        try std.testing.expect(contrastRatio(palette.primary, composer_surface) >= 3.0);
        try std.testing.expect(luminance(palette.primary) > luminance(composer_border));
    }
}

test "IGSH-461 selected row contrast and rectangle radius on every theme" {
    try std.testing.expectEqual(@as(i32, 8), selected_row_radius);
    const palettes = [_]Palette{ green, amoled };
    try std.testing.expectEqual(@typeInfo(Choice).@"enum".fields.len, palettes.len);
    for (palettes) |palette| {
        const selected_fill = palette.surface_container_highest;
        try std.testing.expect(contrastRatio(selected_fill, palette.surface_container_low) >= 1.15);
        try std.testing.expect(contrastRatio(palette.on_surface, selected_fill) >= 4.5);
        try std.testing.expect(contrastRatio(palette.on_surface_variant, selected_fill) >= 4.5);
    }
}

test "IGSH-667 selection fill is distinguishable at 1.3:1 and text readable at 4.5:1 on every theme and direction" {
    const palettes = [_]Palette{ green, amoled };
    try std.testing.expectEqual(@typeInfo(Choice).@"enum".fields.len, palettes.len);
    for (palettes) |palette| {
        for ([_]bool{ false, true }) |from_me| {
            const colors = selectionColors(palette, from_me);
            const bubble = if (from_me) palette.primary_container else palette.surface_container_high;
            try std.testing.expect(colors.fill != bubble);
            try std.testing.expect(contrastRatio(colors.fill, bubble) >= 1.3);
            try std.testing.expect(contrastRatio(colors.text, colors.fill) >= 4.5);
        }
    }
}

test "COLORREF conversion" {
    try std.testing.expectEqual(@as(u32, 0x00563412), hex(0x123456));
}

test "Material 3 text contrast" {
    for ([_]Palette{ green, amoled }) |palette| {
        const pairs = [_][2]u32{
            .{ palette.on_surface, palette.surface },
            .{ palette.on_surface, palette.surface_container_low },
            .{ palette.on_surface, palette.sidebar_surface },
            .{ palette.on_surface, palette.surface_container },
            .{ palette.on_surface, palette.surface_container_high },
            .{ palette.on_surface, palette.surface_container_highest },
            .{ palette.on_surface_variant, palette.surface_container_low },
            .{ palette.on_surface_variant, palette.sidebar_surface },
            .{ palette.on_surface_variant, palette.surface_container_high },
            .{ palette.on_surface_variant, palette.primary_container },
            .{ palette.on_primary_container, palette.primary_container },
            .{ palette.on_secondary_container, palette.secondary_container },
            .{ palette.on_primary, palette.primary },
        };
        for (pairs) |pair| {
            try std.testing.expect(contrastRatio(pair[0], pair[1]) >= 4.5);
        }
    }
}

test "unread dot size is between 6 and 10" {
    try std.testing.expect(unread_dot_px >= 6 and unread_dot_px <= 10);
}

test "green palette preserves every original COLORREF" {
    const expected = [_]u32{ hex(0x0f1512), hex(0x171d1a), hex(0x1b211e), hex(0x252b28), hex(0x303633), hex(0xdee4df), hex(0xbfc9c3), hex(0x89938e), hex(0x3f4944), hex(0x88d6ba), hex(0x00382a), hex(0x00513e), hex(0xa4f2d5), hex(0x344c43), hex(0xcee9dc), hex(0xffb4ab), hex(0x1b211e), hex(0x303633) };
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

test "theme DWORD selection defaults unknown values to AMOLED" {
    try std.testing.expectEqual(Choice.green, choiceFromSaved(0));
    try std.testing.expectEqual(Choice.amoled, choiceFromSaved(1));
    try std.testing.expectEqual(Choice.amoled, choiceFromSaved(2));
    try std.testing.expectEqual(Choice.amoled, choiceFromSaved(std.math.maxInt(u32)));
}

test "runtime selection updates every palette field" {
    defer set(.amoled);
    for ([_]Choice{ .amoled, .green }) |selected| {
        set(selected);
        try std.testing.expectEqual(selected, choice);
        const expected = if (selected == .amoled) amoled else green;
        try std.testing.expectEqualDeep(expected, current.*);
    }
}

test "IGSH-461 default missing theme is AMOLED" {
    try std.testing.expectEqual(Choice.amoled, choiceFromSaved(null));
}

test "IGSH-461 default preserves explicit saved green" {
    try std.testing.expectEqual(Choice.green, choiceFromSaved(0));
}

test "IGSH-461 default preserves explicit saved AMOLED" {
    try std.testing.expectEqual(Choice.amoled, choiceFromSaved(1));
}

test "IGSH-461 AMOLED composer button states are visible without glare and have readable text" {
    for ([_]u32{ amoled_button, amoled_button_hover, amoled_button_pressed, amoled_send, amoled_send_hover, amoled_send_pressed }) |fill| {
        const contrast = contrastRatio(fill, amoled.surface);
        try std.testing.expect(contrast >= 1.2 and contrast <= 4.0);
        try std.testing.expect(contrastRatio(amoled_button_text, fill) >= 4.5);
    }
    try std.testing.expect(luminance(amoled_button) < luminance(amoled_button_hover));
    try std.testing.expect(luminance(amoled_button_hover) < luminance(amoled_button_pressed));
    try std.testing.expect(luminance(amoled_send) < luminance(amoled_send_hover));
    try std.testing.expect(luminance(amoled_send_hover) < luminance(amoled_send_pressed));
    try std.testing.expect(luminance(amoled_send) > luminance(amoled_button_pressed));
}

test "IGSH-461 AMOLED control boundaries and popup selections are visible without light slabs" {
    try std.testing.expect(contrastRatio(amoled.outline, amoled.surface) >= 3.0);
    try std.testing.expect(contrastRatio(amoled.outline, amoled.surface_container_high) >= 3.0);
    try std.testing.expect(contrastRatio(amoled.outline_variant, amoled.surface) >= 3.0);
    const selection_contrast = contrastRatio(amoled.secondary_container, amoled.surface);
    try std.testing.expect(selection_contrast >= 1.2 and selection_contrast <= 4.0);
    try std.testing.expect(contrastRatio(amoled.on_secondary_container, amoled.secondary_container) >= 4.5);
}

test "IGSH-461 default initial palette is AMOLED" {
    try std.testing.expectEqual(Choice.amoled, choice);
    try std.testing.expectEqual(&amoled, current);
}

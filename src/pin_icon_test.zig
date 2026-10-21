const std = @import("std");
const pin = @import("pin_icon.zig");
const shared = @import("smooth_geometry.zig");

test "IGSH-494 pin outline and slash stay inside the icon box at both scales" {
    for ([_]f32{ 1, 1.5, 2 }) |scale| {
        const margin = pin.stroke_width * scale / 2;
        inline for (.{ pin.outline, pin.needle, pin.slash }) |points| {
            for (points) |point| {
                for (point) |coordinate| {
                    try std.testing.expect(coordinate * scale >= margin);
                    try std.testing.expect(coordinate * scale <= pin.grid_size * scale - margin);
                }
            }
        }
    }
    try std.testing.expectEqualDeep(pin.outline[0], pin.outline[pin.outline.len - 1]);
}

test "IGSH-494 pin head and tapered body are symmetric with a centred needle" {
    for (pin.outline) |point| {
        const mirrored = for (pin.outline) |other| {
            if (other[0] == pin.grid_size - point[0] and other[1] == point[1]) break true;
        } else false;
        try std.testing.expect(mirrored);
    }
    try std.testing.expectEqualDeep([2]f32{ 8, 3 }, pin.outline[0]);
    try std.testing.expectEqualDeep([2]f32{ 16, 3 }, pin.outline[1]);
    try std.testing.expectEqualDeep([2]f32{ 15, 10 }, pin.outline[4]);
    try std.testing.expectEqualDeep([2]f32{ 18, 14 }, pin.outline[5]);
    try std.testing.expectEqualDeep([2][2]f32{ .{ 12, 15 }, .{ 12, 21 } }, pin.needle);
    try std.testing.expectEqualDeep([2][2]f32{ .{ 3, 3 }, .{ 21, 21 } }, pin.slash);
}

test "IGSH-494 pin stroke equals the shared neighbouring icon stroke" {
    try std.testing.expectEqual(@as(f32, @floatFromInt(shared.icon_stroke_width)), pin.stroke_width);
    try std.testing.expectEqual(@as(f32, 24), pin.grid_size);
}

test "IGSH-494 fallback pin strokes have smooth edges and a hollow body at both scales" {
    const coverage = @import("smooth_coverage.zig");
    for ([_]f32{ 1, 1.5, 2 }) |scale| {
        var points: [pin.outline.len][2]f32 = undefined;
        for (pin.outline, &points) |point, *scaled| scaled.* = .{ point[0] * scale, point[1] * scale };
        const shape = coverage.Polyline{ .points = &points, .width = pin.stroke_width * scale };
        var solid: usize = 0;
        var partial: usize = 0;
        const size: i32 = @intFromFloat(pin.grid_size * scale);
        var y: i32 = -2;
        while (y < size + 2) : (y += 1) {
            var x: i32 = -2;
            while (x < size + 2) : (x += 1) {
                const alpha = shape.alphaAt(x, y);
                if (x < 0 or y < 0 or x >= size or y >= size) try std.testing.expectEqual(@as(u8, 0), alpha);
                if (alpha == 255) solid += 1 else if (alpha > 0) {
                    partial += 1;
                }
            }
        }
        try std.testing.expect(solid > 0);
        try std.testing.expect(partial > 0);
        try std.testing.expectEqual(@as(u8, 0), shape.alphaAt(@intFromFloat(12 * scale), @intFromFloat(9 * scale)));
    }
    const empty = coverage.Polyline{ .points = &.{}, .width = pin.stroke_width };
    try std.testing.expectEqual(@as(u8, 0), empty.alphaAt(0, 0));
}

test "IGSH-494 pin colours contrast with AMOLED and Green normal selected and bulk rows" {
    const theme = @import("theme.zig");
    for ([_]theme.Palette{ theme.amoled, theme.green }) |palette| {
        for ([_]u32{ palette.surface_container_low, palette.surface_container_highest }) |background| {
            try std.testing.expect(theme.contrastRatio(palette.on_surface_variant, background) >= 3);
        }
        try std.testing.expect(theme.contrastRatio(palette.on_primary_container, palette.primary_container) >= 3);
    }
}

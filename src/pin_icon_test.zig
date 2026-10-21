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

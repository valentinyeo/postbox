const std = @import("std");

pub fn compute(outer: anytype, max_diameter: i32) struct { diameter: i32, inner: @TypeOf(outer) } {
    const height = @max(0, outer.bottom - outer.top);
    const width = @max(0, outer.right - outer.left);
    const diameter = @min(@max(0, max_diameter), height);
    const inset = @divTrunc(diameter, 2) + @mod(diameter, 2);
    var inner = outer;
    inner.left += @min(inset, @divTrunc(width, 2));
    inner.right = @max(inner.left, outer.right - inset);
    return .{ .diameter = diameter, .inner = inner };
}

const Rect = struct { left: i32, top: i32, right: i32, bottom: i32 };

test "inner edit corners stay inside the rounded pill away from corner arcs" {
    for ([_]i32{ 96, 120, 144, 192 }) |dpi| {
        for ([_]i32{ 34, 44, 55, 56, 57, 80, 240 }) |height| {
            const outer = Rect{ .left = -13, .top = 9, .right = 600, .bottom = 9 + @divTrunc(height * dpi, 96) };
            const pill = compute(outer, @divTrunc(56 * dpi, 96));
            const radius = @as(f64, @floatFromInt(pill.diameter)) / 2;
            for ([_]i32{ pill.inner.left, pill.inner.right }) |x| {
                for ([_]i32{ pill.inner.top, pill.inner.bottom }) |y| {
                    const xf: f64 = @floatFromInt(x);
                    const yf: f64 = @floatFromInt(y);
                    const cx = std.math.clamp(xf, @as(f64, @floatFromInt(outer.left)) + radius, @as(f64, @floatFromInt(outer.right)) - radius);
                    const cy = std.math.clamp(yf, @as(f64, @floatFromInt(outer.top)) + radius, @as(f64, @floatFromInt(outer.bottom)) - radius);
                    const dx = xf - cx;
                    const dy = yf - cy;
                    try std.testing.expect(dx * dx + dy * dy <= radius * radius);
                }
            }
            try std.testing.expectEqual(outer.top, pill.inner.top);
            try std.testing.expectEqual(outer.bottom, pill.inner.bottom);
        }
    }
}

test "diameter clamps to height and the scaled maximum" {
    for ([_]i32{ 0, 1, 17, 34, 44, 56, 120 }) |height| {
        const outer = Rect{ .left = 12, .top = 8, .right = 288, .bottom = 8 + height };
        const pill = compute(outer, 56);
        try std.testing.expectEqual(@min(@as(i32, 56), height), pill.diameter);
    }
}

test "small widths never produce a negative inner width" {
    for (0..65) |width| {
        const outer = Rect{ .left = 12, .top = 8, .right = 12 + @as(i32, @intCast(width)), .bottom = 52 };
        const pill = compute(outer, 56);
        try std.testing.expect(pill.inner.right >= pill.inner.left);
        try std.testing.expect(pill.inner.left >= outer.left);
        try std.testing.expect(pill.inner.right <= outer.right);
    }
}

test "normal fields inset both ends by half the diameter rounded up" {
    const search = compute(Rect{ .left = 12, .top = 8, .right = 288, .bottom = 42 }, 56);
    try std.testing.expectEqual(Rect{ .left = 29, .top = 8, .right = 271, .bottom = 42 }, search.inner);
    const compose = compute(Rect{ .left = 404, .top = 600, .right = 900, .bottom = 681 }, 57);
    try std.testing.expectEqual(Rect{ .left = 433, .top = 600, .right = 871, .bottom = 681 }, compose.inner);
}

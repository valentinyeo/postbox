const std = @import("std");
const geometry = @import("smooth_geometry.zig");
const mask = @import("avatar_mask.zig");

pub const Polyline = struct {
    points: []const [2]f32,
    width: f32,

    pub fn alphaAt(self: Polyline, x: i32, y: i32) u8 {
        if (self.points.len < 2) return 0;
        var distance_squared = std.math.inf(f32);
        const sample = [2]f32{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5 };
        for (self.points[0 .. self.points.len - 1], self.points[1..]) |start, end| {
            const dx = end[0] - start[0];
            const dy = end[1] - start[1];
            const length_squared = dx * dx + dy * dy;
            const t = if (length_squared > 0) std.math.clamp(((sample[0] - start[0]) * dx + (sample[1] - start[1]) * dy) / length_squared, 0, 1) else 0;
            const ox = sample[0] - start[0] - t * dx;
            const oy = sample[1] - start[1] - t * dy;
            distance_squared = @min(distance_squared, ox * ox + oy * oy);
        }
        return mask.distanceAlpha(@sqrt(distance_squared) - self.width / 2);
    }
};

const Edge = struct { distance: f32, nx: f32, ny: f32 };

pub const Shape = struct {
    rect: geometry.Rect,
    corner_width: i32 = 0,
    corner_height: i32 = 0,
    ellipse: bool = false,
    stroke: ?i32 = null,
    arc: ?struct { start: f32, sweep: f32 } = null,

    pub fn alphaAt(self: Shape, x: i32, y: i32) u8 {
        const inset: f32 = if (self.stroke != null) 1 else 0;
        const width = @as(f32, @floatFromInt(self.rect.right - self.rect.left)) - inset;
        const height = @as(f32, @floatFromInt(self.rect.bottom - self.rect.top)) - inset;
        if (width <= 0 or height <= 0) return 0;
        const cx = @as(f32, @floatFromInt(self.rect.left)) + width / 2;
        const cy = @as(f32, @floatFromInt(self.rect.top)) + height / 2;
        const px = @as(f32, @floatFromInt(x)) + 0.5 - cx;
        const py = @as(f32, @floatFromInt(y)) + 0.5 - cy;
        const rx = if (self.ellipse) width / 2 else @as(f32, @floatFromInt(std.math.clamp(self.corner_width, 0, @as(i32, @intFromFloat(width))))) / 2;
        const ry = if (self.ellipse) height / 2 else @as(f32, @floatFromInt(std.math.clamp(self.corner_height, 0, @as(i32, @intFromFloat(height))))) / 2;
        const qx = @abs(px) - (width / 2 - rx);
        const qy = @abs(py) - (height / 2 - ry);
        const curved = rx > 0 and ry > 0 and (qx > 0 and qy > 0 or self.ellipse);
        if (curved) {
            const normalized = @sqrt(qx * qx / (rx * rx) + qy * qy / (ry * ry));
            const lower_bound = @abs(normalized - 1) * @min(rx, ry);
            const reach = if (self.stroke) |stroke| @as(f32, @floatFromInt(@max(1, stroke))) / 2 + 0.75 else 0.75;
            if (lower_bound >= reach) return if (self.stroke == null and normalized < 1) 255 else 0;
        }
        const edge: Edge = if (rx == 0 or ry == 0)
            .{ .distance = @max(@abs(px) - width / 2, @abs(py) - height / 2), .nx = @as(f32, if (@abs(px) - width / 2 > @abs(py) - height / 2) 1 else 0), .ny = @as(f32, if (@abs(px) - width / 2 > @abs(py) - height / 2) 0 else 1) }
        else if (curved)
            ellipseDistance(@abs(qx), @abs(qy), rx, ry)
        else
            .{ .distance = @max(qx - rx, qy - ry), .nx = @as(f32, if (qx - rx > qy - ry) 1 else 0), .ny = @as(f32, if (qx - rx > qy - ry) 0 else 1) };
        const half_stroke = if (self.stroke) |stroke| if (stroke <= 1) @max(edge.nx, edge.ny) / 2 else @as(f32, @floatFromInt(stroke)) / 2 else 0;
        var start: f32 = 0;
        var end: f32 = 0;
        var direction: f32 = 1;
        var sweep: f32 = 2 * std.math.pi;
        if (self.arc) |arc| {
            if (arc.sweep == 0) return 0;
            if (@abs(arc.sweep) < 360) {
                const radians: f32 = std.math.pi / 180.0;
                const from = arc.start * radians;
                const to = (arc.start + arc.sweep) * radians;
                start = std.math.atan2(rx * @sin(from), ry * @cos(from));
                end = std.math.atan2(rx * @sin(to), ry * @cos(to));
                direction = if (arc.sweep > 0) 1 else -1;
                sweep = @mod((end - start) * direction, 2 * std.math.pi);
            }
        }
        var samples: u32 = 0;
        for (0..4) |sy| {
            for (0..8) |sx| {
                const dx = (@as(f32, @floatFromInt(sx)) + 0.5) / 8 - 0.5;
                const dy = (@as(f32, @floatFromInt(sy)) + 0.5) / 4 - 0.5;
                const distance = edge.distance + dx * edge.nx + dy * edge.ny;
                if (if (self.stroke != null) @abs(distance) >= half_stroke else distance >= 0) continue;
                if (sweep < 2 * std.math.pi) {
                    const x_sample = px + dx * @as(f32, if (px < 0) -1 else 1);
                    const y_sample = py + dy * @as(f32, if (py < 0) -1 else 1);
                    const angle = std.math.atan2(y_sample / ry, x_sample / rx);
                    const progress = @mod((angle - start) * direction, 2 * std.math.pi);
                    const sx_cap = x_sample - rx * @cos(start);
                    const sy_cap = y_sample - ry * @sin(start);
                    const ex_cap = x_sample - rx * @cos(end);
                    const ey_cap = y_sample - ry * @sin(end);
                    const near_start = sx_cap * sx_cap + sy_cap * sy_cap < ex_cap * ex_cap + ey_cap * ey_cap;
                    const reach = @as(f32, @floatFromInt(@max(1, self.stroke.?))) / 2 + 1;
                    if (@min(sx_cap * sx_cap + sy_cap * sy_cap, ex_cap * ex_cap + ey_cap * ey_cap) <= reach * reach) {
                        const cap = if (near_start) capDistance(x_sample, y_sample, rx, ry, start) * direction else -capDistance(x_sample, y_sample, rx, ry, end) * direction;
                        if (cap < 0) continue;
                    } else if (progress > sweep) continue;
                }
                samples += 1;
            }
        }
        return mask.distanceAlpha(0.5 - @as(f32, @floatFromInt(samples)) / 32);
    }
};

fn capDistance(x: f32, y: f32, rx: f32, ry: f32, angle: f32) f32 {
    const tx = -rx * @sin(angle);
    const ty = ry * @cos(angle);
    return ((x - rx * @cos(angle)) * tx + (y - ry * @sin(angle)) * ty) / @sqrt(tx * tx + ty * ty);
}

fn ellipseDistance(x: f32, y: f32, rx: f32, ry: f32) Edge {
    if (rx == ry) {
        const length = @sqrt(x * x + y * y);
        return .{ .distance = length - rx, .nx = if (length > 0) x / length else 1, .ny = if (length > 0) y / length else 0 };
    }
    const normalized = x * x / (rx * rx) + y * y / (ry * ry);
    var lo: f32 = 0;
    var hi: f32 = std.math.pi / 2.0;
    for (0..32) |_| {
        const a = (2 * lo + hi) / 3;
        const b = (lo + 2 * hi) / 3;
        const ax = rx * @cos(a) - x;
        const ay = ry * @sin(a) - y;
        const bx = rx * @cos(b) - x;
        const by = ry * @sin(b) - y;
        if (ax * ax + ay * ay < bx * bx + by * by) hi = b else lo = a;
    }
    const angle = (lo + hi) / 2;
    const dx = rx * @cos(angle) - x;
    const dy = ry * @sin(angle) - y;
    const nx = @cos(angle) / rx;
    const ny = @sin(angle) / ry;
    const length = @sqrt(nx * nx + ny * ny);
    return .{ .distance = @sqrt(dx * dx + dy * dy) * @as(f32, if (normalized < 1) -1 else 1), .nx = nx / length, .ny = ny / length };
}

pub fn premultiplied(color: u32, alpha: u8) u32 {
    const a: u32 = alpha;
    const r = ((color & 255) * a + 127) / 255;
    const g = (((color >> 8) & 255) * a + 127) / 255;
    const b = (((color >> 16) & 255) * a + 127) / 255;
    return (a << 24) | (r << 16) | (g << 8) | b;
}

test "fallback corner has partial edge coverage opaque interior and transparent exterior" {
    const shape = Shape{ .rect = .{ .left = 0, .top = 0, .right = 40, .bottom = 30 }, .corner_width = 16, .corner_height = 16 };
    try std.testing.expectEqual(@as(u8, 0), shape.alphaAt(0, 0));
    try std.testing.expectEqual(@as(u8, 255), shape.alphaAt(7, 7));
    try std.testing.expectEqual(@as(u8, 0), shape.alphaAt(-1, 10));
    const edge = shape.alphaAt(2, 2);
    try std.testing.expect(edge > 0 and edge < 255);
}

test "fallback bands and coverage corners tile every translated pixel exactly once" {
    for ([_][4]i32{ .{ 80, 30, 16, 16 }, .{ 31, 47, 15, 21 }, .{ 9, 60, 99, 9 }, .{ 60, 9, 9, 9 } }) |dimensions| {
        const rect = geometry.Rect{ .left = -7, .top = 11, .right = dimensions[0] - 7, .bottom = dimensions[1] + 11 };
        const parts = geometry.partition(rect, dimensions[2], dimensions[3]).?;
        const shape = Shape{ .rect = rect, .corner_width = dimensions[2], .corner_height = dimensions[3] };
        var y = rect.top;
        while (y < rect.bottom) : (y += 1) {
            var x = rect.left;
            while (x < rect.right) : (x += 1) {
                var hits: usize = 0;
                var alpha: u8 = 0;
                for (parts.bands ++ parts.corners, 0..) |box, i| {
                    if (x >= box.left and x < box.right and y >= box.top and y < box.bottom) {
                        hits += 1;
                        alpha = if (i < parts.bands.len) 255 else shape.alphaAt(x, y);
                    }
                }
                try std.testing.expectEqual(@as(usize, 1), hits);
                try std.testing.expectEqual(shape.alphaAt(x, y), alpha);
            }
        }
    }
}

test "fallback pixels premultiply every colour channel" {
    for (0..256) |alpha| {
        const a: u8 = @intCast(alpha);
        const pixel = premultiplied(0x007f80ff, a);
        try std.testing.expectEqual(a, pixel >> 24);
        try std.testing.expectEqual(a, (pixel >> 16) & 255);
        try std.testing.expectEqual((128 * alpha + 127) / 255, (pixel >> 8) & 255);
        try std.testing.expectEqual((127 * alpha + 127) / 255, pixel & 255);
    }
}

test "fallback circles have symmetric sampled coverage at both display scales" {
    for ([_]usize{ 42, 63 }) |size| {
        const shape = Shape{ .rect = .{ .left = 0, .top = 0, .right = @intCast(size), .bottom = @intCast(size) }, .ellipse = true };
        for (0..size) |y| {
            for (0..size) |x| {
                try std.testing.expectEqual(shape.alphaAt(@intCast(size - 1 - x), @intCast(size - 1 - y)), shape.alphaAt(@intCast(x), @intCast(y)));
            }
        }
    }
}

test "fallback ring has a hollow centre and antialiased inner and outer edges" {
    const shape = Shape{ .rect = .{ .left = 0, .top = 0, .right = 41, .bottom = 41 }, .ellipse = true, .stroke = 3 };
    try std.testing.expectEqual(@as(u8, 0), shape.alphaAt(20, 20));
    try std.testing.expectEqual(@as(u8, 0), shape.alphaAt(-3, 20));
    try std.testing.expectEqual(@as(u8, 255), shape.alphaAt(0, 20));
    const outer = shape.alphaAt(-2, 20);
    const inner = shape.alphaAt(1, 20);
    try std.testing.expect(outer > 0 and outer < 255);
    try std.testing.expect(inner > 0 and inner < 255);
}

test "one pixel ellipse strokes follow the dominant normal with sampled coverage" {
    const shape = Shape{ .rect = .{ .left = 0, .top = 0, .right = 81, .bottom = 61 }, .ellipse = true, .stroke = 1 };
    var area: u64 = 0;
    var y: i32 = -2;
    while (y < 63) : (y += 1) {
        var x: i32 = -2;
        while (x < 83) : (x += 1) {
            const alpha = shape.alphaAt(x, y);
            area += alpha;
            try std.testing.expect(alpha == 0 or alpha == 255 or (alpha + 1) % 8 == 0);
        }
    }
    const projected_perimeter = 2 * @sqrt(@as(f64, 80 * 80 + 60 * 60));
    try std.testing.expect(@abs(@as(f64, @floatFromInt(area)) / 255 - projected_perimeter) <= projected_perimeter * 0.02);
}

test "fallback arc respects clockwise and counterclockwise sweeps and flat caps" {
    const rect = geometry.Rect{ .left = 0, .top = 0, .right = 41, .bottom = 21 };
    const lower = Shape{ .rect = rect, .ellipse = true, .stroke = 2, .arc = .{ .start = 180, .sweep = -180 } };
    const upper = Shape{ .rect = rect, .ellipse = true, .stroke = 2, .arc = .{ .start = 180, .sweep = 180 } };
    try std.testing.expectEqual(@as(u8, 255), lower.alphaAt(20, 19));
    try std.testing.expectEqual(@as(u8, 0), lower.alphaAt(20, 0));
    try std.testing.expectEqual(@as(u8, 0), upper.alphaAt(20, 19));
    try std.testing.expectEqual(@as(u8, 255), upper.alphaAt(20, 0));
    const empty = Shape{ .rect = rect, .ellipse = true, .stroke = 2, .arc = .{ .start = 180, .sweep = 0 } };
    try std.testing.expectEqual(@as(u8, 0), empty.alphaAt(0, 10));
}

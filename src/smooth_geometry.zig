const std = @import("std");

pub const icon_stroke_width: i32 = 2;

pub const Rect = extern struct { left: i32, top: i32, right: i32, bottom: i32 };

pub const Partition = struct {
    bands: [3]Rect,
    corners: [4]Rect,
};

pub fn partition(rect: Rect, corner_width: i32, corner_height: i32) ?Partition {
    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    if (width <= 0 or height <= 0) return null;
    const w = std.math.clamp(corner_width, 0, width);
    const h = std.math.clamp(corner_height, 0, height);
    if (w == 0 or h == 0 or (width - w <= 2 and height - h <= 2)) return null;
    const x1 = rect.left + @divTrunc(w, 2) + @mod(w, 2);
    const x2 = @max(x1, rect.right - @divTrunc(w, 2) - @mod(w, 2));
    const y1 = rect.top + @divTrunc(h, 2) + @mod(h, 2);
    const y2 = @max(y1, rect.bottom - @divTrunc(h, 2) - @mod(h, 2));
    return .{
        .bands = .{
            .{ .left = rect.left, .top = y1, .right = rect.right, .bottom = y2 },
            .{ .left = x1, .top = rect.top, .right = x2, .bottom = y1 },
            .{ .left = x1, .top = y2, .right = x2, .bottom = rect.bottom },
        },
        .corners = .{
            .{ .left = rect.left, .top = rect.top, .right = x1, .bottom = y1 },
            .{ .left = x2, .top = rect.top, .right = rect.right, .bottom = y1 },
            .{ .left = x2, .top = y2, .right = rect.right, .bottom = rect.bottom },
            .{ .left = rect.left, .top = y2, .right = x1, .bottom = rect.bottom },
        },
    };
}

test "bands and corner boxes exactly tile translated rounded bounds at both scales" {
    for ([_]i32{ 2, 3 }) |scale| {
        for ([_][4]i32{
            .{ 300, 40, 32, 32 },
            .{ 700, 200, 32, 32 },
            .{ 120, 40, 32, 32 },
            .{ 9, 60, 9, 9 },
            .{ 60, 9, 9, 9 },
            .{ 31, 47, 15, 21 },
            .{ 9, 60, 99, 9 },
        }) |dimensions| {
            const width = @divTrunc(dimensions[0] * scale, 2);
            const height = @divTrunc(dimensions[1] * scale, 2);
            const rect = Rect{ .left = -7, .top = 11, .right = width - 7, .bottom = height + 11 };
            const parts = partition(rect, @divTrunc(dimensions[2] * scale, 2), @divTrunc(dimensions[3] * scale, 2)).?;
            var area: i32 = 0;
            for (parts.bands ++ parts.corners) |cell| {
                try std.testing.expect(cell.left >= rect.left and cell.right <= rect.right);
                try std.testing.expect(cell.top >= rect.top and cell.bottom <= rect.bottom);
                try std.testing.expect(cell.left <= cell.right and cell.top <= cell.bottom);
                area += (cell.right - cell.left) * (cell.bottom - cell.top);
            }
            try std.testing.expectEqual(width * height, area);
            var y = rect.top;
            while (y < rect.bottom) : (y += 1) {
                var x = rect.left;
                while (x < rect.right) : (x += 1) {
                    var hits: usize = 0;
                    for (parts.bands ++ parts.corners) |cell| {
                        if (x >= cell.left and x < cell.right and y >= cell.top and y < cell.bottom) hits += 1;
                    }
                    try std.testing.expectEqual(@as(usize, 1), hits);
                }
            }
        }
    }
}

test "small full-path shapes and invalid or square corners do not use hybrid bands" {
    const rect = Rect{ .left = 3, .top = 5, .right = 25, .bottom = 27 };
    try std.testing.expect(partition(rect, 20, 20) == null);
    try std.testing.expect(partition(rect, 100, 100) == null);
    try std.testing.expect(partition(rect, 0, 10) == null);
    try std.testing.expect(partition(rect, 10, -1) == null);
    try std.testing.expect(partition(.{ .left = 3, .top = 5, .right = 3, .bottom = 27 }, 10, 10) == null);
    try std.testing.expect(partition(.{ .left = 3, .top = 5, .right = 25, .bottom = 4 }, 10, 10) == null);
    try std.testing.expect(partition(rect, 19, 20) != null);
}

pub fn counterclockwiseArc(rect: Rect, from: [2]i32, to: [2]i32) struct { start: f32, sweep: f32 } {
    const cx = (@as(f32, @floatFromInt(rect.left)) + @as(f32, @floatFromInt(rect.right))) / 2;
    const cy = (@as(f32, @floatFromInt(rect.top)) + @as(f32, @floatFromInt(rect.bottom))) / 2;
    const start = @mod(std.math.atan2(@as(f32, @floatFromInt(from[1])) - cy, @as(f32, @floatFromInt(from[0])) - cx) * 180 / std.math.pi, 360);
    const end = @mod(std.math.atan2(@as(f32, @floatFromInt(to[1])) - cy, @as(f32, @floatFromInt(to[0])) - cx) * 180 / std.math.pi, 360);
    const sweep = end - start;
    return .{ .start = start, .sweep = if (sweep >= 0) sweep - 360 else sweep };
}

test "GDI counterclockwise endpoint rays convert to lower microphone cradle at both scales" {
    for ([_]i32{ 96, 144 }) |dpi| {
        const arc = @divTrunc(7 * dpi + 48, 96);
        const top = -@divTrunc(7 * dpi + 48, 96);
        const bottom = @divTrunc(6 * dpi + 48, 96);
        const y = -@divTrunc(dpi + 48, 96);
        const angles = counterclockwiseArc(.{ .left = 20 - arc, .top = 30 + top, .right = 20 + arc + 1, .bottom = 30 + bottom }, .{ 20 - arc, 30 + y }, .{ 20 + arc + 1, 30 + y });
        try std.testing.expectApproxEqAbs(@as(f32, if (dpi == 96) 183.814075 else 184.969741), angles.start, 0.0001);
        try std.testing.expectApproxEqAbs(@as(f32, if (dpi == 96) -187.628150 else -189.939482), angles.sweep, 0.0001);
        try std.testing.expect(@sin((angles.start + angles.sweep / 2) * std.math.pi / 180) > 0.99);
    }
}

test "GDI counterclockwise arcs wrap around zero and identical rays draw a full ellipse" {
    const rect = Rect{ .left = -10, .top = -5, .right = 10, .bottom = 5 };
    const quarter = counterclockwiseArc(rect, .{ 10, 0 }, .{ 0, -5 });
    try std.testing.expectEqual(@as(f32, 0), quarter.start);
    try std.testing.expectEqual(@as(f32, -90), quarter.sweep);
    const full = counterclockwiseArc(rect, .{ 10, 0 }, .{ 20, 0 });
    try std.testing.expectEqual(@as(f32, -360), full.sweep);
}

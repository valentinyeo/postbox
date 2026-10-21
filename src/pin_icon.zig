const shared = @import("smooth_geometry.zig");

pub const grid_size: f32 = 24;
pub const stroke_width: f32 = @floatFromInt(shared.icon_stroke_width);
pub const outline = [_][2]f32{
    .{ 8, 3 },
    .{ 16, 3 },
    .{ 16, 5 },
    .{ 15, 5 },
    .{ 15, 10 },
    .{ 18, 14 },
    .{ 18, 15 },
    .{ 6, 15 },
    .{ 6, 14 },
    .{ 9, 10 },
    .{ 9, 5 },
    .{ 8, 5 },
    .{ 8, 3 },
};
pub const needle = [_][2]f32{ .{ 12, 15 }, .{ 12, 21 } };
pub const slash = [_][2]f32{ .{ 3, 3 }, .{ 21, 21 } };

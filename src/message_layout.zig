const std = @import("std");
const read_receipt = @import("read_receipt.zig");

pub const Rect = struct { left: i32, top: i32, right: i32, bottom: i32 };

pub const bubble_bottom_pad: i32 = 10;
pub const tick_size: i32 = 6;
pub const tick_gap: i32 = 3;
pub const tick_stroke: i32 = 2;
pub const tick_right_inset: i32 = 11;
pub const tick_bottom_inset: i32 = 3;
pub const max_ticks: usize = 2;
pub const tick_points: usize = 3;
pub const Point = [2]f32;
pub const Polyline = [tick_points]Point;
pub const TickStorage = [max_ticks]Polyline;

const tick_low: f32 = 0.5;
const tick_knee: f32 = 0.35;

pub fn fillTicks(storage: *TickStorage, bubble_right: i32, bubble_bottom: i32, count: usize) []const Polyline {
    const shown = @min(count, max_ticks);
    for (storage[0..shown], 0..) |*poly, ordinal| {
        poly.* = tickPolyline(tickRect(bubble_right, bubble_bottom, ordinal));
    }
    return storage[0..shown];
}

pub fn tickRect(bubble_right: i32, bubble_bottom: i32, ordinal: usize) Rect {
    const right = bubble_right - tick_right_inset - @as(i32, @intCast(ordinal)) * (tick_size + tick_gap);
    const bottom = bubble_bottom - tick_bottom_inset;
    return .{ .left = right - tick_size, .top = bottom - tick_size, .right = right, .bottom = bottom };
}

pub fn tickPolyline(rect: Rect) Polyline {
    const width: f32 = @floatFromInt(rect.right - rect.left);
    const height: f32 = @floatFromInt(rect.bottom - rect.top);
    const left: f32 = @floatFromInt(rect.left);
    const top: f32 = @floatFromInt(rect.top);
    return .{
        .{ left, top + height * tick_low },
        .{ left + width * tick_knee, top + height },
        .{ left + width, top },
    };
}

pub const Parts = struct {
    quote: i32 = 0,
    header: i32 = 0,
    forwarded: i32 = 0,
    body: i32 = 0,
    unfurl: i32 = 0,
    media: i32 = 0,
    voice_status: i32 = 0,
    transcript: i32 = 0,
    tail_pad: i32 = 0,
    min_body: i32 = 0,
    reaction_overhang: i32 = 0,
    skip_body: bool = false,
};

pub fn total(parts: Parts) i32 {
    const sum = parts.quote + parts.header + parts.forwarded + (if (parts.skip_body) @as(i32, 0) else parts.body) + parts.unfurl + parts.media + parts.voice_status + parts.transcript + parts.tail_pad;
    return @max(sum, parts.header + parts.min_body) + @max(0, parts.reaction_overhang);
}

test "empty parts have zero height" {
    try std.testing.expectEqual(@as(i32, 0), total(.{}));
}

test "each part contributes to height" {
    inline for (.{ "quote", "header", "forwarded", "body", "unfurl", "media", "voice_status", "transcript", "tail_pad", "reaction_overhang" }) |name| {
        var parts = Parts{};
        @field(parts, name) = 7;
        try std.testing.expectEqual(@as(i32, 7), total(parts));
    }
    try std.testing.expectEqual(@as(i32, 7), total(.{ .min_body = 7 }));
    try std.testing.expectEqual(@as(i32, 0), total(.{ .body = 7, .skip_body = true }));
}

test "minimum height includes header when body is empty" {
    try std.testing.expectEqual(@as(i32, 30), total(.{ .header = 10, .min_body = 20, .tail_pad = 5, .skip_body = true }));
    try std.testing.expectEqual(@as(i32, 35), total(.{ .header = 10, .min_body = 20, .body = 20, .tail_pad = 5 }));
}

test "only positive reaction overhang adds height" {
    try std.testing.expectEqual(@as(i32, 10), total(.{ .body = 10, .reaction_overhang = -4 }));
    try std.testing.expectEqual(@as(i32, 10), total(.{ .body = 10 }));
    try std.testing.expectEqual(@as(i32, 14), total(.{ .body = 10, .reaction_overhang = 4 }));
}

test "height is monotonic in each part" {
    inline for (.{ "quote", "header", "forwarded", "body", "unfurl", "media", "voice_status", "transcript", "tail_pad", "min_body", "reaction_overhang" }) |name| {
        var parts = Parts{ .quote = 3, .header = 5, .forwarded = 2, .body = 11, .unfurl = 4, .media = 8, .voice_status = 3, .transcript = 6, .tail_pad = 2, .min_body = 50, .reaction_overhang = 1 };
        const before = total(parts);
        @field(parts, name) += 10;
        try std.testing.expect(total(parts) >= before);
    }
}

test "height scales with measured parts across widths and font scales" {
    const cases = [_]struct { width: i32, body: i32, media: i32 }{
        .{ .width = 200, .body = 73, .media = 91 },
        .{ .width = 400, .body = 37, .media = 143 },
        .{ .width = 800, .body = 19, .media = 211 },
    };
    for (cases) |case| {
        try std.testing.expect(case.width > 0);
        const base = Parts{ .quote = 23, .header = 17, .forwarded = 13, .body = case.body, .unfurl = 29, .media = case.media, .voice_status = 11, .transcript = 31, .tail_pad = 7, .min_body = 20, .reaction_overhang = 5 };
        for ([_]i32{ 100, 125, 150, 200 }) |scale| {
            var scaled = base;
            inline for (.{ "quote", "header", "forwarded", "body", "unfurl", "media", "voice_status", "transcript", "tail_pad", "min_body", "reaction_overhang" }) |name| {
                @field(scaled, name) = @divTrunc(@field(base, name) * scale + 50, 100);
            }
            const expected = @divTrunc(total(base) * scale + 50, 100);
            try std.testing.expect(@abs(total(scaled) - expected) <= 11);
        }
    }
}

test "SOFT-3129 one tick sits in the bubble bottom pad and stays inside the bubble" {
    var storage: TickStorage = undefined;
    const sent = fillTicks(&storage, 400, 300, read_receipt.ticks(.sent));
    try std.testing.expectEqual(@as(usize, 1), sent.len);
    const rect = tickRect(400, 300, 0);
    try std.testing.expectEqual(@as(i32, 400 - tick_right_inset), rect.right);
    try std.testing.expectEqual(@as(i32, 300 - tick_bottom_inset), rect.bottom);
    try std.testing.expectEqual(@as(i32, tick_size), rect.right - rect.left);
    try std.testing.expect(rect.bottom <= 300);
    try std.testing.expect(rect.top >= 300 - bubble_bottom_pad);
    try std.testing.expect(tick_size + tick_bottom_inset <= bubble_bottom_pad);
}

test "SOFT-3129 two ticks sit side by side under the same time edge" {
    var storage: TickStorage = undefined;
    const delivered = fillTicks(&storage, 400, 300, read_receipt.ticks(.delivered));
    const read = fillTicks(&storage, 400, 300, read_receipt.ticks(.read));
    try std.testing.expectEqual(@as(usize, 2), delivered.len);
    try std.testing.expectEqual(@as(usize, 2), read.len);
    const newest = tickRect(400, 300, 0);
    const older = tickRect(400, 300, 1);
    try std.testing.expectEqual(newest.left - tick_gap, older.right);
    try std.testing.expectEqual(newest.bottom, older.bottom);
    try std.testing.expect(older.left >= 400 - tick_right_inset - (tick_size * max_ticks + tick_gap * (max_ticks - 1)));
    try std.testing.expectEqual(@as(usize, 0), fillTicks(&storage, 400, 300, read_receipt.ticks(.none)).len);
    try std.testing.expectEqual(max_ticks, fillTicks(&storage, 400, 300, 9).len);
}

test "SOFT-3129 the ticks stay inside the rounded bubble corner" {
    const design = @import("design_tokens.zig");
    var storage: TickStorage = undefined;
    const ticks = fillTicks(&storage, 400, 300, read_receipt.ticks(.delivered));
    const radius: f32 = @floatFromInt(design.bubble_radius);
    const reach: f32 = @floatFromInt(tick_stroke / 2);
    for (ticks) |poly| {
        for (poly) |point| {
            const above: f32 = 300 - point[1];
            const drop = @max(@as(f32, 0), radius - above);
            const inset = radius - @sqrt(@max(@as(f32, 0), radius * radius - drop * drop));
            try std.testing.expect(point[0] + reach <= 400 - inset + 1);
        }
    }
}

test "SOFT-3129 each tick draws a check inside its own box" {
    const rect = tickRect(400, 300, 0);
    const poly = tickPolyline(rect);
    try std.testing.expectEqual(@as(f32, @floatFromInt(rect.left)), poly[0][0]);
    try std.testing.expectEqual(@as(f32, @floatFromInt(rect.right)), poly[2][0]);
    try std.testing.expectEqual(@as(f32, @floatFromInt(rect.bottom)), poly[1][1]);
    for (poly) |point| {
        try std.testing.expect(point[0] >= @as(f32, @floatFromInt(rect.left)));
        try std.testing.expect(point[0] <= @as(f32, @floatFromInt(rect.right)));
        try std.testing.expect(point[1] >= @as(f32, @floatFromInt(rect.top)));
        try std.testing.expect(point[1] <= @as(f32, @floatFromInt(rect.bottom)));
    }
}

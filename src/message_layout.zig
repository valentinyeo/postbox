const std = @import("std");

pub const Rect = struct { left: i32, top: i32, right: i32, bottom: i32 };

pub const read_mark_gap: i32 = 3;
pub const read_mark_text_gap: i32 = 5;

pub fn readMarkSlot(line_height: i32) i32 {
    return line_height + read_mark_gap;
}

pub fn readMarkRect(bubble_right: i32, bubble_bottom: i32, overhang: i32, slot: i32, width: i32) Rect {
    const top = bubble_bottom + @max(0, overhang) + read_mark_gap;
    const right = bubble_right;
    return .{ .left = right - width, .top = top, .right = right, .bottom = top + slot - read_mark_gap };
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
    read_mark: i32 = 0,
    skip_body: bool = false,
};

pub fn total(parts: Parts) i32 {
    const sum = parts.quote + parts.header + parts.forwarded + (if (parts.skip_body) @as(i32, 0) else parts.body) + parts.unfurl + parts.media + parts.voice_status + parts.transcript + parts.tail_pad;
    return @max(sum, parts.header + parts.min_body) + @max(0, parts.reaction_overhang) + @max(0, parts.read_mark);
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

test "a read mark reserves room below the bubble" {
    try std.testing.expectEqual(@as(i32, 26), total(.{ .body = 10, .read_mark = 16 }));
    try std.testing.expectEqual(@as(i32, 10), total(.{ .body = 10, .read_mark = -4 }));
    try std.testing.expectEqual(@as(i32, 16), readMarkSlot(13));
}

test "the read mark sits under the bubble right edge, below any reaction overhang" {
    const plain = readMarkRect(400, 300, 0, 16, 60);
    try std.testing.expectEqual(@as(i32, 303), plain.top);
    try std.testing.expectEqual(@as(i32, 316), plain.bottom);
    try std.testing.expectEqual(@as(i32, 340), plain.left);
    try std.testing.expectEqual(@as(i32, 400), plain.right);
    const with_chip = readMarkRect(400, 300, 22, 16, 60);
    try std.testing.expectEqual(@as(i32, 325), with_chip.top);
    try std.testing.expectEqual(@as(i32, 338), with_chip.bottom);
    try std.testing.expectEqual(@as(i32, 300), plain.top - read_mark_gap);
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

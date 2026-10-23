const std = @import("std");

pub const Endpoint = struct {
    message: usize,
    word: usize,
    start: usize,
    end: usize,
};

pub const Range = struct { start: usize, end: usize };

pub const Selection = struct {
    anchor: ?Endpoint = null,
    focus: Endpoint = .{ .message = 0, .word = 0, .start = 0, .end = 0 },

    pub fn active(self: Selection) bool {
        const anchor = self.anchor orelse return false;
        return anchor.message != self.focus.message or anchor.word != self.focus.word;
    }

    pub fn bounds(self: Selection) ?[2]Endpoint {
        const anchor = self.anchor orelse return null;
        const forward = anchor.message < self.focus.message or
            (anchor.message == self.focus.message and anchor.word <= self.focus.word);
        return if (forward) .{ anchor, self.focus } else .{ self.focus, anchor };
    }

    pub fn range(self: Selection, message: usize, text_len: usize) ?Range {
        if (!self.active()) return null;
        const ends = self.bounds() orelse return null;
        if (message < ends[0].message or message > ends[1].message) return null;
        const start = @min(text_len, if (message == ends[0].message) ends[0].start else 0);
        const end = @min(text_len, if (message == ends[1].message) ends[1].end else text_len);
        return .{ .start = start, .end = @max(start, end) };
    }
};

pub const Message = struct {
    sender: []const u16,
    from_me: bool = false,
    time: []const u16,
    day: []const u8,
    text: []const u16,
    start: usize = 0,
    end: usize,
};

pub fn build(allocator: std.mem.Allocator, messages: []const Message) ![]u16 {
    var out: std.ArrayList(u16) = .empty;
    errdefer out.deinit(allocator);
    var day: ?[]const u8 = null;
    for (messages) |message| {
        const start = @min(message.start, message.text.len);
        const end = @min(message.end, message.text.len);
        if (end <= start) continue;
        if (messages.len == 1) return allocator.dupe(u16, message.text[start..end]);
        if (day) |previous| {
            try out.appendSlice(allocator, wide("\r\n"));
            if (!std.mem.eql(u8, previous, message.day)) {
                for (message.day) |unit| try out.append(allocator, unit);
                try out.appendSlice(allocator, wide("\r\n"));
            }
        }
        day = message.day;
        try out.appendSlice(allocator, if (message.from_me) wide("You") else message.sender);
        try out.appendSlice(allocator, wide(", "));
        try out.appendSlice(allocator, message.time);
        try out.appendSlice(allocator, wide(": "));
        var index = start;
        while (index < end) : (index += 1) {
            const unit = message.text[index];
            if (unit == '\r' or unit == '\n') {
                try out.appendSlice(allocator, wide("\r\n"));
                if (unit == '\r' and index + 1 < end and message.text[index + 1] == '\n') index += 1;
            } else try out.append(allocator, unit);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn wide(comptime text: []const u8) []const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

test "passage partial first and last messages retain stamps" {
    const text = wide("alpha middle omega");
    const messages = [_]Message{
        .{ .sender = wide("Fixture Amber"), .time = wide("12:02"), .day = "2026-10-10", .text = text, .start = 6, .end = text.len },
        .{ .sender = wide("Fixture Cobalt"), .time = wide("12:03"), .day = "2026-10-10", .text = text, .end = 12 },
    };
    const actual = try build(std.testing.allocator, &messages);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualSlices(u16, wide("Fixture Amber, 12:02: middle omega\r\nFixture Cobalt, 12:03: alpha middle"), actual);
}

test "passage own messages use You" {
    const messages = [_]Message{
        .{ .sender = wide("Fixture Amber"), .from_me = true, .time = wide("09:00"), .day = "2026-10-10", .text = wide("one"), .end = 3 },
        .{ .sender = wide("Fixture Cobalt"), .time = wide("09:01"), .day = "2026-10-10", .text = wide("two"), .end = 3 },
    };
    const actual = try build(std.testing.allocator, &messages);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualSlices(u16, wide("You, 09:00: one\r\nFixture Cobalt, 09:01: two"), actual);
}

test "passage date appears only at an internal day change" {
    const messages = [_]Message{
        .{ .sender = wide("A"), .time = wide("23:59"), .day = "2026-10-10", .text = wide("one"), .end = 3 },
        .{ .sender = wide("B"), .time = wide("00:01"), .day = "2026-10-11", .text = wide("two"), .end = 3 },
        .{ .sender = wide("A"), .time = wide("00:02"), .day = "2026-10-11", .text = wide("end"), .end = 3 },
    };
    const actual = try build(std.testing.allocator, &messages);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualSlices(u16, wide("A, 23:59: one\r\n2026-10-11\r\nB, 00:01: two\r\nA, 00:02: end"), actual);
}

test "passage skips media-only messages with empty text" {
    const messages = [_]Message{
        .{ .sender = wide("A"), .time = wide("12:00"), .day = "2026-10-10", .text = wide("one"), .end = 3 },
        .{ .sender = wide("B"), .time = wide("12:01"), .day = "2026-10-11", .text = &.{}, .end = 0 },
        .{ .sender = wide("A"), .time = wide("12:02"), .day = "2026-10-11", .text = wide("two"), .end = 3 },
    };
    const actual = try build(std.testing.allocator, &messages);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualSlices(u16, wide("A, 12:00: one\r\n2026-10-11\r\nA, 12:02: two"), actual);
}

test "passage single-message range returns only selected words" {
    const actual = try build(std.testing.allocator, &.{.{ .sender = wide("A"), .time = wide("12:00"), .day = "2026-10-10", .text = wide("alpha middle omega"), .start = 6, .end = 12 }});
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualSlices(u16, wide("middle"), actual);
}

test "passage preserves UTF-16 and normalizes multiline blocks to CRLF" {
    const messages = [_]Message{
        .{ .sender = wide("A"), .time = wide("12:00"), .day = "2026-10-10", .text = wide("one\ntwo\r\nthree\rend"), .end = 18 },
        .{ .sender = wide("B"), .time = wide("12:01"), .day = "2026-10-10", .text = wide("🟢"), .end = 2 },
    };
    const actual = try build(std.testing.allocator, &messages);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualSlices(u16, wide("A, 12:00: one\r\ntwo\r\nthree\r\nend\r\nB, 12:01: 🟢"), actual);
}

test "passage reversed endpoints select partial edges and full interior without layout" {
    const first = Endpoint{ .message = 1, .word = 2, .start = 6, .end = 12 };
    const last = Endpoint{ .message = 4, .word = 0, .start = 0, .end = 5 };
    for ([_]Selection{ .{ .anchor = first, .focus = last }, .{ .anchor = last, .focus = first } }) |selection| {
        try std.testing.expectEqual(Range{ .start = 6, .end = 18 }, selection.range(1, 18).?);
        try std.testing.expectEqual(Range{ .start = 0, .end = 18 }, selection.range(2, 18).?);
        try std.testing.expectEqual(Range{ .start = 0, .end = 5 }, selection.range(4, 18).?);
        try std.testing.expect(selection.range(0, 18) == null);
        try std.testing.expect(selection.range(5, 18) == null);
    }
    try std.testing.expect(!(Selection{ .anchor = first, .focus = first }).active());
    try std.testing.expect(!(Selection{}).active());
}

test "passage single-message selection retains inclusive word offsets in either direction" {
    const first = Endpoint{ .message = 2, .word = 1, .start = 6, .end = 12 };
    const last = Endpoint{ .message = 2, .word = 2, .start = 13, .end = 18 };
    for ([_]Selection{ .{ .anchor = first, .focus = last }, .{ .anchor = last, .focus = first } }) |selection| {
        const range = selection.range(2, 18).?;
        const actual = try build(std.testing.allocator, &.{.{ .sender = wide("A"), .time = wide("12:00"), .day = "2026-10-10", .text = wide("alpha middle omega"), .start = range.start, .end = range.end }});
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualSlices(u16, wide("middle omega"), actual);
    }
}

test "passage empty ranges and absent messages return empty text" {
    const actual = try build(std.testing.allocator, &.{});
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqual(@as(usize, 0), actual.len);
}

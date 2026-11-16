const std = @import("std");

pub const VoicePill = struct {
    name: []const u16,
    position_ms: i64,
    duration_ms: i64,
    state: enum { playing, paused },

    pub fn init(name: []const u16, position_ms: i64, duration_ms: i64, state: @FieldType(VoicePill, "state")) VoicePill {
        return .{
            .name = if (name.len > 0 and std.mem.indexOfScalar(u16, name, '@') == null) name else std.unicode.utf8ToUtf16LeStringLiteral("Voice message"),
            .position_ms = @min(@max(0, position_ms), @max(0, duration_ms)),
            .duration_ms = @max(0, duration_ms),
            .state = state,
        };
    }

    pub fn time(self: VoicePill, buffer: []u8) []const u8 {
        const position: u64 = @intCast(@divTrunc(self.position_ms, 1000));
        const duration: u64 = @intCast(@divTrunc(self.duration_ms, 1000));
        return std.fmt.bufPrint(buffer, "{d}:{d:0>2} / {d}:{d:0>2}", .{ @divTrunc(position, 60), @mod(position, 60), @divTrunc(duration, 60), @mod(duration, 60) }) catch "";
    }
};

pub const Rect = extern struct { left: i32, top: i32, right: i32, bottom: i32 };

pub fn voicePillRect(width: i32, dpi: i32) Rect {
    const pill_width = @min(@max(0, width - @divTrunc(16 * dpi, 96)), @divTrunc(360 * dpi, 96));
    const left = @divTrunc(width - pill_width, 2);
    return .{ .left = left, .top = @divTrunc(60 * dpi, 96), .right = left + pill_width, .bottom = @divTrunc(92 * dpi, 96) };
}

test "voice pill uses a display name and elapsed time without an address" {
    const name = std.unicode.utf8ToUtf16LeStringLiteral("Fixture chat");
    const pill = VoicePill.init(name, 12000, 48000, .paused);
    try std.testing.expectEqualSlices(u16, name, pill.name);
    var buffer: [40]u8 = undefined;
    try std.testing.expectEqualStrings("0:12 / 0:48", pill.time(&buffer));
    const fallback = VoicePill.init(std.unicode.utf8ToUtf16LeStringLiteral("fixture@example.invalid"), 50000, 48000, .playing);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("Voice message"), fallback.name);
    try std.testing.expectEqualStrings("0:48 / 0:48", fallback.time(&buffer));
}

test "voice pill stays below the title and inside narrow canvases" {
    for ([_]i32{ 1, 2 }) |scale| {
        for ([_]i32{ 120, 800 }) |width| {
            const rect = voicePillRect(width * scale, 96 * scale);
            try std.testing.expect(rect.top > 52 * scale);
            try std.testing.expect(rect.left >= 0 and rect.right <= width * scale);
            try std.testing.expect(rect.right - rect.left <= 360 * scale);
        }
    }
}

pub const ChatRow = struct {
    title: []const u16,
    subtitle: []const u16,

    pub fn init(name: []const u16, preview: []const u16) ChatRow {
        return .{ .title = name, .subtitle = preview };
    }
};

test "chat row keeps its normal preview while audio plays" {
    const name = std.unicode.utf8ToUtf16LeStringLiteral("Fixture chat");
    const preview = std.unicode.utf8ToUtf16LeStringLiteral("Voice message");
    const row = ChatRow.init(name, preview);
    try std.testing.expectEqualSlices(u16, name, row.title);
    try std.testing.expectEqualSlices(u16, preview, row.subtitle);
    const pill = VoicePill.init(name, 12000, 48000, .paused);
    try std.testing.expectEqual(.paused, pill.state);
    try std.testing.expectEqualSlices(u16, preview, ChatRow.init(name, preview).subtitle);
}

test "empty chats show their name without a kind subtitle" {
    const name = std.unicode.utf8ToUtf16LeStringLiteral("Fixture chat");
    const row = ChatRow.init(name, &.{});
    try std.testing.expectEqualSlices(u16, name, row.title);
    try std.testing.expectEqual(@as(usize, 0), row.subtitle.len);
}

pub const Day = struct {
    year: u16,
    month: u16,
    day: u16,

    pub fn equal(self: Day, other: Day) bool {
        return self.year == other.year and self.month == other.month and self.day == other.day;
    }

    pub fn label(self: Day, today: Day, buffer: []u8) []const u8 {
        if (self.equal(today)) return "Today";
        return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day }) catch "";
    }
};

pub const GroupMessage = struct {
    day: ?Day = null,
    seconds: ?i64 = null,
    from_me: bool = false,
    sender_id: []const u8 = "",
    sender: []const u16 = &.{},
};

pub const GroupHeader = struct {
    day: ?Day,
    kind: enum { none, time, sender_time },
};

pub fn groupHeader(current: GroupMessage, previous: ?GroupMessage, group: bool) GroupHeader {
    const new_day = if (current.day) |day| if (previous) |before| if (before.day) |old| !day.equal(old) else true else true else false;
    const starts = if (previous) |before| blk: {
        if (new_day or current.from_me != before.from_me) break :blk true;
        if (current.seconds != null and before.seconds != null and current.seconds.? - before.seconds.? >= 3600) break :blk true;
        if (current.from_me or !group) break :blk false;
        if (current.sender_id.len > 0 and before.sender_id.len > 0) break :blk !std.mem.eql(u8, current.sender_id, before.sender_id);
        break :blk current.sender.len == 0 or before.sender.len == 0 or !std.mem.eql(u16, current.sender, before.sender);
    } else true;
    return .{ .day = if (new_day) current.day else null, .kind = if (!starts) .none else if (group and !current.from_me) .sender_time else .time };
}

test "day label has no time and uses the local calendar day" {
    const today = Day{ .year = 2026, .month = 1, .day = 2 };
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("Today", today.label(today, &buffer));
    try std.testing.expectEqualStrings("2026-01-01", (Day{ .year = 2026, .month = 1, .day = 1 }).label(today, &buffer));
}

test "message groups show one time and only day changes show a day line" {
    const day = Day{ .year = 2026, .month = 1, .day = 2 };
    const first = GroupMessage{ .day = day, .seconds = 10, .sender_id = "sender-a" };
    try std.testing.expectEqual(.sender_time, groupHeader(first, null, true).kind);
    try std.testing.expectEqual(.time, groupHeader(first, null, false).kind);
    try std.testing.expectEqual(.none, groupHeader(first, first, true).kind);
    var next = first;
    next.seconds = 3610;
    const later = groupHeader(next, first, true);
    try std.testing.expectEqual(.sender_time, later.kind);
    try std.testing.expect(later.day == null);
    next.day = .{ .year = 2026, .month = 1, .day = 3 };
    try std.testing.expect(groupHeader(next, first, true).day != null);
    next = first;
    next.sender_id = "sender-b";
    try std.testing.expectEqual(.sender_time, groupHeader(next, first, true).kind);
    next.from_me = true;
    try std.testing.expectEqual(.time, groupHeader(next, first, true).kind);
    try std.testing.expectEqual(.none, groupHeader(next, next, true).kind);
    try std.testing.expect(groupHeader(.{}, null, false).day == null);
}

pub const LinkCard = struct {
    title: []const u16,
    site: []const u8,
    omitted: ?struct { start: usize, end: usize },

    pub fn init(text: []const u16, canonical: []const u8, title: []const u16) LinkCard {
        const unfurl = @import("unfurl.zig");
        const target = unfurl.classify(canonical);
        const rest = if (std.mem.indexOf(u8, canonical, "://")) |at| canonical[at + 3 ..] else canonical;
        var host = rest[0 .. std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len];
        if (std.mem.startsWith(u8, host, "www.")) host = host[4..];
        var card = LinkCard{ .title = if (title.len > 0) title else switch (target.provider) {
            .instagram => std.unicode.utf8ToUtf16LeStringLiteral("Reel"),
            .youtube, .facebook => std.unicode.utf8ToUtf16LeStringLiteral("Video"),
            else => std.unicode.utf8ToUtf16LeStringLiteral("Open link"),
        }, .site = host, .omitted = null };
        var words = std.mem.tokenizeAny(u16, text, &.{ ' ', '\t', '\r', '\n', '<', '>' });
        while (words.next()) |word| {
            var buffer: [2048]u8 = undefined;
            const length = std.unicode.utf16LeToUtf8(&buffer, word) catch continue;
            const info = unfurl.classify(buffer[0..length]);
            if (target.provider == .none or info.provider != target.provider or !std.mem.eql(u8, info.idSlice(), target.idSlice())) continue;
            const start = (@intFromPtr(word.ptr) - @intFromPtr(text.ptr)) / @sizeOf(u16);
            card.omitted = .{ .start = start, .end = start + word.len };
            break;
        }
        return card;
    }

    pub fn body(self: LinkCard, input: @import("message_format.zig").Parsed) @import("message_format.zig").Parsed {
        const omitted = self.omitted orelse return input;
        var result = input;
        result.len = 0;
        for (0..input.len) |index| {
            const source = input.source[index];
            if (source >= omitted.start and source < omitted.end) continue;
            result.text[result.len] = input.text[index];
            result.styles[result.len] = input.styles[index];
            result.source[result.len] = source;
            result.len += 1;
        }
        var start: usize = 0;
        while (start < result.len and std.mem.indexOfScalar(u16, &.{ ' ', '\r', '\n', '\t', '<', '>' }, result.text[start]) != null) : (start += 1) {}
        var end = result.len;
        while (end > start and std.mem.indexOfScalar(u16, &.{ ' ', '\r', '\n', '\t', '<', '>' }, result.text[end - 1]) != null) : (end -= 1) {}
        std.mem.copyForwards(u16, &result.text, result.text[start..end]);
        std.mem.copyForwards(@import("message_format.zig").Style, &result.styles, result.styles[start..end]);
        std.mem.copyForwards(u16, &result.source, result.source[start..end]);
        result.len = end - start;
        return result;
    }
};

test "a link card replaces a bare URL with its title and site" {
    const text = std.unicode.utf8ToUtf16LeStringLiteral("https://www.example.com/story?x=1");
    const title = std.unicode.utf8ToUtf16LeStringLiteral("Fixture headline");
    const card = LinkCard.init(text, "https://www.example.com/story?x=1", title);
    try std.testing.expectEqualSlices(u16, title, card.title);
    try std.testing.expectEqualStrings("example.com", card.site);
    try std.testing.expectEqual(@as(usize, 0), card.body(@import("message_format.zig").parse(text, false)).len);
}

test "card removal keeps captions styles source offsets and other links" {
    const text = std.unicode.utf8ToUtf16LeStringLiteral("*Caption* https://www.instagram.com/reel/ABCDE/?x=1\nafter https://example.com/other");
    const card = LinkCard.init(text, "https://www.instagram.com/reel/ABCDE/", &.{});
    const body = card.body(@import("message_format.zig").parse(text, false));
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("Caption \nafter https://example.com/other"), body.text[0..body.len]);
    try std.testing.expect(body.styles[0].bold);
    for (body.text[0..body.len], body.source[0..body.len]) |unit, source| try std.testing.expectEqual(text[source], unit);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("Reel"), card.title);
    const unrelated = LinkCard.init(text, "https://example.com/missing", &.{});
    try std.testing.expect(unrelated.omitted == null);
}

test "voice pill accepts signed player clocks and normalizes unset positions" {
    var buffer: [40]u8 = undefined;
    const pill = VoicePill.init(&.{}, -1, -1, .playing);
    try std.testing.expectEqualStrings("0:00 / 0:00", pill.time(&buffer));
    const duration: i64 = 48000;
    try std.testing.expectEqualStrings("0:12 / 0:48", VoicePill.init(&.{}, 12000, duration, .paused).time(&buffer));
}

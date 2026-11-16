const std = @import("std");

pub const VoicePill = struct {
    name: []const u16,
    position_ms: u32,
    duration_ms: u32,
    state: enum { playing, paused },

    pub fn init(name: []const u16, position_ms: u32, duration_ms: u32, state: @FieldType(VoicePill, "state")) VoicePill {
        return .{
            .name = if (name.len > 0 and std.mem.indexOfScalar(u16, name, '@') == null) name else std.unicode.utf8ToUtf16LeStringLiteral("Voice message"),
            .position_ms = @min(position_ms, duration_ms),
            .duration_ms = duration_ms,
            .state = state,
        };
    }

    pub fn time(self: VoicePill, buffer: []u8) []const u8 {
        const position = self.position_ms / 1000;
        const duration = self.duration_ms / 1000;
        return std.fmt.bufPrint(buffer, "{d}:{d:0>2} / {d}:{d:0>2}", .{ position / 60, position % 60, duration / 60, duration % 60 }) catch "";
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

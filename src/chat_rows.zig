const std = @import("std");
const chat_key = @import("chat_key.zig");

pub fn rowEqual(comptime T: type, left: *const T, right: *const T) bool {
    if (!chat_key.Key.eql(chat_key.of(left), chat_key.of(right))) return false;
    inline for (.{ "name", "kind", "time" }) |field| {
        if (!std.mem.eql(u16, @field(left, field).slice(), @field(right, field).slice())) return false;
    }
    return (left.unread or left.unread_count > 0) == (right.unread or right.unread_count > 0) and
        left.pinned == right.pinned and left.archived == right.archived;
}

pub fn equal(comptime T: type, left: []const T, right: []const T) bool {
    if (left.len != right.len) return false;
    for (left, right) |*before, *after| {
        if (!rowEqual(T, before, after)) return false;
    }
    return true;
}

const Text = struct {
    value: []const u8 = "",
    pub fn slice(self: *const Text) []const u8 {
        return self.value;
    }
};
const Wide = struct {
    value: []const u16 = &.{},
    pub fn slice(self: *const Wide) []const u16 {
        return self.value;
    }
};
const Row = struct {
    provider: @import("transport.zig").Provider = .whatsapp,
    account: Text = .{ .value = "fixture" },
    jid: Text = .{ .value = "chat-a" },
    name: Wide = .{ .value = std.unicode.utf8ToUtf16LeStringLiteral("A") },
    kind: Wide = .{},
    time: Wide = .{},
    timestamp: Text = .{},
    unread: bool = false,
    unread_count: i64 = 0,
    pinned: bool = false,
    archived: bool = false,
};

test "identical visible rows skip rebuilding despite nonvisual metadata changes" {
    const before = [_]Row{.{}};
    var after = before;
    after[0].timestamp.value = "new timestamp";
    try std.testing.expect(equal(Row, &before, &after));
    after[0].unread_count = 1;
    try std.testing.expect(!equal(Row, &before, &after));
    var unread = after;
    unread[0].unread_count = 2;
    try std.testing.expect(equal(Row, &after, &unread));
    try std.testing.expect(!equal(Row, &before, &.{}));
}

test "row identity order labels and visual flags are significant" {
    const before = Row{};
    inline for (.{ "name", "kind", "time" }) |field| {
        var after = before;
        @field(after, field).value = std.unicode.utf8ToUtf16LeStringLiteral("B");
        try std.testing.expect(!rowEqual(Row, &before, &after));
    }
    inline for (.{ "unread", "pinned", "archived" }) |field| {
        var after = before;
        @field(after, field) = true;
        try std.testing.expect(!rowEqual(Row, &before, &after));
    }
    var other = before;
    other.account.value = "other";
    try std.testing.expect(!rowEqual(Row, &before, &other));
    other = before;
    other.provider = .slack;
    try std.testing.expect(!rowEqual(Row, &before, &other));
    other = before;
    other.jid.value = "chat-b";
    const rows = [_]Row{ before, other };
    const reversed = [_]Row{ other, before };
    try std.testing.expect(!equal(Row, &rows, &reversed));
}

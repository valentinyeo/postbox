const std = @import("std");
const chat_key = @import("chat_key.zig");

pub const Activity = struct {
    const Entry = struct {
        key: chat_key.Stored = .{},
        timestamp: [47]u8 = undefined,
        len: usize = 0,

        fn slice(self: *const Entry) []const u8 {
            return self.timestamp[0..self.len];
        }
    };
    entries: std.ArrayList(Entry) = .empty,

    pub fn deinit(self: *Activity, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);
    }

    pub fn retain(self: *Activity, allocator: std.mem.Allocator, key: chat_key.Key, timestamp: []const u8) ![]const u8 {
        var normalized: [47]u8 = undefined;
        const len = @min(std.mem.trimEnd(u8, timestamp, "Z").len, normalized.len - 1);
        @memcpy(normalized[0..len], timestamp[0..len]);
        if (len > 10 and normalized[10] == ' ') normalized[10] = 'T';
        var found: ?*Entry = null;
        for (self.entries.items) |*entry| {
            if (chat_key.Key.eql(entry.key.key(), key)) {
                found = entry;
                break;
            }
        }
        const entry = found orelse blk: {
            if (len == 0) return "";
            const entry = try self.entries.addOne(allocator);
            entry.* = .{};
            entry.key.set(key);
            break :blk entry;
        };
        if (std.mem.order(u8, normalized[0..len], std.mem.trimEnd(u8, entry.slice(), "Z")) == .gt) {
            @memcpy(entry.timestamp[0..len], normalized[0..len]);
            entry.timestamp[len] = 'Z';
            entry.len = len + 1;
        }
        return entry.slice();
    }
};

test "sent and phone activity survives stale snapshots without crossing provider or account" {
    var activity = Activity{};
    defer activity.deinit(std.testing.allocator);
    const key = chat_key.Key{ .provider = .whatsapp, .account = "first", .id = "contact" };
    const old = "2026-10-29T10:00:00Z";
    const sent = "2026-10-29 12:00:00";
    const phone = "2026-10-29T12:00:01.123Z";
    try std.testing.expectEqualStrings("2026-10-29T10:00:00Z", try activity.retain(std.testing.allocator, key, old));
    try std.testing.expectEqualStrings("2026-10-29T12:00:00Z", try activity.retain(std.testing.allocator, key, sent));
    try std.testing.expectEqualStrings("2026-10-29T12:00:00Z", try activity.retain(std.testing.allocator, key, old));
    try std.testing.expectEqualStrings("2026-10-29T12:00:01.123Z", try activity.retain(std.testing.allocator, key, phone));
    try std.testing.expectEqualStrings("2026-10-29T12:00:01.123Z", try activity.retain(std.testing.allocator, key, ""));
    for ([_]chat_key.Key{
        .{ .provider = .whatsapp, .account = "second", .id = key.id },
        .{ .provider = .slack, .account = key.account, .id = key.id },
    }) |other| try std.testing.expectEqualStrings("2026-10-29T10:00:00Z", try activity.retain(std.testing.allocator, other, old));
}

pub fn shouldMoveUp(pin_left: bool, pin_right: bool, by_time: std.math.Order, by_name: std.math.Order, jid_tiebreak: std.math.Order) bool {
    if (pin_right != pin_left) return pin_right;
    return by_time == .lt or (by_time == .eq and (by_name == .gt or (by_name == .eq and jid_tiebreak == .gt)));
}

test "pinned chats move above unpinned ones regardless of age" {
    try std.testing.expect(shouldMoveUp(false, true, .gt, .lt, .lt));
    try std.testing.expect(!shouldMoveUp(true, false, .lt, .gt, .gt));
}

test "Slack and WhatsApp sort by last message newest first with unknown last and name ties" {
    const Row = struct { name: []const u8, time: []const u8, id: []const u8 };
    var rows = [_]Row{
        .{ .name = "Unknown", .time = "", .id = "a" },
        .{ .name = "Oldest", .time = "2026-01-01T00:00:00Z", .id = "b" },
        .{ .name = "Zulu", .time = "2026-01-03T00:00:00Z", .id = "c" },
        .{ .name = "Alpha", .time = "2026-01-03T00:00:00Z", .id = "z" },
        .{ .name = "Middle", .time = "2026-01-02T00:00:00Z", .id = "d" },
    };
    for (1..rows.len) |i| {
        var j = i;
        while (j > 0 and shouldMoveUp(false, false, std.mem.order(u8, rows[j - 1].time, rows[j].time), std.mem.order(u8, rows[j - 1].name, rows[j].name), std.mem.order(u8, rows[j - 1].id, rows[j].id))) : (j -= 1) {
            std.mem.swap(Row, &rows[j - 1], &rows[j]);
        }
    }
    for (rows, [_][]const u8{ "Alpha", "Zulu", "Middle", "Oldest", "Unknown" }) |row, name| {
        try std.testing.expectEqualStrings(name, row.name);
    }
    try std.testing.expect(shouldMoveUp(false, false, .lt, .lt, .lt));
    try std.testing.expect(!shouldMoveUp(false, false, .gt, .gt, .gt));
    try std.testing.expect(shouldMoveUp(false, false, .eq, .eq, .gt));
    try std.testing.expect(!shouldMoveUp(false, false, .eq, .eq, .lt));
}

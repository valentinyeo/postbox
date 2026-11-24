const std = @import("std");
const chat_key = @import("chat_key.zig");
const media_age = @import("media_age.zig");

pub const State = struct {
    timestamps: std.StringHashMapUnmanaged(i64) = .empty,
    baseline: ?i64 = null,

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        var keys = self.timestamps.keyIterator();
        while (keys.next()) |key| allocator.free(key.*);
        self.timestamps.deinit(allocator);
    }

    pub fn previous(self: *const State, key: chat_key.Key) ?i64 {
        var buffer: [256]u8 = undefined;
        const id = std.fmt.bufPrint(&buffer, "{s}/{s}/{s}", .{ @tagName(key.provider), key.account, key.id }) catch return null;
        return self.timestamps.get(id) orelse self.baseline;
    }

    pub fn record(self: *State, allocator: std.mem.Allocator, key: chat_key.Key, timestamp: i64) void {
        const id = std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ @tagName(key.provider), key.account, key.id }) catch return;
        const entry = self.timestamps.getOrPut(allocator, id) catch {
            allocator.free(id);
            return;
        };
        if (entry.found_existing) allocator.free(id);
        entry.value_ptr.* = if (entry.found_existing) @max(entry.value_ptr.*, timestamp) else timestamp;
    }
};

pub const Gap = struct {
    since: ?i64 = null,
    count: u32 = 0,
    active: bool = false,

    pub fn begin(self: *Gap, since: i64) void {
        self.* = .{ .since = if (since > 0) since else null, .active = true };
    }

    pub fn observe(self: *Gap, unread: i64) void {
        if (!self.active) return;
        const counted: u32 = @intCast(@max(unread, 1));
        self.count = self.count +| counted;
    }

    pub fn finish(self: *Gap) ?u32 {
        if (!self.active) return null;
        const count = self.count;
        self.* = .{};
        return count;
    }
};

pub fn gapLabel(buffer: []u8, count: u32, clock: []const u8) []const u8 {
    if (clock.len == 0) return std.fmt.bufPrint(buffer, "{d} new", .{count}) catch "New messages";
    return std.fmt.bufPrint(buffer, "{d} new since {s}", .{ count, clock }) catch "New messages";
}

pub fn incoming(messages: []const std.json.Value, after: i64) ?std.json.ObjectMap {
    var latest = after;
    var result: ?std.json.ObjectMap = null;
    for (messages) |message| {
        if (message != .object) continue;
        const object = message.object;
        const from_me = object.get("FromMe") orelse continue;
        if (from_me != .bool or from_me.bool) continue;
        if (object.get("ReactionToID")) |reaction| {
            if (reaction != .string or reaction.string.len > 0) continue;
        }
        const raw_timestamp = object.get("Timestamp") orelse continue;
        if (raw_timestamp != .string) continue;
        const timestamp = media_age.unixSeconds(raw_timestamp.string) orelse continue;
        if (timestamp <= latest) continue;
        const id = object.get("MsgID") orelse continue;
        if (id != .string or id.string.len == 0) continue;
        latest = timestamp;
        result = object;
    }
    return result;
}

test "incoming alert ignores own messages reactions history and chooses newest human message" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\[{"MsgID":"old","Timestamp":"2026-10-28T10:00:00Z","FromMe":false},
        \\{"MsgID":"own","Timestamp":"2026-10-28T10:00:05Z","FromMe":true},
        \\{"MsgID":"reaction","Timestamp":"2026-10-28T10:00:06Z","FromMe":false,"ReactionToID":"old"},
        \\{"MsgID":"new","Timestamp":"2026-10-28T10:00:01Z","FromMe":false}]
    , .{});
    defer parsed.deinit();
    const after = media_age.unixSeconds("2026-10-28T10:00:00Z").?;
    try std.testing.expectEqualStrings("new", incoming(parsed.value.array.items, after).?.get("MsgID").?.string);
    try std.testing.expect(incoming(parsed.value.array.items, after + 1) == null);
}

test "a gap counts one chat as one message and finishes once" {
    var buffer: [63]u8 = undefined;
    var gap: Gap = .{};
    try std.testing.expect(gap.finish() == null);
    gap.observe(9);
    try std.testing.expectEqual(@as(u32, 0), gap.count);
    gap.begin(0);
    try std.testing.expectEqual(@as(?i64, null), gap.since);
    gap.observe(3);
    gap.observe(0);
    try std.testing.expectEqual(@as(u32, 4), gap.count);
    try std.testing.expectEqual(@as(?u32, 4), gap.finish());
    try std.testing.expect(gap.finish() == null);
    try std.testing.expectEqualStrings("4 new since 08:45", gapLabel(&buffer, 4, "08:45"));
    try std.testing.expectEqualStrings("1 new", gapLabel(&buffer, 1, ""));
}

test "notification baselines isolate accounts avoid startup replay and never move backwards" {
    const allocator = std.testing.allocator;
    var state: State = .{};
    defer state.deinit(allocator);
    const personal = chat_key.Key{ .provider = .whatsapp, .account = "personal", .id = "contact" };
    const business = chat_key.Key{ .provider = .whatsapp, .account = "business", .id = "contact" };
    try std.testing.expect(state.previous(personal) == null);
    state.record(allocator, personal, 100);
    state.baseline = 150;
    try std.testing.expectEqual(@as(?i64, 100), state.previous(personal));
    try std.testing.expectEqual(@as(?i64, 150), state.previous(business));
    state.record(allocator, business, 160);
    state.record(allocator, business, 120);
    try std.testing.expectEqual(@as(?i64, 160), state.previous(business));
}

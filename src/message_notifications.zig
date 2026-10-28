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

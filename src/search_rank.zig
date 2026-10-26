const std = @import("std");

fn lower(unit: u16) u16 {
    return if (unit >= 'A' and unit <= 'Z') unit + 32 else unit;
}

pub fn quality(label: []const u16, query: []const u16) i32 {
    const suffix = std.unicode.utf8ToUtf16LeStringLiteral("  ·  ");
    const name = label[0 .. std.mem.indexOf(u16, label, suffix) orelse label.len];
    if (query.len == 0 or query.len > name.len) return 0;
    for (0..name.len - query.len + 1) |start| {
        var matches = true;
        for (query, 0..) |unit, offset| {
            if (lower(unit) != lower(name[start + offset])) {
                matches = false;
                break;
            }
        }
        if (matches) return if (name.len == query.len) 3 else if (start == 0) 2 else 1;
    }
    return 0;
}

pub fn sentCount(allocator: std.mem.Allocator, raw: []const u8) u32 {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch return 0;
    defer parsed.deinit();
    if (parsed.value != .object) return 0;
    const data = parsed.value.object.get("data") orelse return 0;
    if (data != .object) return 0;
    const messages = data.object.get("messages") orelse return 0;
    if (messages != .array) return 0;
    var ids: std.StringHashMapUnmanaged(void) = .empty;
    defer ids.deinit(allocator);
    for (messages.array.items) |message| {
        if (message != .object) continue;
        const from_me = message.object.get("FromMe") orelse continue;
        if (from_me != .bool or !from_me.bool) continue;
        if (message.object.get("ReactionToID")) |reaction| {
            if (reaction == .string and reaction.string.len > 0) continue;
        }
        const id = message.object.get("MsgID") orelse continue;
        if (id != .string or id.string.len == 0) continue;
        ids.put(allocator, id.string, {}) catch continue;
    }
    return @intCast(ids.count());
}

test "equal quality preserves exact names ahead of frequent partial matches" {
    const wide = std.unicode.utf8ToUtf16LeStringLiteral;
    try std.testing.expect(quality(wide("Alex"), wide("alex")) > quality(wide("Alex Smith"), wide("alex")));
    try std.testing.expectEqual(quality(wide("Alex Smith"), wide("alex")), quality(wide("Alex Doe  ·  Archived"), wide("alex")));
    try std.testing.expectEqual(@as(i32, 0), quality(wide("Someone  ·  Archived"), wide("Archived")));
}

test "frequency counts sent messages not incoming volume reactions or duplicate history" {
    const raw =
        \\{"data":{"messages":[{"MsgID":"sent","FromMe":true},{"MsgID":"sent","FromMe":true},{"MsgID":"incoming","FromMe":false},{"MsgID":"reaction","FromMe":true,"ReactionToID":"incoming"},{"MsgID":"file","FromMe":true,"MediaType":"image"}]}}
    ;
    try std.testing.expectEqual(@as(u32, 2), sentCount(std.testing.allocator, raw));
    try std.testing.expectEqual(@as(u32, 0), sentCount(std.testing.allocator, "{}"));
}

pub const Row = struct {
    id: []const u8,
    text: []const u8 = "",
    media_type: []const u8 = "",
    filename: []const u8 = "",
    local_path: []const u8 = "",
    revoked: bool = false,
    reaction_to: []const u8 = "",
};

pub fn isRealMessage(row: Row) bool {
    if (row.id.len == 0) return false;
    return row.text.len > 0 or row.media_type.len > 0 or
        row.filename.len > 0 or row.local_path.len > 0 or row.revoked or
        row.reaction_to.len > 0;
}

pub fn order(left_time: []const u8, left_id: []const u8, right_time: []const u8, right_id: []const u8) std.math.Order {
    var left = std.mem.splitScalar(u8, std.mem.trimEnd(u8, left_time, "Z"), '.');
    var right = std.mem.splitScalar(u8, std.mem.trimEnd(u8, right_time, "Z"), '.');
    const by_seconds = std.mem.order(u8, left.first(), right.first());
    if (by_seconds != .eq) return by_seconds;
    const by_fraction = std.mem.order(u8, std.mem.trimEnd(u8, left.next() orelse "", "0"), std.mem.trimEnd(u8, right.next() orelse "", "0"));
    if (by_fraction != .eq) return by_fraction;
    return std.mem.order(u8, left_id, right_id);
}

pub fn stripPlaceholder(text: []const u8) []const u8 {
    if (std.mem.eql(u8, text, "(message)")) return "";
    return text;
}

const std = @import("std");

test "text message is real" {
    try std.testing.expect(isRealMessage(.{ .id = "ABC1", .text = "hello" }));
}

test "media row without text is real" {
    try std.testing.expect(isRealMessage(.{ .id = "ABC2", .media_type = "image" }));
    try std.testing.expect(isRealMessage(.{ .id = "ABC3", .local_path = "C:\\x.jpg" }));
}

test "revoked row keeps its delete notice" {
    try std.testing.expect(isRealMessage(.{ .id = "ABC4", .revoked = true }));
}

test "reaction row survives so it can merge into its target" {
    try std.testing.expect(isRealMessage(.{ .id = "ABC6", .reaction_to = "ABC1" }));
}

test "protocol stub without content is hidden" {
    try std.testing.expect(!isRealMessage(.{ .id = "ABC5" }));
    try std.testing.expect(!isRealMessage(.{ .id = "", .text = "orphan" }));
}

test "wacli placeholder counts as no text" {
    try std.testing.expectEqualStrings("", stripPlaceholder("(message)"));
    try std.testing.expectEqualStrings("hello", stripPlaceholder("hello"));
    try std.testing.expectEqualStrings("(message) later", stripPlaceholder("(message) later"));
    try std.testing.expect(!isRealMessage(.{ .id = "ABC7", .text = stripPlaceholder("(message)") }));
    try std.testing.expect(isRealMessage(.{ .id = "ABC8", .text = stripPlaceholder("(message)"), .media_type = "gif" }));
    try std.testing.expect(isRealMessage(.{ .id = "ABC9", .text = stripPlaceholder("(message)"), .revoked = true }));
    try std.testing.expect(isRealMessage(.{ .id = "ABC10", .text = stripPlaceholder("(message)"), .reaction_to = "ABC1" }));
}

test "message order compares provider time before opaque ids" {
    try std.testing.expectEqual(std.math.Order.lt, order("2026-10-01T12:29:00Z", "Z", "2026-10-01T13:06:00Z", "A"));
    try std.testing.expectEqual(std.math.Order.lt, order("2026-10-01T13:06:00Z", "Z", "2026-10-01T13:06:00.1Z", "A"));
    try std.testing.expectEqual(std.math.Order.lt, order("2026-10-01T13:06:00.10Z", "A", "2026-10-01T13:06:00.1Z", "B"));
    try std.testing.expectEqual(std.math.Order.eq, order("2026-10-01T13:06:00Z", "A", "2026-10-01T13:06:00.000Z", "A"));
}

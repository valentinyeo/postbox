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

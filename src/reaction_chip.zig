const std = @import("std");

pub const Action = union(enum) { add: []const u8, remove };

pub fn decide(text: []const u8, segment_index: usize, my_reaction: []const u8) ?Action {
    var segments = std.mem.splitSequence(u8, text, "  ");
    var index: usize = 0;
    while (segments.next()) |segment| : (index += 1) {
        if (index != segment_index) continue;
        const trimmed = std.mem.trim(u8, segment, " ");
        const emoji = trimmed[0 .. std.mem.indexOfScalar(u8, trimmed, ' ') orelse trimmed.len];
        if (emoji.len == 0) return null;
        return if (std.mem.eql(u8, emoji, my_reaction)) .remove else .{ .add = emoji };
    }
    return null;
}

test "IGSH-674 single emoji chip adds the same emoji" {
    const action = decide("❤️", 0, "").?;
    try std.testing.expectEqualStrings("❤️", action.add);
}

test "IGSH-674 same as my reaction removes it" {
    try std.testing.expect(decide("❤️", 0, "❤️").? == .remove);
}

test "IGSH-674 multi emoji Slack chip picks the segment and strips the count" {
    const text = "😂 2  ❤️ 1";
    try std.testing.expectEqualStrings("😂", decide(text, 0, "").?.add);
    try std.testing.expectEqualStrings("❤️", decide(text, 1, "😂").?.add);
    try std.testing.expect(decide(text, 1, "❤️").? == .remove);
}

test "IGSH-674 empty or missing segments do not react" {
    try std.testing.expect(decide("", 0, "") == null);
    try std.testing.expect(decide("❤️", 1, "") == null);
}

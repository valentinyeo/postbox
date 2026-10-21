const std = @import("std");

pub const Action = enum { add, remove, ignore };
pub const thumbs_up = "👍";

pub fn decide(from_me: bool, my_reaction: []const u8) Action {
    if (from_me) return .ignore;
    return if (std.mem.eql(u8, my_reaction, thumbs_up)) .remove else .add;
}

test "IGSH-463 received message adds thumbs up without my reaction" {
    try std.testing.expectEqual(Action.add, decide(false, ""));
}

test "IGSH-463 received message removes my existing thumbs up" {
    try std.testing.expectEqual(Action.remove, decide(false, thumbs_up));
}

test "IGSH-463 received message replaces my different reaction with thumbs up" {
    try std.testing.expectEqual(Action.add, decide(false, "❤️"));
}

test "IGSH-463 own messages ignore double-click regardless of reaction" {
    for ([_][]const u8{ "", thumbs_up, "❤️" }) |reaction| {
        try std.testing.expectEqual(Action.ignore, decide(true, reaction));
    }
}

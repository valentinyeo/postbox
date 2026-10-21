const std = @import("std");

pub const Action = enum { none, load, save, update };

pub const Decision = struct {
    key: []const u8,
    action: Action,
};

pub fn decide(stored: ?[]const u8, seed: ?[]const u8) Decision {
    if (seed) |value| {
        if (stored) |previous| {
            if (std.mem.eql(u8, value, previous)) return .{ .key = previous, .action = .load };
            return .{ .key = value, .action = .update };
        }
        return .{ .key = value, .action = .save };
    }
    if (stored) |value| return .{ .key = value, .action = .load };
    return .{ .key = "", .action = .none };
}

test "IGSH-470 neither key -> none" {
    const decision = decide(null, null);
    try std.testing.expectEqual(Action.none, decision.action);
    try std.testing.expectEqualStrings("", decision.key);
}

test "IGSH-470 seed only -> save" {
    const decision = decide(null, "seed");
    try std.testing.expectEqual(Action.save, decision.action);
    try std.testing.expectEqualStrings("seed", decision.key);
}

test "IGSH-470 stored only -> load" {
    const decision = decide("stored", null);
    try std.testing.expectEqual(Action.load, decision.action);
    try std.testing.expectEqualStrings("stored", decision.key);
}

test "IGSH-470 equal seed and stored -> load" {
    const decision = decide("stored", "stored");
    try std.testing.expectEqual(Action.load, decision.action);
    try std.testing.expectEqualStrings("stored", decision.key);
}

test "IGSH-470 seed differs from stored -> update" {
    const decision = decide("revoked", "replacement");
    try std.testing.expectEqual(Action.update, decision.action);
    try std.testing.expectEqualStrings("replacement", decision.key);
}

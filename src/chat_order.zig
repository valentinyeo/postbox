const std = @import("std");

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

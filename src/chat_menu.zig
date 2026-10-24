const std = @import("std");
const wide = std.unicode.utf8ToUtf16LeStringLiteral;

pub const Item = struct { command: u16, label: [:0]const u16 };
pub const State = struct { archived: bool, pinned: bool, show_archived: bool };
pub const Commands = struct { archive: u16, pin: u16 };

pub fn items(state: State, commands: Commands, out: *[2]Item) []const Item {
    out[0] = .{ .command = commands.pin, .label = if (state.pinned) wide("Unpin selected chat") else wide("Pin chat to top") };
    out[1] = .{ .command = commands.archive, .label = if (state.archived or state.show_archived) wide("Unarchive\tCtrl+E") else wide("Archive\tCtrl+E") };
    return out;
}

test "inbox chat offers pin and archive only" {
    var out: [2]Item = undefined;
    const rows = items(.{ .archived = false, .pinned = false, .show_archived = false }, .{ .archive = 11, .pin = 13 }, &out);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(@as(u16, 13), rows[0].command);
    try std.testing.expectEqualSlices(u16, wide("Pin chat to top"), rows[0].label);
    try std.testing.expectEqual(@as(u16, 11), rows[1].command);
    try std.testing.expectEqualSlices(u16, wide("Archive\tCtrl+E"), rows[1].label);
    for (rows) |row| try std.testing.expectEqual(@as(u16, 0), row.label[row.label.len]);
}

test "archived chat offers unarchive" {
    var out: [2]Item = undefined;
    const rows = items(.{ .archived = true, .pinned = false, .show_archived = false }, .{ .archive = 11, .pin = 13 }, &out);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualSlices(u16, wide("Unarchive\tCtrl+E"), rows[1].label);
}

test "archived view offers unarchive even without archived flag" {
    var out: [2]Item = undefined;
    const rows = items(.{ .archived = false, .pinned = false, .show_archived = true }, .{ .archive = 11, .pin = 13 }, &out);
    try std.testing.expectEqualSlices(u16, wide("Unarchive\tCtrl+E"), rows[1].label);
}

test "pinned chat offers palette unpin wording" {
    var out: [2]Item = undefined;
    const rows = items(.{ .archived = false, .pinned = true, .show_archived = false }, .{ .archive = 21, .pin = 23 }, &out);
    try std.testing.expectEqual(@as(u16, 23), rows[0].command);
    try std.testing.expectEqualSlices(u16, wide("Unpin selected chat"), rows[0].label);
}

const std = @import("std");
const wide = std.unicode.utf8ToUtf16LeStringLiteral;

pub const Item = struct { command: u16, label: [:0]const u16 };
pub const State = struct { whatsapp: bool, archived: bool, kept: bool, pinned: bool, show_archived: bool };
pub const Commands = struct { archive: u16, keep: u16, pin: u16 };

pub fn items(state: State, commands: Commands, out: *[3]Item) []const Item {
    out[0] = .{ .command = commands.pin, .label = if (state.pinned) wide("Unpin selected chat") else wide("Pin chat to top") };
    out[1] = .{ .command = commands.archive, .label = if (state.archived or state.show_archived) wide("Unarchive\tCtrl+E") else wide("Archive\tCtrl+E") };
    if (!state.whatsapp) return out[0..2];
    out[2] = .{ .command = commands.keep, .label = if (state.kept) wide("Allow resurfacing") else wide("Keep archived\tCtrl+Shift+E") };
    return out;
}

test "inbox whatsapp chat offers archive and keep archived" {
    var out: [3]Item = undefined;
    const rows = items(.{ .whatsapp = true, .archived = false, .kept = false, .pinned = false, .show_archived = false }, .{ .archive = 11, .keep = 12, .pin = 13 }, &out);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqual(@as(u16, 13), rows[0].command);
    try std.testing.expectEqualSlices(u16, wide("Pin chat to top"), rows[0].label);
    try std.testing.expectEqual(@as(u16, 11), rows[1].command);
    try std.testing.expectEqualSlices(u16, wide("Archive\tCtrl+E"), rows[1].label);
    try std.testing.expectEqual(@as(u16, 12), rows[2].command);
    try std.testing.expectEqualSlices(u16, wide("Keep archived\tCtrl+Shift+E"), rows[2].label);
    for (rows) |row| try std.testing.expectEqual(@as(u16, 0), row.label[row.label.len]);
}

test "kept chat offers allow resurfacing" {
    var out: [3]Item = undefined;
    const rows = items(.{ .whatsapp = true, .archived = true, .kept = true, .pinned = false, .show_archived = false }, .{ .archive = 11, .keep = 12, .pin = 13 }, &out);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualSlices(u16, wide("Unarchive\tCtrl+E"), rows[1].label);
    try std.testing.expectEqual(@as(u16, 12), rows[2].command);
    try std.testing.expectEqualSlices(u16, wide("Allow resurfacing"), rows[2].label);
}

test "non whatsapp chat has no keep archived" {
    var out: [3]Item = undefined;
    for ([_]bool{ false, true }) |kept| {
        const rows = items(.{ .whatsapp = false, .archived = false, .kept = kept, .pinned = false, .show_archived = false }, .{ .archive = 11, .keep = 12, .pin = 13 }, &out);
        try std.testing.expectEqual(@as(usize, 2), rows.len);
        try std.testing.expectEqual(@as(u16, 13), rows[0].command);
        try std.testing.expectEqual(@as(u16, 11), rows[1].command);
    }
}

test "archived view offers unarchive even without archived flag" {
    var out: [3]Item = undefined;
    const rows = items(.{ .whatsapp = true, .archived = false, .kept = false, .pinned = false, .show_archived = true }, .{ .archive = 11, .keep = 12, .pin = 13 }, &out);
    try std.testing.expectEqualSlices(u16, wide("Unarchive\tCtrl+E"), rows[1].label);
    try std.testing.expectEqualSlices(u16, wide("Keep archived\tCtrl+Shift+E"), rows[2].label);
}

test "pinned chat offers palette unpin wording" {
    var out: [3]Item = undefined;
    const rows = items(.{ .whatsapp = true, .archived = false, .kept = false, .pinned = true, .show_archived = false }, .{ .archive = 21, .keep = 22, .pin = 23 }, &out);
    try std.testing.expectEqual(@as(u16, 23), rows[0].command);
    try std.testing.expectEqualSlices(u16, wide("Unpin selected chat"), rows[0].label);
}

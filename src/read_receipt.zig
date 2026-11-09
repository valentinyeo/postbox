const std = @import("std");

pub const Capability = enum { whatsapp_dm, whatsapp_group, slack, telegram, telegram_dm, signal, signal_dm };

pub fn shows(capability: Capability, from_me: bool, sent: bool, revoked: bool, read_by: i64) bool {
    if (!from_me or !sent or revoked) return false;
    return switch (capability) {
        .whatsapp_dm, .telegram_dm, .signal_dm => read_by >= 1,
        .whatsapp_group, .slack, .telegram, .signal => false,
    };
}

pub fn upgrade(previous_read: bool, read_by: i64) i64 {
    if (previous_read and read_by < 1) return 1;
    return read_by;
}

pub fn newestOwn(count: usize, context: anytype, comptime own: fn (@TypeOf(context), usize) bool) ?usize {
    var index = count;
    while (index > 0) {
        index -= 1;
        if (own(context, index)) return index;
    }
    return null;
}

const Rows = struct {
    from_me: []const bool,
    sent: []const bool,
};

fn rowOwn(rows: Rows, index: usize) bool {
    return rows.from_me[index] and rows.sent[index];
}

test "IGSH-1307 only a read one-to-one WhatsApp chat shows ticks" {
    try std.testing.expect(shows(.whatsapp_dm, true, true, false, 1));
    try std.testing.expect(!shows(.whatsapp_dm, true, true, false, 0));
    try std.testing.expect(!shows(.whatsapp_group, true, true, false, 3));
    try std.testing.expect(!shows(.slack, true, true, false, 1));
    try std.testing.expect(!shows(.telegram, true, true, false, 1));
    try std.testing.expect(!shows(.signal, true, true, false, 1));
}

test "IGSH-1899 a read one-to-one Telegram or Signal chat shows ticks" {
    try std.testing.expect(shows(.telegram_dm, true, true, false, 1));
    try std.testing.expect(!shows(.telegram_dm, true, true, false, 0));
    try std.testing.expect(shows(.signal_dm, true, true, false, 1));
    try std.testing.expect(!shows(.signal_dm, true, true, false, 0));
    try std.testing.expect(!shows(.signal_dm, false, true, false, 1));
}

test "IGSH-1307 incoming, unsent and deleted messages never show ticks" {
    try std.testing.expect(!shows(.whatsapp_dm, false, true, false, 1));
    try std.testing.expect(!shows(.whatsapp_dm, true, false, false, 1));
    try std.testing.expect(!shows(.whatsapp_dm, true, true, true, 1));
}

test "IGSH-1307 a read mark never goes back to unread" {
    try std.testing.expectEqual(@as(i64, 1), upgrade(true, 0));
    try std.testing.expectEqual(@as(i64, 0), upgrade(false, 0));
    try std.testing.expectEqual(@as(i64, 2), upgrade(true, 2));
}

test "IGSH-1307 only the newest own message is picked" {
    const from_me = [_]bool{ true, false, true, false };
    const sent = [_]bool{ true, true, true, true };
    const rows = Rows{ .from_me = &from_me, .sent = &sent };
    try std.testing.expectEqual(@as(?usize, 2), newestOwn(4, rows, rowOwn));
    const none = [_]bool{ false, false };
    try std.testing.expectEqual(@as(?usize, null), newestOwn(2, Rows{ .from_me = &none, .sent = &sent }, rowOwn));
    try std.testing.expectEqual(@as(?usize, null), newestOwn(0, rows, rowOwn));
}

const std = @import("std");

pub const Capability = enum { whatsapp_dm, whatsapp_group, slack, telegram, telegram_dm, signal, signal_dm };

pub const Status = enum { none, sent, delivered, read };

pub fn status(capability: Capability, from_me: bool, sent: bool, revoked: bool, delivered: i64, read_by: i64) Status {
    if (!from_me or !sent or revoked) return .none;
    return switch (capability) {
        .whatsapp_dm, .telegram_dm, .signal_dm => direct(delivered, read_by),
        .whatsapp_group => group(delivered, read_by),
        .slack, .telegram, .signal => .none,
    };
}

pub fn ticks(state: Status) usize {
    return switch (state) {
        .none => 0,
        .sent => 1,
        .delivered, .read => 2,
    };
}

fn direct(delivered: i64, read_by: i64) Status {
    if (read_by >= 1) return .read;
    if (delivered >= 1) return .delivered;
    return .sent;
}

fn group(delivered: i64, read_by: i64) Status {
    if (read_by >= 1 and read_by >= delivered) return .read;
    if (delivered >= 1) return .delivered;
    return .sent;
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
    read_by: []const i64,
};

fn rowOwn(rows: Rows, index: usize) bool {
    return rows.from_me[index] and rows.sent[index];
}

test "SOFT-3129 a one-to-one message shows sent, delivered or read from the recipient counts" {
    try std.testing.expectEqual(Status.sent, status(.whatsapp_dm, true, true, false, 0, 0));
    try std.testing.expectEqual(Status.delivered, status(.whatsapp_dm, true, true, false, 1, 0));
    try std.testing.expectEqual(Status.read, status(.whatsapp_dm, true, true, false, 1, 1));
    try std.testing.expectEqual(Status.read, status(.whatsapp_dm, true, true, false, 0, 1));
    try std.testing.expectEqual(Status.read, status(.telegram_dm, true, true, false, 0, 1));
    try std.testing.expectEqual(Status.read, status(.signal_dm, true, true, false, 0, 1));
}

test "SOFT-3129 sent is one tick and delivered or read is two" {
    try std.testing.expectEqual(@as(usize, 0), ticks(.none));
    try std.testing.expectEqual(@as(usize, 1), ticks(.sent));
    try std.testing.expectEqual(@as(usize, 2), ticks(.delivered));
    try std.testing.expectEqual(@as(usize, 2), ticks(.read));
}

test "SOFT-3129 incoming, pending and deleted messages show no state" {
    try std.testing.expectEqual(Status.none, status(.whatsapp_dm, false, true, false, 1, 1));
    try std.testing.expectEqual(Status.none, status(.whatsapp_dm, true, false, false, 1, 1));
    try std.testing.expectEqual(Status.none, status(.whatsapp_dm, true, true, true, 1, 1));
}

test "SOFT-3129 Slack and Telegram channels show no state" {
    try std.testing.expectEqual(Status.none, status(.slack, true, true, false, 1, 1));
    try std.testing.expectEqual(Status.none, status(.telegram, true, true, false, 1, 1));
    try std.testing.expectEqual(Status.none, status(.signal, true, true, false, 1, 1));
}

test "SOFT-3129 a group reads only once the recipients it reached have all read" {
    try std.testing.expectEqual(Status.sent, status(.whatsapp_group, true, true, false, 0, 0));
    try std.testing.expectEqual(Status.delivered, status(.whatsapp_group, true, true, false, 2, 0));
    try std.testing.expectEqual(Status.delivered, status(.whatsapp_group, true, true, false, 2, 1));
    try std.testing.expectEqual(Status.read, status(.whatsapp_group, true, true, false, 2, 2));
    try std.testing.expectEqual(Status.read, status(.whatsapp_group, true, true, false, 1, 3));
}

test "IGSH-1307 a read mark never goes back to unread" {
    try std.testing.expectEqual(@as(i64, 1), upgrade(true, 0));
    try std.testing.expectEqual(@as(i64, 0), upgrade(false, 0));
    try std.testing.expectEqual(@as(i64, 2), upgrade(true, 2));
}

test "IGSH-1307 only the newest own message is picked" {
    const from_me = [_]bool{ true, false, true, false };
    const sent = [_]bool{ true, true, true, true };
    const read_by = [_]i64{ 1, 0, 1, 0 };
    const rows = Rows{ .from_me = &from_me, .sent = &sent, .read_by = &read_by };
    try std.testing.expectEqual(@as(?usize, 2), newestOwn(4, rows, rowOwn));
    const none = [_]bool{ false, false };
    try std.testing.expectEqual(@as(?usize, null), newestOwn(2, Rows{ .from_me = &none, .sent = &sent, .read_by = &read_by }, rowOwn));
    try std.testing.expectEqual(@as(?usize, null), newestOwn(0, rows, rowOwn));
}

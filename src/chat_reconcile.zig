const std = @import("std");

pub const max_message_read_retries = 2;

pub fn openChatStale(chat_jid: []const u8, chat_ts: []const u8, displayed_jid: []const u8, displayed_ts: []const u8) bool {
    if (chat_jid.len == 0 or chat_ts.len == 0) return false;
    if (!std.mem.eql(u8, chat_jid, displayed_jid)) return false;
    if (displayed_ts.len == 0) return true;
    return std.mem.order(u8, chat_ts, displayed_ts) == .gt;
}

pub fn retryDelayTicks(attempt: u32) ?u32 {
    if (attempt > max_message_read_retries) return null;
    return 2 * attempt;
}

test "a newer chat row timestamp flags the open conversation stale" {
    try std.testing.expect(openChatStale("123@g.us", "2026-09-06T13:34:39", "123@g.us", "2026-09-06T13:30:00"));
    try std.testing.expect(!openChatStale("123@g.us", "2026-09-06T13:34:39", "123@g.us", "2026-09-06T13:34:39"));
    try std.testing.expect(!openChatStale("123@g.us", "2026-09-06T13:34:39", "123@g.us", "2026-09-06T13:40:00"));
}

test "other chats and rows without a timestamp never trigger a read" {
    try std.testing.expect(!openChatStale("123@g.us", "2026-09-06T13:34:39", "456@g.us", ""));
    try std.testing.expect(!openChatStale("123@g.us", "", "123@g.us", ""));
    try std.testing.expect(!openChatStale("", "2026-09-06T13:34:39", "", ""));
}

test "a conversation that never finished a read counts as stale" {
    try std.testing.expect(openChatStale("123@g.us", "2026-09-06T13:34:39", "123@g.us", ""));
}

test "retry backoff grows and the budget stops after two retries" {
    try std.testing.expectEqual(@as(?u32, 2), retryDelayTicks(1));
    try std.testing.expectEqual(@as(?u32, 4), retryDelayTicks(2));
    try std.testing.expectEqual(@as(?u32, null), retryDelayTicks(3));
}

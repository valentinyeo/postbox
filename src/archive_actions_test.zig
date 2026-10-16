//! Host tests of the archive handlers extracted from main.zig by build.zig.
//! Only Windows UI, persistence and the child-process queue are stubbed.
const std = @import("std");
const archive_rules = @import("archive_rules");

fn Utf8Text(comptime capacity: usize) type {
    return struct {
        data: [capacity]u8 = undefined,
        len: usize = 0,
        fn set(self: *@This(), text: []const u8) void {
            self.len = @min(text.len, capacity);
            @memcpy(self.data[0..self.len], text[0..self.len]);
        }
        fn slice(self: *const @This()) []const u8 {
            return self.data[0..self.len];
        }
    };
}
const Provider = enum { whatsapp, slack, telegram };
const Chat = struct {
    jid: Utf8Text(191) = .{},
    timestamp: Utf8Text(47) = .{},
    provider: Provider = .whatsapp,
    archived: bool = false,
};
const PendingArchive = struct {
    jid: Utf8Text(191) = .{},
    should_unarchive: bool = false,
};
const App = struct {
    chats: [4]Chat = @splat(.{}),
    chat_count: usize = 2,
    selected_chat: usize = 0,
    show_archived: bool = false,
    bulk: archive_rules.Selection(4) = .{},
    archive_state: ?*archive_rules.State,
    pending_archives: [4]PendingArchive = @splat(.{}),
    pending_archive_count: usize = 0,
    chats_hwnd: ?usize = null,
    canvas: ?usize = null,
    status: Utf8Text(191) = .{},
    saved: [4096]u8 = undefined,
    saved_len: usize = 0,
    persisted_before_start: bool = true,
    unarchive_retry: Utf8Text(191) = .{},
};
const win = struct {
    const FALSE = 0;
    fn InvalidateRect(_: usize, _: ?*anyopaque, _: i32) i32 {
        return 1;
    }
};
fn fixture(state: *archive_rules.State) App {
    var a = App{ .archive_state = state };
    a.chats[0].jid.set("a@g.us");
    a.chats[1].jid.set("b@g.us");
    for (a.chats[0..2]) |*chat| chat.timestamp.set("2026-10-10T10:00:00Z");
    return a;
}
fn setStatus(a: *App, status: []const u8) void {
    a.status.set(status);
}
fn saveArchiveState(a: *App) void {
    a.saved_len = a.archive_state.?.format(&a.saved).len;
}
fn isKeptArchived(a: *const App, jid: []const u8) bool {
    return if (a.archive_state) |state| state.isKept(jid) else false;
}
fn startNextArchive(a: *App) void {
    a.persisted_before_start = a.persisted_before_start and a.saved_len > 0;
}
fn paneFollowSelection(_: *App, _: []const u8) void {}
fn visibleChatIndex(a: *const App, jid: []const u8) ?usize {
    for (a.chats[0..a.chat_count], 0..) |*chat, i| {
        if (std.mem.eql(u8, chat.jid.slice(), jid)) return i;
    }
    return null;
}
fn chatProvider(a: *App, jid: []const u8) Provider {
    return if (visibleChatIndex(a, jid)) |i| a.chats[i].provider else .whatsapp;
}
fn removeChatRow(a: *App, removed: usize) void {
    var i = removed + 1;
    while (i < a.chat_count) : (i += 1) a.chats[i - 1] = a.chats[i];
    a.chat_count -= 1;
    if (a.chat_count > 0 and a.selected_chat >= a.chat_count) a.selected_chat = a.chat_count - 1;
}

test "keep archives the selected chat and persists before the child starts" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    archiveSelectedChat(&a, true);
    try std.testing.expect(a.persisted_before_start);
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expect(!a.pending_archives[0].should_unarchive);
    try std.testing.expectEqualStrings("a@g.us", a.pending_archives[0].jid.slice());
    try std.testing.expectEqual(@as(usize, 1), a.chat_count);
    try std.testing.expectEqualStrings("Kept archived. Won't come back", a.status.slice());
    var restarted = archive_rules.State{};
    restarted.parse(a.saved[0..a.saved_len]);
    try std.testing.expect(restarted.isKept("a@g.us"));
    try std.testing.expect(!archive_rules.shouldResurface(false, restarted.isKept("a@g.us"), "2026-10-10T11:00:00Z", restarted.baseline("a@g.us").?));
}

test "Ctrl+A keep acts on the snapshot and not rows added later" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    selectAllChats(&a);
    a.chats[2].jid.set("later@g.us");
    a.chat_count = 3;
    archiveSelectedChat(&a, true);
    try std.testing.expectEqual(@as(usize, 2), a.pending_archive_count);
    try std.testing.expect(state.isKept("a@g.us"));
    try std.testing.expect(state.isKept("b@g.us"));
    try std.testing.expect(!state.isKept("later@g.us"));
    try std.testing.expectEqual(@as(usize, 0), a.bulk.count);
    try std.testing.expectEqualStrings("later@g.us", a.chats[0].jid.slice());
}

test "keep shortcut is idempotent in archived view and palette allows resurfacing" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.show_archived = true;
    archiveSelectedChat(&a, true);
    archiveSelectedChat(&a, true);
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expectEqual(@as(usize, 2), a.chat_count);
    try std.testing.expect(state.isKept("a@g.us"));
    toggleKeepArchived(&a);
    var restarted = archive_rules.State{};
    restarted.parse(a.saved[0..a.saved_len]);
    try std.testing.expect(!restarted.isKept("a@g.us"));
    try std.testing.expect(archive_rules.shouldResurface(false, restarted.isKept("a@g.us"), "2026-10-10T11:00:00Z", restarted.baseline("a@g.us").?));
}

test "palette keep applies to the entire selection even when the first chat is kept" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.show_archived = true;
    try std.testing.expect(state.archive("a@g.us", a.chats[0].timestamp.slice(), true));
    selectAllChats(&a);
    toggleKeepArchived(&a);
    try std.testing.expect(state.isKept("a@g.us"));
    try std.testing.expect(state.isKept("b@g.us"));
    try std.testing.expectEqual(@as(usize, 2), a.pending_archive_count);
}

test "plain bulk archive resurfaces on incoming but not outgoing messages" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    selectAllChats(&a);
    archiveSelectedChat(&a, false);
    try std.testing.expectEqual(@as(usize, 2), a.pending_archive_count);
    try std.testing.expectEqualStrings("Archived. Comes back on a new message", a.status.slice());
    for ([_][]const u8{ "a@g.us", "b@g.us" }) |jid| {
        try std.testing.expect(archive_rules.shouldResurface(false, state.isKept(jid), "2026-10-10T11:00:00Z", state.baseline(jid).?));
        try std.testing.expect(!archive_rules.shouldResurface(true, state.isKept(jid), "2026-10-10T11:00:00Z", state.baseline(jid).?));
    }
}

test "unarchive clears keep while unavailable and full queues do not claim success" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.show_archived = true;
    state.setKeep("a@g.us", true);
    archiveSelectedChat(&a, false);
    try std.testing.expect(a.pending_archives[0].should_unarchive);
    try std.testing.expect(!state.isKept("a@g.us"));

    a = fixture(&state);
    a.pending_archive_count = a.pending_archives.len;
    archiveSelectedChat(&a, true);
    try std.testing.expectEqualStrings("Archive queue is full", a.status.slice());
    try std.testing.expect(!state.isKept("a@g.us"));
    a = fixture(&state);
    a.archive_state = null;
    archiveSelectedChat(&a, true);
    try std.testing.expectEqualStrings("Keep archived is not available", a.status.slice());
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "keep rejects other providers without queuing a WhatsApp write" {
    var state = archive_rules.State{};
    for ([_]Provider{ .slack, .telegram }) |provider| {
        var a = fixture(&state);
        a.chats[0].provider = provider;
        archiveSelectedChat(&a, true);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        try std.testing.expect(!state.isKept("a@g.us"));
    }
}

test "keep overrides an earlier archive followed by an unarchive" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    try std.testing.expect(archiveChat(&a, "a@g.us", .archive) == null);
    try std.testing.expect(archiveChat(&a, "a@g.us", .unarchive) == null);
    try std.testing.expect(archiveChat(&a, "a@g.us", .keep) == null);
    try std.testing.expectEqual(@as(usize, 3), a.pending_archive_count);
    try std.testing.expect(!a.pending_archives[2].should_unarchive);
    try std.testing.expect(state.isKept("a@g.us"));
}

test "a delayed resurfacing retry cannot unarchive a chat kept since the probe" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.unarchive_retry.set("a@g.us");
    archiveSelectedChat(&a, true);
    queueUnarchiveChat(&a, "a@g.us");
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expectEqual(@as(usize, 0), a.unarchive_retry.len);
    try std.testing.expect(state.isKept("a@g.us"));

    queueUnarchiveChat(&a, "b@g.us");
    try std.testing.expectEqual(@as(usize, 2), a.pending_archive_count);
    try std.testing.expect(a.pending_archives[1].should_unarchive);
}

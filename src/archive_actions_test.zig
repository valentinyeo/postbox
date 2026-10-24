const std = @import("std");
const verification_fixture = false;
const chat_key = @import("chat_key");
const archive_rules = @import("archive_rules");
const voice_sent = @import("voice_sent");
const ArchiveSource = if (@hasDecl(archive_rules, "Source")) archive_rules.Source else enum { shortcut, menu, control, send };
const command_archive: u16 = 2007;
const PendingSend = struct {
    provider: Provider = .whatsapp,
    jid: Utf8Text(191) = .{},
    file: Utf8Text(520) = .{},
    queued_unix: i64 = 0,
    voice_seconds: u32 = 0,
    seq: u64 = 0,
    ptt: bool = false,
};

fn Utf8Text(comptime capacity: usize) type {
    return struct {
        data: [capacity]u8 = undefined,
        len: usize = 0,
        fn set(self: *@This(), text: []const u8) void {
            self.len = @min(text.len, capacity);
            @memcpy(self.data[0..self.len], text[0..self.len]);
        }
        pub fn slice(self: *const @This()) []const u8 {
            return self.data[0..self.len];
        }
    };
}
const Provider = @FieldType(chat_key.Key, "provider");
const Chat = struct {
    account: Utf8Text(32) = .{},
    jid: Utf8Text(191) = .{},
    timestamp: Utf8Text(47) = .{},
    provider: Provider = .whatsapp,
    archived: bool = false,
};
const PendingArchive = struct {
    jid: Utf8Text(191) = .{},
    should_unarchive: bool = false,
    source: ArchiveSource = .shortcut,
};
const App = struct {
    cache_tag: Utf8Text(32) = .{},
    chats: [4]Chat = @splat(.{}),
    chat_count: usize = 2,
    selected_chat: usize = 0,
    displayed_provider: @TypeOf((Chat{}).provider) = .whatsapp,
    displayed_account: Utf8Text(32) = .{},
    displayed_jid: Utf8Text(191) = .{},
    show_archived: bool = false,
    bulk: archive_rules.Selection(4) = .{},
    archive_state: ?*archive_rules.State,
    pending_archives: [4]PendingArchive = @splat(.{}),
    pending_archive_count: usize = 0,
    archive_batch_total: usize = 0,
    chats_hwnd: ?usize = null,
    canvas: ?usize = null,
    compose: ?usize = null,
    status: Utf8Text(191) = .{},
    saved: [4096]u8 = undefined,
    saved_len: usize = 0,
    persisted_before_start: bool = true,
    unarchive_retry: Utf8Text(191) = .{},
    unarchive_retry_source: ArchiveSource = .send,
    palette_archive_key: chat_key.Stored = .{},
    palette_archive_bulk_count: usize = 0,
    palette_archive_show_archived: bool = false,
    palette_archive_was_archived: bool = false,
    hwnd: ?usize = null,
    archive_child: ?u8 = null,
    read_child: ?u8 = null,
    send_child: ?u8 = null,
    io: u8 = 0,
    wacli_path: []const u8 = "wacli",
    log: Utf8Text(288) = .{},
    log_count: usize = 0,
    spawned_jid: Utf8Text(191) = .{},
    pending_sends: [4]PendingSend = @splat(.{}),
    pending_send_count: usize = 0,
    sent_voice: [voice_sent.max_entries]voice_sent.Entry = @splat(.{}),
    sent_voice_count: usize = 0,
    people: struct {
        fn find(_: @This(), _: []const u8) ?struct { origin: enum { archived, contact } } {
            return null;
        }
    } = .{},
};
const win = struct {
    const FALSE = 0;
    const HWND = usize;
    const LPARAM = isize;
    const MSG = struct { lParam: LPARAM = 0 };
    fn InvalidateRect(_: usize, _: ?*anyopaque, _: i32) i32 {
        return 1;
    }
};
fn fixture(state: *archive_rules.State) App {
    var a = App{ .archive_state = state, .chats_hwnd = 4, .canvas = 6, .hwnd = 5, .compose = 1 };
    a.chats[0].jid.set("a@g.us");
    a.chats[1].jid.set("b@g.us");
    for (a.chats[0..2]) |*chat| chat.timestamp.set("2026-10-10T10:00:00Z");
    return a;
}
fn nowUnixSeconds() i64 {
    return 1791628200;
}
fn setStatus(a: *App, status: []const u8) void {
    var buffer: [64]u8 = undefined;
    const progress = if (a.pending_archive_count > 0)
        archive_rules.progressStatus(&buffer, a.pending_archives[0].should_unarchive, a.archive_batch_total, a.pending_archive_count)
    else
        null;
    a.status.set(progress orelse status);
}
fn saveArchiveState(a: *App) void {
    a.saved_len = a.archive_state.?.format(&a.saved).len;
}
fn isKeptArchived(a: *const App, jid: []const u8) bool {
    return if (a.archive_state) |state| state.isKept(jid) else false;
}
var spawning_app: ?*App = null;
const child_process = struct {
    const Options = struct {
        argv: []const []const u8,
        stdin: enum { ignore },
        stdout: enum { ignore },
        stderr: enum { ignore },
        create_no_window: bool,
    };
    fn spawn(_: u8, options: Options) !u8 {
        const a = spawning_app.?;
        a.spawned_jid.set(options.argv[options.argv.len - 1]);
        a.persisted_before_start = a.persisted_before_start and a.saved_len > 0;
        return 1;
    }
};
fn stopSync(a: *App, _: []const u8) void {
    spawning_app = a;
}
fn startSync(_: *App) void {}
fn mediaBusy(_: *App) bool {
    return false;
}
fn avatarBusy(_: *App) bool {
    return false;
}
fn sendReadyPending(_: *App) bool {
    return false;
}
fn appendLaunchLog(a: *App, text: []const u8) void {
    a.log.set(text);
    a.log_count += 1;
}
fn persistFileOutbox(_: *App) void {}
fn deleteFileUtf8(_: []const u8) void {}
fn closePalette(_: *App) void {}
fn runCommand(a: *App, command: u16) void {
    if (command == command_archive) archiveSelected(a, false);
}
fn archiveSelected(a: *App, keep: bool) void {
    if (@typeInfo(@TypeOf(archiveSelectedChat)).@"fn".params.len == 3) archiveSelectedChat(a, keep, .shortcut) else archiveSelectedChat(a, keep);
}
fn archiveRequest(a: *App, jid: []const u8, action: archive_rules.Action) ?[]const u8 {
    return archiveChat(a, archiveChatKey(a, jid), action, .control);
}
fn paneFollowSelection(_: *App, _: []const u8) void {}
fn holdKept(a: *App, jid: []const u8, provider_archived: bool, ts: []const u8) bool {
    if (comptime @hasDecl(@This(), "holdKeptArchived")) return @field(@This(), "holdKeptArchived")(a, jid, provider_archived, ts);
    return false;
}
fn visibleChatIndex(a: *const App, key: chat_key.Key) ?usize {
    return chat_key.indexOf(Chat, a.chats[0..a.chat_count], key);
}
fn chatProvider(a: *App, jid: []const u8) Provider {
    for (a.chats[0..a.chat_count]) |*chat| {
        if (std.mem.eql(u8, chat.jid.slice(), jid)) return chat.provider;
    }
    return .whatsapp;
}
fn removeChatRow(a: *App, removed: usize) void {
    var i = removed + 1;
    while (i < a.chat_count) : (i += 1) a.chats[i - 1] = a.chats[i];
    a.chat_count -= 1;
    if (a.chat_count > 0 and a.selected_chat >= a.chat_count) a.selected_chat = a.chat_count - 1;
}

test "a new message that unarchives a kept chat sends it straight back to the archive" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    try std.testing.expect(state.archive("a@g.us", "2026-10-10T10:00:00Z", true));
    try std.testing.expect(state.archive("b@g.us", "2026-10-10T10:00:00Z", false));
    try std.testing.expect(!holdKept(&a, "a@g.us", true, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expect(holdKept(&a, "a@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expect(!a.pending_archives[0].should_unarchive);
    try std.testing.expectEqualStrings("a@g.us", a.spawned_jid.slice());
    try std.testing.expectEqualStrings("archive: jid=a@g.us archived=true source=kept", a.log.slice());
    try std.testing.expect(pendingArchiveHidesChat(&a, "a@g.us", false));
    try std.testing.expect(!pendingArchiveHidesChat(&a, "a@g.us", true));
    try std.testing.expect(state.isKept("a@g.us"));
    try std.testing.expectEqual(@as(usize, 1), a.chat_count);
    try std.testing.expectEqualStrings("b@g.us", a.chats[0].jid.slice());
    try std.testing.expect(!holdKept(&a, "a@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expect(!holdKept(&a, "b@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
}

test "a kept chat refused by a full archive queue is tried again for the same message" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    try std.testing.expect(state.archive("kept@g.us", "2026-10-10T10:00:00Z", true));
    var name: [16]u8 = undefined;
    for (0..a.pending_archives.len) |i| {
        try std.testing.expect(archiveRequest(&a, try std.fmt.bufPrint(&name, "{d}@g.us", .{i}), .archive) == null);
    }
    try std.testing.expect(!holdKept(&a, "kept@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqual(a.pending_archives.len, a.pending_archive_count);
    a.archive_child = null;
    removeFirstPendingArchive(&a);
    try std.testing.expect(holdKept(&a, "kept@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqualStrings("kept@g.us", a.pending_archives[a.pending_archive_count - 1].jid.slice());
}

test "a kept chat stays kept through a restart and is archived again on the next new message" {
    var state = archive_rules.State{};
    var before = fixture(&state);
    archiveSelected(&before, true);
    var restarted = archive_rules.State{};
    restarted.parse(before.saved[0..before.saved_len]);
    var a = fixture(&restarted);
    try std.testing.expect(holdKept(&a, "a@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expect(!a.pending_archives[0].should_unarchive);
    var again = archive_rules.State{};
    again.parse(a.saved[0..a.saved_len]);
    try std.testing.expect(again.isKept("a@g.us"));
    again.setKeep("a@g.us", false);
    var reloaded = archive_rules.State{};
    var buffer: [512]u8 = undefined;
    reloaded.parse(again.format(&buffer));
    var b = fixture(&reloaded);
    try std.testing.expect(!holdKept(&b, "a@g.us", false, "2026-10-10T12:00:00Z"));
    try std.testing.expectEqual(@as(usize, 0), b.pending_archive_count);
}

test "keep archives the selected chat and persists before the child starts" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    archiveSelected(&a, true);
    try std.testing.expect(a.persisted_before_start);
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expect(!a.pending_archives[0].should_unarchive);
    try std.testing.expectEqualStrings("a@g.us", a.pending_archives[0].jid.slice());
    try std.testing.expectEqual(@as(usize, 1), a.chat_count);
    try std.testing.expectEqualStrings("Kept archived. Won't come back", a.status.slice());
    var restarted = archive_rules.State{};
    restarted.parse(a.saved[0..a.saved_len]);
    try std.testing.expect(restarted.isKept("a@g.us"));
}

test "Ctrl+A keep acts on the snapshot and not rows added later" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    selectAllChats(&a);
    a.chats[2].jid.set("later@g.us");
    a.chat_count = 3;
    archiveSelected(&a, true);
    try std.testing.expectEqual(@as(usize, 2), a.pending_archive_count);
    try std.testing.expect(state.isKept("a@g.us"));
    try std.testing.expect(state.isKept("b@g.us"));
    try std.testing.expect(!state.isKept("later@g.us"));
    try std.testing.expectEqual(@as(usize, 0), a.bulk.count);
    try std.testing.expectEqualStrings("later@g.us", a.chats[0].jid.slice());
}

test "plain bulk archive persists both archived chats" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    selectAllChats(&a);
    archiveSelected(&a, false);
    try std.testing.expectEqual(@as(usize, 2), a.pending_archive_count);
    try std.testing.expectEqualStrings("Archiving 1 of 2", a.status.slice());
    var restarted = archive_rules.State{};
    restarted.parse(a.saved[0..a.saved_len]);
    for ([_][]const u8{ "a@g.us", "b@g.us" }) |jid| {
        try std.testing.expect(restarted.find(jid) != null);
        try std.testing.expect(!restarted.isKept(jid));
    }
}

test "a plain archive baselines at the archive moment when the list row is stale" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    archiveSelected(&a, false);
    try std.testing.expectEqualStrings("2026-10-10T10:30:00Z", state.baseline("a@g.us").?);
}

test "a plain archive keeps a list row time that is later than the archive moment" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.chats[0].timestamp.set("2026-10-10T12:00:00Z");
    archiveSelected(&a, false);
    try std.testing.expectEqualStrings("2026-10-10T12:00:00Z", state.baseline("a@g.us").?);
}

test "unarchive clears keep while unavailable and full queues do not claim success" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.show_archived = true;
    state.setKeep("a@g.us", true);
    archiveSelected(&a, false);
    try std.testing.expect(a.pending_archives[0].should_unarchive);
    try std.testing.expect(!state.isKept("a@g.us"));

    a = fixture(&state);
    a.pending_archive_count = a.pending_archives.len;
    archiveSelected(&a, true);
    try std.testing.expectEqualStrings("Archive queue is full", a.status.slice());
    try std.testing.expect(!state.isKept("a@g.us"));
    a = fixture(&state);
    a.archive_state = null;
    archiveSelected(&a, true);
    try std.testing.expectEqualStrings("Keep archived is not available", a.status.slice());
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "keep rejects other providers without queuing a WhatsApp write" {
    var state = archive_rules.State{};
    for ([_]Provider{ .telegram, .signal }) |provider| {
        var a = fixture(&state);
        a.chats[0].provider = provider;
        archiveSelected(&a, true);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        try std.testing.expect(!state.isKept("a@g.us"));
    }
}

test "keep overrides an earlier archive followed by an unarchive" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    try std.testing.expect(archiveRequest(&a, "a@g.us", .archive) == null);
    try std.testing.expect(archiveRequest(&a, "a@g.us", .unarchive) == null);
    try std.testing.expect(archiveRequest(&a, "a@g.us", .keep) == null);
    try std.testing.expectEqual(@as(usize, 3), a.pending_archive_count);
    try std.testing.expect(!a.pending_archives[2].should_unarchive);
    try std.testing.expect(state.isKept("a@g.us"));
}

test "pending archive rows stay hidden through queue advancement and view switches" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    selectAllChats(&a);
    archiveSelected(&a, false);
    try std.testing.expectEqual(@as(usize, 2), a.archive_batch_total);
    try std.testing.expect(pendingArchiveHidesChat(&a, "a@g.us", false));
    try std.testing.expect(pendingArchiveHidesChat(&a, "b@g.us", false));
    try std.testing.expect(!pendingArchiveHidesChat(&a, "later@g.us", false));
    try std.testing.expect(!pendingArchiveHidesChat(&a, "b@g.us", true));
    removeFirstPendingArchive(&a);
    setStatus(&a, "Refreshed");
    try std.testing.expectEqualStrings("Archiving 2 of 2", a.status.slice());
    try std.testing.expect(pendingArchiveHidesChat(&a, "b@g.us", false));
    try std.testing.expect(!pendingArchiveHidesChat(&a, "a@g.us", false));
    removeFirstPendingArchive(&a);
    setStatus(&a, archive_rules.Action.archive.status());
    try std.testing.expectEqualStrings("Archived", a.status.slice());
    try std.testing.expect(!pendingArchiveHidesChat(&a, "b@g.us", false));
    try std.testing.expect(archiveRequest(&a, "later@g.us", .archive) == null);
    try std.testing.expectEqual(@as(usize, 1), a.archive_batch_total);
}

test "pending unarchives stay hidden in archived view and share batch accounting" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.show_archived = true;
    archiveSelected(&a, false);
    queueUnarchiveChat(&a, "b@g.us", .send);
    queueUnarchiveChat(&a, "b@g.us", .send);
    try std.testing.expectEqual(@as(usize, 2), a.archive_batch_total);
    setStatus(&a, "Refreshed");
    try std.testing.expectEqualStrings("Unarchiving 1 of 2", a.status.slice());
    try std.testing.expect(pendingArchiveHidesChat(&a, "a@g.us", true));
    try std.testing.expect(pendingArchiveHidesChat(&a, "b@g.us", true));
    try std.testing.expect(!pendingArchiveHidesChat(&a, "b@g.us", false));
    removeFirstPendingArchive(&a);
    try std.testing.expect(pendingArchiveHidesChat(&a, "b@g.us", true));
    removeFirstPendingArchive(&a);
    setStatus(&a, archive_rules.Action.unarchive.status());
    try std.testing.expectEqualStrings("Chat unarchived", a.status.slice());
}

test "Ctrl+E archives from the compose box and Ctrl+Shift+E is unbound" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    const message = win.MSG{};
    try std.testing.expect(!archiveKey(&a, 'E', true, true, false, a.compose, &message));
    try std.testing.expect(!archiveKey(&a, 'E', true, false, true, a.compose, &message));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expect(archiveKey(&a, 'E', true, false, false, a.compose, &message));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expectEqualStrings("a@g.us", a.pending_archives[0].jid.slice());
    try std.testing.expect(!a.pending_archives[0].should_unarchive);
    try std.testing.expect(!state.isKept("a@g.us"));
    try std.testing.expectEqualStrings("Archived", a.status.slice());
    const repeated = win.MSG{ .lParam = 1 << 30 };
    try std.testing.expect(!archiveKey(&a, 'E', true, false, false, a.compose, &repeated));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
}

test "archive shortcuts ignore composer search and other edit fields" {
    {
        var state = archive_rules.State{};
        var a = fixture(&state);
        const message = win.MSG{};
        try std.testing.expect(!archiveKey(&a, 'E', false, false, false, a.compose, &message));
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        try std.testing.expectEqual(@as(usize, 0), a.log_count);
    }
    for ([_]usize{ 2, 3 }) |focus| {
        for ([_]bool{ false, true }) |keep| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            const message = win.MSG{};
            _ = archiveKey(&a, 'E', true, false, keep, focus, &message);
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            try std.testing.expectEqual(@as(usize, 0), a.log_count);
        }
    }
}

test "held archive keys cannot consume successive chats" {
    for ([_]bool{ false, true }) |control| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        const pressed = win.MSG{};
        try std.testing.expect(archiveKey(&a, 'E', control, false, false, 4, &pressed));
        const repeated = win.MSG{ .lParam = 1 << 30 };
        _ = archiveKey(&a, 'E', control, false, false, 4, &repeated);
        try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
        try std.testing.expectEqualStrings("a@g.us", a.pending_archives[0].jid.slice());
        try std.testing.expectEqualStrings("b@g.us", a.chats[0].jid.slice());
    }
}

test "modified bare E does not archive" {
    for ([_]bool{ false, true }) |alt| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        const message = win.MSG{};
        _ = archiveKey(&a, 'E', false, alt, !alt, 4, &message);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "archive shortcut refuses a row that disagrees with the displayed chat" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.displayed_jid.set("gone@g.us");
    archiveSelected(&a, false);
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "palette archive refuses a changed chat instead of archiving the replacement row" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    buildPaletteItems(&a);
    a.chats[0] = a.chats[1];
    a.chat_count = 1;
    activateArchivePalette(&a, .{ .command = command_archive });
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "palette archive rejects a changed bulk selection or archive view" {
    for ([_]bool{ false, true }) |view_changed| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        selectAllChats(&a);
        buildPaletteItems(&a);
        if (view_changed) a.show_archived = true else a.bulk.clear();
        activateArchivePalette(&a, .{ .command = command_archive });
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "palette archive follows the same jid through a list reorder" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    buildPaletteItems(&a);
    std.mem.swap(Chat, &a.chats[0], &a.chats[1]);
    a.selected_chat = 1;
    activateArchivePalette(&a, .{ .command = command_archive });
    try std.testing.expectEqualStrings("a@g.us", a.pending_archives[0].jid.slice());
    try std.testing.expectEqual(ArchiveSource.menu, a.pending_archives[0].source);
}

test "successful local text file and voice sends unarchive even kept chats" {
    for ([_]bool{ false, true }) |keep| {
        for (0..3) |kind| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            a.chats[0].archived = true;
            try std.testing.expect(state.archive("a@g.us", "baseline", keep));
            a.pending_sends[0].jid.set("a@g.us");
            if (kind > 0) a.pending_sends[0].file.set("sent.ogg");
            a.pending_sends[0].ptt = kind == 2;
            a.pending_send_count = 1;
            removeFirstPendingSend(&a, true);
            try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
            try std.testing.expect(a.pending_archives[0].should_unarchive);
            try std.testing.expectEqual(ArchiveSource.send, a.pending_archives[0].source);
            try std.testing.expect(!state.isKept("a@g.us"));
            try std.testing.expectEqualStrings("archive: jid=a@g.us archived=false source=send", a.log.slice());
        }
    }
}

test "failed local sends and successful inbox sends do not unarchive" {
    for ([_]bool{ false, true }) |delivered| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        a.chats[0].archived = !delivered;
        a.pending_sends[0].jid.set("a@g.us");
        a.pending_send_count = 1;
        removeFirstPendingSend(&a, delivered);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "local send unarchives its jid even when a different chat is selected" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    try std.testing.expect(state.archive("sent@g.us", "baseline", false));
    a.pending_sends[0].jid.set("sent@g.us");
    a.pending_send_count = 1;
    removeFirstPendingSend(&a, true);
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expectEqualStrings("sent@g.us", a.pending_archives[0].jid.slice());
    try std.testing.expect(a.pending_archives[0].should_unarchive);
}

test "every archive child logs its exact jid direction and queued source once" {
    for ([_]archive_rules.Action{ .archive, .unarchive }) |action| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        a.read_child = 1;
        try std.testing.expect(archiveRequest(&a, "a@g.us", action) == null);
        a.chats[0].jid.set("replacement@g.us");
        try std.testing.expectEqual(@as(usize, 0), a.log_count);
        a.read_child = null;
        startNextArchive(&a);
        startNextArchive(&a);
        const expected = if (action == .archive)
            "archive: jid=a@g.us archived=true source=control"
        else
            "archive: jid=a@g.us archived=false source=control";
        try std.testing.expectEqualStrings(expected, a.log.slice());
        try std.testing.expectEqual(@as(usize, 1), a.log_count);
        try std.testing.expectEqualStrings("a@g.us", a.spawned_jid.slice());
    }
}

test "archive shortcuts ignore unrelated windows and buttons" {
    for ([_]?usize{ null, 7, 8 }) |focus| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        const message = win.MSG{};
        _ = archiveKey(&a, 'E', true, false, false, focus, &message);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "palette cannot turn unarchive into archive after a remote unarchive" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.chats[0].archived = true;
    buildPaletteItems(&a);
    a.chats[0].archived = false;
    activateArchivePalette(&a, .{ .command = command_archive });
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "oversized archive ids cannot truncate into a different chat" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    var jid: [archive_rules.max_jid + 1]u8 = @splat('a');
    jid[archive_rules.max_jid - 2] = '@';
    try std.testing.expect(archiveRequest(&a, &jid, .archive) != null);
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "local send deferred unarchive retains send source past a full queue" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    state.setKeep("a@g.us", true);
    a.pending_archive_count = a.pending_archives.len;
    a.read_child = 1;
    a.pending_sends[0].jid.set("a@g.us");
    a.pending_send_count = 1;
    removeFirstPendingSend(&a, true);
    try std.testing.expectEqualStrings("a@g.us", a.unarchive_retry.slice());
    try std.testing.expectEqual(ArchiveSource.send, a.unarchive_retry_source);
    removeFirstPendingArchive(&a);
    retryUnarchiveChat(&a);
    try std.testing.expectEqual(@as(usize, 0), a.unarchive_retry.len);
    try std.testing.expect(a.pending_archives[a.pending_archive_count - 1].should_unarchive);
    try std.testing.expectEqual(ArchiveSource.send, a.pending_archives[a.pending_archive_count - 1].source);
    try std.testing.expect(!state.isKept("a@g.us"));
}

test "Slack archive persists per Key without ever queuing either archive transport" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.chats[0].provider = .slack;
    a.chats[0].account.set("fixture-first");
    a.chats[0].jid.set("channel-shared");
    var key = chat_key.Stored{};
    key.set(chat_key.of(&a.chats[0]));
    archiveSelected(&a, false);
    try std.testing.expect(state.localArchived(key.key()));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expect(a.archive_child == null);
    try std.testing.expectEqual(@as(usize, 0), a.log_count);
    try std.testing.expectEqualStrings("Kept archived. Won't come back", a.status.slice());
    var loaded = archive_rules.State{};
    loaded.parse(a.saved[0..a.saved_len]);
    try std.testing.expect(loaded.localArchived(key.key()));
    for ([_][]const u8{ "2026-10-10T11:00:00Z", "2026-10-10T12:00:00Z", "2026-10-10T13:00:00Z" }) |stamp| {
        try std.testing.expect(!loaded.holdKept(key.key().id, false, stamp));
        try std.testing.expect(loaded.localArchived(key.key()));
    }
    try std.testing.expect(archiveChat(&a, key.key(), .unarchive, .shortcut) == null);
    try std.testing.expect(!state.localArchived(key.key()));
    loaded.parse(a.saved[0..a.saved_len]);
    try std.testing.expect(!loaded.localArchived(key.key()));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "two Slack accounts with the same channel id archive and unarchive independently" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    for (a.chats[0..2], 0..) |*chat, index| {
        chat.provider = .slack;
        chat.account.set(if (index == 0) "fixture-first" else "fixture-second");
        chat.jid.set("channel-shared");
    }
    var first = chat_key.Stored{};
    first.set(chat_key.of(&a.chats[0]));
    var second = chat_key.Stored{};
    second.set(chat_key.of(&a.chats[1]));
    archiveSelected(&a, false);
    try std.testing.expect(state.localArchived(first.key()));
    try std.testing.expect(!state.localArchived(second.key()));
    try std.testing.expectEqualStrings("fixture-second", a.chats[0].account.slice());
    archiveSelected(&a, false);
    try std.testing.expect(state.localArchived(second.key()));
    var loaded = archive_rules.State{};
    loaded.parse(a.saved[0..a.saved_len]);
    try std.testing.expect(loaded.localArchived(first.key()));
    try std.testing.expect(loaded.localArchived(second.key()));
    try std.testing.expect(archiveChat(&a, first.key(), .unarchive, .menu) == null);
    try std.testing.expect(!state.localArchived(first.key()));
    try std.testing.expect(state.localArchived(second.key()));
    try std.testing.expect(!state.localArchived(chat_key.Key{ .provider = .whatsapp, .account = second.key().account, .id = second.key().id }));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "Slack Ctrl E bare E and menu archive share the local action" {
    for ([_]bool{ false, true }) |control| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        a.chats[0].provider = .slack;
        a.chats[0].account.set("fixture-team");
        var key = chat_key.Stored{};
        key.set(chat_key.of(&a.chats[0]));
        const message = win.MSG{};
        try std.testing.expect(archiveKey(&a, 'E', control, false, false, a.chats_hwnd, &message));
        try std.testing.expect(state.localArchived(key.key()));
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        a = fixture(&state);
        a.chats[0].provider = .slack;
        a.chats[0].account.set("fixture-team");
        a.chats[0].archived = true;
        a.show_archived = true;
        archiveSelected(&a, false);
        try std.testing.expect(!state.localArchived(key.key()));
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "Slack palette archive rejects a replacement account with the same channel id" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    a.chats[0].provider = .slack;
    a.chats[0].account.set("fixture-first");
    buildPaletteItems(&a);
    a.chats[0].account.set("fixture-second");
    activateArchivePalette(&a, .{ .command = command_archive });
    try std.testing.expectEqual(@as(usize, 0), state.count);
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "bulk Slack archive keeps account identities and never queues hub archive" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    for (a.chats[0..2], 0..) |*chat, index| {
        chat.provider = .slack;
        chat.account.set(if (index == 0) "fixture-first" else "fixture-second");
        chat.jid.set("channel-shared");
    }
    var first = chat_key.Stored{};
    first.set(chat_key.of(&a.chats[0]));
    var second = chat_key.Stored{};
    second.set(chat_key.of(&a.chats[1]));
    selectAllChats(&a);
    archiveSelected(&a, false);
    try std.testing.expect(state.localArchived(first.key()));
    try std.testing.expect(state.localArchived(second.key()));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expectEqual(@as(usize, 0), a.chat_count);
}

test "Slack local state coexists with WhatsApp keep and plain archive round trips" {
    var state = archive_rules.State{};
    const key = chat_key.Key{ .provider = .slack, .account = "fixture-team", .id = "shared-chat" };
    try std.testing.expect(state.archive(key.id, "baseline", true));
    try std.testing.expect(state.setLocalArchived(key, true));
    var buffer: [1024]u8 = undefined;
    var loaded = archive_rules.State{};
    loaded.parse(state.format(&buffer));
    try std.testing.expect(loaded.localArchived(key));
    try std.testing.expect(loaded.isKept(key.id));
    try std.testing.expect(loaded.setLocalArchived(key, false));
    try std.testing.expect(!loaded.localArchived(key));
    try std.testing.expect(loaded.isKept(key.id));
    try std.testing.expect(loaded.archive(key.id, "baseline", false));
}

test "sending to an archived Slack chat never queues unarchive or clears local state" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    const key = chat_key.Key{ .provider = .slack, .account = "fixture-team", .id = "fixture-channel" };
    try std.testing.expect(state.setLocalArchived(key, true));
    a.pending_sends[0].provider = .slack;
    a.pending_sends[0].jid.set(key.id);
    a.pending_send_count = 1;
    removeFirstPendingSend(&a, true);
    try std.testing.expect(state.localArchived(key));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

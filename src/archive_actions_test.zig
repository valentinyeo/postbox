const std = @import("std");
const verification_fixture = false;
const chat_key = @import("chat_key.zig");
const archive_rules = @import("archive_rules.zig");
const read_state = @import("read_state.zig");
const voice_sent = @import("voice_sent.zig");
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
    provider_archived: bool = false,
    unread: bool = false,
    unread_count: i64 = 0,
    pinned: bool = false,
    kind: struct {
        text: []const u16 = &.{},
        fn slice(self: *const @This()) []const u16 {
            return self.text;
        }
    } = .{},
};
const PendingArchive = struct {
    batch_count: usize = 0,
    jid: Utf8Text(191) = .{},
    should_unarchive: bool = false,
    source: ArchiveSource = .shortcut,
    retry_at_ms: u64 = 0,
};
const WacliResult = struct {
    gen: u64 = 0,
    data: []const u8 = "",
    extra: Utf8Text(47) = .{},
    msg_id: Utf8Text(191) = .{},
    kind: enum { hub_archive, hub_media } = .hub_archive,
    provider: Provider = .whatsapp,
    account: Utf8Text(32) = .{},
    jid: Utf8Text(191) = .{},
    ok: bool = false,
    http_status: u32 = 502,
};
const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    unified_hub: bool = false,
    cache_tag: Utf8Text(32) = .{},
    chats: [4]Chat = @splat(.{}),
    chat_count: usize = 2,
    selected_chat: usize = 0,
    displayed_provider: @TypeOf((Chat{}).provider) = .whatsapp,
    displayed_account: Utf8Text(32) = .{},
    displayed_jid: Utf8Text(191) = .{},
    show_archived: bool = false,
    include_archived: bool = false,
    unread_only: bool = false,
    chat_view: enum { all, whatsapp } = .whatsapp,
    bulk: std.ArrayList(Chat) = .empty,
    archive_state: ?*archive_rules.State,
    read_state: read_state.State = .{ .allow_opaque = true },
    startup_probe_pending: bool = false,
    pending_archives: []PendingArchive = &.{},
    pending_archive_count: usize = 0,
    archive_batch_total: usize = 0,
    chats_hwnd: ?usize = null,
    canvas: ?usize = null,
    compose: ?usize = null,
    thread_compose: ?usize = null,
    search: ?usize = null,
    emoji_edit: ?usize = null,
    palette_edit: ?usize = null,
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
    hub_archive_requests: usize = 0,
    hub_archive_batch_count: usize = 0,
    hub_archive_inflight: bool = false,
    refresh_key: chat_key.Stored = .{},
    refresh_stamp: Utf8Text(47) = .{},
    chats_refreshes: usize = 0,
    chats_gen: u32 = 0,
    chats_pending_flags: u8 = 0,
    chats_raw: ?[]const u8 = null,
    chats_raw_flags: u8 = 0,
    archive_toggle_started_ms: ?u64 = null,
    archive_toggle_fetches: u32 = 0,
    chats_request: WacliJob = .{},
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
var list_invalidations: usize = 0;
var compose_text_len: i32 = 0;
var text_selections: usize = 0;
const win = struct {
    const FALSE = 0;
    const EM_SETSEL = 0x00b1;
    fn GetWindowTextLengthW(_: usize) i32 {
        return compose_text_len;
    }
    fn SendMessageW(_: usize, _: u32, _: usize, _: isize) isize {
        text_selections += 1;
        return 0;
    }
    const HWND = usize;
    const LPARAM = isize;
    const MSG = struct { lParam: LPARAM = 0 };
    fn GetTickCount64() u64 {
        return 1000;
    }
    fn InvalidateRect(handle: usize, _: ?*anyopaque, _: i32) i32 {
        if (handle == 4) list_invalidations += 1;
        return 1;
    }
};
fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
fn fixture(state: *archive_rules.State) App {
    var a = App{ .archive_state = state, .chats_hwnd = 4, .canvas = 6, .hwnd = 5, .compose = 1 };
    a.pending_archives = std.testing.allocator.alloc(PendingArchive, 4) catch unreachable;
    @memset(a.pending_archives, .{});
    a.chats[0].jid.set("a@g.us");
    a.chats[1].jid.set("b@g.us");
    for (a.chats[0..2]) |*chat| chat.timestamp.set("2026-10-10T10:00:00Z");
    return a;
}
fn refixture(a: *App, state: *archive_rules.State) void {
    a.allocator.free(a.pending_archives);
    a.bulk.deinit(a.allocator);
    a.* = fixture(state);
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
fn startHubArchive(a: *App) void {
    if (a.bulk.items.len > 0 or a.pending_archive_count == 0 or a.hub_archive_inflight or a.read_child != null) return;
    a.persisted_before_start = a.persisted_before_start and a.saved_len > 0;
    a.hub_archive_inflight = true;
    a.hub_archive_requests += 1;
    a.hub_archive_batch_count = a.pending_archives[0].batch_count;
    a.spawned_jid = a.pending_archives[0].jid;
}
fn refreshChats(a: *App) void {
    a.chats_refreshes += 1;
    if (a.refresh_key.id_len > 0) _ = holdKeptArchived(a, a.refresh_key.key(), false, a.refresh_stamp.slice());
}
const WacliJob = struct {
    account: Utf8Text(32) = .{},
    kind: enum { chats } = .chats,
    started_ms: u64 = 0,
    args: [8]Utf8Text(191) = @splat(.{}),
    arg_count: usize = 0,
    gen: u32 = 0,
};
fn wacliJobArgs(job: *WacliJob, args: []const []const u8) void {
    for (args, 0..) |arg, index| job.args[index].set(arg);
    job.arg_count = args.len;
}
fn wacliPendingGet(_: *App, _: @FieldType(WacliJob, "kind")) usize {
    return 0;
}
fn wacliEnqueue(a: *App, job: WacliJob, _: bool) bool {
    a.chats_request = job;
    return true;
}
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
    if (comptime @hasDecl(@This(), "holdKeptArchived")) return @field(@This(), "holdKeptArchived")(a, archiveChatKey(a, jid), provider_archived, ts);
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
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    try std.testing.expect(state.archive("a@g.us", "2026-10-10T10:00:00Z", true));
    try std.testing.expect(state.archive("b@g.us", "2026-10-10T10:00:00Z", false));
    try std.testing.expect(!holdKept(&a, "a@g.us", true, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expect(holdKept(&a, "a@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expect(!a.pending_archives[0].should_unarchive);
    try std.testing.expectEqualStrings("a@g.us", a.spawned_jid.slice());
    try std.testing.expect(pendingArchiveHidesChat(&a, "a@g.us", false));
    try std.testing.expect(!pendingArchiveHidesChat(&a, "a@g.us", true));
    try std.testing.expect(state.isKept("a@g.us"));
    try std.testing.expectEqual(@as(usize, 1), a.chat_count);
    try std.testing.expectEqualStrings("b@g.us", a.chats[0].jid.slice());
    try std.testing.expect(!holdKept(&a, "a@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expect(!holdKept(&a, "b@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expect(!state.isKept("b@g.us"));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
}

test "a plain archive persists intent separately from the keep flag before saving" {
    for ([_]bool{ false, true }) |keep| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        var key = chat_key.Stored{};
        key.set(chat_key.of(&a.chats[0]));
        try std.testing.expect(state.archive(key.key().id, "baseline", keep));
        archiveSelected(&a, false);
        try std.testing.expect(state.find(key.key().id) != null);
        try std.testing.expect(!state.isKept(key.key().id));
        try std.testing.expect(state.baseline(key.key().id) != null);
        try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
        try std.testing.expect(!a.pending_archives[0].should_unarchive);
        try std.testing.expectEqual(@as(usize, 1), a.chat_count);
        var loaded = archive_rules.State{};
        loaded.parse(a.saved[0..a.saved_len]);
        try std.testing.expect(loaded.find(key.key().id) != null);
        try std.testing.expect(!loaded.isKept(key.key().id));
    }
}

test "a legacy non-kept entry alone sends no hub archive request" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.unified_hub = true;
    a.refresh_key.set(chat_key.of(&a.chats[0]));
    a.refresh_stamp.set("incoming");
    const key = a.refresh_key.key();
    try std.testing.expect(state.archive(key.id, "baseline", false));
    refreshChats(&a);
    a.refresh_stamp.set("newer");
    refreshChats(&a);
    try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expect(!a.hub_archive_inflight);
    try std.testing.expectEqual(@as(usize, 2), a.chat_count);
    try std.testing.expect(state.find(key.id) == null);
}

test "a kept entry alone still sends a hub archive request" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.unified_hub = true;
    a.refresh_key.set(chat_key.of(&a.chats[0]));
    a.refresh_stamp.set("incoming");
    const key = a.refresh_key.key();
    try std.testing.expect(state.archive(key.id, "baseline", true));
    refreshChats(&a);
    refreshChats(&a);
    try std.testing.expectEqual(@as(usize, 1), a.hub_archive_requests);
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expect(a.hub_archive_inflight);
    try std.testing.expect(!a.pending_archives[0].should_unarchive);
    try std.testing.expectEqual(ArchiveSource.kept, a.pending_archives[0].source);
    try std.testing.expectEqualStrings(key.id, a.spawned_jid.slice());
    try std.testing.expectEqual(@as(usize, 1), a.chat_count);
    try std.testing.expect(state.isKept(key.id));
}

test "a kept chat refused by a full archive queue is tried again for the same message" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
    defer before.allocator.free(before.pending_archives);
    defer before.bulk.deinit(before.allocator);
    archiveSelected(&before, true);
    var restarted = archive_rules.State{};
    restarted.parse(before.saved[0..before.saved_len]);
    var a = fixture(&restarted);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    try std.testing.expect(holdKept(&a, "a@g.us", false, "2026-10-10T11:00:00Z"));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expect(!a.pending_archives[0].should_unarchive);
    var again = archive_rules.State{};
    again.parse(a.saved[0..a.saved_len]);
    try std.testing.expect(again.isKept("a@g.us"));
    again.remove("a@g.us");
    var reloaded = archive_rules.State{};
    var buffer: [512]u8 = undefined;
    reloaded.parse(again.format(&buffer));
    var b = fixture(&reloaded);
    defer b.allocator.free(b.pending_archives);
    defer b.bulk.deinit(b.allocator);
    try std.testing.expect(!holdKept(&b, "a@g.us", false, "2026-10-10T12:00:00Z"));
    try std.testing.expectEqual(@as(usize, 0), b.pending_archive_count);
}

test "keep archives the selected chat and persists before the child starts" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    selectAllChats(&a);
    a.chats[2].jid.set("later@g.us");
    a.chat_count = 3;
    archiveSelected(&a, true);
    try std.testing.expectEqual(@as(usize, 2), a.pending_archive_count);
    try std.testing.expect(state.isKept("a@g.us"));
    try std.testing.expect(state.isKept("b@g.us"));
    try std.testing.expect(!state.isKept("later@g.us"));
    try std.testing.expectEqual(@as(usize, 0), a.bulk.items.len);
    try std.testing.expectEqualStrings("later@g.us", a.chats[0].jid.slice());
}

test "plain bulk archive leaves no kept state for either archived chat" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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

test "a kept archive baselines at the archive moment when the list row is stale" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    archiveSelected(&a, true);
    try std.testing.expectEqualStrings("2026-10-10T10:30:00Z", state.baseline("a@g.us").?);
}

test "a kept archive keeps a list row time that is later than the archive moment" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.chats[0].timestamp.set("2026-10-10T12:00:00Z");
    archiveSelected(&a, true);
    try std.testing.expectEqualStrings("2026-10-10T12:00:00Z", state.baseline("a@g.us").?);
}

test "unarchive clears keep while unavailable and full queues do not claim success" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.show_archived = true;
    state.setKeep("a@g.us", true);
    archiveSelected(&a, false);
    try std.testing.expect(a.pending_archives[0].should_unarchive);
    try std.testing.expect(!state.isKept("a@g.us"));

    refixture(&a, &state);
    a.pending_archive_count = a.pending_archives.len;
    archiveSelected(&a, true);
    try std.testing.expectEqualStrings("Archive queue is full", a.status.slice());
    try std.testing.expect(!state.isKept("a@g.us"));
    refixture(&a, &state);
    a.archive_state = null;
    archiveSelected(&a, true);
    try std.testing.expectEqualStrings("Keep archived is not available", a.status.slice());
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "keep rejects other providers without queuing a WhatsApp write" {
    var state = archive_rules.State{};
    for ([_]Provider{ .telegram, .signal }) |provider| {
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.chats[0].provider = provider;
        archiveSelected(&a, true);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        try std.testing.expect(!state.isKept("a@g.us"));
    }
}

test "keep overrides an earlier archive followed by an unarchive" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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

test "Ctrl+Shift+E keeps the chat archived" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    const message = win.MSG{};
    try std.testing.expect(archiveKey(&a, 'E', true, false, true, a.compose, &message));
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expect(state.isKept("a@g.us"));
    try std.testing.expectEqualStrings(archive_rules.Action.keep.status(), a.status.slice());
}

test "Ctrl+E archives from the compose box and Ctrl+Alt+E is unbound" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    const message = win.MSG{};
    try std.testing.expect(!archiveKey(&a, 'E', true, true, false, a.compose, &message));
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
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        const message = win.MSG{};
        try std.testing.expect(!archiveKey(&a, 'E', false, false, false, a.compose, &message));
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        try std.testing.expectEqual(@as(usize, 0), a.log_count);
    }
    for ([_]usize{ 2, 3 }) |focus| {
        for ([_]bool{ false, true }) |keep| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            defer a.allocator.free(a.pending_archives);
            defer a.bulk.deinit(a.allocator);
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
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
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
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        const message = win.MSG{};
        _ = archiveKey(&a, 'E', false, alt, !alt, 4, &message);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "archive shortcut refuses a row that disagrees with the displayed chat" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.displayed_jid.set("gone@g.us");
    archiveSelected(&a, false);
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "palette archive refuses a changed chat instead of archiving the replacement row" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        selectAllChats(&a);
        buildPaletteItems(&a);
        if (view_changed) a.show_archived = true else a.bulk.clearRetainingCapacity();
        activateArchivePalette(&a, .{ .command = command_archive });
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "palette archive follows the same jid through a list reorder" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
            defer a.allocator.free(a.pending_archives);
            defer a.bulk.deinit(a.allocator);
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
        }
    }
}

test "failed local sends and successful inbox sends do not unarchive" {
    for ([_]bool{ false, true }) |delivered| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
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
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    try std.testing.expect(state.archive("sent@g.us", "baseline", false));
    a.pending_sends[0].jid.set("sent@g.us");
    a.pending_send_count = 1;
    removeFirstPendingSend(&a, true);
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expectEqualStrings("sent@g.us", a.pending_archives[0].jid.slice());
    try std.testing.expect(a.pending_archives[0].should_unarchive);
}

test "hub archive dispatch uses the queued jid direction and source once" {
    for ([_]archive_rules.Action{ .archive, .unarchive }) |action| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.read_child = 1;
        try std.testing.expect(archiveRequest(&a, "a@g.us", action) == null);
        a.chats[0].jid.set("replacement@g.us");
        try std.testing.expectEqual(@as(usize, 0), a.log_count);
        a.read_child = null;
        startNextArchive(&a);
        startNextArchive(&a);
        try std.testing.expectEqual(@as(usize, 1), a.hub_archive_requests);
        try std.testing.expectEqual(action == .unarchive, a.pending_archives[0].should_unarchive);
        try std.testing.expectEqual(ArchiveSource.control, a.pending_archives[0].source);
        try std.testing.expectEqualStrings("a@g.us", a.spawned_jid.slice());
    }
}

test "archive shortcuts ignore unrelated windows and buttons" {
    for ([_]?usize{ null, 7, 8 }) |focus| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        const message = win.MSG{};
        _ = archiveKey(&a, 'E', true, false, false, focus, &message);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "palette cannot turn unarchive into archive after a remote unarchive" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.chats[0].archived = true;
    buildPaletteItems(&a);
    a.chats[0].archived = false;
    activateArchivePalette(&a, .{ .command = command_archive });
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "oversized archive ids cannot truncate into a different chat" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    var jid: [archive_rules.max_jid + 1]u8 = @splat('a');
    jid[archive_rules.max_jid - 2] = '@';
    try std.testing.expect(archiveRequest(&a, &jid, .archive) != null);
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "local send deferred unarchive retains send source past a full queue" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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

test "shortcut and select all archive are ordinary and return on newer messages on every provider" {
    for ([_]Provider{ .whatsapp, .slack, .telegram, .signal }) |provider| {
        for ([_]bool{ false, true }) |bulk| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            defer a.allocator.free(a.pending_archives);
            defer a.bulk.deinit(a.allocator);
            a.unified_hub = true;
            a.include_archived = true;
            for (a.chats[0..a.chat_count]) |*chat| {
                chat.provider = provider;
                chat.account.set("fixture-account");
            }
            const rows = a.chats;
            if (bulk) selectAllChats(&a);
            const message = win.MSG{};
            try std.testing.expect(archiveKey(&a, 'E', true, false, false, a.compose, &message));
            const action: archive_rules.Action = if (state.entries[0].keep) .keep else .archive;
            try std.testing.expectEqual(archive_rules.Action.archive, action);
            try std.testing.expectEqualStrings("Archived", action.status());
            try std.testing.expectEqualStrings(if (bulk and provider == .whatsapp) "Archiving 1 of 2" else action.status(), a.status.slice());
            try std.testing.expectEqual(@as(usize, if (bulk) 2 else 1), state.count);
            for (state.entries[0..state.count]) |*entry| try std.testing.expect(!entry.keep);
            var loaded = archive_rules.State{};
            loaded.parse(a.saved[0..a.saved_len]);
            a.archive_state = &loaded;
            a.pending_archive_count = 0;
            a.archive_child = null;
            a.hub_archive_inflight = false;
            for (rows[0..if (bulk) @as(usize, 2) else 1], 0..) |*row, index| {
                const key = chat_key.of(row);
                try std.testing.expect(loaded.localArchived(key));
                try std.testing.expectEqualSlices(u16, std.mem.span(lit("Archived")), std.mem.span(archiveMarker(&a, &a.chats[index]).?));
                try std.testing.expect(!holdKeptArchived(&a, key, false, "2026-10-10T10:30:00Z"));
                try std.testing.expect(loaded.localArchived(key));
                try std.testing.expect(!holdKeptArchived(&a, key, false, "2026-10-10T11:00:00Z"));
                try std.testing.expect(!loaded.localArchived(key));
                var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"archived\":false}", .{});
                defer parsed.deinit();
                inline for (.{ archiveInboxRow, archiveControlRow }) |filter| {
                    const incoming = filter(&a, row.*, parsed.value.object) orelse return error.OrdinaryArchiveDidNotReturn;
                    try std.testing.expect(!incoming.archived);
                }
            }
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            var restarted = archive_rules.State{};
            restarted.parse(a.saved[0..a.saved_len]);
            for (rows[0..if (bulk) @as(usize, 2) else 1]) |*row| try std.testing.expect(!restarted.localArchived(chat_key.of(row)));
        }
    }
}

test "explicit keep alone persists kept status and label on every provider" {
    for ([_]Provider{ .whatsapp, .slack, .telegram, .signal }) |provider| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.unified_hub = true;
        a.include_archived = true;
        a.chats[0].provider = provider;
        a.chats[0].account.set("fixture-account");
        const key = chat_key.of(&a.chats[0]);
        archiveSelected(&a, true);
        try std.testing.expectEqualStrings("Kept archived. Won't come back", a.status.slice());
        try std.testing.expectEqualSlices(u16, std.mem.span(lit("Kept archived")), std.mem.span(archiveMarker(&a, &a.chats[0]).?));
        var loaded = archive_rules.State{};
        loaded.parse(a.saved[0..a.saved_len]);
        try std.testing.expect(if (provider == .whatsapp) loaded.isKept(key.id) else loaded.localKept(key));
        a.archive_state = &loaded;
        _ = holdKeptArchived(&a, key, false, "2026-10-10T11:00:00Z");
        try std.testing.expect(loaded.localArchived(key));
        try std.testing.expect(if (provider == .whatsapp) loaded.isKept(key.id) else loaded.localKept(key));
    }
}

test "stored Slack keep unarchives across restart then shortcut archives without keep" {
    for ([_][]const u8{ "slack\tfixture-team\tchannel-shared\n", "slack\tfixture-team\tchannel-shared\t1\n" }) |stored| {
        var state = archive_rules.State{};
        state.parse(stored);
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.include_archived = true;
        a.chats[0].provider = .slack;
        a.chats[0].account.set("fixture-team");
        a.chats[0].jid.set("channel-shared");
        a.chats[0].archived = true;
        a.chats[0].provider_archived = true;
        const key = chat_key.of(&a.chats[0]);
        try std.testing.expect(state.localKept(key));
        archiveSelected(&a, false);
        try std.testing.expectEqualStrings("Chat unarchived", a.status.slice());
        try std.testing.expect(!state.localKept(key));
        var loaded = archive_rules.State{};
        loaded.parse(a.saved[0..a.saved_len]);
        a.archive_state = &loaded;
        for ([_][]const u8{ "2026-10-10T10:00:00Z", "2026-10-10T10:30:00Z" }) |stamp| {
            try std.testing.expect(!holdKeptArchived(&a, key, true, stamp));
            try std.testing.expect(!loaded.isArchived(key, true));
        }
        archiveSelected(&a, false);
        try std.testing.expectEqualStrings("Archived", a.status.slice());
        try std.testing.expect(loaded.localArchived(key));
        try std.testing.expect(!loaded.localKept(key));
        try std.testing.expectEqual(archive_rules.ArchiveState.archived, chatArchiveState(&a, &a.chats[0]));
        state.parse(a.saved[0..a.saved_len]);
        try std.testing.expect(state.localArchived(key));
        try std.testing.expect(!state.localKept(key));
        try std.testing.expect(!holdKeptArchived(&a, key, false, "2026-10-10T11:00:00Z"));
        try std.testing.expect(!loaded.localArchived(key));
        try std.testing.expect(!loaded.isArchived(key, false));
        try std.testing.expect(loaded.isArchived(key, true));
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "Slack archive persists per Key without ever queuing either archive transport" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
    try std.testing.expectEqualStrings("Archived", a.status.slice());
    try std.testing.expect(!state.localKept(key.key()));
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
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.chats[0].provider = .slack;
        a.chats[0].account.set("fixture-team");
        var key = chat_key.Stored{};
        key.set(chat_key.of(&a.chats[0]));
        const message = win.MSG{};
        try std.testing.expect(archiveKey(&a, 'E', control, false, false, a.chats_hwnd, &message));
        try std.testing.expect(state.localArchived(key.key()));
        try std.testing.expect(!state.localKept(key.key()));
        try std.testing.expectEqualStrings(archive_rules.Action.archive.status(), a.status.slice());
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        refixture(&a, &state);
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
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
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
    try std.testing.expect(!state.localKept(first.key()));
    try std.testing.expect(!state.localKept(second.key()));
    try std.testing.expectEqualStrings("Archived", a.status.slice());
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expectEqual(@as(usize, 0), a.chat_count);
}

test "Slack local state coexists with WhatsApp keep and plain archive round trips" {
    var state = archive_rules.State{};
    const key = chat_key.Key{ .provider = .slack, .account = "fixture-team", .id = "shared-chat" };
    try std.testing.expect(state.archive(key.id, "baseline", true));
    try std.testing.expect(state.setLocalArchived(key, true, "baseline", false));
    var buffer: [1024]u8 = undefined;
    var loaded = archive_rules.State{};
    loaded.parse(state.format(&buffer));
    try std.testing.expect(loaded.localArchived(key));
    try std.testing.expect(loaded.isKept(key.id));
    try std.testing.expect(loaded.setLocalArchived(key, false, "baseline", false));
    try std.testing.expect(!loaded.localArchived(key));
    try std.testing.expect(loaded.isKept(key.id));
    try std.testing.expect(loaded.archive(key.id, "baseline", false));
}

test "sending to an archived Slack chat never queues unarchive or clears local state" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    const key = chat_key.Key{ .provider = .slack, .account = "fixture-team", .id = "fixture-channel" };
    try std.testing.expect(state.setLocalArchived(key, true, "baseline", false));
    a.pending_sends[0].provider = .slack;
    a.pending_sends[0].jid.set(key.id);
    a.pending_send_count = 1;
    removeFirstPendingSend(&a, true);
    try std.testing.expect(state.localArchived(key));
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "hub Ctrl E locally archives the last Telegram or Signal row from every allowed focus" {
    for ([_]Provider{ .telegram, .signal }) |provider| {
        for ([_]?usize{ 1, 4, 5, 6 }) |focus| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            defer a.allocator.free(a.pending_archives);
            defer a.bulk.deinit(a.allocator);
            a.unified_hub = true;
            a.cache_tag.set("hub-cache");
            a.chat_count = 1;
            a.chats[0].provider = provider;
            a.chats[0].account.set(if (provider == .telegram) "telegram" else "signal");
            a.chats[0].jid.set(if (provider == .telegram) "telegram:user:7001" else "signal:fixture");
            a.displayed_provider = provider;
            a.displayed_account = a.chats[0].account;
            a.displayed_jid = a.chats[0].jid;
            var key = chat_key.Stored{};
            key.set(chat_key.of(&a.chats[0]));
            const message = win.MSG{};
            try std.testing.expect(archiveKey(&a, 'E', true, false, false, focus, &message));
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
            try std.testing.expectEqual(@as(usize, 0), a.chat_count);
            try std.testing.expect(state.localArchived(key.key()));
            var loaded = archive_rules.State{};
            loaded.parse(a.saved[0..a.saved_len]);
            try std.testing.expect(loaded.localArchived(key.key()));
            a.archive_state = &loaded;
            for ([_][]const u8{ "incoming", "newer" }) |stamp| {
                try std.testing.expect(!holdKeptArchived(&a, key.key(), false, stamp));
                try std.testing.expect(!loaded.localArchived(key.key()));
                try std.testing.expect(!loaded.isArchived(key.key(), false));
                try std.testing.expect(!loaded.localKept(key.key()));
                try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
            }
            try std.testing.expect(archiveChat(&a, key.key(), .unarchive, .shortcut) == null);
            try std.testing.expect(!loaded.localArchived(key.key()));
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
        }
    }
}

test "hub Ctrl E archives a one-row bulk selection outside the WhatsApp cache account" {
    for ([_]Provider{ .telegram, .signal, .whatsapp }) |provider| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.unified_hub = true;
        a.cache_tag.set("hub-cache");
        a.chat_count = 1;
        a.chats[0].provider = provider;
        a.chats[0].account.set("fixture-account");
        a.chats[0].jid.set(if (provider == .telegram) "telegram:user:7001" else if (provider == .signal) "signal:fixture" else "personal:fixture@s.whatsapp.net");
        var key = chat_key.Stored{};
        key.set(chat_key.of(&a.chats[0]));
        selectAllChats(&a);
        const message = win.MSG{};
        try std.testing.expect(archiveKey(&a, 'E', true, false, false, a.compose, &message));
        try std.testing.expectEqual(@as(usize, if (provider == .whatsapp) 1 else 0), a.pending_archive_count);
        try std.testing.expectEqual(@as(usize, if (provider == .whatsapp) 1 else 0), a.hub_archive_requests);
        if (provider == .whatsapp) try std.testing.expectEqualStrings(key.key().id, a.pending_archives[0].jid.slice());
        try std.testing.expectEqual(@as(usize, 0), a.chat_count);
        try std.testing.expectEqual(@as(usize, 0), a.bulk.items.len);
        try std.testing.expect(state.localArchived(key.key()));
        if (provider == .whatsapp) try std.testing.expect(state.baseline(key.key().id) != null);
    }
}

test "only kept hub archives hold the real provider account and remove the matching row only" {
    for ([_]Provider{ .telegram, .signal, .whatsapp }) |provider| {
        for ([_]bool{ false, true }) |keep| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            defer a.allocator.free(a.pending_archives);
            defer a.bulk.deinit(a.allocator);
            a.unified_hub = true;
            a.cache_tag.set("hub-cache");
            a.chats[0].provider = provider;
            a.chats[0].account.set("fixture-account");
            a.chats[0].jid.set(if (provider == .telegram) "telegram:user:7001" else if (provider == .signal) "signal:fixture" else "personal:fixture@s.whatsapp.net");
            var key = chat_key.Stored{};
            key.set(chat_key.of(&a.chats[0]));
            if (provider != .whatsapp) {
                try std.testing.expect(state.setLocalArchived(key.key(), true, "baseline", keep));
                try std.testing.expect(!holdKeptArchived(&a, key.key(), false, "incoming"));
                try std.testing.expectEqual(@as(usize, 2), a.chat_count);
                try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
                try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
                try std.testing.expectEqual(keep, state.localArchived(key.key()));
                try std.testing.expectEqual(keep, state.localKept(key.key()));
                try std.testing.expect(archiveChat(&a, key.key(), .unarchive, .shortcut) == null);
                try std.testing.expect(!state.localArchived(key.key()));
                continue;
            }
            try std.testing.expect(state.archive(key.key().id, "baseline", keep));
            if (!keep) {
                try std.testing.expect(!holdKeptArchived(&a, key.key(), false, "incoming"));
                try std.testing.expect(!holdKeptArchived(&a, key.key(), false, "newer"));
                try std.testing.expectEqual(@as(usize, 2), a.chat_count);
                try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
                try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
                continue;
            }
            try std.testing.expect(holdKeptArchived(&a, key.key(), false, "incoming"));
            try std.testing.expectEqual(@as(usize, 1), a.chat_count);
            try std.testing.expectEqualStrings("b@g.us", a.chats[0].jid.slice());
            try std.testing.expectEqual(keep, state.isKept(key.key().id));
            try std.testing.expect(!holdKeptArchived(&a, key.key(), false, "incoming"));
            try std.testing.expect(holdKeptArchived(&a, key.key(), false, "newer"));
            try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
            try std.testing.expect(archiveChat(&a, key.key(), .unarchive, .shortcut) == null);
            try std.testing.expect(!state.localArchived(key.key()));
            try std.testing.expect(!holdKeptArchived(&a, key.key(), false, "newest"));
        }
    }
}

test "hub sends preserve local Telegram and Signal archives and an out of range row never archives" {
    for ([_]Provider{ .telegram, .signal }) |provider| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.unified_hub = true;
        a.chat_count = 1;
        a.selected_chat = 1;
        archiveSelected(&a, false);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        const key = chat_key.Key{ .provider = provider, .account = "fixture-account", .id = if (provider == .telegram) "telegram:user:7001" else "signal:fixture" };
        try std.testing.expect(state.setLocalArchived(key, true, "baseline", false));
        a.pending_sends[0].provider = provider;
        a.pending_sends[0].jid.set(key.id);
        a.pending_send_count = 1;
        removeFirstPendingSend(&a, true);
        try std.testing.expect(state.localArchived(key));
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
    }
}

test "a late unsupported hub archive preserves legacy local intent without retrying" {
    for ([_]Provider{ .signal, .telegram }) |provider| {
        for ([_]bool{ false, true }) |keep| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            defer a.allocator.free(a.pending_archives);
            defer a.bulk.deinit(a.allocator);
            a.unified_hub = true;
            a.cache_tag.set("hub-cache");
            a.chats[0].provider = provider;
            a.chats[0].account.set(if (provider == .signal) "signal" else "telegram");
            a.chats[0].jid.set(if (provider == .signal) "signal:fixture-contact" else "telegram:user:1001");
            a.refresh_key.set(chat_key.of(&a.chats[0]));
            a.refresh_stamp.set("2026-10-10T11:00:00Z");
            const key = a.refresh_key.key();
            var text: [256]u8 = undefined;
            state.parse(try std.fmt.bufPrint(&text, "{s}\t{d}\tbaseline\n", .{ key.id, @intFromBool(keep) }));
            saveArchiveState(&a);
            a.pending_archives[0].jid.set(key.id);
            a.pending_archive_count = 1;
            var result = WacliResult{ .account = a.cache_tag };
            result.jid.set(key.id);
            applyHubArchiveResult(&a, &result);
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            try std.testing.expect(state.localArchived(key));
            var loaded = archive_rules.State{};
            loaded.parse(a.saved[0..a.saved_len]);
            try std.testing.expect(loaded.localArchived(key));
            a.refresh_stamp.set("2026-10-10T12:00:00Z");
            refreshChats(&a);
            startNextArchive(&a);
            try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            try std.testing.expectEqualStrings("Chat archive is managed locally in Wazig", a.status.slice());
            result.jid.set("unrelated:fixture");
            applyHubArchiveResult(&a, &result);
            try std.testing.expect(state.localArchived(key));
        }
    }
}

test "non hub Telegram and Signal archiving remains unavailable" {
    for ([_]Provider{ .signal, .telegram }) |provider| {
        for ([_]bool{ false, true }) |bulk| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            defer a.allocator.free(a.pending_archives);
            defer a.bulk.deinit(a.allocator);
            a.chat_count = 1;
            a.chats[0].provider = provider;
            a.chats[0].jid.set(if (provider == .signal) "signal:fixture-contact" else "telegram:user:1001");
            if (bulk) selectAllChats(&a);
            archiveSelected(&a, false);
            try std.testing.expectEqualStrings(if (bulk) "Archiving is only available for the active WhatsApp account" else if (provider == .signal) "Archiving is not available for Signal chats yet" else "Archiving is not available for Telegram chats yet", a.status.slice());
            try std.testing.expectEqual(@as(usize, 0), state.count);
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            try std.testing.expectEqual(@as(usize, 1), a.chat_count);
        }
    }
}

test "plain hub archives return while kept archives stay sticky and transient failures retain intent" {
    for ([_]bool{ false, true }) |keep| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.unified_hub = true;
        a.cache_tag.set("hub-cache");
        a.chats[0].provider = .whatsapp;
        a.chats[0].account.set("fixture-account");
        a.chats[0].jid.set("personal:fixture@s.whatsapp.net");
        a.refresh_key.set(chat_key.of(&a.chats[0]));
        a.refresh_stamp.set("2026-10-10T11:00:00Z");
        const key = a.refresh_key.key();
        try std.testing.expect(state.archive(key.id, "2026-10-10T10:00:00Z", keep));
        refreshChats(&a);
        if (!keep) {
            refreshChats(&a);
            a.refresh_stamp.set("2026-10-10T12:00:00Z");
            refreshChats(&a);
            try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            try std.testing.expectEqual(@as(usize, 2), a.chat_count);
            try std.testing.expect(!state.isKept(key.id));
            try std.testing.expect(state.baseline(key.id) == null);
            continue;
        }
        try std.testing.expectEqual(@as(usize, 1), a.hub_archive_requests);
        var result = WacliResult{ .account = a.cache_tag, .jid = a.spawned_jid, .ok = true, .http_status = 200 };
        a.hub_archive_inflight = false;
        applyHubArchiveResult(&a, &result);
        refreshChats(&a);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        try std.testing.expectEqual(@as(usize, 1), a.hub_archive_requests);
        try std.testing.expect(state.localArchived(key));
        try std.testing.expectEqual(keep, state.isKept(key.id));
        a.refresh_stamp.set("2026-10-10T12:00:00Z");
        refreshChats(&a);
        refreshChats(&a);
        try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
        try std.testing.expectEqual(@as(usize, 2), a.hub_archive_requests);
        result.ok = false;
        result.http_status = 503;
        a.hub_archive_inflight = false;
        applyHubArchiveResult(&a, &result);
        try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
        try std.testing.expect(a.pending_archives[0].retry_at_ms > win.GetTickCount64());
        try std.testing.expect(state.localArchived(key));
        try std.testing.expectEqual(keep, state.isKept(key.id));
        var loaded = archive_rules.State{};
        loaded.parse(a.saved[0..a.saved_len]);
        try std.testing.expect(loaded.localArchived(key));
        try std.testing.expectEqualStrings(state.baseline(key.id).?, loaded.baseline(key.id).?);
        try std.testing.expectEqual(keep, loaded.isKept(key.id));
    }
}

test "bulk hub Telegram and Signal archives persist every row without a hub request" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.unified_hub = true;
    a.cache_tag.set("hub-cache");
    a.chats[0].provider = .telegram;
    a.chats[0].account.set("telegram");
    a.chats[0].jid.set("telegram:user:7001");
    a.chats[1].provider = .signal;
    a.chats[1].account.set("signal");
    a.chats[1].jid.set("signal:fixture");
    var keys: [2]chat_key.Stored = @splat(.{});
    for (&keys, a.chats[0..2]) |*key, *chat| key.set(chat_key.of(chat));
    selectAllChats(&a);
    const message = win.MSG{};
    try std.testing.expect(archiveKey(&a, 'E', true, false, false, a.compose, &message));
    try std.testing.expectEqual(@as(usize, 0), a.chat_count);
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
    var loaded = archive_rules.State{};
    loaded.parse(a.saved[0..a.saved_len]);
    for (&keys) |*key| try std.testing.expect(loaded.localArchived(key.key()));
    a.archive_state = &loaded;
    for (&keys) |*key| {
        try std.testing.expect(!holdKeptArchived(&a, key.key(), false, "incoming"));
        try std.testing.expect(archiveChat(&a, key.key(), .unarchive, .shortcut) == null);
        try std.testing.expect(!loaded.localArchived(key.key()));
    }
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    try std.testing.expectEqual(@as(usize, 0), a.hub_archive_requests);
}

test "inbox and control filters treat plain WhatsApp archive entries as archived" {
    var state = archive_rules.State{};
    state.parse("fixture:live@g.us\t0\tbaseline\nfixture:kept@g.us\t1\tbaseline\n");
    var buffer: [512]u8 = undefined;
    var loaded = archive_rules.State{};
    loaded.parse(state.format(&buffer));
    const rows = [_]struct { id: []const u8, provider_archived: bool, archived: bool }{
        .{ .id = "fixture:live@g.us", .provider_archived = true, .archived = true },
        .{ .id = "fixture:kept@g.us", .provider_archived = false, .archived = true },
        .{ .id = "fixture:phone@g.us", .provider_archived = true, .archived = true },
        .{ .id = "fixture:inbox@g.us", .provider_archived = false, .archived = false },
    };
    inline for (.{ archiveInboxRow, archiveControlRow }) |filter| {
        var a = fixture(&loaded);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.unified_hub = true;
        requestChats(&a);
        try std.testing.expect(!a.show_archived and !a.include_archived);
        try std.testing.expectEqualStrings("--include-archived", a.chats_request.args[a.chats_request.arg_count - 1].slice());
        var visible: usize = 0;
        for (rows) |row| {
            var chat = Chat{};
            chat.account.set("fixture-account");
            chat.jid.set(row.id);
            var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, if (row.provider_archived) "{\"archived\":true}" else "{\"archived\":false}", .{});
            defer parsed.deinit();
            const shown = filter(&a, chat, parsed.value.object);
            try std.testing.expectEqual(!row.archived, shown != null);
            if (shown) |current| {
                try std.testing.expect(!current.archived);
                if (visible == 0) try std.testing.expectEqualStrings("fixture:inbox@g.us", current.jid.slice());
                visible += 1;
            }
            a.show_archived = true;
            const archived = filter(&a, chat, parsed.value.object);
            try std.testing.expectEqual(row.archived, archived != null);
            a.show_archived = false;
        }
        try std.testing.expectEqual(@as(usize, 1), visible);
    }
}

test "hub Telegram and Signal archives honor both phone and local state in both chat filters" {
    inline for (.{ archiveInboxRow, archiveControlRow }) |filter| {
        for ([_]Provider{ .telegram, .signal }) |provider| {
            for ([_]bool{ false, true }) |local| {
                var state = archive_rules.State{};
                var a = fixture(&state);
                defer a.allocator.free(a.pending_archives);
                defer a.bulk.deinit(a.allocator);
                a.unified_hub = true;
                var chat = Chat{ .provider = provider };
                chat.account.set(if (provider == .telegram) "telegram" else "signal");
                chat.jid.set(if (provider == .telegram) "telegram:user:7001" else "signal:fixture");
                if (local) try std.testing.expect(state.setLocalArchived(chat_key.of(&chat), true, "baseline", false));
                try std.testing.expectEqual(@as(usize, if (local) 1 else 0), state.count);
                const raw = if (local) "{\"archived\":false}" else "{\"archived\":true}";
                var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
                defer parsed.deinit();
                try std.testing.expect(filter(&a, chat, parsed.value.object) == null);
                a.show_archived = true;
                const archived = filter(&a, chat, parsed.value.object) orelse return error.MissingArchivedChat;
                try std.testing.expect(archived.archived);
                try std.testing.expect(chat_key.Key.eql(chat_key.of(&chat), chat_key.of(&archived)));
            }
        }
    }
}

fn activeChatView(a: *App) @TypeOf(a.chat_view) {
    return a.chat_view;
}

test "mixed archive and unarchive keep the row selected and visibly marked on every provider" {
    for ([_]Provider{ .whatsapp, .telegram, .signal, .slack }) |provider| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.unified_hub = true;
        a.include_archived = true;
        a.chats[0].provider = provider;
        a.chats[0].account.set("fixture-account");
        a.chats[0].jid.set(if (provider == .whatsapp) "personal:fixture@s.whatsapp.net" else "fixture:local");
        var key = chat_key.Stored{};
        key.set(chat_key.of(&a.chats[0]));
        try std.testing.expect(archiveChat(&a, key.key(), .archive, .shortcut) == null);
        try std.testing.expectEqual(@as(usize, 2), a.chat_count);
        try std.testing.expect(a.chats[0].archived);
        try std.testing.expect(!pendingArchiveHidesChat(&a, key.key().id, false));
        try std.testing.expect(archiveChat(&a, key.key(), .unarchive, .shortcut) == null);
        try std.testing.expectEqual(@as(usize, 2), a.chat_count);
        try std.testing.expect(!a.chats[0].archived);
        try std.testing.expectEqual(@as(usize, 0), a.selected_chat);
        if (provider != .whatsapp) try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
    }
}

test "mixed locally unarchived phone rows remain unarchived after reloading state" {
    for ([_]Provider{ .telegram, .signal, .slack }) |provider| {
        var state = archive_rules.State{};
        var a = fixture(&state);
        defer a.allocator.free(a.pending_archives);
        defer a.bulk.deinit(a.allocator);
        a.unified_hub = true;
        a.include_archived = true;
        a.chats[0].provider = provider;
        a.chats[0].account.set("fixture-account");
        a.chats[0].jid.set("fixture:phone-archived");
        a.chats[0].archived = true;
        a.chats[0].provider_archived = true;
        var key = chat_key.Stored{};
        key.set(chat_key.of(&a.chats[0]));
        try std.testing.expect(archiveChat(&a, key.key(), .unarchive, .shortcut) == null);
        try std.testing.expectEqual(@as(usize, 2), a.chat_count);
        try std.testing.expect(!a.chats[0].archived);
        try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
        var loaded = archive_rules.State{};
        loaded.parse(a.saved[0..a.saved_len]);
        try std.testing.expect(!loaded.isArchived(key.key(), true));
    }
}

test "archive row labels survive contact kind pin unread and Show archived toggles on every provider" {
    for ([_]Provider{ .whatsapp, .telegram, .slack, .signal }) |provider| {
        for ([_]archive_rules.ArchiveState{ .incoming, .archived, .kept_archived }) |expected| {
            for ([_]bool{ false, true }) |pinned| {
                for ([_]bool{ false, true }) |unread| {
                    var state = archive_rules.State{};
                    var a = fixture(&state);
                    defer a.allocator.free(a.pending_archives);
                    defer a.bulk.deinit(a.allocator);
                    a.unified_hub = true;
                    var chat = Chat{ .provider = provider, .archived = expected != .incoming, .pinned = pinned, .unread = unread };
                    chat.jid.set("fixture:row");
                    chat.account.set("fixture-account");
                    chat.kind.text = std.mem.span(lit("Contact"));
                    const kept = expected == .kept_archived;
                    if (kept) {
                        if (provider == .whatsapp) {
                            try std.testing.expect(state.archive(chat.jid.slice(), "baseline", true));
                        } else {
                            try std.testing.expect(state.setLocalArchived(chat_key.of(&chat), true, "baseline", true));
                        }
                    }
                    const row_state = chatArchiveState(&a, &chat);
                    try std.testing.expectEqual(archive_rules.archiveState(chat.archived, kept), row_state);
                    if (expected != .incoming) {
                        const label = archiveMarker(&a, &chat) orelse return error.MissingArchiveLabel;
                        try std.testing.expectEqualSlices(u16, std.mem.span(if (kept) lit("Kept archived") else lit("Archived")), std.mem.span(label));
                    } else if (provider != .whatsapp) {
                        try std.testing.expect(archiveMarker(&a, &chat) == null);
                    } else {
                        try std.testing.expectEqualSlices(u16, std.mem.span(lit("Contact")), std.mem.span(archiveMarker(&a, &chat).?));
                    }
                    const original_label = archiveMarker(&a, &chat);
                    for ([_]bool{ false, true }) |include_archived| {
                        a.include_archived = include_archived;
                        try std.testing.expectEqual(expected == .incoming or include_archived, messenger_view.archiveMatches(false, a.include_archived, false, false, chatArchiveState(&a, &chat), unread));
                        try std.testing.expectEqual(expected != .incoming, messenger_view.archiveMatches(true, a.include_archived, false, false, chatArchiveState(&a, &chat), unread));
                        for ([_]bool{ false, true }) |archived_only| {
                            a.show_archived = archived_only;
                            try std.testing.expectEqualSlices(u16, std.mem.span(original_label orelse lit("")), std.mem.span(archiveMarker(&a, &chat) orelse lit("")));
                        }
                    }
                }
            }
        }
    }
}

test "hub rows without archive metadata preserve saved intent in sidebar and control after restart" {
    inline for (.{ archiveInboxRow, archiveControlRow }) |filter| {
        for ([_]Provider{ .whatsapp, .slack, .telegram, .signal }) |provider| {
            for ([_]bool{ false, true }) |keep| {
                var state = archive_rules.State{};
                var a = fixture(&state);
                defer a.allocator.free(a.pending_archives);
                defer a.bulk.deinit(a.allocator);
                a.unified_hub = true;
                a.chats[0].provider = provider;
                a.chats[0].account.set("fixture-account");
                a.chats[0].jid.set("fixture:archived@g.us");
                const row = a.chats[0];
                try std.testing.expect(archiveChat(&a, chat_key.of(&row), if (keep) .keep else .archive, .shortcut) == null);
                var loaded = archive_rules.State{};
                loaded.parse(a.saved[0..a.saved_len]);
                a.archive_state = &loaded;
                a.pending_archive_count = 0;
                for ([_][]const u8{ "{}", "{\"archived\":false}", "{\"archived\":true}" }) |raw| {
                    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
                    defer parsed.deinit();
                    a.show_archived = false;
                    a.include_archived = false;
                    try std.testing.expect(filter(&a, row, parsed.value.object) == null);
                    a.show_archived = true;
                    const archived = filter(&a, row, parsed.value.object) orelse return error.ArchiveIntentLost;
                    try std.testing.expect(archived.archived);
                    try std.testing.expect(archiveMarker(&a, &archived) != null);
                    try std.testing.expect(loaded.localArchived(chat_key.of(&row)));
                    var bytes: [4096]u8 = undefined;
                    try std.testing.expectEqualStrings(a.saved[0..a.saved_len], loaded.format(&bytes));
                }
            }
        }
    }
}

test "ten select all presses rebuild the current snapshot and invalidate the list each time" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    for (0..10) |press| {
        a.chat_count = if (press % 2 == 0) 2 else 1;
        const before = list_invalidations;
        selectAllChats(&a);
        try std.testing.expectEqual(a.chat_count, a.bulk.items.len);
        try std.testing.expect(list_invalidations > before);
        for (a.bulk.items, 0..) |*chat, index| try std.testing.expect(chat_key.Key.eql(chat_key.of(chat), chat_key.of(&a.chats[index])));
        try std.testing.expect(std.mem.indexOf(u8, a.status.slice(), "chats selected") != null);
    }
    a.chat_count = 0;
    selectAllChats(&a);
    try std.testing.expectEqual(@as(usize, 0), a.bulk.items.len);
    try std.testing.expectEqualStrings("No chats to select", a.status.slice());
}

test "bulk snapshot survives a list refresh to zero rows" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    selectAllChats(&a);
    a.chat_count = 0;
    archiveSelected(&a, false);
    try std.testing.expectEqual(@as(usize, 2), a.pending_archive_count);
    try std.testing.expect(state.find("a@g.us") != null);
    try std.testing.expect(state.find("b@g.us") != null);
}

test "IGSH-777 bulk hub archive dispatches one batch and refreshes after every result" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.unified_hub = true;
    selectAllChats(&a);
    archiveSelected(&a, false);
    try std.testing.expectEqual(@as(usize, 1), a.hub_archive_requests);
    try std.testing.expectEqual(@as(usize, 2), a.hub_archive_batch_count);
    const result = WacliResult{ .account = a.cache_tag, .jid = a.spawned_jid, .gen = 2, .ok = true, .http_status = 200, .data = "{\"results\":[{\"chat\":\"a@g.us\",\"ok\":true},{\"chat\":\"b@g.us\",\"ok\":true}]}" };
    a.hub_archive_inflight = false;
    applyHubArchiveResult(&a, &result);
    try std.testing.expectEqual(@as(usize, 1), a.chats_refreshes);
    try std.testing.expectEqual(@as(usize, 1), a.hub_archive_requests);
    try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
}

test "IGSH-777 failed first result preserves intent without hiding later success" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    a.unified_hub = true;
    selectAllChats(&a);
    archiveSelected(&a, false);
    const result = WacliResult{ .account = a.cache_tag, .jid = a.spawned_jid, .gen = 2, .ok = true, .http_status = 200, .data = "{\"results\":[{\"chat\":\"a@g.us\",\"ok\":false,\"error\":\"fixture failure\"},{\"chat\":\"b@g.us\",\"ok\":true}]}" };
    applyHubArchiveResult(&a, &result);
    try std.testing.expectEqual(@as(usize, 1), a.pending_archive_count);
    try std.testing.expectEqualStrings("a@g.us", a.pending_archives[0].jid.slice());
    try std.testing.expect(a.pending_archives[0].retry_at_ms > win.GetTickCount64());
    try std.testing.expect(state.isArchived(.{ .provider = .whatsapp, .account = "", .id = "a@g.us" }, false));
    try std.testing.expect(state.isArchived(.{ .provider = .whatsapp, .account = "", .id = "b@g.us" }, false));
}

test "Ctrl A routes every non-text control and empty composer focus but preserves every text field" {
    var state = archive_rules.State{};
    var a = fixture(&state);
    defer a.allocator.free(a.pending_archives);
    defer a.bulk.deinit(a.allocator);
    defer compose_text_len = 0;
    a.search = 7;
    a.thread_compose = 8;
    a.emoji_edit = 9;
    a.palette_edit = 10;
    const messages_list: win.HWND = 11;
    const button: win.HWND = 12;
    const list_scrollbar: win.HWND = 13;
    for ([_]i32{ 0, 5 }) |text_len| {
        compose_text_len = text_len;
        for ([_]?win.HWND{ a.chats_hwnd, a.canvas, a.hwnd, messages_list, button, list_scrollbar, null }) |focus| {
            a.bulk.clearRetainingCapacity();
            const before = text_selections;
            try std.testing.expect(selectAllKey(&a, focus));
            try std.testing.expectEqual(a.chat_count, a.bulk.items.len);
            try std.testing.expectEqual(before, text_selections);
        }
        for ([_]?win.HWND{ a.compose, a.search, a.thread_compose, a.emoji_edit, a.palette_edit }) |focus| {
            a.bulk.clearRetainingCapacity();
            const before = text_selections;
            try std.testing.expect(selectAllKey(&a, focus));
            if (focus == a.compose and text_len == 0) {
                try std.testing.expectEqual(a.chat_count, a.bulk.items.len);
                try std.testing.expectEqual(before, text_selections);
            } else {
                try std.testing.expectEqual(@as(usize, 0), a.bulk.items.len);
                try std.testing.expectEqual(before + 1, text_selections);
            }
        }
    }
}

fn queueUnreadProbe(_: *App, _: *const Chat) void {}
fn invalidateChatRow(_: *App, _: usize) void {}

test "IGSH-833 bulk plain group and direct chat return on an incoming message while kept stays archived" {
    for ([_][]const u8{ "personal:120363000000000002@g.us", "personal:15550000007@s.whatsapp.net" }) |id| {
        for ([_]bool{ false, true }) |keep| {
            var state = archive_rules.State{};
            var a = fixture(&state);
            defer a.allocator.free(a.pending_archives);
            defer a.bulk.deinit(a.allocator);
            defer a.read_state.deinit(a.allocator);
            a.unified_hub = true;
            a.cache_tag.set("0123456789abcdef");
            a.chats[0].account.set("fixture-account");
            a.chats[0].jid.set(id);
            const row = a.chats[0];
            selectAllChats(&a);
            archiveSelected(&a, keep);
            try std.testing.expectEqual(@as(usize, 0), a.chat_count);
            try std.testing.expectEqual(keep, state.isKept(id));
            var loaded = archive_rules.State{};
            loaded.parse(a.saved[0..a.saved_len]);
            a.archive_state = &loaded;
            a.pending_archive_count = 0;
            a.hub_archive_inflight = false;
            try std.testing.expect(!holdKeptArchived(&a, chat_key.of(&row), true, "2026-10-10T12:04:00Z"));
            try std.testing.expect(loaded.localArchived(chat_key.of(&row)));
            try std.testing.expectEqual(!keep, loaded.needsReturnProbe(id, "2026-10-10T12:04:00Z"));
            var result = WacliResult{ .provider = .whatsapp, .account = row.account, .jid = row.jid, .ok = true };
            result.msg_id.set(a.cache_tag.slice());
            result.extra.set("2026-10-10T11:00:00Z");
            result.data = "{\"data\":{\"messages\":[{\"Timestamp\":\"2026-10-10T11:00:00Z\",\"FromMe\":true,\"ReactionToID\":\"old-message\"}]}}";
            applyUnreadProbe(&a, &result);
            try std.testing.expect(loaded.localArchived(chat_key.of(&row)));
            try std.testing.expectEqual(@as(usize, 0), a.pending_archive_count);
            result.extra.set("2026-10-10T12:04:00Z");
            result.data = "{\"data\":{\"messages\":[{\"Timestamp\":\"2026-10-10T12:04:00Z\",\"FromMe\":false}]}}";
            applyUnreadProbe(&a, &result);
            try std.testing.expectEqual(keep, loaded.localArchived(chat_key.of(&row)));
            try std.testing.expectEqual(@as(usize, if (keep) 0 else 1), a.pending_archive_count);
            if (!keep) try std.testing.expect(a.pending_archives[0].should_unarchive);
            try std.testing.expectEqual(keep, loaded.isKept(id));
            var parsed = try std.json.parseFromSlice(std.json.Value, a.allocator, "{\"archived\":true}", .{});
            defer parsed.deinit();
            const inbox = archiveInboxRow(&a, row, parsed.value.object);
            try std.testing.expectEqual(!keep, inbox != null);
            a.show_archived = true;
            try std.testing.expectEqual(keep, archiveInboxRow(&a, row, parsed.value.object) != null);
            if (inbox) |chat| try std.testing.expect(!chat.archived);
        }
    }
}

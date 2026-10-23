const std = @import("std");
const chat_key = @import("chat_key");
const chat_reconcile = @import("chat_reconcile");
const wa_hub = @import("wa_hub.zig");

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
const Provider = enum { whatsapp, slack, telegram };
const Chat = struct {
    account: Utf8Text(32) = .{},
    jid: Utf8Text(191) = .{},
    timestamp: Utf8Text(47) = .{},
    provider: Provider = .whatsapp,
};
const WacliJobKind = enum { messages, chats, cache_tag };
const WacliJob = struct {
    provider: Provider = .whatsapp,
    account: Utf8Text(32) = .{},
    hub_account: Utf8Text(32) = .{},
    kind: WacliJobKind = .messages,
    gen: u64 = 0,
    jid: Utf8Text(191) = .{},
    msg_id: Utf8Text(191) = .{},
    extra: Utf8Text(63) = .{},
    started_ms: u64 = 0,
};
const WacliResult = struct {
    provider: Provider = .whatsapp,
    account: Utf8Text(32) = .{},
    kind: WacliJobKind = .messages,
    gen: u64 = 0,
    jid: Utf8Text(191) = .{},
    msg_id: Utf8Text(191) = .{},
    extra: Utf8Text(63) = .{},
    started_ms: u64 = 0,
    ok: bool = true,
    data: []const u8 = "{\"data\":{\"messages\":[]}}",
};
const App = struct {
    cache_tag: Utf8Text(32) = .{},
    unified_hub: bool = false,
    hub_account: Utf8Text(32) = .{},
    wa_bridge_url: []const u8 = "fixture-origin",
    wa_bridge_account: []const u8 = "",
    startup_probe_pending: bool = false,
    sync_logged_out: bool = false,
    wacli_mutex: std.Io.Mutex = .init,
    io: std.Io = std.testing.io,
    persisted_tag: Utf8Text(32) = .{},
    log_count: usize = 0,
    last_log: Utf8Text(191) = .{},
    allocator: std.mem.Allocator = std.testing.allocator,
    chats: [2]Chat = .{ .{}, .{} },
    chat_count: usize = 1,
    selected_chat: usize = 0,
    user_viewed: bool = true,
    chat_selection_pending: bool = false,
    displayed_provider: @TypeOf((Chat{}).provider) = .whatsapp,
    displayed_account: Utf8Text(32) = .{},
    displayed_jid: Utf8Text(191) = .{},
    displayed_timestamp: Utf8Text(47) = .{},
    messages_gen: u64 = 0,
    messages_read_key: chat_key.Stored = .{},
    messages_refresh_again: bool = false,
    chats_gen: u64 = 1,
    chats_read_attempts: u32 = 0,
    chats_read_retry_ticks: u32 = 0,
    slack_history_hash: u64 = 0,
    msg_read_last_jid: Utf8Text(191) = .{},
    msg_read_attempts: u32 = 0,
    msg_read_retry_ticks: u32 = 0,
    wacli_path: []const u8 = "wacli.exe",
    pending: u32 = 0,
    queued: u32 = 0,
    last_job: WacliJob = .{},
    painted: u32 = 0,
    cached: u32 = 0,
    refreshed_chats: u32 = 0,
    cache_data: ?[]const u8 = null,
    message_count: usize = 0,
    messages: [1]struct { transcript_state: enum { none, loading, ready, failed } = .none } = .{.{}},
    transcribe_attempts: [512]u64 = [_]u64{0} ** 512,
    transcribe_attempt_count: usize = 0,
    transcribe_active_id: Utf8Text(191) = .{},
    pending_send_count: usize = 0,
    failed_send_count: usize = 0,
    msg_applied_hash: u64 = 0,
};
fn markChatRead(_: *App) void {}
fn fixture() App {
    var a = App{};
    a.chats[0].jid.set("a@g.us");
    a.chats[0].timestamp.set("2026-09-06T13:30:00");
    a.displayed_jid = a.chats[0].jid;
    a.displayed_timestamp = a.chats[0].timestamp;
    return a;
}
fn clearMessages(a: *App) void {
    a.message_count = 0;
}
fn cancelSlackMark(_: *App) void {}
fn stopAudio(_: *App) void {}
fn refreshTelegramMessages(_: *App) void {}
fn refreshSlackHistory(_: *App) void {}
fn msgCacheGet(a: *App, _: chat_key.Key) ?[]const u8 {
    return a.cache_data;
}
fn loadMsgCacheDisk(_: *App, _: []const u8) ?[]u8 {
    return null;
}
fn wacliPendingGet(a: *App, _: WacliJobKind) u32 {
    return a.pending;
}
fn wacliJobArgs(_: *WacliJob, _: []const []const u8) void {}
fn wacliEnqueue(a: *App, job: WacliJob, _: bool) bool {
    a.pending += 1;
    a.queued += 1;
    a.last_job = job;
    return true;
}
fn msgCacheStore(a: *App, _: chat_key.Key, _: []const u8) void {
    a.cached += 1;
}
fn applyChats(a: *App, raw: []const u8, _: bool) bool {
    a.chats[0].timestamp.set(raw);
    return true;
}
fn saveChatsCache(_: *App, _: []const u8) void {}
fn setStatus(_: *App, _: []const u8) void {}
fn appendLaunchLog(a: *App, line: []const u8) void {
    a.log_count += 1;
    a.last_log.set(line);
}
fn persistTag(a: *App, tag: []const u8) void {
    a.persisted_tag.set(tag);
}
fn bindOutboxAccount(_: *App) void {}
fn loadChatsCache(_: *App) void {}
fn refreshGroups(_: *App) void {}
fn refreshChats(_: *App) void {}
fn refreshVisibleChats(a: *App) void {
    a.refreshed_chats += 1;
}
fn refreshContactsIndex(_: *App) void {}

test "fresh sidebar row triggers one generation-guarded read" {
    var a = fixture();
    const chats = WacliResult{ .kind = .chats, .gen = a.chats_gen, .data = "2026-09-06T13:34:39" };
    deliverChats(&a, &chats);
    deliverChats(&a, &chats);
    try std.testing.expectEqual(@as(u32, 1), a.queued);
    try std.testing.expectEqual(@as(u64, 1), a.last_job.gen);
}

test "failed and malformed reads retry but a valid empty conversation succeeds" {
    var a = fixture();
    refreshMessages(&a);
    var result = resultFor(a.last_job);
    result.ok = false;
    deliver(&a, &result);
    try std.testing.expectEqual(@as(u32, 2), a.msg_read_retry_ticks);
    tick(&a);
    try std.testing.expectEqual(@as(u32, 1), a.queued);
    tick(&a);
    try std.testing.expectEqual(@as(u32, 2), a.queued);
    result = resultFor(a.last_job);
    result.data = "{\"data\":{}}";
    deliver(&a, &result);
    try std.testing.expectEqual(@as(u32, 4), a.msg_read_retry_ticks);
    try std.testing.expectEqual(@as(u32, 0), a.cached);
    for (0..4) |_| tick(&a);
    result = resultFor(a.last_job);
    deliver(&a, &result);
    try std.testing.expectEqual(@as(u32, 0), a.msg_read_attempts);
    try std.testing.expectEqual(@as(u32, 0), a.msg_read_retry_ticks);
    try std.testing.expectEqual(@as(u32, 1), a.cached);
}

test "an identical fresh read for the open chat is not repainted" {
    var a = fixture();
    refreshMessages(&a);
    var result = resultFor(a.last_job);
    a.message_count = 1;
    a.msg_applied_hash = std.hash.Wyhash.hash(0, result.data);
    const painted = a.painted;
    deliver(&a, &result);
    try std.testing.expectEqual(painted, a.painted);
    try std.testing.expectEqual(@as(u32, 0), a.cached);
    refreshMessages(&a);
    result = resultFor(a.last_job);
    result.data = "{\"data\":{\"messages\":[{}]}}";
    deliver(&a, &result);
    try std.testing.expectEqual(@as(u32, 1), a.cached);
}

test "retry budget stops after two retries" {
    var a = fixture();
    refreshMessages(&a);
    for (0..3) |_| {
        var result = resultFor(a.last_job);
        result.ok = false;
        deliver(&a, &result);
        for (0..4) |_| tick(&a);
    }
    try std.testing.expectEqual(@as(u32, 3), a.queued);
    try std.testing.expectEqual(@as(u32, 0), a.msg_read_retry_ticks);
}

test "leaving WhatsApp or clearing selection resets a spent budget" {
    inline for (.{ Provider.slack, Provider.telegram }) |provider| {
        var a = fixture();
        refreshMessages(&a);
        a.pending = 0;
        a.msg_read_attempts = 2;
        a.chats[0].provider = provider;
        refreshMessages(&a);
        a.chats[0].provider = .whatsapp;
        refreshMessages(&a);
        var result = resultFor(a.last_job);
        result.ok = false;
        deliver(&a, &result);
        try std.testing.expectEqual(@as(u32, 2), a.msg_read_retry_ticks);
    }
    var a = fixture();
    refreshMessages(&a);
    a.msg_read_attempts = 2;
    a.chat_count = 0;
    refreshMessages(&a);
    try std.testing.expectEqual(@as(u32, 0), a.msg_read_attempts);
}

test "stale success and failure never paint, cache or consume retry budget" {
    var a = fixture();
    refreshMessages(&a);
    var old = resultFor(a.last_job);
    a.chats[1].jid.set("b@g.us");
    a.chats[1].timestamp.set("2026-09-06T13:30:00");
    a.chat_count = 2;
    a.selected_chat = 1;
    refreshMessages(&a);
    const painted = a.painted;
    deliver(&a, &old);
    try std.testing.expectEqual(painted, a.painted);
    try std.testing.expectEqual(@as(u32, 0), a.cached);
    a.selected_chat = 0;
    refreshMessages(&a);
    old.ok = false;
    deliver(&a, &old);
    try std.testing.expectEqual(@as(u32, 0), a.msg_read_attempts);
}

test "reconciliation respects provider, selection and user-view guards" {
    var a = fixture();
    a.chats[0].timestamp.set("2026-09-06T13:34:39");
    a.user_viewed = false;
    reconcileOpenChat(&a);
    a.user_viewed = true;
    a.chat_selection_pending = true;
    reconcileOpenChat(&a);
    a.chat_selection_pending = false;
    a.chats[0].provider = .slack;
    reconcileOpenChat(&a);
    try std.testing.expectEqual(@as(u32, 0), a.queued);
}

test "uncached contact opens an empty conversation before the fresh read" {
    var a = fixture();
    a.chats[0].jid.set("447700900100@s.whatsapp.net");
    a.chats[0].timestamp.set("");
    refreshMessages(&a);
    try std.testing.expectEqual(@as(u32, 1), a.painted);
    try std.testing.expectEqual(@as(u32, 0), a.cached);
    try std.testing.expectEqual(@as(u32, 1), a.queued);
    try std.testing.expectEqualStrings(a.chats[0].jid.slice(), a.displayed_jid.slice());
    try std.testing.expectEqualStrings(a.chats[0].jid.slice(), a.last_job.jid.slice());
}

test "same jid from another WhatsApp account cannot paint or retry the current chat" {
    for ([_]bool{ false, true }) |ok| {
        var a = fixture();
        a.cache_tag.set("aaaaaaaaaaaaaaaa");
        a.chats[0].account = a.cache_tag;
        refreshMessages(&a);
        var result = resultFor(a.last_job);
        try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaa", result.account.slice());
        result.ok = ok;
        a.cache_tag.set("bbbbbbbbbbbbbbbb");
        a.chats[0].account = a.cache_tag;
        const painted = a.painted;
        deliver(&a, &result);
        try std.testing.expectEqual(painted, a.painted);
        try std.testing.expectEqual(@as(u32, 0), a.cached);
        try std.testing.expectEqual(@as(u32, 0), a.msg_read_retry_ticks);
        refreshMessages(&a);
        result = resultFor(a.last_job);
        try std.testing.expectEqualStrings("bbbbbbbbbbbbbbbb", result.account.slice());
        deliver(&a, &result);
        try std.testing.expectEqual(@as(u32, 1), a.cached);
    }
}

test "ISSUE-517 chat refresh keeps failed attempts until the next chat open" {
    var a = fixture();
    a.message_count = 1;
    a.messages[0].transcript_state = .failed;
    try std.testing.expect(!transcribeWasAttempted(&a, "failed-note"));
    refreshMessages(&a);
    try std.testing.expectEqual(.failed, a.messages[0].transcript_state);
    try std.testing.expect(transcribeWasAttempted(&a, "failed-note"));
    a.chats[0].jid.set("another-chat@g.us");
    refreshMessages(&a);
    try std.testing.expectEqual(.none, a.messages[0].transcript_state);
    try std.testing.expect(!transcribeWasAttempted(&a, "failed-note"));
}

test "IGSH-575 timestamped hub chat clears old messages and accepts its cache-tagged result" {
    var a = fixture();
    a.cache_tag.set("aaaaaaaaaaaaaaaa");
    a.chats[0].account = a.cache_tag;
    a.displayed_account = a.cache_tag;
    a.message_count = 1;
    a.chats[1].account = a.cache_tag;
    a.chats[1].jid.set("b@g.us");
    a.chats[1].timestamp = a.chats[0].timestamp;
    a.chat_count = 2;
    a.selected_chat = 1;

    refreshMessages(&a);
    try std.testing.expectEqual(@as(usize, 0), a.message_count);
    try std.testing.expectEqual(@as(u32, 1), a.painted);
    try std.testing.expect(chat_key.Key.eql(chat_key.of(&a.chats[1]), chat_key.displayed(&a)));

    a.last_job.hub_account.set("personal");
    var result = resultFor(a.last_job);
    result.data = "{\"data\":{\"messages\":[{\"MsgID\":\"BETA\",\"Text\":\"Fixture Beta\"}]}}";
    try std.testing.expectEqualStrings(a.cache_tag.slice(), result.account.slice());
    try std.testing.expect(!std.mem.eql(u8, a.last_job.hub_account.slice(), result.account.slice()));
    deliver(&a, &result);
    try std.testing.expectEqual(@as(usize, 1), a.message_count);
    try std.testing.expectEqual(@as(u32, 2), a.painted);
    try std.testing.expectEqual(@as(u32, 1), a.cached);
    try std.testing.expect(chat_key.Key.eql(chat_key.of(&a.chats[1]), chat_key.displayed(&a)));
    try std.testing.expectEqualStrings(a.chats[1].timestamp.slice(), a.displayed_timestamp.slice());
}

test "IGSH-575 switching to cached history displays it before the reply" {
    var a = fixture();
    a.chats[0].jid.set("cached@g.us");
    a.cache_data = "{\"data\":{\"messages\":[{\"MsgID\":\"CACHED\",\"Text\":\"Fixture cached\"}]}}";
    refreshMessages(&a);
    try std.testing.expectEqual(@as(usize, 1), a.message_count);
    try std.testing.expectEqual(@as(u32, 1), a.painted);
    try std.testing.expectEqual(@as(u32, 0), a.cached);
    try std.testing.expectEqual(@as(u32, 1), a.pending);
    try std.testing.expect(chat_key.Key.eql(chat_key.of(&a.chats[0]), chat_key.displayed(&a)));
}

test "IGSH-575 unified hub repairs a saved bridge tag and shows fresh history" {
    for ([_]bool{ true, false }) |account_ready| {
        var a = fixture();
        a.unified_hub = true;
        a.cache_tag.set("aaaaaaaaaaaaaaaa");
        if (account_ready) a.hub_account.set("hub");
        var tag_buffer: [16]u8 = undefined;
        const tag = try std.fmt.bufPrint(&tag_buffer, "{x:0>16}", .{std.hash.Wyhash.hash(std.hash.Wyhash.hash(0, a.wa_bridge_url), "hub")});
        a.chats[0].account.set(tag);
        a.chats[0].jid.set("fixture-room@g.us");
        a.message_count = 1;
        a.displayed_account = a.cache_tag;
        a.displayed_jid.set("personal:fixture-previous@g.us");
        const accounts = WacliResult{ .kind = .cache_tag, .data = "[{\"account\":\"hub\",\"state\":\"linked\"}]" };
        applyHubAccounts(&a, &accounts);
        try std.testing.expectEqual(@as(usize, 0), a.message_count);
        try std.testing.expect(chat_key.Key.eql(chat_key.of(&a.chats[0]), chat_key.displayed(&a)));
        var result = resultFor(a.last_job);
        result.data = "{\"success\":true,\"data\":{\"messages\":[{\"MsgID\":\"FRESH\",\"ChatJID\":\"personal:fixture-room@g.us\",\"Text\":\"Fixture message\",\"FromMe\":false,\"Timestamp\":\"2026-01-01T00:00:00Z\"}]}}";
        deliver(&a, &result);
        try std.testing.expectEqual(@as(usize, 1), a.message_count);
        try std.testing.expectEqual(@as(u32, 2), a.painted);
        try std.testing.expectEqual(@as(u32, 1), a.cached);
        try std.testing.expect(chat_key.Key.eql(chat_key.of(&a.chats[0]), chat_key.displayed(&a)));
        try std.testing.expectEqualStrings(a.chats[0].timestamp.slice(), a.displayed_timestamp.slice());
        try std.testing.expectEqualStrings(tag, a.cache_tag.slice());
        try std.testing.expectEqualStrings(tag, a.persisted_tag.slice());
        const queued = a.queued;
        hubRefreshMessages(&a, a.chats[0].jid.slice());
        try std.testing.expectEqual(queued + 1, a.queued);
    }
}

test "IGSH-575 dropped account and selected generation replies each log once" {
    var a = fixture();
    a.unified_hub = true;
    a.cache_tag.set("aaaaaaaaaaaaaaaa");
    a.chats[0].account.set("bbbbbbbbbbbbbbbb");
    refreshMessages(&a);
    var result = resultFor(a.last_job);
    deliver(&a, &result);
    try std.testing.expectEqual(@as(usize, 1), a.log_count);
    try std.testing.expect(std.mem.indexOf(u8, a.last_log.slice(), "account mismatch") != null);
    try std.testing.expectEqual(@as(usize, 0), a.message_count);
    a.cache_tag = a.chats[0].account;
    refreshMessages(&a);
    result = resultFor(a.last_job);
    a.messages_gen += 1;
    deliver(&a, &result);
    try std.testing.expectEqual(@as(usize, 2), a.log_count);
    try std.testing.expect(std.mem.indexOf(u8, a.last_log.slice(), "generation changed") != null);
    try std.testing.expectEqual(@as(usize, 0), a.message_count);
}

test "IGSH-575 hub events during uncached history do not supersede its reply" {
    var a = fixture();
    a.unified_hub = true;
    a.cache_tag.set("aaaaaaaaaaaaaaaa");
    a.chats[0].account = a.cache_tag;
    a.chats[0].jid.set("uncached@g.us");
    refreshMessages(&a);
    var first = resultFor(a.last_job);
    first.data = "{\"data\":{\"messages\":[{\"MsgID\":\"FIRST\"}]}}";
    const gen = a.messages_gen;
    const painted = a.painted;

    for (0..3) |_| hubRefreshMessages(&a, a.chats[0].jid.slice());
    const chats = WacliResult{ .kind = .chats, .gen = a.chats_gen, .data = "2026-09-06T13:34:39" };
    deliverChats(&a, &chats);
    try std.testing.expectEqual(gen, a.messages_gen);
    try std.testing.expectEqual(@as(u32, 1), a.queued);
    try std.testing.expectEqual(painted, a.painted);
    try std.testing.expectEqual(@as(usize, 0), a.message_count);

    deliver(&a, &first);
    try std.testing.expectEqual(@as(usize, 1), a.message_count);
    try std.testing.expectEqual(@as(u32, 1), a.cached);
    try std.testing.expectEqual(painted + 1, a.painted);
    try std.testing.expectEqual(@as(usize, 1), a.log_count);
    try std.testing.expect(std.mem.indexOf(u8, a.last_log.slice(), "dropped reply") == null);
    try std.testing.expectEqual(@as(u32, 2), a.queued);
    try std.testing.expectEqual(gen + 1, a.messages_gen);
    try std.testing.expectEqual(@as(u32, 1), a.pending);

    var followup = resultFor(a.last_job);
    followup.data = "{\"data\":{\"messages\":[{\"MsgID\":\"NEWER\"}]}}";
    deliver(&a, &followup);
    try std.testing.expectEqual(@as(u32, 2), a.cached);
    try std.testing.expectEqual(@as(u32, 2), a.queued);
    try std.testing.expectEqual(@as(u32, 0), a.pending);
}

test "IGSH-575 returning to a chat keeps the newer click ahead of older reads" {
    var a = fixture();
    a.unified_hub = true;
    a.chats[1].jid.set("b@g.us");
    a.chat_count = 2;
    refreshMessages(&a);
    var first = resultFor(a.last_job);
    a.selected_chat = 1;
    refreshMessages(&a);
    var other = resultFor(a.last_job);
    a.selected_chat = 0;
    refreshMessages(&a);
    var newest = resultFor(a.last_job);
    newest.data = "{\"data\":{\"messages\":[{}]}}";
    const gen = a.messages_gen;
    const painted = a.painted;
    hubRefreshMessages(&a, a.chats[0].jid.slice());
    deliver(&a, &other);
    try std.testing.expectEqualStrings("messages-read: dropped reply, identity changed", a.last_log.slice());
    deliver(&a, &first);
    try std.testing.expectEqualStrings("messages-read: dropped reply, generation changed", a.last_log.slice());
    try std.testing.expectEqual(painted, a.painted);
    try std.testing.expectEqual(@as(u32, 0), a.cached);
    try std.testing.expectEqual(gen, a.messages_gen);
    try std.testing.expect(a.messages_refresh_again);
    try std.testing.expect(chat_key.Key.eql(a.messages_read_key.key(), chat_key.of(&a.chats[0])));
    deliver(&a, &newest);
    try std.testing.expectEqual(@as(usize, 1), a.message_count);
    try std.testing.expectEqual(@as(u32, 1), a.cached);
    try std.testing.expectEqual(gen + 1, a.messages_gen);
    var followup = resultFor(a.last_job);
    deliver(&a, &followup);
}

test "IGSH-575 coalescing distinguishes provider and account for the same jid" {
    inline for (.{ Provider.slack, Provider.telegram, Provider.whatsapp }) |provider| {
        var a = fixture();
        a.unified_hub = true;
        refreshMessages(&a);
        var first = resultFor(a.last_job);
        a.chats[0].provider = provider;
        if (provider == .whatsapp) a.chats[0].account.set("other-account");
        refreshMessages(&a);
        var newest = resultFor(a.last_job);
        try std.testing.expectEqual(@as(u32, 2), a.queued);
        const painted = a.painted;
        deliver(&a, &first);
        try std.testing.expectEqualStrings("messages-read: dropped reply, identity changed", a.last_log.slice());
        try std.testing.expectEqual(painted, a.painted);
        a.cache_tag = a.chats[0].account;
        deliver(&a, &newest);
        try std.testing.expectEqual(@as(u32, 1), a.cached);
    }
}

test "IGSH-575 cleared selection drops its reply and can reopen while it is pending" {
    var a = fixture();
    refreshMessages(&a);
    var old = resultFor(a.last_job);
    a.chat_count = 0;
    refreshMessages(&a);
    deliver(&a, &old);
    try std.testing.expectEqualStrings("messages-read: dropped reply, selection changed", a.last_log.slice());
    a.chat_count = 1;
    refreshMessages(&a);
    old = resultFor(a.last_job);
    a.chat_count = 0;
    refreshMessages(&a);
    a.chat_count = 1;
    refreshMessages(&a);
    var newest = resultFor(a.last_job);
    const gen = a.messages_gen;
    deliver(&a, &old);
    try std.testing.expectEqualStrings("messages-read: dropped reply, generation changed", a.last_log.slice());
    try std.testing.expectEqual(gen, a.messages_gen);
    deliver(&a, &newest);
    try std.testing.expectEqual(@as(u32, 1), a.cached);
}

test "IGSH-575 coalesced refresh preserves failure and malformed retry scheduling" {
    for ([_]bool{ false, true }) |ok| {
        var a = fixture();
        refreshMessages(&a);
        var result = resultFor(a.last_job);
        result.ok = ok;
        result.data = "{\"data\":{}}";
        refreshMessages(&a);
        deliver(&a, &result);
        try std.testing.expectEqual(@as(u32, 1), a.queued);
        try std.testing.expectEqual(@as(u32, 2), a.msg_read_retry_ticks);
        try std.testing.expectEqual(@as(u32, 0), a.cached);
        tick(&a);
        tick(&a);
        try std.testing.expectEqual(@as(u32, 2), a.queued);
        result = resultFor(a.last_job);
        deliver(&a, &result);
    }
}

test "IGSH-575 late older reads cannot replace the newest click or block its next refresh" {
    var a = fixture();
    refreshMessages(&a);
    var first = resultFor(a.last_job);
    a.chats[1].jid.set("b@g.us");
    a.chat_count = 2;
    a.selected_chat = 1;
    refreshMessages(&a);
    var other = resultFor(a.last_job);
    a.selected_chat = 0;
    refreshMessages(&a);
    var newest = resultFor(a.last_job);
    newest.data = "{\"data\":{\"messages\":[{}]}}";
    deliver(&a, &newest);
    const painted = a.painted;
    refreshMessages(&a);
    var followup = resultFor(a.last_job);
    try std.testing.expectEqual(newest.gen + 1, followup.gen);
    deliver(&a, &first);
    deliver(&a, &other);
    try std.testing.expectEqual(painted, a.painted);
    try std.testing.expectEqual(@as(usize, 1), a.message_count);
    try std.testing.expectEqual(@as(u32, 1), a.cached);
    try std.testing.expect(chat_key.Key.eql(a.messages_read_key.key(), chat_key.of(&a.chats[0])));
    deliver(&a, &followup);
}

test "hub Slack history refreshes ordering after caching its last message fallback" {
    var a = fixture();
    a.unified_hub = true;
    a.chats[0].provider = .slack;
    refreshMessages(&a);
    var result = resultFor(a.last_job);
    deliver(&a, &result);
    try std.testing.expectEqual(@as(u32, 1), a.cached);
    try std.testing.expectEqual(@as(u32, 1), a.refreshed_chats);
}

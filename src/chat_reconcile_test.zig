const std = @import("std");
const chat_key = @import("chat_key");
const chat_reconcile = @import("chat_reconcile");

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
const WacliJobKind = enum { messages, chats };
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
fn wacliEnqueue(a: *App, job: WacliJob, _: bool) void {
    a.pending += 1;
    a.queued += 1;
    a.last_job = job;
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
fn appendLaunchLog(_: *App, _: []const u8) void {}

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

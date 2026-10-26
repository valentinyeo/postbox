const std = @import("std");
const transport = @import("transport.zig");
const chat_key = @import("chat_key.zig");
const media_drain = @import("media_drain.zig");
const played = @import("played.zig");
const max_chats = 4;
const max_wacli_args = 16;
const wacli_arg_cap = 256;
const media_cache_eviction_days = 14;
const win = struct {
    var now: u64 = 100_000;
    fn GetTickCount64() u64 {
        return now;
    }
};
const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    cache_tag: Utf8Text(32) = .{},
    wacli_path: []const u8 = "wacli.exe",
    background_media_chats: [max_chats]BackgroundMediaChat = [_]BackgroundMediaChat{.{}} ** max_chats,
    background_media_count: usize = 0,
    background_media: BackgroundMedia = .{},
    chats: [1]BackgroundMediaChat = .{.{}},
    chat_count: usize = 0,
    selected_chat: usize = 0,
    displayed_provider: transport.Provider = .whatsapp,
    displayed_account: Utf8Text(32) = .{},
    displayed_jid: Utf8Text(191) = .{},
    startup_probe_pending: bool = false,
    sync_logged_out: bool = false,
    accounts_maintenance: bool = false,
    media_burst_files: usize = 0,
    media_burst_started_ms: u64 = 0,
    media_resume_after_ms: u64 = 0,
    last_sync_stop_ms: ?u64 = null,
    sync_child: ?u8 = null,
    media_failures: [16]MediaFailure = [_]MediaFailure{.{}} ** 16,
    media_attempts: [512]u64 = [_]u64{0} ** 512,
    media_attempt_count: usize = 0,
    media_unavailable: [512]u64 = [_]u64{0} ** 512,
    media_unavailable_count: usize = 0,
    busy: bool = false,
    open_candidate: bool = false,
    pending_messages: bool = false,
    pending_background: bool = false,
    queue_ok: bool = true,
    job: WacliJob = .{},
    jobs: usize = 0,
    started: Utf8Text(191) = .{},
    starts: usize = 0,
    media_downloads: [1]MediaDownload = .{.{}},
    audio_chain_id: Utf8Text(191) = .{},
    audio_chain_waiting: bool = false,
    cached_media_jid: Utf8Text(191) = .{},
    cached_media_id: Utf8Text(191) = .{},
    cached: ?[]u8 = null,

    fn deinit(a: *App) void {
        if (a.cached) |raw| a.allocator.free(raw);
    }
};
fn getString(object: std.json.ObjectMap, key: []const u8) []const u8 {
    const value = object.get(key) orelse return "";
    return if (value == .string) value.string else "";
}
fn getBool(object: std.json.ObjectMap, key: []const u8) bool {
    const value = object.get(key) orelse return false;
    return value == .bool and value.bool;
}
fn nowUnixSeconds() i64 {
    return @import("media_age.zig").unixSeconds("2026-09-06T13:34:39").?;
}
fn wacliEnqueue(a: *App, job: WacliJob, urgent: bool) bool {
    std.debug.assert(!urgent);
    if (!a.queue_ok) return false;
    a.job = job;
    a.jobs += 1;
    a.pending_background = true;
    return true;
}
fn wacliPendingGet(a: *App, kind: WacliJobKind) u32 {
    return @intFromBool(if (kind == .background_media) a.pending_background else a.pending_messages);
}
fn mediaBusy(a: *const App) bool {
    return a.busy;
}
fn nextOpenMediaCandidate(a: *App, _: u64) ?usize {
    return if (a.open_candidate) 0 else null;
}
fn mediaDownloading(a: *const App, _: []const u8, _: []const u8) bool {
    return a.busy;
}
fn startMediaDownload(a: *App, jid: []const u8, id: []const u8) bool {
    std.debug.assert(!a.busy);
    std.testing.expectEqualStrings(jid, a.background_media.jid.slice()) catch @panic("unexpected chat identity");
    a.busy = true;
    a.started.set(id);
    a.starts += 1;
    a.media_downloads[0] = .{ .hub_pending = true, .started_ms = win.now };
    a.media_downloads[0].jid.set(jid);
    a.media_downloads[0].id.set(id);
    return true;
}
fn hubConfigured(_: *const App) bool {
    return true;
}
fn hubMediaPath(a: *App, allocator: std.mem.Allocator, key: chat_key.Key, id: []const u8) ![]u8 {
    const cached = std.mem.eql(u8, key.account, a.cache_tag.slice()) and
        std.mem.eql(u8, key.id, a.cached_media_jid.slice()) and std.mem.eql(u8, id, a.cached_media_id.slice());
    return allocator.dupe(u8, if (cached) "cached" else "missing");
}
fn fileExistsUtf8(path: []const u8) bool {
    return std.mem.eql(u8, path, "cached");
}
fn msgCacheStore(a: *App, _: chat_key.Key, raw: []const u8) void {
    if (a.cached) |old| a.allocator.free(old);
    a.cached = a.allocator.dupe(u8, raw) catch @panic("allocation failed");
}
fn drainMediaDownloads(a: *App) void {
    _ = autoDownloadBackgroundMedia(a);
}
const image_viewer = struct {
    fn downloadFinished(a: *App, jid: []const u8, id: []const u8, ok: bool) void {
        if (!ok) return;
        a.cached_media_jid.set(jid);
        a.cached_media_id.set(id);
    }
};
fn setStatus(_: *App, _: []const u8) void {}
fn refreshMessages(_: *App) void {}
fn finish(a: *App) void {
    const result = WacliResult{ .kind = .hub_media, .account = a.cache_tag, .jid = a.media_downloads[0].jid, .msg_id = a.media_downloads[0].id, .ok = true, .http_status = 200 };
    finishHubMedia(a, &result);
    a.busy = false;
}
fn deliver(a: *App, raw: []const u8, ok: bool) void {
    a.pending_background = false;
    const result = WacliResult{ .account = a.job.account, .jid = a.job.jid, .extra = a.job.extra, .ok = ok, .data = @constCast(raw) };
    applyBackgroundMedia(a, &result);
}
fn observe(a: *App, raw: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, a.allocator, raw, .{});
    defer parsed.deinit();
    observeBackgroundMediaChats(a, parsed.value.array.items);
}
const chats = "[{\"jid\":\"older\",\"last_message_ts\":\"2026-09-05T00:00:00\"},{\"jid\":\"newest\",\"last_message_ts\":\"2026-09-06T00:00:00\"}]";

test "background wiring queues the newest chat read-only once and drains all eligible kinds through the shared slot" {
    win.now = 100_000;
    var a = App{};
    defer a.deinit();
    a.cache_tag.set("account");
    try observe(&a, chats);
    try std.testing.expect(!autoDownloadBackgroundMedia(&a));
    try std.testing.expectEqualStrings("newest", a.job.jid.slice());
    try std.testing.expectEqualStrings("--read-only", a.job.args[2].slice());
    try std.testing.expectEqualStrings("16", a.job.args[a.job.arg_count - 1].slice());
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqual(@as(usize, 1), a.jobs);
    deliver(&a, "{\"data\":{\"messages\":[{\"MsgID\":\"local\",\"MediaType\":\"image\",\"LocalPath\":\"cached\"},{\"MsgID\":\"large\",\"MediaType\":\"video\",\"FileSize\":104857601},{\"MsgID\":\"deleted\",\"MediaType\":\"audio\",\"Revoked\":true},{\"MsgID\":\"file\",\"MediaType\":\"document\",\"FileLength\":\"42\"},{\"MsgID\":\"voice\",\"MediaType\":\"audio\"},{\"MsgID\":\"video\",\"MediaType\":\"video\"},{\"MsgID\":\"sticker\",\"MediaType\":\"sticker\"}]}}", true);
    try std.testing.expectEqualStrings("file", a.started.slice());
    try std.testing.expectEqual(@as(u64, 42), a.background_media.sizes[0]);
    try std.testing.expect(!autoDownloadBackgroundMedia(&a));
    for ([_][]const u8{ "voice", "video", "sticker" }) |id| {
        finish(&a);
        try std.testing.expect(autoDownloadBackgroundMedia(&a));
        try std.testing.expectEqualStrings(id, a.started.slice());
    }
    finish(&a);
    try std.testing.expect(!autoDownloadBackgroundMedia(&a));
    try std.testing.expectEqual(.caching, a.background_media.phase);
    try std.testing.expect(a.cached == null);
    try std.testing.expectEqualStrings("80", a.job.args[a.job.arg_count - 1].slice());
    const cached = "{\"data\":{\"messages\":[{\"MsgID\":\"file\",\"MediaType\":\"document\",\"LocalPath\":\"cached\"}]}}";
    deliver(&a, cached, true);
    try std.testing.expectEqualStrings(cached, a.cached.?);
    try std.testing.expectEqualStrings(a.background_media_chats[1].timestamp.slice(), a.background_media_chats[1].swept.slice());
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqualStrings("older", a.job.jid.slice());
}

test "IGSH-670 hub Giphy completion advances the cached batch without refetching on reopen" {
    win.now = 100_000;
    var a = App{};
    defer a.deinit();
    a.cache_tag.set("account");
    const jid = "slack:fixture-emoji:channel";
    try observe(&a, "[{\"jid\":\"slack:fixture-emoji:channel\",\"last_message_ts\":\"2026-09-06T00:00:00\"}]");
    _ = autoDownloadBackgroundMedia(&a);
    deliver(&a, "{\"data\":{\"messages\":[{\"MsgID\":\"GIPHY\",\"MediaType\":\"image\",\"MimeType\":\"image/gif\"}]}}", true);
    try std.testing.expectEqual(@as(usize, 1), a.starts);
    finish(&a);
    try std.testing.expect(mediaAttempted(&a, jid, "GIPHY"));
    try std.testing.expect(!mediaUnavailable(&a, jid, "GIPHY"));
    try std.testing.expect(!a.media_downloads[0].hub_pending);
    media_drain.forgetAttempt(&a.media_attempts, &a.media_attempt_count, played.Set.pairKey(jid, "GIPHY"));
    try std.testing.expect(!mediaAttempted(&a, jid, "GIPHY"));
    for (0..3) |_| try std.testing.expect(!autoDownloadBackgroundMedia(&a));
    try std.testing.expectEqual(.caching, a.background_media.phase);
    try std.testing.expectEqual(@as(usize, 1), a.starts);
    try std.testing.expectEqual(@as(usize, 2), a.jobs);
    deliver(&a, "{\"data\":{\"messages\":[{\"MsgID\":\"GIPHY\",\"MediaType\":\"image\",\"LocalPath\":\"cached\"}]}}", true);
    a.chat_count = 1;
    a.chats[0] = a.background_media_chats[0];
    a.displayed_jid = a.chats[0].jid;
    a.displayed_account = a.cache_tag;
    try std.testing.expect(!autoDownloadBackgroundMedia(&a));
    a.chat_count = 0;
    try std.testing.expect(!autoDownloadBackgroundMedia(&a));
    try std.testing.expectEqual(@as(usize, 1), a.starts);
    try std.testing.expectEqual(@as(usize, 2), a.jobs);
    try observe(&a, "[{\"jid\":\"slack:fixture-emoji:channel\",\"last_message_ts\":\"2026-09-06T01:00:00\"}]");
    _ = autoDownloadBackgroundMedia(&a);
    deliver(&a, "{\"data\":{\"messages\":[{\"MsgID\":\"GIPHY\",\"MediaType\":\"image\",\"LocalPath\":\"cached\"}]}}", true);
    try std.testing.expectEqual(@as(usize, 1), a.starts);
    try std.testing.expectEqual(.caching, a.background_media.phase);
    deliver(&a, "{\"data\":{\"messages\":[]}}", true);
    a.cached_media_id.set("");
    try observe(&a, "[{\"jid\":\"slack:fixture-emoji:channel\",\"last_message_ts\":\"2026-09-06T02:00:00\"}]");
    _ = autoDownloadBackgroundMedia(&a);
    deliver(&a, "{\"data\":{\"messages\":[{\"MsgID\":\"GIPHY\",\"MediaType\":\"image\"}]}}", true);
    try std.testing.expectEqual(@as(usize, 2), a.starts);
}

test "IGSH-670 pending and failed hub media do not suppress a later download" {
    for ([_]u32{ 202, 404 }) |status| {
        win.now = 100_000;
        var a = App{};
        defer a.deinit();
        a.cache_tag.set("account");
        try observe(&a, chats);
        _ = autoDownloadBackgroundMedia(&a);
        deliver(&a, "{\"data\":{\"messages\":[{\"MsgID\":\"GIPHY\",\"MediaType\":\"image\"}]}}", true);
        const slot = &a.media_downloads[0];
        const result = WacliResult{ .kind = .hub_media, .account = a.cache_tag, .jid = slot.jid, .msg_id = slot.id, .ok = status == 202, .http_status = status };
        finishHubMedia(&a, &result);
        try std.testing.expect(!mediaAttempted(&a, "newest", "GIPHY"));
        try std.testing.expectEqual(status == 202, slot.hub_pending);
        if (status == 202) {
            try std.testing.expectEqual(win.now + 1000, slot.hub_retry_ms);
            finish(&a);
            try std.testing.expect(mediaAttempted(&a, "newest", "GIPHY"));
        } else {
            a.busy = false;
            try std.testing.expect(!autoDownloadBackgroundMedia(&a));
            win.now += 30_000;
            try std.testing.expect(!autoDownloadBackgroundMedia(&a));
            win.now += 15 * 60_000;
            try std.testing.expect(autoDownloadBackgroundMedia(&a));
            try std.testing.expectEqual(@as(usize, 2), a.starts);
        }
    }
}

test "background wiring leaves selected provider identity alone and waits for open messages and pacing" {
    win.now = 100_000;
    var a = App{};
    defer a.deinit();
    a.cache_tag.set("account");
    try observe(&a, chats);
    a.open_candidate = true;
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqual(@as(usize, 0), a.jobs);
    a.open_candidate = false;
    a.pending_messages = true;
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqual(@as(usize, 0), a.jobs);
    a.pending_messages = false;
    a.chat_count = 1;
    a.chats[0] = a.background_media_chats[1];
    a.displayed_jid = a.chats[0].jid;
    a.displayed_account = a.cache_tag;
    a.sync_child = 1;
    a.last_sync_stop_ms = win.now;
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqual(@as(usize, 0), a.jobs);
    win.now += 15_000;
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqualStrings("older", a.job.jid.slice());
    deliver(&a, "{\"data\":{\"messages\":[]}}", true);
    a.chats[0].provider = .slack;
    a.pending_background = false;
    a.background_media = .{};
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqualStrings("newest", a.job.jid.slice());
}

test "background wiring retries failed reads and preserves newer activity during a sweep" {
    win.now = 100_000;
    var a = App{};
    defer a.deinit();
    a.cache_tag.set("account");
    try observe(&a, chats);
    _ = autoDownloadBackgroundMedia(&a);
    deliver(&a, "", false);
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqual(@as(usize, 1), a.jobs);
    try std.testing.expectEqual(@as(usize, 0), a.background_media_chats[1].swept.len);
    win.now += 30_000;
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqual(@as(usize, 2), a.jobs);
    deliver(&a, "{\"data\":{\"messages\":[]}}", true);
    try observe(&a, "[{\"jid\":\"newest\",\"last_message_ts\":\"2026-09-06T01:00:00\"}]");
    deliver(&a, "{\"data\":{\"messages\":[]}}", true);
    try std.testing.expectEqualStrings("2026-09-06T00:00:00", a.background_media_chats[1].swept.slice());
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqualStrings("newest", a.job.jid.slice());
    try std.testing.expectEqualStrings("2026-09-06T01:00:00", a.job.extra.slice());
}

test "background wiring discards a probe when its chat opens and resets sweep identities on account changes" {
    win.now = 100_000;
    var a = App{};
    defer a.deinit();
    a.cache_tag.set("account");
    try observe(&a, chats);
    _ = autoDownloadBackgroundMedia(&a);
    a.chat_count = 1;
    a.chats[0] = a.background_media_chats[1];
    deliver(&a, "{\"data\":{\"messages\":[{\"MsgID\":\"file\",\"MediaType\":\"document\"}]}}", true);
    try std.testing.expectEqual(.idle, a.background_media.phase);
    try std.testing.expect(!a.busy);
    try std.testing.expect(a.cached == null);
    a.cache_tag.set("other-account");
    try observe(&a, "[{\"jid\":\"newest\",\"last_message_ts\":\"2026-09-06T00:00:00\"}]");
    try std.testing.expectEqual(@as(usize, 1), a.background_media_count);
    try std.testing.expectEqualStrings("other-account", a.background_media_chats[0].account.slice());
    try std.testing.expectEqual(@as(usize, 0), a.background_media_chats[0].swept.len);
}

test "background wiring abandons repeatedly failing listings and picks the next due chat" {
    for ([_]struct { raw: []const u8, ok: bool }{
        .{ .raw = "", .ok = false },
        .{ .raw = "invalid json", .ok = true },
        .{ .raw = "[]", .ok = true },
        .{ .raw = "{}", .ok = true },
        .{ .raw = "{\"data\":null}", .ok = true },
        .{ .raw = "{\"data\":{}}", .ok = true },
        .{ .raw = "{\"data\":{\"messages\":null}}", .ok = true },
    }) |failure| {
        win.now = 100_000;
        var a = App{};
        defer a.deinit();
        a.cache_tag.set("account");
        try observe(&a, chats);
        for (0..3) |attempt| {
            _ = autoDownloadBackgroundMedia(&a);
            try std.testing.expectEqualStrings("newest", a.job.jid.slice());
            try std.testing.expectEqual(attempt + 1, a.jobs);
            deliver(&a, failure.raw, failure.ok);
            if (attempt < 2) {
                try std.testing.expectEqual(.listing, a.background_media.phase);
                try std.testing.expectEqual(@as(usize, 0), a.background_media_chats[1].swept.len);
                _ = autoDownloadBackgroundMedia(&a);
                try std.testing.expectEqual(attempt + 1, a.jobs);
                win.now += 30_000;
            }
        }
        try std.testing.expectEqual(.idle, a.background_media.phase);
        try std.testing.expectEqualStrings(a.background_media_chats[1].timestamp.slice(), a.background_media_chats[1].swept.slice());
        _ = autoDownloadBackgroundMedia(&a);
        try std.testing.expectEqualStrings("older", a.job.jid.slice());
        deliver(&a, "{\"data\":{\"messages\":[]}}", true);
        deliver(&a, "{\"data\":{\"messages\":[]}}", true);
        _ = autoDownloadBackgroundMedia(&a);
        try std.testing.expectEqual(@as(usize, 5), a.jobs);
        try observe(&a, "[{\"jid\":\"newest\",\"last_message_ts\":\"2026-09-06T01:00:00\"}]");
        _ = autoDownloadBackgroundMedia(&a);
        try std.testing.expectEqual(@as(usize, 6), a.jobs);
        try std.testing.expectEqualStrings("newest", a.job.jid.slice());
        try std.testing.expectEqualStrings("2026-09-06T01:00:00", a.job.extra.slice());
        try std.testing.expectEqual(@as(u8, 0), a.background_media.read_failures);
    }
}

test "background wiring exhausted download retries and cache failures cannot block the next chat" {
    win.now = 100_000;
    var a = App{};
    defer a.deinit();
    a.cache_tag.set("account");
    try observe(&a, chats);
    _ = autoDownloadBackgroundMedia(&a);
    deliver(&a, "{\"data\":{\"messages\":[{\"MsgID\":\"file\",\"MediaType\":\"document\"}]}}", true);
    for (0..max_media_retries) |attempt| {
        try std.testing.expect(a.busy);
        try std.testing.expectEqualStrings("file", a.started.slice());
        noteMediaFailure(&a, a.background_media.jid.slice(), a.started.slice());
        a.busy = false;
        try std.testing.expect(!autoDownloadBackgroundMedia(&a));
        if (attempt + 1 < max_media_retries) {
            try std.testing.expectEqual(.downloading, a.background_media.phase);
            win.now += 30_000;
            try std.testing.expect(autoDownloadBackgroundMedia(&a));
        }
    }
    try std.testing.expect(mediaUnavailable(&a, "newest", "file"));
    try std.testing.expectEqual(.caching, a.background_media.phase);
    try std.testing.expectEqual(@as(u8, 0), a.background_media.read_failures);
    for (0..3) |attempt| {
        deliver(&a, "", false);
        if (attempt < 2) {
            try std.testing.expectEqual(.caching, a.background_media.phase);
            win.now += 30_000;
            _ = autoDownloadBackgroundMedia(&a);
        }
    }
    try std.testing.expectEqual(.idle, a.background_media.phase);
    _ = autoDownloadBackgroundMedia(&a);
    try std.testing.expectEqualStrings("older", a.job.jid.slice());
}

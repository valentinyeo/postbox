const std = @import("std");
const outbox = @import("outbox.zig");
const unified_snapshot = @import("unified_snapshot.zig");
const transport = @import("transport.zig");
const chat_key = @import("chat_key.zig");
const Utf8Text = outbox.Str;

const App = struct {
    outbox_load_failed: bool = false,
    unified_storage_blocked: bool = false,
    hub_account: Utf8Text(32) = .{},
    cache_tag: Utf8Text(32) = .{},
    view_account: Utf8Text(32) = .{},
    unified_imports_clean: bool = true,
    unified_inflight: ?struct { id: [outbox.id_len]u8, attempt: u64 } = null,
    unified_unsaved_result: ?unified_snapshot.UnifiedOutcome = null,
    unified_result_lost: std.atomic.Value(bool) = .init(false),
    unified_refill_pending: bool = false,
    unified_refill_retry_at_ms: u64 = 0,
    attachment_available: bool = true,
    refill_calls: usize = 0,
    refill_fail: bool = false,
    unified_snapshot: ?*unified_snapshot.Snapshot = null,
    unified_candidate: ?*unified_snapshot.Snapshot = null,
    save_calls: usize = 0,
    fail_save_at: usize = 0,
    enqueue_calls: usize = 0,
    enqueue_allowed: bool = true,
    checkpoint_seen: bool = false,
    observed_job: ?WacliJob = null,
};

fn unifiedHub(_: *const App) bool { return true; }
fn hubConfigured(_: *const App) bool { return true; }
fn wacliPendingGet(_: *App, _: WacliJobKind) u32 { return 0; }
const win = struct { fn GetTickCount64() u64 { return 1_000; } };
fn unifiedOwnedFileAvailable(a: *App, _: *const unified_snapshot.Record) !bool { return a.attachment_available; }
fn refreshMessages(_: *App) void {}
fn refreshChats(_: *App) void {}
fn importUnifiedOutbox(a: *App) !void {
    a.refill_calls += 1;
    if (a.refill_fail) return error.RefillFailed;
    a.unified_imports_clean = true;
    a.unified_storage_blocked = false;
}
fn setStatus(_: *App, _: []const u8) void {}
fn refreshUnifiedViews(_: *App) void {}
fn saveUnifiedCandidate(a: *App) bool {
    a.save_calls += 1;
    if (a.save_calls == a.fail_save_at) return false;
    const old = a.unified_snapshot;
    a.unified_snapshot = a.unified_candidate;
    a.unified_candidate = old;
    return true;
}
fn wacliEnqueue(a: *App, job: WacliJob, _: bool) bool {
    a.enqueue_calls += 1;
    a.observed_job = job;
    const owner = a.unified_inflight orelse return false;
    for (a.unified_snapshot.?.records[0..a.unified_snapshot.?.count]) |*record| {
        if (!std.mem.eql(u8, record.entry.idSlice(), job.msg_id.slice())) continue;
        a.checkpoint_seen = record.phase == .uncertain and record.attempt_serial == job.gen and
            owner.attempt == job.gen and std.mem.eql(u8, &owner.id, job.msg_id.slice());
    }
    return a.enqueue_allowed;
}

const Fixture = struct {
    a: *App,
    first: *unified_snapshot.Snapshot,
    second: *unified_snapshot.Snapshot,
    fn init() !Fixture {
        const first = try std.testing.allocator.create(unified_snapshot.Snapshot);
        errdefer std.testing.allocator.destroy(first);
        const second = try std.testing.allocator.create(unified_snapshot.Snapshot);
        errdefer std.testing.allocator.destroy(second);
        const a = try std.testing.allocator.create(App);
        first.* = .{};
        second.* = .{};
        first.backend.set("https://example.invalid:443");
        const r = &first.records[0];
        r.entry.id = [_]u8{'a'} ** outbox.id_len;
        r.entry.provider = .slack;
        r.entry.account.set("workspace-a");
        r.entry.jid.set("slack:workspace-a:channel");
        r.entry.text.set("caption");
        r.entry.reply_to.set("reply-id");
        r.entry.reply_sender.set("sender");
        r.entry.file.set("C:\\original\\voice.ogg");
        r.entry.ptt = true;
        r.entry.voice_seconds = 7;
        r.phase = .ready;
        r.attempt_serial = 41;
        r.owned_file.set("C:\\private\\voice.ogg");
        r.wire_filename.set("saved-name.ogg");
        r.file_sha256 = [_]u8{0xab} ** 32;
        r.file_bytes = 42;
        r.attachment_ready = true;
        first.count = 1;
        a.* = .{ .unified_snapshot = first, .unified_candidate = second };
        a.hub_account.set("hub");
        return .{ .a = a, .first = first, .second = second };
    }
    fn deinit(self: Fixture) void {
        std.testing.allocator.destroy(self.a);
        std.testing.allocator.destroy(self.first);
        std.testing.allocator.destroy(self.second);
    }
};

test "checkpoint precedes enqueue and job captures immutable intent" {
    const f = try Fixture.init();
    defer f.deinit();
    beginUnifiedSend(f.a, 100);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
    try std.testing.expect(f.a.checkpoint_seen);
    const job = f.a.observed_job.?;
    try std.testing.expectEqual(@as(u64, 42), job.gen);
    try std.testing.expectEqual(transport.Provider.slack, job.provider);
    try std.testing.expectEqualStrings("workspace-a", job.account.slice());
    try std.testing.expectEqualStrings("slack:workspace-a:channel", job.jid.slice());
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", job.msg_id.slice());
    try std.testing.expectEqualStrings("caption", job.args[0].slice());
    try std.testing.expectEqualStrings("C:\\private\\voice.ogg", job.args[1].slice());
    try std.testing.expectEqualStrings("reply-id", job.args[2].slice());
    try std.testing.expectEqualStrings("true", job.args[3].slice());
    try std.testing.expectEqualStrings("saved-name.ogg", job.unified_filename.slice());
    try std.testing.expectEqual(@as(u64, 42), job.unified_file_bytes);
    try std.testing.expectEqualSlices(u8, &([_]u8{0xab} ** 32), &job.unified_file_sha256);
    try std.testing.expectEqualStrings("sender", f.a.unified_snapshot.?.records[0].entry.reply_sender.slice());
    try std.testing.expectEqual(@as(u32, 7), f.a.unified_snapshot.?.records[0].entry.voice_seconds);
    beginUnifiedSend(f.a, 200);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
}

test "failed checkpoint makes no enqueue" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.fail_save_at = 1;
    beginUnifiedSend(f.a, 100);
    try std.testing.expectEqual(@as(usize, 0), f.a.enqueue_calls);
    try std.testing.expectEqual(unified_snapshot.Phase.ready, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expect(f.a.unified_storage_blocked);
}

test "attempt serial overflow makes no enqueue" {
    const f = try Fixture.init();
    defer f.deinit();
    f.first.records[0].attempt_serial = std.math.maxInt(u64);
    beginUnifiedSend(f.a, 100);
    try std.testing.expectEqual(@as(usize, 0), f.a.enqueue_calls);
    try std.testing.expectEqual(@as(usize, 0), f.a.save_calls);
    try std.testing.expect(f.a.unified_storage_blocked);
}

test "enqueue refusal restores ready only after durable save" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.enqueue_allowed = false;
    beginUnifiedSend(f.a, 100);
    try std.testing.expect(f.a.checkpoint_seen);
    try std.testing.expectEqual(@as(usize, 2), f.a.save_calls);
    try std.testing.expectEqual(unified_snapshot.Phase.ready, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expectEqual(@as(u64, 42), f.a.unified_snapshot.?.records[0].attempt_serial);
    try std.testing.expect(f.a.unified_inflight == null);
}

test "failed enqueue rollback keeps uncertainty blocked" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.enqueue_allowed = false;
    f.a.fail_save_at = 2;
    beginUnifiedSend(f.a, 100);
    try std.testing.expectEqual(unified_snapshot.Phase.uncertain, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expect(f.a.unified_storage_blocked);
    beginUnifiedSend(f.a, 200);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
}

test "barrier and backoff prevent checkpoint" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.unified_imports_clean = false;
    beginUnifiedSend(f.a, 100);
    f.a.unified_imports_clean = true;
    f.first.records[0].not_before_ms = 101;
    beginUnifiedSend(f.a, 100);
    try std.testing.expectEqual(@as(usize, 0), f.a.save_calls);
    try std.testing.expectEqual(@as(usize, 0), f.a.enqueue_calls);
}


test "only unowned uncertainty permits explicit retry" {
    const f = try Fixture.init();
    defer f.deinit();
    f.first.records[0].phase = .uncertain;
    f.a.unified_inflight = .{ .id = f.first.records[0].entry.id, .attempt = 41 };
    const key = chat_key.Key{ .provider = .slack, .account = "workspace-a", .id = "slack:workspace-a:channel" };
    try std.testing.expectError(error.InFlight, retryUnifiedSend(f.a, f.first.records[0].entry.idSlice(), key));
    try std.testing.expectEqual(@as(usize, 0), f.a.save_calls);
    f.a.unified_inflight = null;
    const wrong = chat_key.Key{ .provider = .slack, .account = "other", .id = key.id };
    try std.testing.expectError(error.IntentNotFound, retryUnifiedSend(f.a, f.first.records[0].entry.idSlice(), wrong));
    try retryUnifiedSend(f.a, f.first.records[0].entry.idSlice(), key);
    try std.testing.expectEqual(unified_snapshot.Phase.ready, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expectEqual(@as(u64, 41), f.a.unified_snapshot.?.records[0].attempt_serial);
}


fn completedResult(_: Fixture, ok: bool, status: u32) WacliResult {
    var result = WacliResult{ .kind = .hub_send, .provider = .slack, .gen = 42, .ok = ok, .http_status = status };
    result.msg_id.set("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    return result;
}

test "failed acknowledgement save keeps one blocked outcome" {
    const f = try Fixture.init();
    defer f.deinit();
    beginUnifiedSend(f.a, 100);
    f.a.fail_save_at = 2;
    const result = completedResult(f, true, 200);
    finishUnifiedSend(f.a, &result);
    try std.testing.expectEqual(@as(usize, 1), f.a.unified_snapshot.?.count);
    try std.testing.expectEqual(unified_snapshot.Phase.uncertain, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expect(f.a.unified_unsaved_result != null and f.a.unified_storage_blocked);
    try std.testing.expect(f.a.unified_inflight == null);
    const key = chat_key.Key{ .provider = .slack, .account = "workspace-a", .id = "slack:workspace-a:channel" };
    try std.testing.expectError(error.OutboxUnavailable, retryUnifiedSend(f.a, f.a.unified_snapshot.?.records[0].entry.idSlice(), key));
    beginUnifiedSend(f.a, 101);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
    tickUnifiedOutbox(f.a);
    try std.testing.expectEqual(@as(usize, 0), f.a.unified_snapshot.?.count);
    try std.testing.expect(f.a.unified_unsaved_result == null);
    try std.testing.expectEqual(@as(usize, 1), f.a.refill_calls);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
}

test "failed terminal save preserves uncertainty until retry" {
    const f = try Fixture.init();
    defer f.deinit();
    beginUnifiedSend(f.a, 100);
    f.a.fail_save_at = 2;
    const result = completedResult(f, false, 403);
    finishUnifiedSend(f.a, &result);
    try std.testing.expectEqual(unified_snapshot.Phase.uncertain, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expect(f.a.unified_unsaved_result != null and f.a.unified_storage_blocked);
    tickUnifiedOutbox(f.a);
    try std.testing.expectEqual(unified_snapshot.Phase.held, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
}

test "stale result never retires active intent" {
    const f = try Fixture.init();
    defer f.deinit();
    beginUnifiedSend(f.a, 100);
    var result = completedResult(f, true, 200);
    result.gen = 41;
    finishUnifiedSend(f.a, &result);
    result.gen = 42;
    result.msg_id.set("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    finishUnifiedSend(f.a, &result);
    try std.testing.expectEqual(@as(usize, 1), f.a.unified_snapshot.?.count);
    try std.testing.expect(f.a.unified_inflight != null);
    try std.testing.expectEqual(@as(usize, 1), f.a.save_calls);
}

test "retryable result commits ambiguity and bounded backoff" {
    const f = try Fixture.init();
    defer f.deinit();
    beginUnifiedSend(f.a, 100);
    const result = completedResult(f, false, 409);
    finishUnifiedSend(f.a, &result);
    const record = &f.a.unified_snapshot.?.records[0];
    try std.testing.expectEqual(unified_snapshot.Phase.ready, record.phase);
    try std.testing.expect(record.entry.ambiguous);
    try std.testing.expectEqual(@as(u8, 1), record.entry.attempts);
    try std.testing.expectEqual(@as(u64, 4_000), record.not_before_ms);
}

test "missing file is held before later text dispatch" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.attachment_available = false;
    const text = &f.first.records[1];
    text.* = .{};
    text.entry.id = [_]u8{'b'} ** outbox.id_len;
    text.entry.provider = .slack;
    text.entry.account.set("workspace-a");
    text.entry.jid.set("slack:workspace-a:channel");
    text.entry.text.set("later text");
    text.phase = .ready;
    f.first.count = 2;
    beginUnifiedSend(f.a, 100);
    try std.testing.expectEqual(unified_snapshot.Phase.held, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expectEqual(@as(usize, 0), f.a.enqueue_calls);
    beginUnifiedSend(f.a, 101);
    try std.testing.expect(f.a.checkpoint_seen);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
    try std.testing.expectEqualStrings("later text", f.a.observed_job.?.args[0].slice());
}

test "lost worker result becomes durable held uncertainty" {
    const f = try Fixture.init();
    defer f.deinit();
    beginUnifiedSend(f.a, 100);
    f.a.unified_result_lost.store(true, .release);
    tickUnifiedOutbox(f.a);
    try std.testing.expectEqual(unified_snapshot.Phase.held, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expect(f.a.unified_snapshot.?.records[0].entry.ambiguous);
    try std.testing.expect(f.a.unified_inflight == null);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
}

test "failed fourth-attempt save keeps full uncertain intent" {
    const f = try Fixture.init();
    defer f.deinit();
    f.first.records[0].entry.attempts = 3;
    beginUnifiedSend(f.a, 100);
    f.a.fail_save_at = 2;
    const result = completedResult(f, false, 503);
    finishUnifiedSend(f.a, &result);
    try std.testing.expectEqual(unified_snapshot.Phase.uncertain, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expectEqualStrings("reply-id", f.a.unified_snapshot.?.records[0].entry.reply_to.slice());
    try std.testing.expectEqualStrings("saved-name.ogg", f.a.unified_snapshot.?.records[0].wire_filename.slice());
    try std.testing.expect(f.a.unified_unsaved_result != null and f.a.unified_storage_blocked);
    tickUnifiedOutbox(f.a);
    try std.testing.expectEqual(unified_snapshot.Phase.held, f.a.unified_snapshot.?.records[0].phase);
    try std.testing.expectEqual(@as(u8, 4), f.a.unified_snapshot.?.records[0].entry.attempts);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
}

test "failed missing-attachment hold blocks later sends" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.attachment_available = false;
    f.a.fail_save_at = 1;
    beginUnifiedSend(f.a, 100);
    try std.testing.expect(f.a.unified_storage_blocked);
    try std.testing.expectEqual(unified_snapshot.Phase.ready, f.a.unified_snapshot.?.records[0].phase);
    beginUnifiedSend(f.a, 101);
    try std.testing.expectEqual(@as(usize, 0), f.a.enqueue_calls);
}


test "failed source refill blocks later dispatch" {
    const f = try Fixture.init();
    defer f.deinit();
    beginUnifiedSend(f.a, 100);
    f.a.refill_fail = true;
    const result = completedResult(f, true, 200);
    finishUnifiedSend(f.a, &result);
    try std.testing.expectEqual(@as(usize, 0), f.a.unified_snapshot.?.count);
    try std.testing.expect(f.a.unified_refill_pending and f.a.unified_storage_blocked);
    try std.testing.expect(!f.a.unified_imports_clean);
    beginUnifiedSend(f.a, 20_000);
    try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
}

test "retry and dispatch retain source account across view switches" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.cache_tag.set("hub-cache");
    f.a.view_account.set("different-display");
    const first = &f.first.records[0];
    first.phase = .held;
    first.entry.provider = .whatsapp;
    first.entry.account.set("personal");
    first.entry.jid.set("same-contact");
    first.entry.file.set("");
    first.entry.ptt = false;
    first.entry.voice_seconds = 0;
    first.owned_file.set("");
    first.wire_filename.set("");
    first.file_sha256 = @splat(0);
    first.file_bytes = 0;
    first.attachment_ready = false;
    const second = &f.first.records[1];
    second.* = first.*;
    second.entry.id = [_]u8{'b'} ** outbox.id_len;
    second.entry.account.set("business");
    f.first.count = 2;
    const wrong = chat_key.Key{ .provider = .whatsapp, .account = "business", .id = "same-contact" };
    try std.testing.expectError(error.IntentNotFound, retryUnifiedSend(f.a, first.entry.idSlice(), wrong));
    const right = chat_key.Key{ .provider = .whatsapp, .account = "personal", .id = "same-contact" };
    try retryUnifiedSend(f.a, first.entry.idSlice(), right);
    beginUnifiedSend(f.a, 100);
    const job = f.a.observed_job.?;
    try std.testing.expectEqualStrings("personal", job.account.slice());
    try std.testing.expectEqualStrings("same-contact", job.jid.slice());
    try std.testing.expectEqualStrings("reply-id", job.args[2].slice());
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", job.msg_id.slice());
}

test "slack workspaces retain retry account and thread reply" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.cache_tag.set("hub-cache");
    f.a.view_account.set("workspace-b");
    f.first.records[0].phase = .held;
    try retryUnifiedSend(f.a, f.first.records[0].entry.idSlice(), .{ .provider = .slack, .account = "workspace-a", .id = "slack:workspace-a:channel" });
    beginUnifiedSend(f.a, 100);
    try std.testing.expectEqualStrings("workspace-a", f.a.observed_job.?.account.slice());
    try std.testing.expectEqualStrings("reply-id", f.a.observed_job.?.args[2].slice());
}

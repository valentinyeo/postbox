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
    unified_imports_clean: bool = true,
    unified_inflight: ?struct { id: [outbox.id_len]u8, attempt: u64 } = null,
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
fn unifiedOwnedFileAvailable(_: *App, _: *const unified_snapshot.Record) !bool { return true; }
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
    const record = &a.unified_snapshot.?.records[0];
    const owner = a.unified_inflight orelse return false;
    a.checkpoint_seen = record.phase == .uncertain and record.attempt_serial == job.gen and
        owner.attempt == job.gen and std.mem.eql(u8, &owner.id, job.msg_id.slice());
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

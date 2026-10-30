const std = @import("std");
const outbox = @import("outbox.zig");
const unified_snapshot = @import("unified_snapshot.zig");
const transport = @import("transport.zig");
const chat_key = @import("chat_key.zig");
const Utf8Text = outbox.Str;
var verification_fixture = true;
var disk: [unified_snapshot.max_document_bytes]u8 = undefined;
var disk_len: usize = 0;
var temp: [unified_snapshot.max_document_bytes]u8 = undefined;
var temp_len: usize = 0;

const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    unified_snapshot_path: []const u8 = "C:\\profile\\snapshot.v2",
    unified_write_fault: enum { none, open, write, flush, close, replace } = .none,
    unified_fault_transition: UnifiedFaultTransition = .any,
    unified_fault_attempt: u64 = 0,
    unified_fault_active: bool = false,
    unified_fault_hits: u64 = 0,
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
const win = struct {
    fn GetTickCount64() u64 { return 1_000; }
    const DWORD = u32;
    const INVALID_HANDLE_VALUE: ?usize = 99;
    const GENERIC_WRITE = 1;
    const CREATE_ALWAYS = 2;
    const FILE_ATTRIBUTE_NORMAL = 0;
    const MOVEFILE_REPLACE_EXISTING = 1;
    const MOVEFILE_WRITE_THROUGH = 2;
    fn CreateFileW(_: [*:0]const u16, _: u32, _: u32, _: ?usize, _: u32, _: u32, _: ?usize) ?usize {
        temp_len = 0;
        return 1;
    }
    fn WriteFile(_: ?usize, data: [*]const u8, length: u32, written: *DWORD, _: ?usize) u32 {
        const n = @min(length, 17);
        @memcpy(temp[temp_len..][0..n], data[0..n]);
        temp_len += n;
        written.* = n;
        return 1;
    }
    fn FlushFileBuffers(_: ?usize) u32 { return 1; }
    fn CloseHandle(_: ?usize) u32 { return 1; }
    fn DeleteFileW(_: [*:0]const u16) u32 { return 1; }
    fn MoveFileExW(_: [*:0]const u16, _: [*:0]const u16, flags: u32) u32 {
        if (flags != (MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) return 0;
        @memcpy(disk[0..temp_len], temp[0..temp_len]);
        disk_len = temp_len;
        return 1;
    }
};
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
        disk_len = 0;
        temp_len = 0;
        verification_fixture = true;
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

fn seed(f: Fixture) !void {
    f.a.unified_candidate.?.* = f.a.unified_snapshot.?.*;
    try std.testing.expect(saveUnifiedCandidate(f.a, .any, 0));
}

fn assertDurable(f: Fixture, phase: unified_snapshot.Phase, expected: *const unified_snapshot.Record, bytes: []const u8) !void {
    try std.testing.expectEqualSlices(u8, bytes, disk[0..disk_len]);
    const decoded = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(decoded);
    try unified_snapshot.decode(std.testing.allocator, disk[0..disk_len], f.a.unified_snapshot.?.backend.slice(), decoded);
    try std.testing.expectEqual(@as(usize, 1), decoded.count);
    try std.testing.expectEqual(phase, decoded.records[0].phase);
    try std.testing.expect(unified_snapshot.sameIntent(expected, &decoded.records[0]));
    try std.testing.expectEqualStrings(expected.owned_file.slice(), decoded.records[0].owned_file.slice());
}

test "targeted checkpoint faults preserve durable ready and enqueue nothing" {
    inline for (.{ .open, .write, .flush, .close, .replace }) |stage| {
        const f = try Fixture.init();
        defer f.deinit();
        f.a.unified_write_fault = stage;
        f.a.unified_fault_transition = .checkpoint;
        f.a.unified_fault_attempt = 42;
        try seed(f);
        try std.testing.expectEqual(@as(u64, 0), f.a.unified_fault_hits);
        const expected = f.a.unified_snapshot.?.records[0];
        const bytes = try std.testing.allocator.dupe(u8, disk[0..disk_len]);
        defer std.testing.allocator.free(bytes);
        beginUnifiedSend(f.a, 100);
        try std.testing.expectEqual(@as(u64, 1), f.a.unified_fault_hits);
        try std.testing.expect(f.a.unified_storage_blocked and f.a.unified_unsaved_result == null);
        try std.testing.expectEqual(@as(usize, 0), f.a.enqueue_calls);
        try assertDurable(f, .ready, &expected, bytes);
        tickUnifiedOutbox(f.a);
        try std.testing.expectEqual(@as(usize, 0), f.a.enqueue_calls);
        try assertDurable(f, .ready, &expected, bytes);
    }
}

test "fourth retryable exhaustion repeatedly fails held save" {
    inline for (.{ .open, .write, .flush, .close, .replace }) |stage| {
        const f = try Fixture.init();
        defer f.deinit();
        f.first.records[0].attempt_serial = 3;
        f.first.records[0].entry.attempts = 3;
        f.first.records[0].entry.ambiguous = true;
        f.a.unified_write_fault = stage;
        f.a.unified_fault_transition = .held;
        f.a.unified_fault_attempt = 4;
        try seed(f);
        beginUnifiedSend(f.a, 100);
        try std.testing.expect(f.a.checkpoint_seen);
        try std.testing.expectEqual(@as(u64, 0), f.a.unified_fault_hits);
        const expected = f.a.unified_snapshot.?.records[0];
        const bytes = try std.testing.allocator.dupe(u8, disk[0..disk_len]);
        defer std.testing.allocator.free(bytes);
        var result = WacliResult{ .kind = .hub_send, .provider = .slack, .gen = 4, .ok = false, .http_status = 409 };
        result.msg_id.set("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        finishUnifiedSend(f.a, &result);
        try std.testing.expect(f.a.unified_unsaved_result.?.kind == .retryable);
        try std.testing.expect(f.a.unified_storage_blocked and f.a.unified_inflight == null);
        const key = chat_key.Key{ .provider = .slack, .account = "workspace-a", .id = "slack:workspace-a:channel" };
        try std.testing.expectError(error.OutboxUnavailable, retryUnifiedSend(f.a, expected.entry.idSlice(), key));
        for (0..2) |_| tickUnifiedOutbox(f.a);
        try std.testing.expectEqual(@as(u64, 3), f.a.unified_fault_hits);
        try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
        try std.testing.expect(f.a.unified_unsaved_result != null and f.a.unified_storage_blocked);
        try assertDurable(f, .uncertain, &expected, bytes);
        f.a.unified_write_fault = .none;
        tickUnifiedOutbox(f.a);
        try std.testing.expect(f.a.unified_unsaved_result == null);
        try std.testing.expectEqual(unified_snapshot.Phase.held, f.a.unified_snapshot.?.records[0].phase);
        try std.testing.expectEqual(@as(u8, 4), f.a.unified_snapshot.?.records[0].entry.attempts);
    }
}

test "acknowledgement removal repeatedly fails without retiring intent" {
    inline for (.{ .open, .write, .flush, .close, .replace }) |stage| {
        const f = try Fixture.init();
        defer f.deinit();
        f.a.unified_write_fault = stage;
        f.a.unified_fault_transition = .acknowledged;
        f.a.unified_fault_attempt = 42;
        try seed(f);
        beginUnifiedSend(f.a, 100);
        try std.testing.expect(f.a.checkpoint_seen);
        const expected = f.a.unified_snapshot.?.records[0];
        const bytes = try std.testing.allocator.dupe(u8, disk[0..disk_len]);
        defer std.testing.allocator.free(bytes);
        var result = WacliResult{ .kind = .hub_send, .provider = .slack, .gen = 42, .ok = true, .http_status = 200 };
        result.msg_id.set("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        finishUnifiedSend(f.a, &result);
        for (0..2) |_| tickUnifiedOutbox(f.a);
        try std.testing.expectEqual(@as(u64, 3), f.a.unified_fault_hits);
        try std.testing.expectEqual(@as(usize, 1), f.a.enqueue_calls);
        try std.testing.expect(f.a.unified_unsaved_result != null and f.a.unified_storage_blocked and f.a.unified_inflight == null);
        const key = chat_key.Key{ .provider = .slack, .account = "workspace-a", .id = "slack:workspace-a:channel" };
        try std.testing.expectError(error.OutboxUnavailable, retryUnifiedSend(f.a, expected.entry.idSlice(), key));
        try assertDurable(f, .uncertain, &expected, bytes);
        f.a.unified_write_fault = .none;
        tickUnifiedOutbox(f.a);
        try std.testing.expectEqual(@as(usize, 0), f.a.unified_snapshot.?.count);
        try std.testing.expect(f.a.unified_unsaved_result == null);
    }
}

test "held transition with wrong attempt is not faulted" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.unified_write_fault = .replace;
    f.a.unified_fault_transition = .held;
    f.a.unified_fault_attempt = 4;
    try seed(f);
    f.a.unified_candidate.?.* = f.a.unified_snapshot.?.*;
    f.a.unified_candidate.?.records[0].phase = .held;
    try std.testing.expect(saveUnifiedCandidate(f.a, .held, 3));
    try std.testing.expectEqual(@as(u64, 0), f.a.unified_fault_hits);
    try std.testing.expectEqual(unified_snapshot.Phase.held, f.a.unified_snapshot.?.records[0].phase);
}

test "wrong transition or attempt and production do not inject" {
    const f = try Fixture.init();
    defer f.deinit();
    f.a.unified_write_fault = .replace;
    f.a.unified_fault_transition = .checkpoint;
    f.a.unified_fault_attempt = 43;
    try seed(f);
    beginUnifiedSend(f.a, 100);
    try std.testing.expect(f.a.checkpoint_seen);
    try std.testing.expectEqual(@as(u64, 0), f.a.unified_fault_hits);
    var result = WacliResult{ .kind = .hub_send, .provider = .slack, .gen = 42, .ok = true, .http_status = 200 };
    result.msg_id.set("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    finishUnifiedSend(f.a, &result);
    try std.testing.expectEqual(@as(usize, 0), f.a.unified_snapshot.?.count);
    try std.testing.expectEqual(@as(u64, 0), f.a.unified_fault_hits);
    f.a.unified_candidate.?.* = f.a.unified_snapshot.?.*;
    verification_fixture = false;
    defer verification_fixture = true;
    f.a.unified_fault_attempt = 42;
    try std.testing.expect(saveUnifiedCandidate(f.a, .checkpoint, 42));
    try std.testing.expectEqual(@as(u64, 0), f.a.unified_fault_hits);
}

const std = @import("std");
const outbox = @import("outbox.zig");
const unified_snapshot = @import("unified_snapshot.zig");
const transport = @import("transport.zig");
const chat_key = @import("chat_key.zig");
const staged_images = @import("staged_images.zig");
const drafts = struct {
    const max_text = 64 * 1024;
};
const wa_hub = struct {
    const max_file_bytes = 64 * 1024 * 1024;
};
const Utf8Text = outbox.Str;
var verification_fixture = true;
var disk: [unified_snapshot.max_document_bytes]u8 = undefined;
var disk_len: usize = 0;
var temp: [unified_snapshot.max_document_bytes]u8 = undefined;
var temp_len: usize = 0;
var read_position: usize = 0;
var before_disk: [unified_snapshot.max_document_bytes]u8 = undefined;
var before_len: usize = 0;

fn captureVerificationCheckpointBefore(a: *App, _: []const u8) void {
    if (!verification_fixture or a.unified_fault_transition != .checkpoint) return;
    @memcpy(before_disk[0..disk_len], disk[0..disk_len]);
    before_len = disk_len;
}

const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    compose: ?usize = 1,
    thread_compose: ?usize = null,
    thread_parent: Utf8Text(191) = .{},
    thread_origin: chat_key.Stored = .{},
    chat_view: u8 = 0,
    show_archived: bool = false,
    chat_count: usize = 1,
    selected_chat: usize = 0,
    chats: [1]struct { provider: transport.Provider = .whatsapp, account: Utf8Text(32) = .{}, jid: Utf8Text(191) = .{} } = .{.{}},
    reply_to: Utf8Text(191) = .{},
    reply_sender: Utf8Text(191) = .{},
    staged_images: staged_images.List(struct { provider: transport.Provider = .whatsapp, account: Utf8Text(32) = .{}, jid: Utf8Text(191) = .{}, path: Utf8Text(519) = .{} }) = .{},
    pending_sends: [max_pending_sends]struct { id: [outbox.id_len]u8 = @splat('0') } = @splat(.{}),
    pending_send_count: usize = 0,
    user_viewed: bool = false,
    scroll_y: i32 = 0,
    compose_client_width: i32 = 0,
    compose_client_height: i32 = 0,
    hwnd: ?usize = null,
    unified_snapshot_path: []const u8 = "C:/profile/snapshot.v2",
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

var compose_text: [4096]u16 = @splat(0);
var compose_len: usize = 0;
var next_id: u8 = 1;
var protected_writes: usize = 0;
var fail_protected_write = false;
fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
fn mintSendId(_: *App, id: *[outbox.id_len]u8) void {
    id.* = outbox.hexId(@splat(next_id));
    next_id += 1;
}
fn nowUnixSeconds() i64 {
    return 42;
}
fn unifiedReadAttachment(a: *App, _: []const u8) !?[]u8 {
    return try a.allocator.dupe(u8, "fixture attachment");
}
fn unifiedWriteProtected(_: *App, path: []const u8, data: []const u8) !void {
    if (fail_protected_write) return error.WriteFailed;
    std.debug.assert(std.mem.endsWith(u8, path, "/payload"));
    std.debug.assert(std.mem.eql(u8, data, "fixture attachment"));
    protected_writes += 1;
}
fn appendWhatsAppPending(_: *App, _: anytype, _: bool) void {}
fn discardStagedImage(a: *App) void {
    a.staged_images.clear();
}
fn clearReply(a: *App) void {
    a.reply_to = .{};
    a.reply_sender = .{};
}
fn saveComposerDraft(_: *App) void {}
fn layout(_: *App, _: i32, _: i32) void {}
fn focusCompose(_: *App) void {}
fn setCompose(text: []const u8) void {
    compose_len = std.unicode.utf8ToUtf16Le(&compose_text, text) catch unreachable;
}

fn unifiedHub(_: *const App) bool {
    return true;
}
fn hubConfigured(_: *const App) bool {
    return true;
}
fn wacliPendingGet(_: *App, _: WacliJobKind) u32 {
    return 0;
}
const win = struct {
    fn GetTickCount64() u64 {
        return 1_000;
    }
    const FALSE = 0;
    fn GetWindowTextW(_: usize, buffer: []u16, capacity: usize) i32 {
        const len = @min(compose_len, capacity - 1);
        @memcpy(buffer[0..len], compose_text[0..len]);
        return @intCast(len);
    }
    fn SetWindowTextW(_: usize, _: [*:0]const u16) u32 {
        compose_len = 0;
        return 1;
    }
    fn SetFocus(_: usize) ?usize {
        return null;
    }
    fn InvalidateRect(_: usize, _: ?usize, _: u32) u32 {
        return 1;
    }
    const DWORD = u32;
    const INVALID_HANDLE_VALUE: ?usize = 99;
    const GENERIC_WRITE = 1;
    const GENERIC_READ = 2;
    const FILE_SHARE_READ = 1;
    const OPEN_EXISTING = 3;
    const ERROR_FILE_NOT_FOUND = 2;
    const LARGE_INTEGER = struct { QuadPart: i64 };
    const CREATE_ALWAYS = 2;
    const FILE_ATTRIBUTE_NORMAL = 0;
    const MOVEFILE_REPLACE_EXISTING = 1;
    const MOVEFILE_WRITE_THROUGH = 2;
    fn CreateFileW(_: [*:0]const u16, access: u32, _: u32, _: ?usize, _: u32, _: u32, _: ?usize) ?usize {
        if (access == GENERIC_READ) {
            read_position = 0;
            return if (disk_len == 0) INVALID_HANDLE_VALUE else 2;
        }
        temp_len = 0;
        return 1;
    }
    fn GetLastError() u32 {
        return ERROR_FILE_NOT_FOUND;
    }
    fn GetFileSizeEx(_: ?usize, size: *LARGE_INTEGER) u32 {
        size.QuadPart = @intCast(disk_len);
        return 1;
    }
    fn ReadFile(_: ?usize, bytes: [*]u8, len: u32, got: *DWORD, _: ?usize) u32 {
        const count = @min(@min(len, 17), disk_len - read_position);
        @memcpy(bytes[0..count], disk[read_position..][0..count]);
        read_position += count;
        got.* = @intCast(count);
        return 1;
    }
    fn WriteFile(_: ?usize, data: [*]const u8, length: u32, written: *DWORD, _: ?usize) u32 {
        const n = @min(length, 17);
        @memcpy(temp[temp_len..][0..n], data[0..n]);
        temp_len += n;
        written.* = n;
        return 1;
    }
    fn FlushFileBuffers(_: ?usize) u32 {
        return 1;
    }
    fn CloseHandle(_: ?usize) u32 {
        return 1;
    }
    fn DeleteFileW(_: [*:0]const u16) u32 {
        return 1;
    }
    fn MoveFileExW(_: [*:0]const u16, _: [*:0]const u16, flags: u32) u32 {
        if (flags != (MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) return 0;
        @memcpy(disk[0..temp_len], temp[0..temp_len]);
        disk_len = temp_len;
        return 1;
    }
};
fn unifiedNoReparse(_: *App, _: []const u8) !bool {
    return true;
}
fn rebuildUnifiedViews(a: *App, _: *const [outbox.max_entries]bool) void {
    refreshUnifiedViews(a);
}
fn unifiedOwnedFileAvailable(a: *App, _: *const unified_snapshot.Record) !bool {
    return a.attachment_available;
}
fn refreshMessages(_: *App) void {}
fn refreshChats(_: *App) void {}
fn importUnifiedOutbox(a: *App) !void {
    a.refill_calls += 1;
    if (a.refill_fail) return error.RefillFailed;
    a.unified_imports_clean = true;
    a.unified_storage_blocked = false;
}
fn setStatus(_: *App, _: []const u8) void {}
fn refreshUnifiedViews(a: *App) void {
    const snapshot = a.unified_snapshot orelse return;
    a.pending_send_count = 0;
    for (snapshot.records[0..snapshot.count]) |*record| {
        if (record.phase != .ready or a.pending_send_count == max_pending_sends) continue;
        a.pending_sends[a.pending_send_count].id = record.entry.id;
        a.pending_send_count += 1;
    }
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
        disk_len = 0;
        temp_len = 0;
        before_len = 0;
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
        if (f.a.unified_write_fault == .replace) {
            try std.testing.expectEqualSlices(u8, bytes, before_disk[0..before_len]);
        } else try std.testing.expectEqual(@as(usize, 0), before_len);
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
        try std.testing.expectEqual(@as(usize, 0), before_len);
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
        try std.testing.expectEqual(@as(usize, 0), before_len);
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

fn prepareAdmission(f: Fixture, provider: transport.Provider) void {
    f.first.count = 0;
    f.a.chats[0].provider = provider;
    f.a.chats[0].account.set("synthetic-account");
    f.a.chats[0].jid.set("synthetic-chat");
    compose_len = 0;
    next_id = 1;
    protected_writes = 0;
    fail_protected_write = false;
}

fn decodedSnapshot(f: Fixture) !*unified_snapshot.Snapshot {
    const live = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(live);
    const candidate = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(candidate);
    live.* = .{};
    candidate.* = .{};
    live.backend = f.a.unified_snapshot.?.backend;
    var restored = App{ .unified_snapshot = live, .unified_candidate = candidate };
    try restoreUnifiedOutbox(&restored);
    const decoded = try std.testing.allocator.create(unified_snapshot.Snapshot);
    decoded.* = restored.unified_snapshot.?.*;
    return decoded;
}

test "IGSH-531 hub outbox preserves every transport provider through restart" {
    for ([_]transport.Provider{ .whatsapp, .slack, .telegram }) |provider| {
        const f = try Fixture.init();
        defer f.deinit();
        prepareAdmission(f, provider);
        setCompose("synthetic text");
        sendUnifiedMessage(f.a, false);
        try std.testing.expectEqual(@as(usize, 0), compose_len);
        try std.testing.expectEqual(@as(usize, 1), f.a.pending_send_count);
        const restored = try decodedSnapshot(f);
        defer std.testing.allocator.destroy(restored);
        try std.testing.expectEqual(@as(usize, 1), restored.count);
        try std.testing.expectEqualStrings(@tagName(provider), @tagName(restored.records[0].entry.provider));
        try std.testing.expectEqualStrings("synthetic-account", restored.records[0].entry.account.slice());
        try std.testing.expectEqualStrings("synthetic-chat", restored.records[0].entry.jid.slice());
        try std.testing.expectEqualStrings("synthetic text", restored.records[0].entry.text.slice());
        try std.testing.expectEqual(unified_snapshot.Phase.ready, restored.records[0].phase);
    }
}

test "staged hub images keep order first caption and independent durable ids on every provider" {
    for ([_]transport.Provider{ .whatsapp, .slack, .signal, .telegram }) |provider| {
        const f = try Fixture.init();
        defer f.deinit();
        prepareAdmission(f, provider);
        for ([_][]const u8{ "first.png", "second.png", "third.png" }) |path| {
            var image = f.a.staged_images.items[0];
            image.provider = provider;
            image.account = f.a.chats[0].account;
            image.jid = f.a.chats[0].jid;
            image.path.set(path);
            try std.testing.expect(f.a.staged_images.add(image));
        }
        setCompose("caption");
        sendUnifiedMessage(f.a, false);
        try std.testing.expectEqual(@as(usize, 3), f.a.pending_send_count);
        try std.testing.expectEqual(@as(usize, 3), protected_writes);
        try std.testing.expectEqual(@as(usize, 0), f.a.staged_images.count);
        try std.testing.expectEqual(@as(usize, 0), compose_len);
        const restored = try decodedSnapshot(f);
        defer std.testing.allocator.destroy(restored);
        try std.testing.expectEqual(@as(usize, 3), restored.count);
        for (restored.records[0..3], [_][]const u8{ "first.png", "second.png", "third.png" }, 0..) |record, path, index| {
            try std.testing.expectEqualStrings(@tagName(provider), @tagName(record.entry.provider));
            try std.testing.expectEqualStrings("synthetic-account", record.entry.account.slice());
            try std.testing.expectEqualStrings("synthetic-chat", record.entry.jid.slice());
            try std.testing.expectEqualStrings(path, record.entry.file.slice());
            try std.testing.expectEqualStrings(path, record.wire_filename.slice());
            try std.testing.expectEqualStrings(if (index == 0) "caption" else "", record.entry.text.slice());
            try std.testing.expectEqual(unified_snapshot.Phase.ready, record.phase);
            try std.testing.expect(record.attachment_ready);
            try std.testing.expect(unified_snapshot.sameIntent(&f.a.unified_snapshot.?.records[index], &record));
            for (restored.records[0..index]) |earlier| try std.testing.expect(!std.mem.eql(u8, &earlier.entry.id, &record.entry.id));
        }
    }
}

test "IGSH-1213 a failing Slack head becomes held and releases the WhatsApp group send" {
    for ([_]u32{ 0, 200, 500, 502, 503 }) |status| {
        const f = try Fixture.init();
        defer f.deinit();
        prepareAdmission(f, .slack);
        f.a.chats[0].jid.set("slack:fixture:channel");
        setCompose("Synthetic failed send");
        sendUnifiedMessage(f.a, false);
        f.a.chats[0].provider = .whatsapp;
        f.a.chats[0].jid.set("personal:fixture-group@g.us");
        setCompose("group text");
        sendUnifiedMessage(f.a, false);
        try std.testing.expectEqual(@as(usize, 2), f.a.unified_snapshot.?.count);
        const first_id = f.a.unified_snapshot.?.records[0].entry.id;
        const group_id = f.a.unified_snapshot.?.records[1].entry.id;
        for (0..4) |attempt| {
            beginUnifiedSend(f.a, @as(u64, @intCast(attempt + 1)) * 100_000);
            const job = f.a.observed_job.?;
            try std.testing.expectEqualSlices(u8, &first_id, job.msg_id.slice());
            var result = WacliResult{ .kind = .hub_send, .provider = .slack, .gen = job.gen, .http_status = status };
            result.msg_id.set(job.msg_id.slice());
            result.extra.set("NetworkFailed");
            finishUnifiedSend(f.a, &result);
        }
        try std.testing.expectEqual(unified_snapshot.Phase.held, f.a.unified_snapshot.?.records[0].phase);
        try std.testing.expectEqual(@as(u8, 4), f.a.unified_snapshot.?.records[0].entry.attempts);
        try std.testing.expectEqualStrings("personal:fixture-group@g.us", f.a.unified_snapshot.?.records[1].entry.jid.slice());
        beginUnifiedSend(f.a, 500_000);
        const group = f.a.observed_job.?;
        try std.testing.expectEqualSlices(u8, &group_id, group.msg_id.slice());
        try std.testing.expectEqualStrings("synthetic-account", group.account.slice());
        try std.testing.expectEqualStrings("personal:fixture-group@g.us", group.jid.slice());
        var ack = WacliResult{ .kind = .hub_send, .provider = .whatsapp, .gen = group.gen, .ok = true, .http_status = 200 };
        ack.msg_id.set(group.msg_id.slice());
        finishUnifiedSend(f.a, &ack);
        const restored = try decodedSnapshot(f);
        defer std.testing.allocator.destroy(restored);
        try std.testing.expectEqual(@as(usize, 1), restored.count);
        try std.testing.expectEqualSlices(u8, &first_id, &restored.records[0].entry.id);
        try std.testing.expectEqual(unified_snapshot.Phase.held, restored.records[0].phase);
    }
}

test "unified attachment staging failure retains draft and all staged images" {
    const f = try Fixture.init();
    defer f.deinit();
    prepareAdmission(f, .slack);
    for ([_][]const u8{ "first.png", "second.png" }) |path| {
        var image = f.a.staged_images.items[0];
        image.provider = f.a.chats[0].provider;
        image.account = f.a.chats[0].account;
        image.jid = f.a.chats[0].jid;
        image.path.set(path);
        try std.testing.expect(f.a.staged_images.add(image));
    }
    f.a.reply_to.set("reply-id");
    setCompose("caption");
    fail_protected_write = true;
    sendUnifiedMessage(f.a, false);
    try std.testing.expectEqual(@as(usize, 0), f.a.unified_snapshot.?.count);
    try std.testing.expectEqual(@as(usize, 2), f.a.staged_images.count);
    try std.testing.expectEqual(@as(usize, 7), compose_len);
    try std.testing.expectEqualStrings("reply-id", f.a.reply_to.slice());
    try std.testing.expectEqual(@as(usize, 0), f.a.enqueue_calls);
}

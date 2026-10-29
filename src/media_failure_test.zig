const std = @import("std");
const chat_key = @import("chat_key.zig");
const media_drain = @import("media_drain.zig");
const played = @import("played.zig");
const voice_sent = struct {
    fn needsDownload(local: bool) bool {
        return !local;
    }
};
const Message = struct {
    media_type: Utf8Text(15) = .{},
    id: Utf8Text(191) = .{},
    local_path: Utf8Text(255) = .{},
    media_size: u64 = 0,
};
const Chat = struct {
    account: Utf8Text(32) = .{},
    jid: Utf8Text(191) = .{},
    provider: enum { whatsapp, slack } = .whatsapp,
};
const win = struct {
    fn GetTickCount64() u64 {
        return 100_000;
    }
    fn UpdateWindow(_: usize) i32 {
        return 1;
    }
};
fn mediaDownloading(_: *const App, _: []const u8, _: []const u8) bool {
    return false;
}
fn freeMediaSlot(_: *App) ?usize {
    return 1;
}
fn avatarBusy(_: *const App) bool {
    return false;
}
fn startMediaDownload(a: *App, _: []const u8, _: []const u8) bool {
    a.started += 1;
    return true;
}
fn setStatus(_: *App, _: []const u8) void {}
fn fixture() App {
    var a = App{};
    a.chats[0].jid.set("chat@example.invalid");
    a.displayed_jid = a.chats[0].jid;
    a.messages[0].media_type.set("document");
    a.messages[0].id.set("attachment-id");
    return a;
}
fn failTerminally(a: *App, jid: []const u8, id: []const u8) void {
    for (0..max_media_retries) |_| noteMediaFailure(a, jid, id);
}

test "success suppression and transient failures are not terminal failures" {
    var a = fixture();
    const jid = a.chats[0].jid.slice();
    const id = a.messages[0].id.slice();
    markMediaAttempted(&a, jid, id);
    try std.testing.expect(mediaAttempted(&a, jid, id));
    try std.testing.expect(!mediaUnavailable(&a, jid, id));
    for (0..max_media_retries - 1) |_| {
        noteMediaFailure(&a, jid, id);
        try std.testing.expect(!mediaUnavailable(&a, jid, id));
    }
    try std.testing.expectEqual(@as(u64, 160_000), a.media_failures[0].retry_after_ms);
    noteMediaFailure(&a, jid, id);
    try std.testing.expect(mediaUnavailable(&a, jid, id));
    try std.testing.expect(!mediaUnavailable(&a, "other@example.invalid", id));
    try std.testing.expectEqual(@as(u8, 0), a.media_failures[0].count);
    try std.testing.expectEqual(if (media_drain.wazi_135) media_drain.AttachmentState.unavailable else .downloading, attachmentState(&a, &a.messages[0], false));
    try std.testing.expectEqual(media_drain.AttachmentState.local, attachmentState(&a, &a.messages[0], true));
    clearMediaFailure(&a, jid, id);
    try std.testing.expect(!mediaUnavailable(&a, jid, id));
    try std.testing.expect(mediaAttempted(&a, jid, id));
    media_drain.forgetAttempt(&a.media_attempts, &a.media_attempt_count, played.Set.pairKey(jid, id));
    try std.testing.expect(!mediaAttempted(&a, jid, id));
}

test "gone media waits out the bridge failure memory and other failures back off" {
    var a = fixture();
    const jid = a.chats[0].jid.slice();
    const id = a.messages[0].id.slice();
    noteMediaFailureStatus(&a, jid, id, 410);
    try std.testing.expectEqual(@as(u64, 100_000 + 15 * 60_000), a.media_failures[0].retry_after_ms);
    var b = fixture();
    noteMediaFailureStatus(&b, jid, id, 502);
    try std.testing.expectEqual(@as(u64, 100_000 + 30_000), b.media_failures[0].retry_after_ms);
    noteMediaFailureStatus(&b, jid, id, 502);
    try std.testing.expectEqual(@as(u64, 100_000 + 60_000), b.media_failures[0].retry_after_ms);
}

test "manual retry resets terminal failure before starting or queuing" {
    for ([_]bool{ false, true }) |busy| {
        var a = fixture();
        const jid = a.chats[0].jid.slice();
        const id = a.messages[0].id.slice();
        failTerminally(&a, jid, id);
        if (busy) a.send_child = 1;
        try std.testing.expect(downloadMedia(&a, 0, false));
        try std.testing.expectEqual(!media_drain.wazi_135, mediaUnavailable(&a, jid, id));
        try std.testing.expectEqual(!media_drain.wazi_135, mediaAttempted(&a, jid, id));
        if (busy) {
            try std.testing.expectEqualStrings(id, a.pending_download_id.slice());
            try std.testing.expectEqualStrings(jid, a.pending_download_jid.slice());
        } else try std.testing.expectEqual(@as(usize, 1), a.started);
        if (media_drain.wazi_135) {
            noteMediaFailure(&a, jid, id);
            try std.testing.expect(!mediaUnavailable(&a, jid, id));
            try std.testing.expectEqual(@as(u8, 1), a.media_failures[0].count);
        }
    }
}

test "full retry table falls back to terminal marking and marker storage stays bounded" {
    var a = fixture();
    for (&a.media_failures, 0..) |*entry, i| entry.* = .{ .hash = @intCast(i + 1), .count = 1 };
    noteMediaFailure(&a, "chat@example.invalid", "overflow-id");
    try std.testing.expect(mediaUnavailable(&a, "chat@example.invalid", "overflow-id"));
    try std.testing.expect(mediaAttempted(&a, "chat@example.invalid", "overflow-id"));
    for (0..a.media_unavailable.len + 1) |i| {
        var buffer: [32]u8 = undefined;
        const id = try std.fmt.bufPrint(&buffer, "attachment-{d}", .{i});
        markMediaUnavailable(&a, "chat@example.invalid", id);
        try std.testing.expect(a.media_unavailable_count <= a.media_unavailable.len);
        try std.testing.expect(mediaUnavailable(&a, "chat@example.invalid", id));
    }
}

test "normal and oversized labels preserve old states" {
    var a = fixture();
    try std.testing.expectEqual(media_drain.AttachmentState.downloading, attachmentState(&a, &a.messages[0], false));
    a.messages[0].media_size = media_drain.max_auto_bytes + 1;
    try std.testing.expectEqual(media_drain.AttachmentState.oversized, attachmentState(&a, &a.messages[0], false));
    try std.testing.expectEqual(media_drain.AttachmentState.local, attachmentState(&a, &a.messages[0], true));
}

test "queued sends cannot starve the independent hub media worker" {
    for ([_]bool{ false, true }) |automatic| {
        var a = fixture();
        a.hub = true;
        a.pending_send_count = 2;
        a.send_child = 1;
        a.read_child = 1;
        a.archive_child = 1;
        try std.testing.expect(downloadMedia(&a, 0, automatic));
        try std.testing.expectEqual(@as(usize, 1), a.started);
        try std.testing.expectEqual(@as(usize, 0), a.pending_download_id.len);
    }
}

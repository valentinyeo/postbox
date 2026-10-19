const std = @import("std");

pub const wazi_135 = true;

pub const max_children = 1;
pub const max_auto_bytes: u64 = 100 * 1024 * 1024;
pub const max_burst_files = 4;
pub const burst_budget_ms = 20_000;

pub const Candidate = struct {
    index: usize,
    downloadable: bool = false,
    has_id: bool = false,
    has_local_path: bool = false,
    in_flight: bool = false,
    attempted: bool = false,
    retry_after_ms: u64 = 0,
    size_bytes: u64 = 0,
    whatsapp_store: bool = false,
};

pub fn downloadable(kind: []const u8) bool {
    for ([_][]const u8{ "image", "sticker", "video", "gif", "audio", "voice", "document" }) |supported| {
        if (std.ascii.eqlIgnoreCase(kind, supported)) return true;
    }
    return false;
}

pub fn isPlaceholder(kind: []const u8, text: []const u8) bool {
    if (!downloadable(kind)) return false;
    if (std.mem.startsWith(u8, text, "Sent ") and std.ascii.eqlIgnoreCase(text[5..], kind)) return true;
    return text.len > 2 and text[0] == '[' and text[text.len - 1] == ']' and
        std.ascii.eqlIgnoreCase(text[1 .. text.len - 1], kind);
}

pub fn oversized(size_bytes: u64) bool {
    return size_bytes > max_auto_bytes;
}

pub fn selectNext(candidates: []const Candidate, now_ms: u64) ?usize {
    for (candidates) |candidate| {
        if (!candidate.downloadable or !candidate.has_id or !candidate.whatsapp_store) continue;
        if (candidate.has_local_path or candidate.in_flight or candidate.attempted) continue;
        if (now_ms < candidate.retry_after_ms or oversized(candidate.size_bytes)) continue;
        return candidate.index;
    }
    return null;
}

pub fn mayContinueBurst(files_started: usize, started_ms: u64, now_ms: u64) bool {
    return files_started < max_burst_files and now_ms -| started_ms < burst_budget_ms;
}

pub const max_drain_steps = max_children;

pub fn mayDrainStep(steps_done: usize, last_step_started: bool) bool {
    return steps_done < max_drain_steps and (steps_done == 0 or last_step_started);
}

pub fn forgetAttempt(attempts: []u64, count: *usize, key: u64) void {
    var i: usize = 0;
    while (i < count.*) {
        if (attempts[i] == key) {
            count.* -= 1;
            attempts[i] = attempts[count.*];
        } else i += 1;
    }
}

pub fn sizeFromJson(object: std.json.ObjectMap) u64 {
    for ([_][]const u8{ "FileSize", "FileLength", "MediaSize", "Size" }) |key| {
        const value = object.get(key) orelse continue;
        const size: u64 = switch (value) {
            .integer => |n| if (n > 0) @intCast(n) else 0,
            .string, .number_string => |text| std.fmt.parseInt(u64, text, 10) catch 0,
            else => 0,
        };
        if (size > 0) return size;
    }
    return 0;
}

pub const AttachmentState = enum { local, downloading, oversized, unavailable };

pub fn attachmentLabel(buffer: []u8, name: []const u8, size_bytes: u64, attachment_state: AttachmentState) []const u8 {
    const state = switch (attachment_state) {
        .local => "Open",
        .downloading => "Downloading...",
        .oversized => "Click to download",
        .unavailable => "Not available, ask the sender to send it again",
    };
    const filename = if (name.len > 0) name else "Attachment";
    if (size_bytes == 0) return std.fmt.bufPrint(buffer, "{s} · {s}", .{ filename, state }) catch filename;
    if (size_bytes < 1024) return std.fmt.bufPrint(buffer, "{s} · {d} B · {s}", .{ filename, size_bytes, state }) catch filename;
    if (size_bytes < 1024 * 1024) return std.fmt.bufPrint(buffer, "{s} · {d} KB · {s}", .{ filename, (size_bytes + 1023) / 1024, state }) catch filename;
    return std.fmt.bufPrint(buffer, "{s} · {d} MB · {s}", .{ filename, size_bytes / (1024 * 1024), state }) catch filename;
}

fn ready(index: usize) Candidate {
    return .{ .index = index, .downloadable = true, .has_id = true, .whatsapp_store = true };
}

test "all media types including stickers and own sent documents are downloadable" {
    for ([_][]const u8{ "image", "sticker", "video", "gif", "audio", "voice", "document", "Document" }) |kind| {
        try std.testing.expect(downloadable(kind));
    }
    try std.testing.expect(!downloadable(""));
    try std.testing.expect(!downloadable("reaction"));
}

test "open chat candidates drain newest first including old and newly synced rows" {
    var candidates = [_]Candidate{ ready(2), ready(1), ready(0) };
    try std.testing.expectEqual(@as(?usize, 2), selectNext(&candidates, 0));
    candidates[0].in_flight = true;
    try std.testing.expectEqual(@as(?usize, 1), selectNext(&candidates, 0));
    candidates[1].has_local_path = true;
    try std.testing.expectEqual(@as(?usize, 0), selectNext(&candidates, 0));
    candidates[2].attempted = true;
    try std.testing.expectEqual(@as(?usize, null), selectNext(&candidates, 0));
}

test "cache hits and in-flight duplicates skip but missing cached files queue again" {
    var candidate = ready(0);
    candidate.has_local_path = true;
    try std.testing.expectEqual(@as(?usize, null), selectNext(&.{candidate}, 0));
    candidate.has_local_path = false;
    try std.testing.expectEqual(@as(?usize, 0), selectNext(&.{candidate}, 0));
    candidate.in_flight = true;
    try std.testing.expectEqual(@as(?usize, null), selectNext(&.{ candidate, candidate }, 0));
}

test "unsupported providers missing ids and non-media cannot start or spin" {
    var candidates = [_]Candidate{ ready(3), ready(2), ready(1) };
    candidates[0].whatsapp_store = false;
    candidates[1].has_id = false;
    candidates[2].downloadable = false;
    try std.testing.expectEqual(@as(?usize, null), selectNext(&candidates, 0));
    try std.testing.expectEqual(@as(?usize, null), selectNext(&.{}, 0));
    var steps: usize = 0;
    var started = true;
    while (mayDrainStep(steps, started)) {
        started = selectNext(&candidates, 0) != null;
        steps += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), steps);
}

test "one slow or failed attachment does not block the remaining queue" {
    var candidates = [_]Candidate{ ready(1), ready(0) };
    candidates[0].retry_after_ms = 30_000;
    try std.testing.expectEqual(@as(?usize, 0), selectNext(&candidates, 29_999));
    try std.testing.expectEqual(@as(?usize, 1), selectNext(&candidates, 30_000));
}

test "size cap skips only above 100 MB and cached oversized files remain usable" {
    var candidates = [_]Candidate{ ready(1), ready(0) };
    candidates[0].size_bytes = max_auto_bytes + 1;
    candidates[1].size_bytes = max_auto_bytes;
    try std.testing.expectEqual(@as(?usize, 0), selectNext(&candidates, 0));
    candidates[1].has_local_path = true;
    try std.testing.expectEqual(@as(?usize, null), selectNext(&candidates, 0));
    try std.testing.expect(!oversized(0));
    try std.testing.expect(!oversized(max_auto_bytes));
    try std.testing.expect(oversized(max_auto_bytes + 1));
}

test "bounded serial refill and burst yield prevent UI loops and long sync starvation" {
    try std.testing.expectEqual(@as(usize, 1), max_children);
    try std.testing.expect(mayDrainStep(0, false));
    try std.testing.expect(!mayDrainStep(1, false));
    try std.testing.expect(!mayDrainStep(max_drain_steps, true));
    try std.testing.expect(mayContinueBurst(0, 100, 100));
    try std.testing.expect(mayContinueBurst(max_burst_files - 1, 100, 100));
    try std.testing.expect(!mayContinueBurst(max_burst_files, 100, 100));
    try std.testing.expect(!mayContinueBurst(1, 100, 100 + burst_budget_ms));
}

test "size metadata tolerates missing negative and string byte counts" {
    for ([_]struct { json: []const u8, size: u64 }{
        .{ .json = "{}", .size = 0 },
        .{ .json = "{\"FileSize\":104857601}", .size = max_auto_bytes + 1 },
        .{ .json = "{\"FileLength\":\"104857600\"}", .size = max_auto_bytes },
        .{ .json = "{\"FileSize\":-1,\"Size\":17}", .size = 17 },
        .{ .json = "{\"FileSize\":\"bad\"}", .size = 0 },
    }) |fixture| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture.json, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(fixture.size, sizeFromJson(parsed.value.object));
    }
}

test "documents show name size and only oversized uncached files request a click" {
    var buffer: [512]u8 = undefined;
    try std.testing.expectEqualStrings("report.pdf · 2 KB · Open", attachmentLabel(&buffer, "report.pdf", 1500, .local));
    try std.testing.expectEqualStrings("report.pdf · Downloading...", attachmentLabel(&buffer, "report.pdf", 0, .downloading));
    try std.testing.expectEqualStrings("report.pdf · 101 MB · Click to download", attachmentLabel(&buffer, "report.pdf", 101 * 1024 * 1024, .oversized));
    try std.testing.expectEqualStrings("report.pdf · 101 MB · Open", attachmentLabel(&buffer, "report.pdf", 101 * 1024 * 1024, .local));
}

test "unavailable attachments retain the filename and optional size" {
    var buffer: [512]u8 = undefined;
    try std.testing.expectEqualStrings("report.pdf · Not available, ask the sender to send it again", attachmentLabel(&buffer, "report.pdf", 0, .unavailable));
    try std.testing.expectEqualStrings("report.pdf · 17 B · Not available, ask the sender to send it again", attachmentLabel(&buffer, "report.pdf", 17, .unavailable));
    try std.testing.expectEqualStrings("report.pdf · 2 KB · Not available, ask the sender to send it again", attachmentLabel(&buffer, "report.pdf", 1500, .unavailable));
    try std.testing.expectEqualStrings("report.pdf · 101 MB · Not available, ask the sender to send it again", attachmentLabel(&buffer, "report.pdf", 101 * 1024 * 1024, .unavailable));
    try std.testing.expectEqualStrings("Attachment · Not available, ask the sender to send it again", attachmentLabel(&buffer, "", 0, .unavailable));
}

test "transport media placeholders are hidden but real captions are retained" {
    try std.testing.expect(isPlaceholder("document", "Sent document"));
    try std.testing.expect(isPlaceholder("image", "[Image]"));
    try std.testing.expect(isPlaceholder("audio", "Sent audio"));
    try std.testing.expect(!isPlaceholder("document", "Sent document yesterday"));
    try std.testing.expect(!isPlaceholder("", "Sent document"));
    try std.testing.expect(!isPlaceholder("video", "holiday.mp4"));
}

test "reopened chat snapshot preserves the local file and prevents another download" {
    const cache = @import("chat_cache.zig");
    const payload = "{\"data\":{\"messages\":[{\"MsgID\":\"sent-document\",\"MediaType\":\"document\",\"FromMe\":true,\"LocalPath\":\"C:\\\\cache\\\\report.pdf\",\"Filename\":\"report.pdf\"}]}}";
    const stored = try cache.envelope(std.testing.allocator, "account", "group@g.us", payload);
    defer std.testing.allocator.free(stored);
    const restored = cache.payloadFor(stored, "account", "group@g.us").?;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, restored, .{});
    defer parsed.deinit();
    const row = parsed.value.object.get("data").?.object.get("messages").?.array.items[0].object;
    var candidate = ready(0);
    candidate.downloadable = downloadable(row.get("MediaType").?.string);
    candidate.has_local_path = row.get("LocalPath").?.string.len > 0;
    try std.testing.expectEqual(@as(?usize, null), selectNext(&.{candidate}, 0));
    candidate.has_local_path = false;
    try std.testing.expectEqual(@as(?usize, 0), selectNext(&.{candidate}, 0));
    try std.testing.expect(cache.payloadFor(stored, "account", "dm@s.whatsapp.net") == null);
}

test "duplicate ids in different chats have independent attempt keys" {
    const played = @import("played.zig");
    var attempts = played.Set{};
    var line: [40]u8 = undefined;
    const group_key = played.Set.pairKey("group@g.us", "same-id");
    const dm_key = played.Set.pairKey("dm@s.whatsapp.net", "same-id");
    _ = attempts.markRaw(group_key, &line);
    try std.testing.expect(attempts.wasPlayedRaw(group_key));
    try std.testing.expect(!attempts.wasPlayedRaw(dm_key));
}

test "confirmed cache hits clear success suppression so later eviction refills" {
    var attempts = [_]u64{ 11, 22, 11 };
    var count: usize = attempts.len;
    forgetAttempt(&attempts, &count, 99);
    try std.testing.expectEqual(@as(usize, 3), count);
    forgetAttempt(&attempts, &count, 11);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u64, 22), attempts[0]);
    forgetAttempt(&attempts, &count, 22);
    try std.testing.expectEqual(@as(usize, 0), count);
    var candidate = ready(0);
    candidate.attempted = std.mem.indexOfScalar(u64, attempts[0..count], 11) != null;
    try std.testing.expectEqual(@as(?usize, 0), selectNext(&.{candidate}, 0));
}

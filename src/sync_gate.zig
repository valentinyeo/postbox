const std = @import("std");

pub const background_stop_gap_ms: u64 = 60_000;
pub const media_stop_gap_ms: u64 = 15_000;
pub const avatar_batch_gap_ms: u64 = 180_000;
pub const avatar_failure_backoff_ms: u64 = 30 * 60 * 1000;
pub const avatar_batch_max: u32 = 10;
pub const avatar_batch_budget_ms: u64 = 20_000;
pub const avatar_cache_ttl_secs: i64 = 7 * 24 * 60 * 60;
pub const avatar_failure_ttl_secs: i64 = 24 * 60 * 60;
pub const delegate_warmup_secs: i64 = 20;
pub const sync_refresh_gap_ms: u64 = 6 * 60 * 60 * 1000;

pub fn gapElapsed(last_stop_ms: ?u64, now_ms: u64, gap_ms: u64) bool {
    const last = last_stop_ms orelse return true;
    return now_ms -| last >= gap_ms;
}

pub fn avatarBatchMayStart(last_stop_ms: ?u64, last_batch_end_ms: ?u64, retry_after_ms: u64, now_ms: u64) bool {
    return now_ms >= retry_after_ms and
        gapElapsed(last_stop_ms, now_ms, background_stop_gap_ms) and
        gapElapsed(last_batch_end_ms, now_ms, avatar_batch_gap_ms);
}

pub fn avatarBatchContinues(fetched: u32, started_ms: u64, now_ms: u64, last_failed: bool) bool {
    return !last_failed and fetched < avatar_batch_max and now_ms -| started_ms < avatar_batch_budget_ms;
}

pub fn fresh(stamp_secs: ?i64, now_secs: i64, ttl_secs: i64) bool {
    const stamp = stamp_secs orelse return false;
    return now_secs - stamp < ttl_secs;
}

pub fn pictureAbsent(output: []const u8) bool {
    return std.mem.indexOf(u8, output, "does not have a profile picture") != null or
        std.mem.indexOf(u8, output, "hidden their profile picture") != null;
}

pub const AvatarCache = struct {
    has_image: bool,
    needs_fetch: bool,
};

pub fn classifyAvatar(image_secs: ?i64, image_decodes: bool, none_secs: ?i64, failed_secs: ?i64, now_secs: i64) AvatarCache {
    if (fresh(failed_secs, now_secs, avatar_failure_ttl_secs)) {
        return .{ .has_image = image_secs != null and image_decodes, .needs_fetch = false };
    }
    if (image_secs != null and image_decodes) {
        return .{ .has_image = true, .needs_fetch = !fresh(image_secs, now_secs, avatar_cache_ttl_secs) };
    }
    return .{ .has_image = false, .needs_fetch = !fresh(none_secs, now_secs, avatar_cache_ttl_secs) };
}

test "background pauses are spaced a minute apart" {
    try std.testing.expect(gapElapsed(null, 5, background_stop_gap_ms));
    try std.testing.expect(!gapElapsed(100_000, 159_999, background_stop_gap_ms));
    try std.testing.expect(gapElapsed(100_000, 160_000, background_stop_gap_ms));
    try std.testing.expect(gapElapsed(100_000, 115_000, media_stop_gap_ms));
}

test "an avatar batch needs both the global gap and the batch gap" {
    try std.testing.expect(avatarBatchMayStart(null, null, 0, 1_000));
    try std.testing.expect(!avatarBatchMayStart(970_000, null, 0, 1_000_000));
    try std.testing.expect(!avatarBatchMayStart(880_000, 880_000, 0, 1_000_000));
    try std.testing.expect(avatarBatchMayStart(820_000, 820_000, 0, 1_000_000));
    try std.testing.expect(!avatarBatchMayStart(null, null, 1_000_001, 1_000_000));
    try std.testing.expect(avatarBatchMayStart(null, null, 1_000_000, 1_000_000));
}

test "an avatar batch stops at its cap, its time budget, or a failure" {
    try std.testing.expect(avatarBatchContinues(1, 0, 5_000, false));
    try std.testing.expect(!avatarBatchContinues(avatar_batch_max, 0, 5_000, false));
    try std.testing.expect(!avatarBatchContinues(3, 0, avatar_batch_budget_ms, false));
    try std.testing.expect(!avatarBatchContinues(1, 0, 5_000, true));
}

test "cached avatars are trusted for a week, failures for a day" {
    const day: i64 = 24 * 60 * 60;
    const now: i64 = 100 * day;
    try std.testing.expectEqual(AvatarCache{ .has_image = true, .needs_fetch = false }, classifyAvatar(now - day, true, null, null, now));
    try std.testing.expectEqual(AvatarCache{ .has_image = true, .needs_fetch = true }, classifyAvatar(now - 8 * day, true, null, null, now));
    try std.testing.expectEqual(AvatarCache{ .has_image = false, .needs_fetch = true }, classifyAvatar(now - day, false, null, null, now));
    try std.testing.expectEqual(AvatarCache{ .has_image = false, .needs_fetch = false }, classifyAvatar(null, false, now - 3 * day, null, now));
    try std.testing.expectEqual(AvatarCache{ .has_image = false, .needs_fetch = true }, classifyAvatar(null, false, now - 8 * day, null, now));
    try std.testing.expectEqual(AvatarCache{ .has_image = true, .needs_fetch = false }, classifyAvatar(now - 8 * day, true, null, now - 3600, now));
    try std.testing.expectEqual(AvatarCache{ .has_image = false, .needs_fetch = true }, classifyAvatar(null, false, null, now - 2 * day, now));
}

test "no picture and hidden picture are answers, a rate limit is a failure" {
    try std.testing.expect(pictureAbsent("{\"error\":\"get profile picture info: that user or group does not have a profile picture\"}"));
    try std.testing.expect(pictureAbsent("get profile picture info: the user has hidden their profile picture from you"));
    try std.testing.expect(!pictureAbsent("info query returned status 429: rate-overlimit"));
    try std.testing.expect(!pictureAbsent("store is locked (another wacli is running?)"));
}

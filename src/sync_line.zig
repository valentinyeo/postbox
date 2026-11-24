const std = @import("std");

pub const State = enum { caught_up, catching_up, offline };

pub const stale_after_ms: u64 = 180_000;
pub const gap_summary_wait_ms: u64 = 10_000;
pub const reconnect_quiet_ms: u64 = 3_000;
pub const label_capacity: usize = 63;
const min_label_width: i32 = 96;

pub const Rect = struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub fn scale(value: i32, dpi: i32) i32 {
    return @divTrunc(value * dpi + 48, 96);
}

pub fn labelRect(client: Rect, pill_right: i32, dpi: i32) ?Rect {
    const right = client.right - scale(16, dpi);
    const left = @max(pill_right + scale(16, dpi), client.left + scale(16, dpi));
    if (right - left < scale(min_label_width, dpi)) return null;
    return .{ .left = left, .top = scale(16, dpi), .right = right, .bottom = scale(52, dpi) };
}

pub fn stateName(state: State) []const u8 {
    return @tagName(state);
}

pub fn classify(live: bool, failures: u32, last_fetch_ms: u64, now_ms: u64) State {
    if (failures > 0 and !live) return .offline;
    if (!live) return .catching_up;
    if (last_fetch_ms == 0) return .catching_up;
    if (now_ms -| last_fetch_ms >= stale_after_ms) return .catching_up;
    return .caught_up;
}

pub const Display = struct {
    shown: State = .catching_up,
    down_ms: ?u64 = null,
};

pub const Step = struct {
    display: Display,
    state_changed: bool,
};

pub fn step(previous: Display, live: bool, failures: u32, last_fetch_ms: u64, now_ms: u64) Step {
    const down_ms: ?u64 = if (live) null else previous.down_ms orelse now_ms;
    const truth = classify(live, failures, last_fetch_ms, now_ms);
    const quiet = !live and failures == 0 and now_ms -| (down_ms orelse now_ms) < reconnect_quiet_ms;
    const shown = if (quiet) previous.shown else truth;
    return .{ .display = .{ .shown = shown, .down_ms = down_ms }, .state_changed = shown != previous.shown };
}

pub fn label(buffer: []u8, state: State, clock: []const u8) []const u8 {
    return switch (state) {
        .caught_up => if (clock.len == 0)
            "Up to date"
        else
            std.fmt.bufPrint(buffer, "Up to date \u{00b7} {s}", .{clock}) catch "Up to date",
        .catching_up => "Catching up\u{2026}",
        .offline => if (clock.len == 0)
            "Offline \u{00b7} not synced yet"
        else
            std.fmt.bufPrint(buffer, "Offline \u{00b7} last sync {s}", .{clock}) catch "Offline",
    };
}

test "a live stream with a recent fetch is caught up" {
    try std.testing.expectEqual(State.caught_up, classify(true, 0, 1_000_000, 1_001_000));
    try std.testing.expectEqual(State.caught_up, classify(true, 2, 1_000_000, 1_001_000));
    try std.testing.expectEqual(State.catching_up, classify(true, 0, 1_000_000, 1_000_000 + stale_after_ms));
    try std.testing.expectEqual(State.catching_up, classify(true, 0, 0, 1_000_000));
}

test "a dropped stream is offline and a fresh reconnect catches up" {
    try std.testing.expectEqual(State.catching_up, classify(false, 0, 1_000_000, 1_001_000));
    try std.testing.expectEqual(State.offline, classify(false, 1, 1_000_000, 1_001_000));
    try std.testing.expectEqual(State.offline, classify(false, 6, 0, 1_001_000));
    try std.testing.expectEqual(State.caught_up, classify(true, 0, 1_001_000, 1_001_000));
}

test "a brief reconnect keeps the shown line and asks for no repaint" {
    const up = Display{ .shown = .caught_up };
    const closing = step(up, false, 0, 1_000_000, 1_200_000);
    try std.testing.expectEqual(State.caught_up, closing.display.shown);
    try std.testing.expect(!closing.state_changed);
    const reopened = step(closing.display, true, 0, 1_200_000, 1_201_000);
    try std.testing.expectEqual(State.caught_up, reopened.display.shown);
    try std.testing.expect(!reopened.state_changed);
    try std.testing.expect(reopened.display.down_ms == null);
}

test "a reconnect longer than the quiet window shows catching up and repaints once" {
    const quiet = Display{ .shown = .caught_up, .down_ms = 1_000_000 };
    const still_quiet = step(quiet, false, 0, 1_000_000, 1_000_000 + reconnect_quiet_ms - 1);
    try std.testing.expectEqual(State.caught_up, still_quiet.display.shown);
    try std.testing.expect(!still_quiet.state_changed);
    const slow = step(quiet, false, 0, 1_000_000, 1_000_000 + reconnect_quiet_ms);
    try std.testing.expectEqual(State.catching_up, slow.display.shown);
    try std.testing.expect(slow.state_changed);
    const steady = step(slow.display, false, 0, 1_000_000, 1_000_000 + reconnect_quiet_ms + 1_000);
    try std.testing.expectEqual(State.catching_up, steady.display.shown);
    try std.testing.expect(!steady.state_changed);
}

test "a failed connection shows offline at once and recovers in one change" {
    const offline = step(.{ .shown = .caught_up }, false, 1, 1_000_000, 1_001_000);
    try std.testing.expectEqual(State.offline, offline.display.shown);
    try std.testing.expect(offline.state_changed);
    const recovered = step(offline.display, true, 0, 1_002_000, 1_003_000);
    try std.testing.expectEqual(State.caught_up, recovered.display.shown);
    try std.testing.expect(recovered.state_changed);
    const steady = step(recovered.display, true, 0, 1_003_000, 1_004_000);
    try std.testing.expect(!steady.state_changed);
}

test "the line names the state and the last successful sync" {
    var buffer: [label_capacity + 1]u8 = undefined;
    try std.testing.expectEqualStrings("Up to date \u{00b7} 08:45", label(&buffer, .caught_up, "08:45"));
    try std.testing.expectEqualStrings("Up to date", label(&buffer, .caught_up, ""));
    try std.testing.expectEqualStrings("Catching up\u{2026}", label(&buffer, .catching_up, "08:45"));
    try std.testing.expectEqualStrings("Offline \u{00b7} last sync 08:45", label(&buffer, .offline, "08:45"));
    try std.testing.expectEqualStrings("Offline \u{00b7} not synced yet", label(&buffer, .offline, ""));
    try std.testing.expectEqualStrings("caught_up", stateName(.caught_up));
    try std.testing.expectEqualStrings("offline", stateName(.offline));
}

test "the line sits right of the chat pill and gives up when the pill is wide" {
    const client = Rect{ .left = 0, .top = 0, .right = 900, .bottom = 600 };
    const wide = labelRect(client, 500, 96).?;
    try std.testing.expect(wide.left > 500 and wide.right == 900 - 16);
    try std.testing.expect(wide.top == 16 and wide.bottom == 52);
    try std.testing.expect(labelRect(client, 860, 96) == null);
    try std.testing.expect(labelRect(.{ .left = 0, .top = 0, .right = 400, .bottom = 600 }, 380, 96) == null);
    for ([_]i32{ 96, 120, 144, 168, 192 }) |dpi| {
        const rect = labelRect(.{ .left = 0, .top = 0, .right = scale(900, dpi), .bottom = scale(600, dpi) }, 0, dpi).?;
        try std.testing.expect(rect.right - rect.left >= scale(min_label_width, dpi));
        try std.testing.expect(rect.bottom <= scale(72, dpi));
    }
}

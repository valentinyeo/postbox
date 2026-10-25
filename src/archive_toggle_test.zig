const std = @import("std");
const messenger_view = @import("messenger_view");

const Text = struct {
    data: [256]u8 = undefined,
    len: usize = 0,

    fn set(self: *Text, text: []const u8) void {
        self.len = text.len;
        @memcpy(self.data[0..text.len], text);
    }

    fn slice(self: *const Text) []const u8 {
        return self.data[0..self.len];
    }
};

const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    chats_raw: ?[]const u8 = null,
    chats_raw_flags: u8 = 0,
    chats_pending_flags: u8 = 0,
    chats_gen: u64 = 0,
    show_archived: bool = false,
    include_archived: bool = false,
    chat_view: messenger_view.View = .all,
    view_account: Text = .{},
    cache_tag: Text = .{},
    wacli_path: []const u8 = "wacli",
    include_archived_button: ?usize = null,
    chats_hwnd: ?usize = null,
    archive_toggle_started_ms: ?u64 = null,
    archive_toggle_ready: bool = false,
    archive_toggle_rebuilds: u32 = 0,
    archive_toggle_rebuild_ms: u64 = 0,
    archive_toggle_fetch_ms: u64 = 0,
    archive_toggle_fetches: u32 = 0,
    archive_toggle_paints: u64 = 0,
    paints: struct { list: u64 = 0 } = .{},
    rebuilds: usize = 0,
    enqueued: usize = 0,
    pending: usize = 0,
    reconciled: usize = 0,
    messages_refreshed: usize = 0,
    cleared: usize = 0,
    registry_ok: bool = true,
    status: Text = .{},
    log: Text = .{},
    logs: usize = 0,
    job: WacliJob = .{},
};

const WacliJob = struct {
    account: Text = .{},
    kind: enum { chats } = .chats,
    started_ms: u64 = 0,
    gen: u64 = 0,
    args: [16]Text = @splat(.{}),
    arg_count: usize = 0,
};

var clock_ms: u64 = 1000;
const win = struct {
    const FALSE = 0;

    fn GetTickCount64() u64 {
        return clock_ms;
    }

    fn SetWindowTextW(_: usize, _: [*:0]const u16) i32 {
        return 1;
    }

    fn InvalidateRect(_: usize, _: ?*anyopaque, _: i32) i32 {
        return 1;
    }
};

fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

fn utf8ToWide(allocator: std.mem.Allocator, text: []const u8) ![:0]u16 {
    return std.unicode.utf8ToUtf16LeAllocZ(allocator, text);
}

fn saveRegistryString(a: std.mem.Allocator, _: [*:0]const u16, value: []const u8) bool {
    _ = a;
    _ = value;
    return current_app.?.registry_ok;
}

var current_app: ?*App = null;

fn setStatus(a: *App, text: []const u8) void {
    a.status.set(text);
}

fn clearBulkSelection(a: *App) bool {
    a.cleared += 1;
    return true;
}

fn reconcileOpenChat(a: *App) void {
    a.reconciled += 1;
}

fn refreshMessages(a: *App) void {
    a.messages_refreshed += 1;
}

fn refreshVisibleChats(a: *App) void {
    _ = applyChats(a, a.chats_raw orelse "{\"data\":[]}", false);
}

fn hubConfigured(_: *App) bool {
    return true;
}

fn wacliPendingGet(a: *App, _: @FieldType(WacliJob, "kind")) usize {
    return a.pending;
}

fn wacliJobArgs(job: *WacliJob, args: []const []const u8) void {
    for (args, 0..) |arg, i| job.args[i].set(arg);
    job.arg_count = args.len;
}

fn wacliEnqueue(a: *App, job: WacliJob, _: bool) bool {
    a.enqueued += 1;
    a.job = job;
    return true;
}

fn appendLaunchLog(a: *App, line: []const u8) void {
    a.log.set(line);
    a.logs += 1;
}

test "Alt A reuses a mixed snapshot in every account and inbox without a child or message refresh" {
    for ([_]messenger_view.View{ .all, .whatsapp, .slack, .telegram, .signal }) |view| {
        var a = App{ .chats_raw = "{\"data\":[]}", .chats_raw_flags = 1, .chat_view = view };
        current_app = &a;
        defer current_app = null;
        clock_ms = 1000;
        toggleViewArchived(&a);
        try std.testing.expect(a.include_archived);
        try std.testing.expectEqual(@as(usize, 1), a.rebuilds);
        try std.testing.expectEqual(@as(usize, 0), a.enqueued);
        try std.testing.expectEqual(@as(usize, 0), a.messages_refreshed);
        try std.testing.expectEqual(@as(usize, 1), a.reconciled);
        clock_ms = 1007;
        a.paints.list += 1;
        logArchiveTogglePaint(&a);
        try std.testing.expectEqualStrings("archive-toggle: include=true rebuilds=1 rebuild_ms=0 fetches=0 fetch_ms=0 first_paint_ms=7 paints=1", a.log.slice());
        logArchiveTogglePaint(&a);
        try std.testing.expectEqual(@as(usize, 1), a.logs);
        toggleViewArchived(&a);
        try std.testing.expect(!a.include_archived);
        try std.testing.expectEqual(@as(usize, 2), a.rebuilds);
        try std.testing.expectEqual(@as(usize, 0), a.enqueued);
    }
}

test "cold toggle repaints the loaded snapshot, fetches once and logs only a covered paint" {
    var a = App{ .chats_raw = "{\"data\":[]}" };
    current_app = &a;
    defer current_app = null;
    toggleViewArchived(&a);
    try std.testing.expectEqual(@as(usize, 1), a.rebuilds);
    try std.testing.expectEqual(@as(usize, 1), a.enqueued);
    try std.testing.expectEqual(@as(u32, 1), a.archive_toggle_fetches);
    try std.testing.expectEqual(@as(u8, 1), a.chats_pending_flags);
    try std.testing.expectEqualStrings("--include-archived", a.job.args[a.job.arg_count - 1].slice());
    logArchiveTogglePaint(&a);
    try std.testing.expectEqual(@as(usize, 0), a.logs);
    a.chats_raw_flags = 1;
    refilterChats(&a);
    try std.testing.expectEqual(@as(usize, 2), a.rebuilds);
    try std.testing.expectEqual(@as(usize, 1), a.enqueued);
    a.paints.list += 1;
    logArchiveTogglePaint(&a);
    try std.testing.expectEqual(@as(usize, 1), a.logs);
}

test "background refresh keeps mixed coverage even with include off or archive only" {
    for ([_]bool{ false, true }) |archived_only| {
        var a = App{ .chats_raw = "{\"data\":[]}", .chats_raw_flags = 1, .show_archived = archived_only };
        refreshChats(&a);
        try std.testing.expectEqual(@as(u8, 1), a.chats_pending_flags);
        try std.testing.expectEqualStrings("--include-archived", a.job.args[a.job.arg_count - 1].slice());
        a.pending = 1;
        refreshChats(&a);
        try std.testing.expectEqual(@as(usize, 1), a.enqueued);
    }
}

test "failed preference persistence leaves the toggle and fetch path untouched" {
    var a = App{ .registry_ok = false };
    current_app = &a;
    defer current_app = null;
    toggleViewArchived(&a);
    try std.testing.expect(!a.include_archived);
    try std.testing.expectEqual(@as(?u64, null), a.archive_toggle_started_ms);
    try std.testing.expectEqual(@as(usize, 0), a.enqueued);
    try std.testing.expectEqual(@as(usize, 0), a.cleared);
}

test "unlabelled disk snapshots fetch fresh coverage before completing the toggle" {
    var a = App{ .chats_raw = "{\"data\":[]}", .chats_raw_flags = 3 };
    current_app = &a;
    defer current_app = null;
    toggleViewArchived(&a);
    try std.testing.expectEqual(@as(usize, 1), a.rebuilds);
    try std.testing.expectEqual(@as(usize, 1), a.enqueued);
    try std.testing.expect(!a.archive_toggle_ready);
    _ = applyChats(&a, "{\"data\":[]}", true);
    try std.testing.expect(a.archive_toggle_ready);
    try std.testing.expectEqual(@as(u32, 2), a.archive_toggle_rebuilds);
}

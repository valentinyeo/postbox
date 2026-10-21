const std = @import("std");
const message_double_click = @import("message_double_click");
const send_args = @import("send_args");
const transport = struct {
    const Provider = enum { whatsapp, slack, telegram };
};
const Rect = struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
const Point = struct { x: i32 = 0, y: i32 = 0 };
const win = struct {
    const WM_LBUTTONDOWN = 1;
    const WM_LBUTTONUP = 2;
    const WM_LBUTTONDBLCLK = 3;
    const WM_MOUSEMOVE = 4;
    const WM_CAPTURECHANGED = 5;
    fn SetCapture(_: usize) usize {
        return 1;
    }
    fn ReleaseCapture() i32 {
        return 1;
    }
    fn DefWindowProcW(_: usize, _: u32, _: usize, _: isize) isize {
        return 0;
    }
    const FALSE = 0;
    const TRUE = 1;
    fn InvalidateRect(_: usize, _: ?*const Rect, _: i32) i32 {
        return 1;
    }
    fn GetTickCount64() u64 {
        return 100;
    }
};
const emoji_picker = struct {
    fn indexOf(_: []const u8) ?usize {
        return null;
    }
    fn pushRecent(_: *[8]usize, _: *usize, _: usize) void {}
};
const Message = struct {
    id: Utf8Text(191) = .{},
    sender_jid: Utf8Text(191) = .{},
    reaction_to: Utf8Text(191) = .{},
    reaction: WideText(1023) = .{},
    my_reaction: Utf8Text(63) = .{},
    from_me: bool = false,
    reaction_pending: bool = false,
    bubble_hit: Rect = .{ .left = 10, .top = 10, .right = 200, .bottom = 100 },
    media_hit: Rect = .{},
    local_path: WideText(519) = .{},
    image: bool = false,
    gif: bool = false,
    word_count: usize = 3,
};
const Chat = struct {
    provider: transport.Provider = .whatsapp,
    account: Utf8Text(32) = .{},
    jid: Utf8Text(191) = .{},
};
const WacliJob = struct {
    provider: transport.Provider = .whatsapp,
    account: Utf8Text(32) = .{},
    kind: enum { reaction } = .reaction,
    jid: Utf8Text(191) = .{},
    msg_id: Utf8Text(191) = .{},
    extra: Utf8Text(63) = .{},
    args: [send_args.max_args]Utf8Text(256) = @splat(.{}),
    arg_count: usize = 0,
};
const WacliResult = struct {
    msg_id: Utf8Text(191) = .{},
    extra: Utf8Text(63) = .{},
    ok: bool = true,
};
const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    chats: [1]Chat = .{.{}},
    chat_count: usize = 1,
    selected_chat: usize = 0,
    messages: [3]Message = @splat(.{}),
    message_count: usize = 1,
    selected_message: ?usize = null,
    pending_reactions: [max_pending_reactions]PendingReaction = @splat(.{}),
    pending_reaction_count: usize = 0,
    canvas: ?usize = 1,
    wacli_path: []const u8 = "wacli.exe",
    emoji_recents: [8]usize = @splat(0),
    emoji_recents_count: usize = 0,
    jobs: [8]WacliJob = @splat(.{}),
    job_count: usize = 0,
    queue_full: bool = false,
    viewer_opens: usize = 0,
    downloads: usize = 0,
    click_origin: Point = .{},
    click_moved: bool = false,
    canvas_double_click_handled: bool = false,
    sel_message: ?usize = null,
    sel_anchor_word: usize = 0,
    sel_focus_word: usize = 0,
    text_dragging: bool = false,
    drag_moved: bool = false,
    drag_origin: Point = .{},
    sb_drag: enum { none, canvas } = .none,
    clicks: usize = 0,
    sync_running: bool = true,
    sync_pauses: usize = 0,
};
fn setStatus(_: *App, _: []const u8) void {}
fn saveEmojiRecents(_: *App) void {}
fn startSync(a: *App) void {
    a.sync_running = true;
}
fn stopSync(a: *App, _: []const u8) void {
    a.sync_running = false;
    a.sync_pauses += 1;
}
fn mediaBusy(_: *App) bool {
    return false;
}
fn sendRetryDelayMs(retries: u8) ?u64 {
    return if (retries < 4) 3000 else null;
}
fn isImage(message: *const Message) bool {
    return message.image;
}
fn isGif(message: *const Message) bool {
    return message.gif;
}
fn isVideoGif(_: *const Message) bool {
    return false;
}
fn openImageViewer(a: *App, _: *Message) void {
    a.viewer_opens += 1;
}
fn downloadMedia(a: *App, _: usize, _: bool) bool {
    a.downloads += 1;
    return true;
}
fn wacliJobArgs(job: *WacliJob, args: []const []const u8) void {
    job.arg_count = args.len;
    for (args, 0..) |arg, i| job.args[i].set(arg);
}
fn wacliEnqueue(a: *App, job: WacliJob, _: bool) bool {
    if (a.queue_full) return false;
    a.jobs[a.job_count] = job;
    a.job_count += 1;
    return true;
}
fn fixture() App {
    var a = App{};
    a.chats[0].jid.set("chat@g.us");
    a.chats[0].account.set("test-account");
    a.messages[0].id.set("received-message");
    a.messages[0].sender_jid.set("sender@chat");
    return a;
}
fn expectReaction(a: *App, emoji: []const u8) !void {
    var expected = WideText(1023){};
    expected.set(a.allocator, emoji);
    try std.testing.expectEqualSlices(u16, expected.slice(), a.messages[0].reaction.slice());
    try std.testing.expectEqualStrings(emoji, a.messages[0].my_reaction.slice());
}

test "IGSH-463 double-click sends exactly one thumbs up to the clicked message and chat" {
    var a = fixture();
    a.message_count = 2;
    a.messages[1].id.set("other-message");
    a.messages[1].bubble_hit = .{ .left = 10, .top = 120, .right = 200, .bottom = 220 };
    a.selected_message = 1;
    try std.testing.expect(handleCanvasDoubleClick(&a, 20, 20));
    try std.testing.expectEqual(@as(usize, 1), a.job_count);
    try std.testing.expectEqualStrings("received-message", a.jobs[0].msg_id.slice());
    try std.testing.expectEqualStrings("chat@g.us", a.jobs[0].jid.slice());
    try std.testing.expectEqualStrings("test-account", a.jobs[0].account.slice());
    try std.testing.expectEqualStrings("sender@chat", a.pending_reactions[0].sender.slice());
    try std.testing.expectEqualStrings("👍", a.jobs[0].extra.slice());
    try std.testing.expectEqualStrings("--lock-wait", a.jobs[0].args[2].slice());
    try std.testing.expectEqualStrings("--id", a.jobs[0].args[8].slice());
    try std.testing.expectEqualStrings("received-message", a.jobs[0].args[9].slice());
    try expectReaction(&a, "👍");
    try std.testing.expect(a.messages[0].reaction_pending);
}

test "IGSH-463 second double-click removes thumbs up before or after delivery" {
    for ([_]bool{ false, true }) |delivered| {
        var a = fixture();
        try std.testing.expect(handleCanvasDoubleClick(&a, 20, 20));
        if (delivered) {
            var result = WacliResult{ .msg_id = a.jobs[0].msg_id, .extra = a.jobs[0].extra };
            applyReaction(&a, &result);
        }
        try std.testing.expect(handleCanvasDoubleClick(&a, 20, 20));
        try std.testing.expectEqual(@as(usize, 2), a.job_count);
        try std.testing.expectEqualStrings("", a.jobs[1].extra.slice());
        try std.testing.expectEqualStrings("received-message", a.jobs[1].msg_id.slice());
        try expectReaction(&a, "");
    }
}

test "IGSH-463 own messages and empty space send no reaction" {
    var a = fixture();
    a.messages[0].from_me = true;
    _ = handleCanvasDoubleClick(&a, 20, 20);
    a.messages[0].from_me = false;
    _ = handleCanvasDoubleClick(&a, 250, 20);
    try std.testing.expectEqual(@as(usize, 0), a.job_count);
    try expectReaction(&a, "");
}

test "IGSH-463 someone else's thumbs up does not remove my reaction" {
    var a = fixture();
    a.messages[0].reaction.set(a.allocator, "👍");
    try std.testing.expect(handleCanvasDoubleClick(&a, 20, 20));
    try std.testing.expectEqualStrings("👍", a.jobs[0].extra.slice());
}

test "IGSH-463 received photo and GIF double-click preserves media handling instead of reacting" {
    for ([_]bool{ false, true }) |image| {
        for ([_]bool{ false, true }) |cached| {
            var a = fixture();
            a.messages[0].image = image;
            a.messages[0].gif = !image;
            a.messages[0].media_hit = .{ .left = 30, .top = 30, .right = 180, .bottom = 80 };
            if (cached) a.messages[0].local_path.set(a.allocator, "cached-media");
            try std.testing.expect(handleCanvasDoubleClick(&a, 40, 40));
            try std.testing.expectEqual(@as(usize, 0), a.job_count);
            try std.testing.expectEqual(@as(?usize, 0), a.selected_message);
            try std.testing.expectEqual(@as(usize, if (cached and !image) 1 else 0), a.viewer_opens);
            try std.testing.expectEqual(@as(usize, if (cached) 0 else 1), a.downloads);
            try expectReaction(&a, "");
        }
    }
}

test "IGSH-463 media bubble outside media still toggles thumbs up" {
    var a = fixture();
    a.messages[0].image = true;
    a.messages[0].media_hit = .{ .left = 30, .top = 30, .right = 180, .bottom = 80 };
    try std.testing.expect(handleCanvasDoubleClick(&a, 20, 20));
    try std.testing.expectEqual(@as(usize, 1), a.job_count);
    try std.testing.expectEqual(@as(usize, 0), a.viewer_opens);
    try std.testing.expectEqual(@as(usize, 0), a.downloads);
    try expectReaction(&a, "👍");
}

test "IGSH-463 non-image media double-click does not react" {
    var a = fixture();
    a.messages[0].media_hit = a.messages[0].bubble_hit;
    try std.testing.expect(!handleCanvasDoubleClick(&a, 20, 20));
    try std.testing.expectEqual(@as(usize, 0), a.job_count);
    try std.testing.expectEqual(@as(usize, 0), a.viewer_opens);
    try std.testing.expectEqual(@as(usize, 0), a.downloads);
}

test "IGSH-463 enqueueing menu reactions leaves sync unchanged even when the queue is full" {
    for ([_]bool{ false, true }) |full| {
        var a = fixture();
        a.queue_full = full;
        var entry = PendingReaction{};
        entry.jid = a.chats[0].jid;
        entry.msg_id = a.messages[0].id;
        entry.emoji.set("❤️");
        enqueueReactionJob(&a, &entry);
        try std.testing.expectEqual(@as(usize, 0), a.sync_pauses);
        try std.testing.expect(a.sync_running);
        try std.testing.expectEqual(@as(usize, if (full) 0 else 1), a.job_count);
        try std.testing.expectEqual(@as(u64, if (full) 3100 else 0), entry.retry_at_ms);
    }
}

test "IGSH-463 unsupported providers never enqueue a WhatsApp reaction" {
    for ([_]transport.Provider{ .slack, .telegram }) |provider| {
        var a = fixture();
        a.chats[0].provider = provider;
        _ = handleCanvasDoubleClick(&a, 20, 20);
        try std.testing.expectEqual(@as(usize, 0), a.job_count);
        try expectReaction(&a, "");
    }
}

test "IGSH-463 loading reactions keeps my thumbs up separate from other senders" {
    var a = fixture();
    a.message_count = 3;
    a.messages[1].reaction_to.set("received-message");
    a.messages[1].from_me = true;
    a.messages[1].reaction.set(a.allocator, "👍");
    a.messages[1].my_reaction.set("👍");
    a.messages[2].reaction_to.set("received-message");
    a.messages[2].reaction.set(a.allocator, "❤️");
    foldReactions(&a);
    try std.testing.expectEqual(@as(usize, 1), a.message_count);
    try std.testing.expectEqualStrings("👍", a.messages[0].my_reaction.slice());
    try std.testing.expect(handleCanvasDoubleClick(&a, 20, 20));
    try std.testing.expectEqualStrings("", a.jobs[0].extra.slice());
}

test "IGSH-463 failure rolls back my reaction and pending refresh preserves the toggle" {
    var a = fixture();
    a.messages[0].my_reaction.set("❤️");
    a.messages[0].reaction.set(a.allocator, "❤️");
    try std.testing.expect(handleCanvasDoubleClick(&a, 20, 20));
    a.messages[0].my_reaction.set("");
    a.messages[0].reaction.set(a.allocator, "");
    reapplyPendingReactions(&a, a.chats[0].jid.slice());
    try expectReaction(&a, "👍");
    a.pending_reactions[0].retries = 3;
    var result = WacliResult{ .msg_id = a.jobs[0].msg_id, .extra = a.jobs[0].extra, .ok = false };
    applyReaction(&a, &result);
    try expectReaction(&a, "❤️");
    try std.testing.expectEqual(@as(usize, 0), a.pending_reaction_count);
}

var app_ptr: ?*App = null;
fn loword(value: usize) u16 {
    return @truncate(value);
}
fn hiword(value: usize) u16 {
    return @truncate(value >> 16);
}
fn canvasStripRect(_: *App) Rect {
    return .{};
}
fn canvasScrollInfo(_: *App) u8 {
    return 0;
}
fn dragStrip(_: *App, _: Rect, _: u8, _: i32, _: @TypeOf(setCanvasScroll)) void {}
fn setCanvasScroll(_: *App, _: i32) void {}
fn handleCanvasClick(a: *App, _: usize, _: i32, _: i32) void {
    a.clicks += 1;
}
fn hitTestWord(_: *Message, x: i32, _: i32) ?usize {
    return @intCast(@divTrunc(x - 10, 30));
}
fn mouse(a: *App, event: u32, x: u16, y: u16) void {
    app_ptr = a;
    defer app_ptr = null;
    _ = canvasProc(1, event, 0, @intCast((@as(u32, y) << 16) | x));
}
fn getString(object: std.json.ObjectMap, key: []const u8) []const u8 {
    return if (object.get(key)) |value| value.string else "";
}

test "IGSH-463 double-click mouse sequence reacts once and consumes the final mouse up" {
    var a = fixture();
    mouse(&a, win.WM_LBUTTONDOWN, 20, 20);
    mouse(&a, win.WM_LBUTTONUP, 20, 20);
    mouse(&a, win.WM_LBUTTONDBLCLK, 20, 20);
    mouse(&a, win.WM_LBUTTONUP, 20, 20);
    try std.testing.expectEqual(@as(usize, 1), a.job_count);
    try std.testing.expectEqual(@as(usize, 1), a.clicks);
    try std.testing.expect(!a.text_dragging);
    mouse(&a, win.WM_LBUTTONDOWN, 20, 20);
    mouse(&a, win.WM_LBUTTONUP, 20, 20);
    mouse(&a, win.WM_LBUTTONDBLCLK, 20, 20);
    mouse(&a, win.WM_LBUTTONUP, 20, 20);
    try std.testing.expectEqual(@as(usize, 2), a.job_count);
    try expectReaction(&a, "");
}

test "IGSH-463 drag text selection still selects words without reacting" {
    var a = fixture();
    mouse(&a, win.WM_LBUTTONDOWN, 20, 20);
    mouse(&a, win.WM_MOUSEMOVE, 80, 20);
    mouse(&a, win.WM_LBUTTONUP, 80, 20);
    try std.testing.expectEqual(@as(?usize, 0), a.sel_message);
    try std.testing.expectEqual(@as(usize, 0), a.sel_anchor_word);
    try std.testing.expectEqual(@as(usize, 2), a.sel_focus_word);
    try std.testing.expectEqual(@as(usize, 0), a.job_count);
    try std.testing.expectEqual(@as(usize, 0), a.clicks);
    try std.testing.expect(!a.text_dragging);
}

test "IGSH-463 reaction JSON loads my emoji only for outgoing reaction events" {
    var a = fixture();
    var parsed = try std.json.parseFromSlice(std.json.Value, a.allocator, "{\"ReactionToID\":\"received-message\",\"ReactionEmoji\":\"👍\"}", .{});
    defer parsed.deinit();
    for ([_]bool{ false, true }) |from_me| {
        var message = Message{ .from_me = from_me };
        loadReaction(&a, &message, parsed.value.object);
        try std.testing.expectEqualStrings(if (from_me) "👍" else "", message.my_reaction.slice());
    }
}

test "IGSH-463 double-click targets another bubble instead of the previously selected message" {
    var a = fixture();
    a.message_count = 2;
    a.messages[1].id.set("other-message");
    a.messages[1].bubble_hit = .{ .left = 10, .top = 120, .right = 200, .bottom = 220 };
    a.selected_message = 0;
    try std.testing.expect(handleCanvasDoubleClick(&a, 20, 140));
    try std.testing.expectEqual(@as(usize, 1), a.job_count);
    try std.testing.expectEqualStrings("other-message", a.jobs[0].msg_id.slice());
    try std.testing.expectEqual(@as(?usize, 1), a.selected_message);
    try std.testing.expectEqualStrings("", a.messages[0].my_reaction.slice());
    try std.testing.expectEqualStrings("👍", a.messages[1].my_reaction.slice());
}

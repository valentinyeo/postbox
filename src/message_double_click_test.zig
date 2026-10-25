const std = @import("std");
const passage = @import("passage");
const timer_passage_scroll = 11;
const message_double_click = @import("message_double_click");
const transport = struct {
    const Provider = enum { whatsapp, slack, telegram, signal };
};
const Rect = struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
const Point = struct { x: i32 = 0, y: i32 = 0 };
const win = struct {
    const HWND = usize;
    const POINT = Point;
    const RECT = Rect;
    const WM_TIMER = 6;
    var timer: usize = 0;
    var cursor: Point = .{};
    fn GetCursorPos(point: *Point) i32 {
        point.* = cursor;
        return 1;
    }
    fn ScreenToClient(_: usize, _: *Point) i32 {
        return 1;
    }
    fn GetClientRect(_: usize, rect: *Rect) i32 {
        rect.* = .{ .right = 400, .bottom = 300 };
        return 1;
    }
    fn UpdateWindow(_: usize) i32 {
        return 1;
    }
    fn SetTimer(_: usize, id: usize, _: u32, _: ?*anyopaque) usize {
        timer = id;
        return 1;
    }
    fn KillTimer(_: usize, _: usize) i32 {
        timer = 0;
        return 1;
    }
    const WM_LBUTTONDOWN = 1;
    const WM_LBUTTONUP = 2;
    const WM_LBUTTONDBLCLK = 3;
    const WM_MOUSEMOVE = 4;
    const WM_CAPTURECHANGED = 5;
    fn SetFocus(_: usize) usize {
        return 1;
    }
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
    reaction_hit: Rect = .{},
    local_path: WideText(519) = .{},
    image: bool = false,
    gif: bool = false,
    text: WideText(4095) = .{},
    word_rects: [3]struct { start: u16, len: u16, rect: Rect } = .{
        .{ .start = 0, .len = 3, .rect = .{ .left = 10, .top = 20, .right = 40, .bottom = 40 } },
        .{ .start = 4, .len = 3, .rect = .{ .left = 40, .top = 20, .right = 70, .bottom = 40 } },
        .{ .start = 8, .len = 5, .rect = .{ .left = 70, .top = 20, .right = 100, .bottom = 40 } },
    },
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
};
const WacliResult = struct {
    msg_id: Utf8Text(191) = .{},
    extra: Utf8Text(63) = .{},
    ok: bool = true,
    http_status: u32 = 0,
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
    scroll_y: i32 = 0,
    max_scroll: i32 = 100,
    text_selection: passage.Selection = .{},
    text_dragging: bool = false,
    drag_moved: bool = false,
    drag_origin: Point = .{},
    sb_drag: enum { none, canvas } = .none,
    clicks: usize = 0,
    sync_running: bool = true,
    sync_pauses: usize = 0,
};
fn unifiedHub(_: *const App) bool {
    return false;
}
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
fn enqueueHubReaction(a: *App, entry: *PendingReaction) void {
    var job = WacliJob{ .provider = entry.provider, .account = entry.account };
    job.jid = entry.jid;
    job.msg_id = entry.msg_id;
    job.extra = entry.emoji;
    if (!wacliEnqueue(a, job, true)) entry.retry_at_ms = win.GetTickCount64() + 3_000;
}
fn wacliEnqueue(a: *App, job: WacliJob, _: bool) bool {
    if (a.queue_full) return false;
    a.jobs[a.job_count] = job;
    a.job_count += 1;
    return true;
}
fn px(_: *const App, value: i32) i32 {
    return value;
}
fn fixture() App {
    win.timer = 0;
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
    try std.testing.expectEqual(@as(usize, 0), a.text_selection.anchor.?.message);
    try std.testing.expectEqual(@as(usize, 0), a.text_selection.anchor.?.word);
    try std.testing.expectEqual(@as(usize, 2), a.text_selection.focus.word);
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

test "IGSH-674 chip reactions preserve other reactions through pending refresh and removal" {
    var a = fixture();
    a.messages[0].reaction.set(a.allocator, "😂 2  ❤️ 1");
    reactToMessageWithChip(&a, a.chats[0].jid.slice(), a.messages[0].id.slice(), "❤️", true);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("😂 2  ❤️ 1"), a.messages[0].reaction.slice());
    try std.testing.expectEqualStrings("❤️", a.messages[0].my_reaction.slice());
    reapplyPendingReactions(&a, a.chats[0].jid.slice());
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("😂 2  ❤️ 1"), a.messages[0].reaction.slice());
    reactToMessageWithChip(&a, a.chats[0].jid.slice(), a.messages[0].id.slice(), "", true);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("😂 2  ❤️ 1"), a.messages[0].reaction.slice());
    try std.testing.expectEqualStrings("", a.messages[0].my_reaction.slice());
    try std.testing.expectEqualStrings("", a.jobs[1].extra.slice());
}

test "IGSH-674 chip reaction failure rolls back both reaction fields" {
    var a = fixture();
    a.messages[0].reaction.set(a.allocator, "❤️");
    reactToMessageWithChip(&a, a.chats[0].jid.slice(), a.messages[0].id.slice(), "❤️", true);
    a.pending_reactions[0].retries = 3;
    var result = WacliResult{ .msg_id = a.jobs[0].msg_id, .extra = a.jobs[0].extra, .ok = false };
    applyReaction(&a, &result);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("❤️"), a.messages[0].reaction.slice());
    try std.testing.expectEqualStrings("", a.messages[0].my_reaction.slice());
    try std.testing.expectEqual(@as(usize, 0), a.pending_reaction_count);
}

test "IGSH-674 chip overlap never triggers double click thumbs up" {
    var a = fixture();
    a.messages[0].reaction_hit = .{ .left = 20, .top = 96, .right = 60, .bottom = 120 };
    try std.testing.expect(!handleCanvasDoubleClick(&a, 30, 98));
    try std.testing.expectEqual(@as(usize, 0), a.job_count);
}

test "IGSH-674 chip mouse down takes priority over passage selection" {
    var a = fixture();
    a.messages[0].reaction_hit = .{ .left = 20, .top = 20, .right = 60, .bottom = 40 };
    mouse(&a, win.WM_LBUTTONDOWN, 30, 30);
    try std.testing.expect(a.text_selection.anchor == null);
    try std.testing.expect(!a.text_dragging);
    try std.testing.expectEqual(@as(usize, 0), win.timer);
    try std.testing.expectEqual(@as(usize, 0), a.job_count);
    mouse(&a, win.WM_LBUTTONUP, 30, 30);
    try std.testing.expectEqual(@as(usize, 1), a.clicks);
}

test "passage mouse drag crosses messages and reverses through the same offsets" {
    var a = fixture();
    a.message_count = 2;
    a.messages[0].text.set(a.allocator, "one two three");
    a.messages[1].text.set(a.allocator, "one two three");
    a.messages[1].bubble_hit = .{ .left = 10, .top = 120, .right = 200, .bottom = 210 };
    for (&a.messages[1].word_rects) |*span| {
        span.rect.top += 110;
        span.rect.bottom += 110;
    }
    mouse(&a, win.WM_LBUTTONDOWN, 50, 20);
    mouse(&a, win.WM_MOUSEMOVE, 50, 130);
    mouse(&a, win.WM_LBUTTONUP, 50, 130);
    try std.testing.expectEqual(@as(usize, 0), a.text_selection.anchor.?.message);
    try std.testing.expectEqual(@as(usize, 1), a.text_selection.focus.message);
    try std.testing.expectEqual(passage.Range{ .start = 4, .end = 13 }, a.text_selection.range(0, 13).?);
    try std.testing.expectEqual(passage.Range{ .start = 0, .end = 7 }, a.text_selection.range(1, 13).?);
    mouse(&a, win.WM_LBUTTONDOWN, 50, 130);
    mouse(&a, win.WM_MOUSEMOVE, 50, 20);
    mouse(&a, win.WM_LBUTTONUP, 50, 20);
    try std.testing.expectEqual(passage.Range{ .start = 4, .end = 13 }, a.text_selection.range(0, 13).?);
    try std.testing.expectEqual(passage.Range{ .start = 0, .end = 7 }, a.text_selection.range(1, 13).?);
}

test "passage focus snaps between bubbles and outside the canvas" {
    var a = fixture();
    a.message_count = 2;
    a.messages[1].bubble_hit = .{ .left = 10, .top = 120, .right = 200, .bottom = 210 };
    for (&a.messages[1].word_rects) |*span| {
        span.rect.top += 110;
        span.rect.bottom += 110;
    }
    updatePassageFocus(&a, 50, 0);
    try std.testing.expectEqual(@as(usize, 0), a.text_selection.focus.message);
    try std.testing.expectEqual(@as(usize, 0), a.text_selection.focus.word);
    updatePassageFocus(&a, 50, 115);
    try std.testing.expectEqual(@as(usize, 1), a.text_selection.focus.message);
    try std.testing.expectEqual(@as(usize, 0), a.text_selection.focus.word);
    updatePassageFocus(&a, 500, 500);
    try std.testing.expectEqual(@as(usize, 1), a.text_selection.focus.message);
    try std.testing.expectEqual(@as(usize, 2), a.text_selection.focus.word);
}

test "passage edge snapping follows message order across opposite bubble alignments" {
    var a = fixture();
    a.message_count = 2;
    a.messages[1].bubble_hit = .{ .left = 900, .top = 120, .right = 1100, .bottom = 210 };
    for (&a.messages[1].word_rects) |*span| {
        span.rect.left += 890;
        span.rect.right += 890;
        span.rect.top += 110;
        span.rect.bottom += 110;
    }
    updatePassageFocus(&a, -1000, 1000);
    try std.testing.expectEqual(@as(usize, 1), a.text_selection.focus.message);
    try std.testing.expectEqual(@as(usize, 2), a.text_selection.focus.word);
    updatePassageFocus(&a, 2000, -1000);
    try std.testing.expectEqual(@as(usize, 0), a.text_selection.focus.message);
    try std.testing.expectEqual(@as(usize, 0), a.text_selection.focus.word);
}

test "passage outside pointer selects at the canvas edge rather than offscreen text" {
    var a = fixture();
    a.messages[0].bubble_hit.bottom = 600;
    a.messages[0].word_rects[1].rect.top = 280;
    a.messages[0].word_rects[1].rect.bottom = 300;
    a.messages[0].word_rects[2].rect.top = 550;
    a.messages[0].word_rects[2].rect.bottom = 570;
    updatePassageFocus(&a, 50, 1000);
    try std.testing.expectEqual(@as(usize, 1), a.text_selection.focus.word);
    a.messages[0].word_count = 0;
    updatePassageFocus(&a, 50, -1000);
    try std.testing.expectEqual(@as(usize, 1), a.text_selection.focus.word);
}

test "passage edge timer scrolls in both directions clamps and stops on release or lost capture" {
    var a = fixture();
    app_ptr = &a;
    defer app_ptr = null;
    _ = canvasProc(1, win.WM_LBUTTONDOWN, 0, @intCast((@as(u32, 20) << 16) | 20));
    try std.testing.expectEqual(@as(usize, timer_passage_scroll), win.timer);
    a.scroll_y = 50;
    win.cursor = .{ .x = 50, .y = 100 };
    _ = canvasProc(1, win.WM_TIMER, timer_passage_scroll, 0);
    try std.testing.expectEqual(@as(i32, 50), a.scroll_y);
    win.cursor.y = 301;
    _ = canvasProc(1, win.WM_TIMER, timer_passage_scroll, 0);
    try std.testing.expectEqual(@as(i32, 26), a.scroll_y);
    a.scroll_y = 5;
    _ = canvasProc(1, win.WM_TIMER, timer_passage_scroll, 0);
    try std.testing.expectEqual(@as(i32, 0), a.scroll_y);
    win.cursor.y = -1;
    a.scroll_y = 95;
    _ = canvasProc(1, win.WM_TIMER, timer_passage_scroll, 0);
    try std.testing.expectEqual(@as(i32, 100), a.scroll_y);
    _ = canvasProc(1, win.WM_LBUTTONUP, 0, @intCast((@as(u32, 20) << 16) | 80));
    try std.testing.expectEqual(@as(usize, 0), win.timer);
    try std.testing.expect(!a.text_dragging);
    _ = canvasProc(1, win.WM_LBUTTONDOWN, 0, @intCast((@as(u32, 20) << 16) | 20));
    _ = canvasProc(1, win.WM_CAPTURECHANGED, 0, 0);
    try std.testing.expectEqual(@as(usize, 0), win.timer);
    try std.testing.expect(!a.text_dragging);
    const previous = a.scroll_y;
    _ = canvasProc(1, win.WM_TIMER, timer_passage_scroll, 0);
    try std.testing.expectEqual(previous, a.scroll_y);
}

const std = @import("std");
const tick_interval_ms = recording_paint.tick_interval_ms;
const Text = struct {
    fn slice(_: Text) []const u8 {
        return "chat";
    }
};
const Note = struct { ogg: []u8, seconds: u32, waveform: [64]u8 };
const State = enum { recording, encoding, ready, failed, idle };
const Session = struct {
    current: State = .recording,
    duration: u64 = 10000,
    reaped: bool = false,
    fn state(self: *Session) State {
        return self.current;
    }
    fn elapsedMs(self: *Session) u64 {
        return self.duration;
    }
    fn reap(self: *Session) void {
        self.reaped = true;
    }
    fn take(_: *Session) ?Note {
        return .{ .ogg = std.testing.allocator.dupe(u8, "encoded voice") catch unreachable, .seconds = 10, .waveform = @splat(17) };
    }
};
const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    hwnd: ?usize = 1,
    voice_btn: ?usize = 2,
    voice_active: bool = true,
    voice_finishing: bool = false,
    voice_session: ?*Session = null,
    voice_jid: Text = .{},
    chats: [1]struct { jid: Text = .{} } = .{.{}},
    selected_chat: usize = 0,
    allowed: bool = true,
    ended: usize = 0,
    cancelled: usize = 0,
    queued: usize = 0,
    status: []const u8 = "",
};
const win = struct {
    const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
    const DRAWITEMSTRUCT = struct { hDC: usize, rcItem: RECT };
    const SRCCOPY = 0;
    var fail_dc = false;
    var fail_bitmap = false;
    var dcs: i32 = 0;
    var bitmaps: i32 = 0;
    var blits: usize = 0;
    var painted: bool = false;
    var selection_restored = false;
    fn CreateCompatibleDC(_: usize) ?usize {
        if (fail_dc) return null;
        dcs += 1;
        return 3;
    }
    fn DeleteDC(_: usize) i32 {
        dcs -= 1;
        return 1;
    }
    fn CreateCompatibleBitmap(_: usize, _: i32, _: i32) ?*anyopaque {
        if (fail_bitmap) return null;
        bitmaps += 1;
        return @ptrFromInt(4);
    }
    fn DeleteObject(_: ?*anyopaque) i32 {
        std.testing.expect(selection_restored) catch unreachable;
        bitmaps -= 1;
        return 1;
    }
    fn SelectObject(_: usize, object: ?*anyopaque) ?*anyopaque {
        selection_restored = object == @as(?*anyopaque, @ptrFromInt(5));
        return @ptrFromInt(5);
    }
    fn BitBlt(destination: usize, x: i32, y: i32, width: i32, height: i32, source: usize, _: i32, _: i32, _: i32) i32 {
        std.testing.expect(painted) catch unreachable;
        std.testing.expectEqual(@as(usize, 9), destination) catch unreachable;
        std.testing.expectEqual(@as(usize, 3), source) catch unreachable;
        std.testing.expectEqual(@as(i32, 10), x) catch unreachable;
        std.testing.expectEqual(@as(i32, 20), y) catch unreachable;
        std.testing.expectEqual(@as(i32, 200), width) catch unreachable;
        std.testing.expectEqual(@as(i32, 44), height) catch unreachable;
        blits += 1;
        return 1;
    }
    const FALSE = 0;
    const TRUE = 1;
    var invalidations: usize = 0;
    var full_window: usize = 0;
    var blanket_window: usize = 0;
    var outside_strip: usize = 0;
    var erased: usize = 0;
    const client = RECT{ .left = 0, .top = 0, .right = 1200, .bottom = 800 };
    const strip = RECT{ .left = 756, .top = 745, .right = 956, .bottom = 789 };
    fn GetClientRect(_: usize, rect: *RECT) i32 {
        rect.* = client;
        return 1;
    }
    fn GetWindowRect(_: usize, rect: *RECT) i32 {
        rect.* = strip;
        return 1;
    }
    fn MapWindowPoints(from: ?usize, to: ?usize, rect: *RECT, _: u32) i32 {
        if (from == 1 and to == 2) {
            rect.left -= strip.left;
            rect.right -= strip.left;
            rect.top -= strip.top;
            rect.bottom -= strip.top;
        }
        return 0;
    }
    fn InvalidateRect(hwnd: usize, rect: ?*const RECT, erase: i32) i32 {
        invalidations += 1;
        if (erase != FALSE) erased += 1;
        if (hwnd == 1 and (rect == null or std.meta.eql(rect.?.*, client))) full_window += 1;
        if (rect == null) blanket_window += 1;
        if (hwnd != 2) outside_strip += 1;
        if (rect) |r| {
            if (r.left < 0 or r.top < 0 or r.right > strip.right - strip.left or r.bottom > strip.bottom - strip.top)
                outside_strip += 1;
        }
        return 1;
    }
};
fn voiceChatAllowed(a: *App) bool {
    return a.allowed;
}
fn cancelVoice(a: *App, _: []const u8) void {
    a.cancelled += 1;
    endVoiceUi(a);
}
fn endVoiceUi(a: *App) void {
    a.ended += 1;
    a.voice_active = false;
}
fn queueVoiceNote(a: *App, jid: []const u8, ogg: []const u8, seconds: u32, waveform: *const [64]u8) bool {
    std.testing.expectEqualStrings("chat", jid) catch unreachable;
    std.testing.expectEqualStrings("encoded voice", ogg) catch unreachable;
    std.testing.expectEqual(@as(u32, 10), seconds) catch unreachable;
    std.testing.expectEqual(@as(u8, 17), waveform[0]) catch unreachable;
    a.queued += 1;
    return true;
}
fn setStatus(a: *App, status: []const u8) void {
    a.status = status;
}

test "IGSH-482 ten seconds at the real recording tick rate never invalidates a whole window or erases" {
    var session = Session{};
    var app = App{ .voice_session = &session };
    win.invalidations = 0;
    win.full_window = 0;
    win.blanket_window = 0;
    win.outside_strip = 0;
    win.erased = 0;
    var elapsed: usize = 0;
    while (elapsed < 10000) : (elapsed += tick_interval_ms) tickVoice(&app);
    if (win.full_window != 0 or win.blanket_window != 0 or win.outside_strip != 0 or win.erased != 0) std.debug.print("recording model: interval={d}ms ticks={d} full-window={d} blanket={d} outside-strip={d} erase={d}\n", .{ tick_interval_ms, win.invalidations, win.full_window, win.blanket_window, win.outside_strip, win.erased });
    try std.testing.expectEqual(@as(usize, @divTrunc(10000 + tick_interval_ms - 1, tick_interval_ms)), win.invalidations);
    try std.testing.expectEqual(@as(usize, 0), win.full_window);
    try std.testing.expectEqual(@as(usize, 0), win.blanket_window);
    try std.testing.expectEqual(@as(usize, 0), win.outside_strip);
    try std.testing.expectEqual(@as(usize, 0), win.erased);
    try std.testing.expectEqual(@as(usize, 0), app.ended);
    try std.testing.expectEqual(@as(usize, 0), app.queued);
}

test "IGSH-482 encoding remains on the recording tick path and ready sends once" {
    var session = Session{ .current = .encoding };
    var app = App{ .voice_session = &session, .voice_finishing = true };
    tickVoice(&app);
    try std.testing.expectEqual(@as(usize, 0), app.ended);
    session.current = .ready;
    tickVoice(&app);
    tickVoice(&app);
    try std.testing.expectEqual(@as(usize, 1), app.ended);
    try std.testing.expectEqual(@as(usize, 1), app.queued);
}

test "IGSH-482 switched chat cancels and failed short recording still reports its error" {
    var session = Session{};
    var app = App{ .voice_session = &session, .allowed = false };
    tickVoice(&app);
    try std.testing.expectEqual(@as(usize, 1), app.cancelled);
    session.current = .failed;
    session.duration = 100;
    app = .{ .voice_session = &session };
    tickVoice(&app);
    try std.testing.expect(session.reaped);
    try std.testing.expectEqualStrings("Voice note too short", app.status);
    try std.testing.expectEqual(@as(usize, 0), app.queued);
}

fn paintVoiceButton(_: *App, item: *win.DRAWITEMSTRUCT) void {
    std.testing.expectEqual(@as(usize, 3), item.hDC) catch unreachable;
    std.testing.expectEqualDeep(win.RECT{ .left = 0, .top = 0, .right = 200, .bottom = 44 }, item.rcItem) catch unreachable;
    win.painted = true;
}

test "IGSH-482 recording strip is painted offscreen then blitted once with no GDI leak" {
    var app = App{};
    var item = win.DRAWITEMSTRUCT{ .hDC = 9, .rcItem = .{ .left = 10, .top = 20, .right = 210, .bottom = 64 } };
    win.blits = 0;
    win.painted = false;
    win.selection_restored = false;
    drawVoiceButton(&app, &item);
    try std.testing.expectEqual(@as(usize, 1), win.blits);
    try std.testing.expectEqual(@as(i32, 0), win.dcs);
    try std.testing.expectEqual(@as(i32, 0), win.bitmaps);
    try std.testing.expectEqual(@as(usize, 9), item.hDC);
    win.fail_bitmap = true;
    drawVoiceButton(&app, &item);
    win.fail_bitmap = false;
    win.fail_dc = true;
    drawVoiceButton(&app, &item);
    win.fail_dc = false;
    try std.testing.expectEqual(@as(usize, 1), win.blits);
    try std.testing.expectEqual(@as(i32, 0), win.dcs);
    try std.testing.expectEqual(@as(i32, 0), win.bitmaps);
}

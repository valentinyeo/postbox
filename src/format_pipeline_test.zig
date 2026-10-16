// Host stubs for the actual load, poll and schedule functions from main.zig.
const std = @import("std");
const format_cache = @import("format_cache");
const format_request = format_cache.format_request;
const Text = struct {
    buf: [20000]u8 = undefined,
    len: usize = 0,
    fn set(self: *@This(), text: []const u8) void {
        self.len = text.len;
        @memcpy(self.buf[0..text.len], text);
    }
    fn slice(self: *const @This()) []const u8 {
        return self.buf[0..self.len];
    }
};
fn Utf8Text(comptime _: usize) type {
    return Text;
}
const Message = struct {
    id: Text = .{},
    transcript: WideText(2047) = .{},
    transcript_state: enum { none, loading, ready, failed } = .none,
    local_path: WideText(519) = .{},
    sender: WideText(159) = .{},
    from_me: bool = false,
};
const Session = struct {
    status: enum { idle, recording, transcribing, ready, failed } = .idle,
    result: []const u8 = summary,
    starts: usize = 0,
    fn state(self: *const @This()) @TypeOf(self.status) {
        return self.status;
    }
    fn takeResult(self: *@This(), destination: []u8) ?[]const u8 {
        if (self.status != .ready) return null;
        @memcpy(destination[0..self.result.len], self.result);
        self.status = .idle;
        return destination[0..self.result.len];
    }
    fn start(self: *@This(), _: []const u8, _: []const u8, _: []const u8, _: []const u8, _: []const u8) bool {
        self.starts += 1;
        self.status = .transcribing;
        return true;
    }
};
const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    cache_tag: Text = .{},
    chats: [1]struct { jid: Text = .{}, name: WideText(159) = .{} } = .{.{}},
    selected_chat: usize = 0,
    chat_count: usize = 1,
    displayed_jid: Text = .{},
    messages: [1]Message = .{.{}},
    message_count: usize = 1,
    openrouter_session: ?*Session = null,
    openrouter_active_id: Text = .{},
    openrouter_active_chat: Text = .{},
    openrouter_active_account: Text = .{},
    openrouter_configured: bool = true,
    openrouter_key: []const u8 = "",
    openrouter_model: []const u8 = "",
    format_workspace: []const u8 = "",
    formatting_requests: format_cache.Requests = .{},
    canvas: ?usize = null,
};
const win = struct {
    const FALSE = 0;
    fn InvalidateRect(_: usize, _: ?usize, _: usize) bool {
        return true;
    }
};
var cache: ?[]u8 = null;
var saved_key: Text = .{};
const summary = "1. Meeting tomorrow\n---\n# Plans\n- Meet at ten";
fn appendDebugLog(_: *App, comptime _: []const u8, _: anytype) void {}
fn ensureOpenRouterSession(a: *App) ?*Session {
    return a.openrouter_session;
}
fn formatCachePath(a: *App, key: format_cache.Key) ?[]u8 {
    return format_cache.filename(a.allocator, key) catch null;
}
fn saveFormattedCache(a: *App, key: format_cache.Key, text: []const u8) void {
    if (cache) |old| a.allocator.free(old);
    cache = format_cache.envelope(a.allocator, key, text) catch unreachable;
    const path = format_cache.filename(a.allocator, key) catch unreachable;
    defer a.allocator.free(path);
    saved_key.set(path);
}
fn readFileWin(allocator: std.mem.Allocator, path: []const u8, _: usize) ?[]u8 {
    if (std.mem.endsWith(u8, path, "audio.ogg.txt")) return allocator.dupe(u8, "raw transcript") catch unreachable;
    if (!std.mem.eql(u8, path, saved_key.slice())) return null;
    return allocator.dupe(u8, cache orelse return null) catch unreachable;
}
fn fixture(session: *Session) App {
    var a = App{ .openrouter_session = session };
    a.cache_tag.set("account-a");
    a.chats[0].jid.set("chat-a");
    a.displayed_jid.set("chat-a");
    a.messages[0].id.set("message-a");
    return a;
}
fn clearCache() void {
    if (cache) |data| std.testing.allocator.free(data);
    cache = null;
    saved_key.len = 0;
}
fn expectTranscript(message: *const Message, expected: []const u8) !void {
    const text = try std.unicode.utf16LeToUtf8Alloc(std.testing.allocator, message.transcript.slice());
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings(expected, text);
}

test "first build loads cached summary without a media path or formatting request" {
    defer clearCache();
    var session = Session{};
    var a = fixture(&session);
    saveFormattedCache(&a, .{ .account = "account-a", .chat = "chat-a", .message = "message-a" }, summary);
    loadTranscriptCache(&a, &a.messages[0]);
    try expectTranscript(&a.messages[0], summary);
    scheduleNextFormatting(&a);
    try std.testing.expectEqual(@as(usize, 0), session.starts);
    // Rebuilt messages and a fresh app (restart) both use the disk result.
    a = fixture(&session);
    loadTranscriptCache(&a, &a.messages[0]);
    try expectTranscript(&a.messages[0], summary);
    scheduleNextFormatting(&a);
    try std.testing.expectEqual(@as(usize, 0), session.starts);
}

test "missing summary shows raw then starts only one request across chat reloads" {
    defer clearCache();
    var session = Session{};
    var a = fixture(&session);
    a.messages[0].local_path.set(a.allocator, "audio.ogg");
    loadTranscriptCache(&a, &a.messages[0]);
    try expectTranscript(&a.messages[0], "raw transcript");
    scheduleNextFormatting(&a);
    scheduleNextFormatting(&a);
    try std.testing.expectEqual(@as(usize, 1), session.starts);
    session.status = .failed;
    pollFormatting(&a);
    a.messages[0] = .{};
    a.messages[0].id.set("message-a");
    a.messages[0].local_path.set(a.allocator, "audio.ogg");
    loadTranscriptCache(&a, &a.messages[0]);
    scheduleNextFormatting(&a);
    try std.testing.expectEqual(@as(usize, 1), session.starts);
}

test "completion after switching chats persists for the original message and restart" {
    defer clearCache();
    var session = Session{};
    var a = fixture(&session);
    a.messages[0].transcript.set(a.allocator, "raw transcript");
    a.messages[0].transcript_state = .ready;
    scheduleNextFormatting(&a);
    // Same message id in another chat must not receive the completed summary.
    a.chats[0].jid.set("chat-b");
    a.displayed_jid.set("chat-b");
    session.status = .ready;
    pollFormatting(&a);
    try expectTranscript(&a.messages[0], "raw transcript");
    try std.testing.expect(cache != null);
    a = fixture(&session);
    loadTranscriptCache(&a, &a.messages[0]);
    try expectTranscript(&a.messages[0], summary);
    scheduleNextFormatting(&a);
    try std.testing.expectEqual(@as(usize, 1), session.starts);
}

test "completion for a removed account is drained without resurrecting its cache" {
    defer clearCache();
    var session = Session{};
    var a = fixture(&session);
    a.messages[0].transcript.set(a.allocator, "raw transcript");
    a.messages[0].transcript_state = .ready;
    scheduleNextFormatting(&a);
    a.cache_tag.set("account-b");
    session.status = .ready;
    pollFormatting(&a);
    try std.testing.expect(cache == null);
    try std.testing.expectEqual(.idle, session.status);
    try expectTranscript(&a.messages[0], "raw transcript");
}

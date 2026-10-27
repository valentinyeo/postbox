const std = @import("std");
const chat_key = @import("chat_key");
const format_cache = struct {
    const max_bytes = 64 * 1024;
};
const transport = struct {
    const Provider = enum { whatsapp, slack, telegram, signal };
};
const Message = struct {
    id: Utf8Text(191) = .{},
    timestamp: Utf8Text(47) = .{},
    time: WideText(15) = .{},
    media_type: Utf8Text(31) = .{},
    local_path: WideText(519) = .{},
    transcript: WideText(2047) = .{},
    visible: bool = true,
};
const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    displayed_provider: transport.Provider = .whatsapp,
    displayed_account: Utf8Text(32) = .{},
    displayed_jid: Utf8Text(191) = .{},
    messages: [5]Message = @splat(.{}),
    message_count: usize = 5,
    selected_message: ?usize = null,
    marked_messages: std.ArrayList(Utf8Text(191)) = .empty,
    marked_chat: chat_key.Stored = .{},
    marked_anchor: Utf8Text(191) = .{},
    marking_message: bool = false,
    transcript_copy_notice: Utf8Text(1023) = .{},
    text_selection: struct {} = .{},
    canvas: ?usize = null,
};
const win = struct {
    const FALSE = 0;
    fn InvalidateRect(_: usize, _: ?usize, _: usize) bool {
        return true;
    }
};
var clipboard: [20000]u16 = undefined;
var clipboard_len: usize = 0;
var raw_texts: [3]?[]const u8 = .{ "first raw", "second raw", "third raw" };
var saved_raw: [20000]u8 = undefined;
var saved_len: usize = 0;
fn readFileWin(allocator: std.mem.Allocator, path: []const u8, _: usize) ?[]u8 {
    for ([_][]const u8{ "a.ogg.txt", "b.ogg.txt", "c.ogg.txt" }, raw_texts) |name, text| {
        if (std.mem.eql(u8, name, path)) return allocator.dupe(u8, text orelse return null) catch unreachable;
    }
    return null;
}
fn writeFileWin(_: []const u8, text: []const u8) void {
    saved_len = text.len;
    @memcpy(saved_raw[0..text.len], text);
}
fn copyRawToClipboard(_: *App, text: []const u16) bool {
    clipboard_len = text.len;
    @memcpy(clipboard[0..text.len], text);
    return true;
}
fn channelMessageVisible(_: *const App, message: *const Message) bool {
    return message.visible;
}
fn setStatus(_: *App, _: []const u8) void {}
fn updateWindowTitle(_: *App) void {}
fn fixture() App {
    raw_texts = .{ "first raw", "second raw", "third raw" };
    clipboard_len = 0;
    var a = App{};
    a.displayed_account.set("account-a");
    a.displayed_jid.set("chat-a");
    for (&a.messages, [_][]const u8{ "third", "text", "first", "missing", "second" }, [_][]const u8{ "03", "04", "01", "05", "02" }) |*message, id, stamp| {
        message.id.set(id);
        message.timestamp.set(stamp);
        message.time.set(a.allocator, stamp);
        message.media_type.set(if (std.mem.eql(u8, id, "text")) "" else "audio");
        message.transcript.set(a.allocator, "1. Formatted display, not the raw words");
    }
    a.messages[0].local_path.set(a.allocator, "c.ogg");
    a.messages[2].local_path.set(a.allocator, "a.ogg");
    a.messages[4].local_path.set(a.allocator, "b.ogg");
    return a;
}
fn expectClipboard(text: []const u8) !void {
    const actual = try std.unicode.utf16LeToUtf8Alloc(std.testing.allocator, clipboard[0..clipboard_len]);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(text, actual);
}

test "marked mixed messages copy raw transcripts oldest first without labels" {
    var a = fixture();
    defer a.marked_messages.deinit(a.allocator);
    for ([_]usize{ 0, 1, 2, 4 }) |index| markMessage(&a, index, false, true);
    try std.testing.expectEqual(@as(usize, 4), markedMessageCount(&a, false));
    try std.testing.expectEqual(@as(usize, 3), markedMessageCount(&a, true));
    copyMarkedTranscripts(&a);
    try expectClipboard("first raw\r\n\r\nsecond raw\r\n\r\nthird raw");
    try std.testing.expectEqualStrings("Copied 3 transcripts", a.transcript_copy_notice.slice());
}

test "missing empty and invalid transcripts are named and never become silent gaps" {
    var a = fixture();
    defer a.marked_messages.deinit(a.allocator);
    raw_texts = .{ "first raw", " \n", "\xff" };
    for (0..a.message_count) |index| markMessage(&a, index, false, true);
    copyMarkedTranscripts(&a);
    try expectClipboard("first raw");
    try std.testing.expectEqualStrings("Copied 1 transcripts. Missing: 02, 03, 05", a.transcript_copy_notice.slice());
    raw_texts[0] = null;
    copyMarkedTranscripts(&a);
    try expectClipboard("first raw");
    try std.testing.expectEqualStrings("Copied 0 transcripts. Missing: 01, 02, 03, 05", a.transcript_copy_notice.slice());
}

test "marks follow IDs through refresh and never cross account or provider" {
    var a = fixture();
    defer a.marked_messages.deinit(a.allocator);
    markMessage(&a, 2, false, true);
    std.mem.swap(Message, &a.messages[0], &a.messages[2]);
    try std.testing.expect(messageMarked(&a, a.messages[0].id.slice()));
    try std.testing.expect(!messageMarked(&a, a.messages[2].id.slice()));
    a.displayed_account.set("account-b");
    try std.testing.expectEqual(@as(usize, 0), markedMessageCount(&a, false));
    a.displayed_account.set("account-a");
    a.displayed_provider = .slack;
    try std.testing.expectEqual(@as(usize, 0), markedMessageCount(&a, false));
    a.displayed_provider = .whatsapp;
    markMessage(&a, 0, false, true);
    try std.testing.expectEqual(@as(usize, 0), markedMessageCount(&a, false));
    markMessage(&a, 0, false, true);
    try std.testing.expect(clearMessageMarks(&a));
    try std.testing.expectEqual(@as(usize, 0), markedMessageCount(&a, false));
}

test "Shift click marks range and Ctrl Shift adds a range" {
    var a = fixture();
    defer a.marked_messages.deinit(a.allocator);
    markMessage(&a, 1, false, true);
    markMessage(&a, 3, true, false);
    try std.testing.expectEqual(@as(usize, 3), markedMessageCount(&a, false));
    try std.testing.expect(!messageMarked(&a, a.messages[0].id.slice()));
    markMessage(&a, 4, true, true);
    try std.testing.expectEqual(@as(usize, 4), markedMessageCount(&a, false));
}

test "long raw Unicode transcripts bypass display truncation and keep original whitespace" {
    var a = fixture();
    defer a.marked_messages.deinit(a.allocator);
    const raw = try a.allocator.alloc(u8, 8000);
    defer a.allocator.free(raw);
    @memset(raw, 'x');
    @memcpy(raw[0.."  1. Grüße\n".len], "  1. Grüße\n");
    raw[raw.len - 1] = '\n';
    raw_texts[0] = raw;
    markMessage(&a, 2, false, true);
    copyMarkedTranscripts(&a);
    try expectClipboard(raw);
    saveTranscriptCache(&a, &a.messages[2], raw);
    try std.testing.expectEqualStrings(raw, saved_raw[0..saved_len]);
}

test "Shift starts from the focused message and excludes hidden thread replies" {
    var a = fixture();
    defer a.marked_messages.deinit(a.allocator);
    a.selected_message = 1;
    a.messages[2].visible = false;
    markMessage(&a, 4, true, false);
    try std.testing.expectEqual(@as(usize, 3), markedMessageCount(&a, false));
    try std.testing.expect(!messageMarked(&a, a.messages[2].id.slice()));
    markMessage(&a, 3, true, false);
    try std.testing.expectEqual(@as(usize, 2), markedMessageCount(&a, false));
    try std.testing.expect(messageMarked(&a, a.messages[1].id.slice()));
}

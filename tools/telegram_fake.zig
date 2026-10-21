const std = @import("std");
const tg = @import("telegram.zig");
const tj = @import("telegram_json.zig");
const transport = @import("transport.zig");
const chat_key = @import("chat_key.zig");
const messenger_view = @import("messenger_view.zig");
const alloc = std.testing.allocator;
const io = std.testing.io;
extern fn tg_fake_push(text: [*:0]const u8) void;
extern fn tg_fake_request() ?[*:0]const u8;

fn push(text: []const u8) !void {
    const z = try alloc.dupeZ(u8, text);
    defer alloc.free(z);
    tg_fake_push(z);
}

fn request(kind: []const u8) !std.json.Parsed(std.json.Value) {
    const raw = tg_fake_request() orelse return error.MissingRequest;
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, std.mem.span(raw), .{ .allocate = .alloc_always });
    errdefer parsed.deinit();
    try std.testing.expectEqualStrings(kind, parsed.value.object.get("@type").?.string);
    return parsed;
}

fn next(client: *tg.Client, tag: std.meta.Tag(tg.Event)) !tg.Event {
    for (0..2000) |_| {
        if (client.poll()) |event| {
            if (std.meta.activeTag(event) == tag) return event;
            var discarded = event;
            discarded.deinit(alloc);
        } else try io.sleep(.fromMilliseconds(1), .awake);
    }
    return error.MissingEvent;
}

fn consumed(client: *tg.Client, tag: std.meta.Tag(tg.Event)) !void {
    var event = try next(client, tag);
    event.deinit(alloc);
}

fn create() !*tg.Client {
    return tg.Client.create(alloc, io, 1, "fixture-app-hash", "fixture-data") orelse error.CreateFailed;
}

fn pushChat(client: *tg.Client, id: i64, group: bool, channel: bool) !void {
    const text = try std.fmt.allocPrint(alloc, "{{\"@type\":\"updateNewChat\",\"chat\":{{\"@type\":\"chat\",\"id\":{d},\"title\":\"Example chat\",\"unread_count\":3,\"type\":{{\"@type\":\"{s}\",\"is_channel\":{s}}}}}}}", .{ id, if (group) "chatTypeSupergroup" else "chatTypePrivate", if (channel) "true" else "false" });
    defer alloc.free(text);
    try push(text);
    try consumed(client, .chat);
}

fn pushMessage(client: *tg.Client, id: i64, text: []const u8) !void {
    const update = try std.fmt.allocPrint(alloc, "{{\"@type\":\"updateNewMessage\",\"message\":{{\"@type\":\"message\",\"id\":{d},\"chat_id\":7,\"date\":1700000000,\"content\":{{\"@type\":\"messageText\",\"text\":{{\"@type\":\"formattedText\",\"text\":\"{s}\"}}}}}}}}", .{ id, text });
    defer alloc.free(update);
    try push(update);
    try consumed(client, .message);
}

fn ok(name: []const u8) void {
    std.debug.print("\nTG_FAKE_OK {s}\n", .{name});
}

test "fake login" {
    const client = try create();
    defer client.destroy();
    client.authPhone("fixture-phone");
    try push("{\"@type\":\"authorizationStateWaitTdlibParameters\"}");
    var parameters = try request("setTdlibParameters");
    defer parameters.deinit();
    try std.testing.expectEqual(@as(i64, 1), parameters.value.object.get("api_id").?.integer);
    try push("{\"@type\":\"authorizationStateWaitPhoneNumber\"}");
    var phone = try request("setAuthenticationPhoneNumber");
    defer phone.deinit();
    try std.testing.expectEqualStrings("fixture-phone", phone.value.object.get("phone_number").?.string);
    try push("{\"@type\":\"authorizationStateWaitCode\"}");
    while (true) {
        var event = try next(client, .auth);
        defer event.deinit(alloc);
        if (event.auth.state == .wait_code) break;
    }
    client.authCode("fixture-code");
    var code = try request("checkAuthenticationCode");
    defer code.deinit();
    try std.testing.expectEqualStrings("fixture-code", code.value.object.get("code").?.string);
    try push("{\"@type\":\"authorizationStateWaitPassword\"}");
    try consumed(client, .auth);
    client.authPassword("fixture-password");
    var password = try request("checkAuthenticationPassword");
    defer password.deinit();
    try std.testing.expectEqualStrings("fixture-password", password.value.object.get("password").?.string);
    try push("{\"@type\":\"authorizationStateReady\"}");
    try consumed(client, .auth);
    try std.testing.expectEqual(tg.AuthState.ready, client.authState());
    ok("login");
}

test "fake list" {
    const client = try create();
    defer client.destroy();
    client.requestChats();
    var sent = try request("getChats");
    defer sent.deinit();
    var loading = try request("loadChats");
    defer loading.deinit();
    try push("{\"@type\":\"ok\",\"@extra\":\"load_chats\"}");
    var more = try request("loadChats");
    defer more.deinit();
    try push("{\"@type\":\"error\",\"code\":404,\"message\":\"Not Found\",\"@extra\":\"load_chats\"}");
    for (0..140) |index| try pushChat(client, @intCast(index + 1), index % 3 != 0, index % 3 == 2);
    try push("{\"@type\":\"chats\",\"chat_ids\":[1,2,3],\"total_count\":140}");
    try consumed(client, .chats_synced);
    try pushChat(client, 2, true, false);
    try push("{\"@type\":\"updateChatReadInbox\",\"chat_id\":2,\"unread_count\":0}");
    try consumed(client, .chat);
    const snapshot = client.chatSnapshot(alloc);
    defer client.freeChatSnapshot(alloc, snapshot);
    try std.testing.expectEqual(@as(usize, 140), snapshot.len);
    for (snapshot) |item| {
        try std.testing.expectEqualStrings("Example chat", item.title);
        if (item.id == 2) {
            try std.testing.expect(item.is_group and item.unread_count == 0);
        } else try std.testing.expectEqual(@as(i32, 3), item.unread_count);
        if (item.id == 3) try std.testing.expect(item.is_channel);
    }
    ok("list");
}

test "fake history" {
    const client = try create();
    defer client.destroy();
    const app = try fixture(client);
    defer freeFixture(app);
    app.displayed_jid.set("");
    refreshTelegramMessages(app);
    var sent = try request("getChatHistory");
    defer sent.deinit();
    try std.testing.expectEqual(@as(i64, 7), sent.value.object.get("chat_id").?.integer);
    try push("{\"@type\":\"messages\",\"messages\":[{\"@type\":\"message\",\"id\":20,\"chat_id\":7,\"date\":1700000001,\"content\":{\"@type\":\"messagePhoto\",\"photo\":{\"@type\":\"photo\",\"sizes\":[{\"photo\":{\"@type\":\"file\",\"id\":51,\"local\":{\"path\":\"cached.png\",\"is_downloading_completed\":true}}}]}}},{\"@type\":\"message\",\"id\":10,\"chat_id\":7,\"date\":1700000000,\"content\":{\"@type\":\"messageVoiceNote\",\"voice_note\":{\"@type\":\"voiceNote\",\"duration\":12,\"mime_type\":\"audio/ogg\",\"voice\":{\"@type\":\"file\",\"id\":77}}}}]}");
    try consumed(client, .history_done);
    const snapshot = client.historySnapshot(alloc, 7);
    defer client.freeHistorySnapshot(alloc, snapshot);
    try std.testing.expectEqual(@as(usize, 2), snapshot.len);
    for (snapshot) |msg| {
        if (msg.id == 20) {
            try std.testing.expectEqual(@as(i32, 51), msg.file_id);
            try std.testing.expectEqualStrings("cached.png", msg.local_path);
        } else {
            try std.testing.expectEqual(@as(i32, 77), msg.file_id);
            try std.testing.expectEqual(@as(i32, 12000), msg.duration_ms);
        }
    }
    refreshTelegramMessages(app);
    try std.testing.expectEqualStrings("10", app.messages[0].id.slice());
    try std.testing.expectEqualStrings("20", app.messages[1].id.slice());
    var download = try request("downloadFile");
    defer download.deinit();
    try std.testing.expectEqual(@as(i64, 77), download.value.object.get("file_id").?.integer);
    ok("history");
}

test "fake send" {
    const client = try create();
    defer client.destroy();
    try pushChat(client, 7, true, false);
    try std.testing.expect(client.sendText(7, "Example \"text\"\nline"));
    var sent = try request("sendMessage");
    defer sent.deinit();
    try std.testing.expectEqual(@as(i64, 7), sent.value.object.get("chat_id").?.integer);
    const content = sent.value.object.get("input_message_content").?.object;
    try std.testing.expectEqualStrings("inputMessageText", content.get("@type").?.string);
    try std.testing.expectEqualStrings("Example \"text\"\nline", content.get("text").?.object.get("text").?.string);
    try push("{\"@type\":\"message\",\"id\":-1,\"chat_id\":7,\"sending_state\":{\"@type\":\"messageSendingStatePending\"},\"content\":{\"@type\":\"messageText\",\"text\":{\"text\":\"pending\"}}}");
    try consumed(client, .message);
    try push("{\"@type\":\"updateMessageSendSucceeded\",\"old_message_id\":-1,\"message\":{\"@type\":\"message\",\"id\":30,\"chat_id\":7,\"is_outgoing\":true,\"content\":{\"@type\":\"messageText\",\"text\":{\"text\":\"sent\"}}}}");
    try consumed(client, .message);
    const snapshot = client.historySnapshot(alloc, 7);
    defer client.freeHistorySnapshot(alloc, snapshot);
    try std.testing.expectEqual(@as(usize, 1), snapshot.len);
    try std.testing.expect(snapshot[0].id == 30 and !snapshot[0].sending);
    ok("send");
}

test "fake send_file" {
    const client = try create();
    defer client.destroy();
    const app = try fixture(client);
    defer freeFixture(app);
    for ([_][]const u8{ "fixture/photo.png", "fixture/report.pdf" }, [_][]const u8{ "inputMessagePhoto", "inputMessageDocument" }, [_][]const u8{ "photo", "document" }) |path, kind, field| {
        if (comptime @hasDecl(@This(), "stageTelegramFile")) {
            try std.testing.expect(@field(@This(), "stageTelegramFile")(app, path));
            try std.testing.expect(!app.staged_image.owned);
            try std.testing.expectEqualStrings(path, app.staged_image.path.slice());
        }
        sendTelegram(app, "caption", path);
        var sent = try request("sendMessage");
        defer sent.deinit();
        const content = sent.value.object.get("input_message_content").?.object;
        try std.testing.expectEqualStrings(kind, content.get("@type").?.string);
        const file = content.get(field).?.object;
        try std.testing.expectEqualStrings("inputFileLocal", file.get("@type").?.string);
        try std.testing.expectEqualStrings(path, file.get("path").?.string);
        try std.testing.expectEqualStrings("caption", content.get("caption").?.object.get("text").?.string);
    }
    if (comptime @hasDecl(@This(), "stageTelegramFile")) {
        const before = deleted_files;
        try std.testing.expect(@field(@This(), "stageTelegramFile")(app, "fixture/original.pdf"));
        discardStagedImage(app);
        try std.testing.expectEqual(before, deleted_files);
        app.staged_image.path.set("fixture/owned.png");
        discardStagedImage(app);
        try std.testing.expectEqual(before + 1, deleted_files);
    }
    ok("send_file");
}

test "fake reply" {
    const client = try create();
    defer client.destroy();
    try push("{\"@type\":\"updateNewMessage\",\"message\":{\"@type\":\"message\",\"id\":20,\"chat_id\":7,\"reply_to\":{\"@type\":\"messageReplyToMessage\",\"chat_id\":7,\"message_id\":10},\"content\":{\"@type\":\"messageText\",\"text\":{\"text\":\"Reply body\"}}}}");
    try consumed(client, .message);
    var original = try request("getMessage");
    defer original.deinit();
    try std.testing.expectEqual(@as(i64, 10), original.value.object.get("message_id").?.integer);
    try push("{\"@type\":\"message\",\"id\":10,\"chat_id\":7,\"content\":{\"@type\":\"messageText\",\"text\":{\"text\":\"Original text\"}}}");
    try consumed(client, .message);
    const app = try fixture(client);
    defer freeFixture(app);
    refreshTelegramMessages(app);
    try std.testing.expectEqual(@as(usize, 2), app.message_count);
    var found = false;
    for (app.messages[0..app.message_count]) |*msg| {
        if (std.mem.eql(u8, msg.id.slice(), "20")) {
            try wideEqual("Original text", msg.quote.slice());
            try wideEqual("Reply body", msg.text.slice());
            found = true;
        }
    }
    try std.testing.expect(found);
    app.reply_to.set("10");
    sendTelegram(app, "New reply", "");
    var sent = try request("sendMessage");
    defer sent.deinit();
    try std.testing.expectEqual(@as(i64, 10), sent.value.object.get("reply_to").?.object.get("message_id").?.integer);
    ok("reply");
}

test "fake live" {
    const client = try create();
    defer client.destroy();
    try pushMessage(client, 10, "Earlier");
    try pushMessage(client, 20, "Live text");
    try push("{\"@type\":\"updateMessageContent\",\"chat_id\":7,\"message_id\":20,\"new_content\":{\"@type\":\"messageText\",\"text\":{\"text\":\"Edited text\"}}}");
    try consumed(client, .message);
    const edited = client.historySnapshot(alloc, 7);
    defer client.freeHistorySnapshot(alloc, edited);
    try std.testing.expectEqual(@as(usize, 2), edited.len);
    try std.testing.expectEqualStrings("Edited text", edited[0].text);
    try push("{\"@type\":\"updateDeleteMessages\",\"chat_id\":7,\"message_ids\":[10,20]}");
    try consumed(client, .deleted);
    const empty = client.historySnapshot(alloc, 7);
    defer client.freeHistorySnapshot(alloc, empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try pushMessage(client, 30, "Newest");
    const app = try fixture(client);
    defer freeFixture(app);
    refreshTelegramMessages(app);
    try std.testing.expectEqual(@as(usize, 1), app.message_count);
    try wideEqual("Newest", app.messages[0].text.slice());
    client.markRead(7, 30);
    var sent = try request("viewMessages");
    defer sent.deinit();
    try std.testing.expectEqual(@as(i64, 30), sent.value.object.get("message_ids").?.array.items[0].integer);
    try push("{\"@type\":\"updateFile\",\"file\":{\"id\":51,\"local\":{\"path\":\"downloaded.png\",\"is_downloading_completed\":true}}}");
    var file = try next(client, .file);
    defer file.deinit(alloc);
    try std.testing.expectEqualStrings("downloaded.png", file.file.local_path);
    ok("live");
}

test "fake inbox" {
    const client = try create();
    defer client.destroy();
    for (0..70) |index| try pushChat(client, @intCast(index + 1), index % 2 == 0, index == 2);
    const app = try fixture(client);
    defer freeFixture(app);
    app.chats[0].provider = .whatsapp;
    app.chats[0].jid.set("7");
    const snapshot = client.chatSnapshot(alloc);
    defer client.freeChatSnapshot(alloc, snapshot);
    for (snapshot) |item| {
        var info = item;
        upsertTgChat(app, &info);
    }
    appendTelegramChats(app, null);
    try std.testing.expectEqual(@as(usize, 71), app.chat_count);
    try std.testing.expectEqual(transport.Provider.whatsapp, app.chats[0].provider);
    for (app.chats[1..app.chat_count]) |row| {
        try std.testing.expectEqual(transport.Provider.telegram, row.provider);
        try std.testing.expect(row.unread_count == 3 and row.unread);
    }
    app.chat_count = 1;
    appendTelegramChats(app, "missing");
    try std.testing.expectEqual(@as(usize, 1), app.chat_count);
    app.unread_only = true;
    app.tg_chats[0].unread_count = 0;
    appendTelegramChats(app, "EXAMPLE");
    try std.testing.expectEqual(@as(usize, 70), app.chat_count);
    app.chat_count = 1;
    app.view = .whatsapp;
    appendTelegramChats(app, null);
    try std.testing.expectEqual(@as(usize, 1), app.chat_count);
    ok("inbox");
}

fn wideEqual(expected: []const u8, wide: []const u16) !void {
    const text = try std.unicode.utf16LeToUtf8Alloc(alloc, wide);
    defer alloc.free(text);
    try std.testing.expectEqualStrings(expected, text);
}

const max_messages = 32;
const Message = struct {
    id: Utf8Text(191) = .{},
    sender_jid: Utf8Text(191) = .{},
    sender: WideText(159) = .{},
    from_me: bool = false,
    text: WideText(4095) = .{},
    quote: WideText(4095) = .{},
    quote_sender: WideText(159) = .{},
    mime_type: Utf8Text(127) = .{},
    local_path: WideText(519) = .{},
    tg_file_id: i32 = 0,
    media_type: Utf8Text(31) = .{},
    time: WideText(15) = .{},
};
const App = struct {
    allocator: std.mem.Allocator = alloc,
    telegram: ?*tg.Client,
    tg_auth: tg.AuthState = .ready,
    tg_account: Utf8Text(32) = .{},
    tg_chats: []TgChat,
    tg_chat_count: usize = 0,
    chats: []Chat,
    chat_count: usize = 1,
    selected_chat: usize = 0,
    unread_only: bool = false,
    view: messenger_view.View = .all,
    messages: [max_messages]Message = @splat(.{}),
    message_count: usize = 0,
    selected_message: ?usize = null,
    displayed_jid: Utf8Text(191) = .{},
    displayed_account: Utf8Text(32) = .{},
    displayed_provider: transport.Provider = .telegram,
    displayed_timestamp: Utf8Text(47) = .{},
    scroll_y: i32 = 0,
    canvas: ?usize = null,
    compose: ?usize = 1,
    staged_image: StagedImage = .{},
    hwnd: ?usize = null,
    reply_to: Utf8Text(191) = .{},
    compose_client_width: i32 = 0,
    compose_client_height: i32 = 0,
};
fn fixture(client: *tg.Client) !*App {
    const app = try alloc.create(App);
    app.* = .{ .telegram = client, .chats = try alloc.alloc(Chat, 256), .tg_chats = try alloc.alloc(TgChat, max_tg_chats) };
    @memset(app.tg_chats, .{});
    @memset(app.chats, .{});
    app.tg_account.set("fixture-account");
    app.chats[0].provider = .telegram;
    app.chats[0].account = app.tg_account;
    app.displayed_account = app.tg_account;
    app.chats[0].jid.set("7");
    app.displayed_jid.set("7");
    return app;
}
fn freeFixture(app: *App) void {
    alloc.free(app.chats);
    alloc.free(app.tg_chats);
    alloc.destroy(app);
}
fn activeChatView(app: *App) messenger_view.View {
    return app.view;
}
fn clearMessages(app: *App) void {
    app.message_count = 0;
}
fn formatTime(_: *WideText(15), _: std.mem.Allocator, _: []const u8) void {}
fn isAudio(_: *Message) bool {
    return false;
}
fn loadTranscriptCache(_: *App, _: *Message) void {}
fn stopAudio(_: *App) void {}
fn markChatRead(_: *App) void {}
fn setStatus(_: *App, _: []const u8) void {}
fn focusCompose(_: *App) void {}
fn saveComposerDraft(_: *App) void {}
fn clearReply(app: *App) void {
    app.reply_to.set("");
}
fn layout(_: *App, _: i32, _: i32) void {}
fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
var deleted_files: usize = 0;
fn deleteFileUtf8(_: []const u8) void {
    deleted_files += 1;
}
const win = struct {
    const HBITMAP = usize;
    fn DeleteObject(_: usize) i32 {
        return 1;
    }
    const TRUE = 1;
    fn InvalidateRect(_: usize, _: ?*anyopaque, _: i32) i32 {
        return 1;
    }
    fn SetWindowTextW(_: usize, _: [*:0]const u16) i32 {
        return 1;
    }
};

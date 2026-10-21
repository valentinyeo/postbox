const std = @import("std");
const hub = @import("wa_hub.zig");
const chat_key = @import("chat_key.zig");
const outbox = @import("outbox.zig");
const key = chat_key.Key{ .provider = .whatsapp, .account = "personal", .id = "15550000001@s.whatsapp.net" };

fn body(allocator: std.mem.Allocator, request: hub.Request) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, allocator, request.body, .{});
}

test "accounts retain linked state and account identity" {
    var accounts = try hub.parseAccounts(
        std.testing.allocator,
        "[{\"account\":\"personal\",\"jid\":\"15550000002@s.whatsapp.net\",\"state\":\"linked\",\"last_event_at\":\"2026-01-01T00:00:00Z\"},{\"account\":\"business\",\"state\":\"logged_out\"}]",
    );
    defer accounts.deinit();
    try std.testing.expectEqualStrings("/v1/accounts", hub.accounts().path);
    try std.testing.expectEqualStrings("personal", accounts.value[0].account);
    try std.testing.expectEqualStrings("logged_out", accounts.value[1].state);
}

test "request paths encode query values and pagination boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const chats = try hub.chats(allocator, "personal", false, 250);
    try std.testing.expectEqualStrings("GET", chats.method);
    try std.testing.expectEqualStrings("/v1/chats?account=personal&archived=false&limit=250", chats.path);
    const archived = try hub.chats(allocator, "personal", true, 500);
    try std.testing.expect(std.mem.indexOf(u8, archived.path, "archived=true") != null);
    const messages = try hub.messages(allocator, key, 80, "MSG:2026-01-01T00:00:00Z");
    try std.testing.expectEqualStrings("/v1/messages?account=personal&chat=15550000001%40s.whatsapp.net&limit=80&before=MSG%3A2026-01-01T00%3A00%3A00Z", messages.path);
    try std.testing.expectEqualStrings("/v1/groups?account=personal&limit=200", (try hub.list(allocator, "personal", .groups)).path);
    var wrong = key;
    wrong.provider = .slack;
    try std.testing.expectError(error.WrongProvider, hub.messages(allocator, wrong, 80, ""));
}

test "chat rows normalize into existing summary and envelope without merging accounts" {
    const allocator = std.testing.allocator;
    const normalized = try hub.normalize(
        allocator,
        "[{\"jid\":\"personal:15550000001@s.whatsapp.net\",\"name\":\"Fixture Chat\",\"kind\":\"direct\",\"last_message_ts\":\"2026-01-01T00:00:00Z\",\"unread_count\":2}]",
        "personal",
        .chats,
    );
    defer allocator.free(normalized);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, normalized, .{});
    defer parsed.deinit();
    const summary = hub.chatSummary(parsed.value.object.get("data").?.array.items[0].object);
    try std.testing.expectEqualStrings(key.id, summary.id);
    try std.testing.expectEqualStrings("Fixture Chat", summary.name);
    try std.testing.expectEqual(@as(i32, 2), summary.unread_count);
    try std.testing.expect(!summary.is_group);
    try std.testing.expectError(error.WrongAccount, hub.normalize(allocator, "[{\"jid\":\"business:15550000001@s.whatsapp.net\"}]", "personal", .chats));
    try std.testing.expectError(error.BadResponse, hub.normalize(allocator, "{}", "personal", .chats));
    var other = key;
    other.account = "business";
    try std.testing.expect(!chat_key.Key.eql(key, other));
    const first = try hub.cacheName(allocator, key, "MSG");
    defer allocator.free(first);
    const second = try hub.cacheName(allocator, other, "MSG");
    defer allocator.free(second);
    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "message and group replies retain production parser fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const normalized = try hub.normalize(
        allocator,
        "[{\"MsgID\":\"personal:MSG\",\"ChatJID\":\"personal:15550000001@s.whatsapp.net\",\"Timestamp\":\"2026-01-01T00:00:00Z\",\"Text\":\"Fixture message\",\"FromMe\":false,\"MediaType\":\"image\",\"Filename\":\"fixture.png\",\"MimeType\":\"image/png\",\"quoted_msg_id\":\"QUOTE\"}]",
        "personal",
        .messages,
    );
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, normalized, .{});
    defer parsed.deinit();
    const row = parsed.value.object.get("data").?.object.get("messages").?.array.items[0].object;
    try std.testing.expectEqualStrings("MSG", row.get("MsgID").?.string);
    try std.testing.expectEqualStrings(key.id, row.get("ChatJID").?.string);
    try std.testing.expectEqualStrings("image", row.get("MediaType").?.string);
    try std.testing.expectEqualStrings("QUOTE", row.get("quoted_msg_id").?.string);
    const groups = try hub.normalize(allocator, "[{\"JID\":\"personal:fixture@g.us\",\"Name\":\"Fixture Group\"}]", "personal", .groups);
    try std.testing.expect(std.mem.indexOf(u8, groups, "personal:") == null);
}

test "text and reply retries carry the persisted outbox id and JSON escaping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var entry = outbox.Entry{};
    entry.id = outbox.hexId(@splat(7));
    const first = try hub.send(allocator, key, "Fixture \"text\"\n", "QUOTE", entry.idSlice());
    const retry = try hub.send(allocator, key, "Fixture \"text\"\n", "QUOTE", entry.idSlice());
    try std.testing.expectEqualStrings("POST", first.method);
    try std.testing.expectEqualStrings("/v1/send", first.path);
    try std.testing.expectEqualStrings(first.body, retry.body);
    var parsed = try body(allocator, first);
    defer parsed.deinit();
    try std.testing.expectEqualStrings(entry.idSlice(), parsed.value.object.get("client_id").?.string);
    try std.testing.expectEqualStrings("QUOTE", parsed.value.object.get("reply_to").?.string);
    try std.testing.expectEqualStrings("Fixture \"text\"\n", parsed.value.object.get("text").?.string);
    try std.testing.expectError(error.InvalidSend, hub.send(allocator, key, "Fixture", "", ""));
    var sent = try hub.parseSend(allocator, "{\"client_id\":\"fixture-id\",\"msg_id\":\"MSG\",\"ts\":\"2026-01-01T00:00:00Z\",\"status\":\"sent\"}");
    defer sent.deinit();
    try std.testing.expectEqualStrings("sent", sent.value.status);
    var unknown = try hub.parseSend(allocator, "{\"client_id\":\"fixture-id\",\"status\":\"unknown\"}");
    defer unknown.deinit();
    try std.testing.expectEqualStrings("unknown", unknown.value.status);
}

test "multipart files and voice notes carry client id reply and ptt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const boundary = "0123456789abcdef0123456789abcdef";
    const file = try hub.sendFile(allocator, key, "Fixture caption", "QUOTE", "fixture-id", "fixture.png", "fixture bytes", false, boundary);
    const voice = try hub.sendFile(allocator, key, "", "", "voice-id", "voice.ogg", "OggSfixture", true, boundary);
    try std.testing.expect(std.mem.startsWith(u8, file.content_type, "multipart/form-data; boundary="));
    try std.testing.expect(std.mem.indexOf(u8, file.body, "name=\"client_id\"\r\n\r\nfixture-id\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, file.body, "name=\"reply_to\"\r\n\r\nQUOTE\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, voice.body, "name=\"ptt\"\r\n\r\ntrue\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, voice.body, "filename=\"voice.ogg\"") != null);
    try std.testing.expectError(error.InvalidBoundary, hub.sendFile(allocator, key, "", "", "fixture-id", "fixture.bin", boundary, false, boundary));
}

test "reaction mark-read and archive build scoped writes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const reaction = try hub.react(allocator, key, "MSG", "👍", "reaction-id");
    try std.testing.expectEqualStrings("/v1/react", reaction.path);
    var parsed = try body(allocator, reaction);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("reaction-id", parsed.value.object.get("client_id").?.string);
    const read = try hub.markRead(allocator, key);
    try std.testing.expectEqualStrings("/v1/mark-read", read.path);
    const archive = try hub.archive(allocator, key, true);
    try std.testing.expectEqualStrings("/v1/archive", archive.path);
    var archived = try body(allocator, archive);
    defer archived.deinit();
    try std.testing.expect(archived.value.object.get("archived").?.bool);
    try std.testing.expectEqualStrings("personal", archived.value.object.get("account").?.string);
    var unarchived = try body(allocator, try hub.archive(allocator, key, false));
    defer unarchived.deinit();
    try std.testing.expect(!unarchived.value.object.get("archived").?.bool);
}

test "pending media is polled at the same scoped path until ready" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const request = try hub.binary(allocator, key, "personal:MEDIA");
    try std.testing.expectEqualStrings("/v1/media/personal/15550000001%40s.whatsapp.net/MEDIA", request.path);
    const replies = [_]u32{ 202, 202, 200 };
    var polls: usize = 0;
    for (replies) |status| {
        polls += 1;
        if (try hub.mediaState(status) == .ready) break;
        try std.testing.expectEqualStrings(request.path, (try hub.binary(allocator, key, "MEDIA")).path);
    }
    try std.testing.expectEqual(@as(usize, 3), polls);
    try std.testing.expectEqual(.unavailable, try hub.mediaState(410));
    try std.testing.expectError(error.HttpFailed, hub.mediaState(401));
    try std.testing.expectEqualStrings("/v1/avatar/personal/15550000001%40s.whatsapp.net", (try hub.binary(allocator, key, null)).path);
}

test "fragmented SSE frames resume only after valid events with Last-Event-ID" {
    var sse = hub.Sse{};
    const stream = ": heartbeat\r\n\r\nid: 41\r\ndata: {\"id\":41,\"account\":\"personal\",\"chat\":\"personal:15550000001@s.whatsapp.net\",\"kind\":\"msg\",\"ts\":\"2026-01-01T00:00:00Z\"}\r\n\r\nid: 42\ndata: {\"id\":42,\"kind\":\"reset\"}\n\n";
    var count: usize = 0;
    for (stream) |byte| {
        if (try sse.push(byte)) |frame| {
            var event = (try sse.parse(std.testing.allocator, frame)) orelse continue;
            defer event.deinit();
            if (count == 0) try std.testing.expect(chat_key.Key.eql(key, event.value.key()));
            count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings("42", sse.lastId());
    const reconnect = hub.events(sse.lastId());
    try std.testing.expectEqualStrings("/v1/events", reconnect.path);
    try std.testing.expectEqualStrings("42", reconnect.last_event_id);
    try std.testing.expectError(error.BadEventId, sse.parse(std.testing.allocator, "id: 43\ndata: {\"id\":44,\"kind\":\"msg\"}\n\n"));
    try std.testing.expectEqualStrings("42", sse.lastId());
}

test "bridge endpoints require HTTPS outside isolated loopback verification" {
    const endpoint = try hub.Endpoint.parse("https://bridge.example.test:8443/", false);
    try std.testing.expect(endpoint.secure);
    try std.testing.expectEqual(@as(u16, 8443), endpoint.port);
    try std.testing.expectEqualStrings("bridge.example.test", endpoint.host);
    try std.testing.expectError(error.InsecureBridgeUrl, hub.Endpoint.parse("http://bridge.example.test", false));
    try std.testing.expectError(error.InsecureBridgeUrl, hub.Endpoint.parse("http://127.0.0.1:8792", false));
    try std.testing.expect(!(try hub.Endpoint.parse("http://127.0.0.1:8792", true)).secure);
    try std.testing.expectError(error.InvalidBridgeUrl, hub.Endpoint.parse("https://bridge.example.test/path", false));
    try std.testing.expectError(error.InvalidBridgeUrl, hub.Endpoint.parse("https://bridge.example.test?key=fixture", false));
}

test "cached media retains Windows file associations without accepting paths" {
    try std.testing.expectEqualStrings(".mp4", hub.mediaExtension("clip.f4v", "video/mp4", "video"));
    try std.testing.expectEqualStrings(".ogg", hub.mediaExtension("", "audio/ogg", "audio"));
    try std.testing.expectEqualStrings(".pdf", hub.mediaExtension("", "application/pdf", "document"));
    try std.testing.expectEqualStrings(".docx", hub.mediaExtension("fixture.docx", "", "document"));
    try std.testing.expectEqualStrings(".bin", hub.mediaExtension("fixture.bad/path", "", "document"));
    try std.testing.expectEqualStrings(".bin", hub.mediaExtension("fixture.verylongextension", "", "document"));
}

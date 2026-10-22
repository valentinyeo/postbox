const std = @import("std");
const hub = @import("hub.zig");
const bridge = @import("wa_hub.zig");

const chat = "fixture/account:room +/";
const client_id = "fixture-client-id";

test "IGSH-531 configured switch and unconfigured direct fallback" {
    try std.testing.expect(hub.igsh_531_hub_provider);
    try std.testing.expect(!hub.selected(""));
    try std.testing.expect(!hub.selected(" \t\r\n"));
    try std.testing.expect(hub.selected("configured-origin"));
}

test "IGSH-531 opaque chat handles are encoded without parsing source identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const list = try hub.chats(allocator, true, 500);
    try std.testing.expectEqualStrings("/v1/wazig/chats?archived=true&limit=500", list.path);
    const history = try hub.messages(allocator, chat, 80, "cursor+/");
    try std.testing.expectEqualStrings("/v1/wazig/messages?chat=fixture%2Faccount%3Aroom%20%2B%2F&limit=80&before=cursor%2B%2F", history.path);
    const media = try hub.binary(allocator, chat, "media/id");
    try std.testing.expectEqualStrings("/v1/wazig/media/fixture%2Faccount%3Aroom%20%2B%2F/media%2Fid", media.path);
    try std.testing.expectError(error.InvalidId, hub.messages(allocator, "", 80, ""));
    try std.testing.expectError(error.InvalidId, hub.binary(allocator, "bad\nhandle", "id"));
}

test "IGSH-531 writes carry escaped text persisted id read watermark and archive state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const send = try hub.send(allocator, chat, "Fixture \"message\"\n", "quoted-id", client_id);
    const retry = try hub.send(allocator, chat, "Fixture \"message\"\n", "quoted-id", client_id);
    try std.testing.expectEqualStrings("POST", send.method);
    try std.testing.expectEqualStrings("/v1/wazig/send", send.path);
    try std.testing.expectEqualStrings(send.body, retry.body);
    const value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, send.body, .{});
    try std.testing.expectEqualStrings(chat, value.object.get("chat").?.string);
    try std.testing.expectEqualStrings(client_id, value.object.get("client_id").?.string);
    try std.testing.expectEqualStrings("Fixture \"message\"\n", value.object.get("text").?.string);
    try std.testing.expect(value.object.get("account") == null);
    const read = try hub.markRead(allocator, chat, "last-message");
    const read_value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, read.body, .{});
    try std.testing.expectEqualStrings("/v1/wazig/mark-read", read.path);
    try std.testing.expectEqualStrings("last-message", read_value.object.get("message_id").?.string);
    for ([_]bool{ true, false }) |archived| {
        const request = try hub.archive(allocator, chat, archived);
        const body = try std.json.parseFromSliceLeaky(std.json.Value, allocator, request.body, .{});
        try std.testing.expectEqualStrings("/v1/wazig/archive", request.path);
        try std.testing.expectEqual(archived, body.object.get("archived").?.bool);
    }
    const reaction = try hub.react(allocator, chat, "message-id", "", client_id);
    try std.testing.expectEqualStrings("/v1/wazig/react", reaction.path);
    try std.testing.expectError(error.InvalidSend, hub.send(allocator, chat, "text", "", ""));
}

test "IGSH-531 aggregate rows retain network labels reject collisions and remove backend paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for ([_][]const u8{ "whatsapp", "slack", "telegram" }) |provider| {
        const raw = try std.fmt.allocPrint(allocator, "[{{\"jid\":\"opaque\",\"provider\":\"{s}\",\"name\":\"Fixture\"}}]", .{provider});
        const normalized = try hub.normalize(allocator, raw, .chats, "");
        const value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, normalized, .{});
        try std.testing.expectEqualStrings(provider, @tagName(hub.sourceProvider(value.object.get("data").?.array.items[0].object).?));
    }
    try std.testing.expectError(error.BadProvider, hub.normalize(allocator, "[{\"jid\":\"opaque\",\"provider\":\"unknown\"}]", .chats, ""));
    try std.testing.expectError(error.DuplicateId, hub.normalize(allocator, "[{\"jid\":\"same\",\"provider\":\"slack\"},{\"jid\":\"same\",\"provider\":\"telegram\"}]", .chats, ""));
    try std.testing.expectError(error.BadResponse, hub.normalize(allocator, "{}", .messages, chat));
    try std.testing.expectError(error.WrongChat, hub.normalize(allocator, "[{\"MsgID\":\"id\",\"ChatJID\":\"other\"}]", .messages, chat));
    const normalized = try hub.normalize(allocator, "[{\"MsgID\":\"id\",\"ChatJID\":\"opaque\",\"Text\":\"Fixture\",\"LocalPath\":\"backend-path\",\"local_path\":\"backend-path\"}]", .messages, "opaque");
    try std.testing.expect(std.mem.indexOf(u8, normalized, "backend-path") == null);
    const file = try hub.sendFile(allocator, chat, "caption", "quote", client_id, "fixture.ogg", "OggSfixture", true, "0123456789abcdef0123456789abcdef");
    try std.testing.expectEqualStrings("/v1/wazig/send", file.path);
    try std.testing.expect(std.mem.indexOf(u8, file.body, "name=\"ptt\"\r\n\r\ntrue\r\n") != null);
}

test "IGSH-531 live updates use bounded validated SSE and resume ids" {
    var sse = hub.Sse{};
    const frame = "id: 7\ndata: {\"id\":7,\"kind\":\"msg\",\"chat\":\"opaque\"}\n\n";
    var seen = false;
    for (frame) |byte| {
        if (try sse.push(byte)) |complete| {
            var event = (try sse.parse(std.testing.allocator, complete)).?;
            defer event.deinit();
            try std.testing.expectEqualStrings("opaque", event.value.chat);
            seen = true;
        }
    }
    try std.testing.expect(seen);
    try std.testing.expectEqualStrings("/v1/wazig/events", hub.events(sse.lastId()).path);
    try std.testing.expectEqualStrings("7", hub.events(sse.lastId()).last_event_id);
    try std.testing.expectError(error.BadEventId, sse.parse(std.testing.allocator, "id: 8\ndata: {\"id\":9,\"kind\":\"reset\"}\n\n"));
    try std.testing.expectEqualStrings("7", sse.lastId());
    try std.testing.expectEqual(.pending, try bridge.mediaState(202));
    try std.testing.expectEqual(.ready, try bridge.mediaState(200));
    try std.testing.expectError(error.HttpFailed, bridge.mediaState(401));
}

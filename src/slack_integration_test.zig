const std = @import("std");
const slack = @import("slack.zig");
const oauth = @import("slack_oauth.zig");
const chat_key = @import("chat_key.zig");

const channel = "C0000000001";
const timestamp = "1700000000.000001";
const message_text = "Example \"message\"\nline";
const client_msg_id = "00000000-0000-4000-8000-000000000001";

const Harness = struct {
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    base: []const u8,

    fn request(self: Harness, path: []const u8, body: ?[]const u8, token: []const u8, content_type: []const u8) ![]const u8 {
        var response: std.Io.Writer.Allocating = .init(self.allocator);
        const auth = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token});
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base, path });
        const result = try self.client.fetch(.{
            .location = .{ .url = url },
            .method = if (body == null) .GET else .POST,
            .payload = body,
            .response_writer = &response.writer,
            .keep_alive = false,
            .headers = .{
                .content_type = .{ .override = content_type },
                .authorization = if (token.len == 0) .omit else .{ .override = auth },
            },
        });
        try require(result.status == .ok);
        return response.writer.buffered();
    }

    fn api(self: Harness, method: []const u8, body: ?[]const u8, token: []const u8) ![]const u8 {
        return self.request(try std.fmt.allocPrint(self.allocator, "/api/{s}", .{method}), body, token, "application/json");
    }

    fn object(self: Harness, body: []const u8) !std.json.ObjectMap {
        const value = try std.json.parseFromSliceLeaky(std.json.Value, self.allocator, body, .{});
        try require(value == .object);
        return value.object;
    }

    fn list(self: Harness) !void {
        var cursor: []const u8 = "";
        var pages: u32 = 0;
        var ids: std.ArrayList([]const u8) = .empty;
        while (true) {
            const encoded = try slack.percentEncode(self.allocator, cursor);
            const method = try std.fmt.allocPrint(self.allocator, "conversations.list?types=public_channel,private_channel,im,mpim&limit=2&cursor={s}", .{encoded});
            const response = try self.api(method, null, "user-fixture-1");
            try require(slack.responseIsOk(self.allocator, response));
            const root = try self.object(response);
            for (root.get("channels").?.array.items) |value| {
                const item = slack.workspaceChannel(value.object) orelse return error.MissingChannel;
                try ids.append(self.allocator, item.id);
                if (std.mem.eql(u8, item.id, "D0000000001")) {
                    try require(item.is_im);
                    try equal("U0000000002", item.user);
                }
            }
            pages += 1;
            cursor = slack.nextCursor(root);
            if (!slack.wantsNextPage(cursor, pages, 512)) break;
        }
        try require(pages == 2 and ids.items.len == 4);
        for ([_][]const u8{ channel, "G0000000001", "D0000000001", "G0000000002" }, ids.items) |expected, actual| try equal(expected, actual);
        const users = try self.object(try self.api("users.list", null, "user-fixture-1"));
        const members = users.get("members").?.array.items;
        try require(members.len == 2);
        try equal("U0000000002", slack.objectStringField(members[1].object, "id"));
        try equal("Example User", slack.objectStringField(members[1].object.get("profile").?.object, "display_name"));
    }

    fn history(self: Harness) !void {
        for ([_][]const u8{ "conversations.history?channel=" ++ channel, "conversations.replies?channel=" ++ channel ++ "&ts=" ++ timestamp }, 0..) |method, index| {
            const response = try self.api(method, null, "user-fixture-1");
            try require(slack.responseIsOk(self.allocator, response));
            const root = try self.object(response);
            const messages = root.get("messages").?.array.items;
            try require(messages.len == 2);
            for (messages) |value| {
                try require(value.object.get("reactions").?.array.items.len > 0);
                const item = slack.readHistoryItem(value) orelse return error.MissingHistoryItem;
                try equal("U0000000002", item.user);
                try require(item.text.len > 0);
                if (index == 1) try equal(timestamp, item.thread_ts);
            }
            const first = slack.readHistoryItem(messages[0]).?;
            if (index == 0) {
                try equal(timestamp, first.ts);
                try require(first.reply_count == 1);
            }
        }
    }

    fn send(self: Harness) !void {
        const body = try slack.buildPostMessageBody(self.allocator, .{ .channel_id = channel, .text = message_text, .client_msg_id = client_msg_id, .thread_ts = timestamp });
        const response = try self.api("chat.postMessage", body, "user-fixture-1");
        try require(slack.responseIsOk(self.allocator, response));
        try equal("1700000001.000001", slack.parseSentTs(self.allocator, response) orelse return error.MissingSentTimestamp);
    }

    fn twoWorkspaces(self: Harness) !void {
        const Record = struct { key: chat_key.Key, ts: []const u8, text: []const u8 };
        var records: [2]Record = undefined;
        for ([_][]const u8{ "user-fixture-1", "user-fixture-2" }, 0..) |token, i| {
            const auth = try self.object(try self.api("auth.test", null, token));
            const root = try self.object(try self.api("conversations.history?channel=" ++ channel, null, token));
            const item = slack.readHistoryItem(root.get("messages").?.array.items[0]) orelse return error.MissingHistoryItem;
            records[i] = .{ .key = .{ .provider = .slack, .account = slack.objectStringField(auth, "team_id"), .id = channel }, .ts = item.ts, .text = item.text };
        }
        try equal("T0000000001", records[0].key.account);
        try equal("T0000000002", records[1].key.account);
        try equal(records[0].key.id, records[1].key.id);
        try equal(records[0].ts, records[1].ts);
        try equal(timestamp, records[0].ts);
        try require(!chat_key.Key.eql(records[0].key, records[1].key));
        for (records) |record| {
            var matches: usize = 0;
            for (records) |candidate| {
                if (chat_key.Key.eql(record.key, candidate.key) and std.mem.eql(u8, record.ts, candidate.ts)) {
                    try equal(record.text, candidate.text);
                    matches += 1;
                }
            }
            try require(matches == 1);
        }
        try require(!std.mem.eql(u8, records[0].text, records[1].text));
        try require(!chat_key.Key.eql(records[0].key, .{ .provider = .whatsapp, .account = records[0].key.account, .id = channel }));
    }

    fn oauthPkce(self: Harness, wrong_verifier: bool) !void {
        const attempt = try oauth.generate(self.client.io);
        const url = try oauth.buildAuthorizeUrl(self.allocator, "desktop-fixture", attempt);
        try require(std.mem.startsWith(u8, url, "https://slack.com/oauth/v2/authorize?"));
        const callback = try self.request(url["https://slack.com".len..], null, "", "application/x-www-form-urlencoded");
        const mismatch = oauth.parseCallback(self.allocator, callback, "wrong-state");
        if (mismatch) |_| return error.AcceptedWrongState else |err| try require(err == error.StateMismatch);
        const code = try oauth.parseCallback(self.allocator, callback, &attempt.state);
        const verifier = if (wrong_verifier) "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" else &attempt.code_verifier;
        const body = try oauth.buildAccessBody(self.allocator, "desktop-fixture", code, verifier);
        const response = try oauth.parseResponse(self.allocator, try self.request("/api/oauth.v2.access", body, "", "application/x-www-form-urlencoded"));
        try equal("T0000000001", response.team_id);
        try equal("Example Workspace", response.team_name);
        try equal("U0000000001", response.user_id);
        try equal("user-fixture-1", response.access_token);
        try equal("refresh-fixture-1", response.refresh_token);
        try equal(oauth.user_scopes, response.scope);
        try require(response.expires_in == 3600);
        const refresh = try oauth.buildRefreshBody(self.allocator, "desktop-fixture", response.refresh_token);
        const rotated = try oauth.parseRefreshResponse(self.allocator, try self.request("/api/oauth.v2.access", refresh, "", "application/x-www-form-urlencoded"));
        try equal("xoxe.xoxp-00000000000000000002", rotated.access_token);
    }

    fn refreshTokens(self: Harness) !void {
        try require(!oauth.refreshDue(699, 1000, true, ""));
        try require(oauth.refreshDue(700, 1000, true, ""));
        const body = try oauth.buildRefreshBody(self.allocator, "desktop-fixture", "refresh-fixture-1");
        const rotated = try oauth.parseRefreshResponse(self.allocator, try self.request("/api/oauth.v2.access", body, "", "application/x-www-form-urlencoded"));
        try equal("xoxe.xoxp-00000000000000000002", rotated.access_token);
        try equal("refresh-fixture-rotated", rotated.refresh_token);
        try require(rotated.expires_in == 3600);
    }

    fn live(self: Harness, missing_ack: bool) !void {
        const response = try self.api("apps.connections.open", "{}", "app-fixture");
        const endpoint = slack.parseWsUrl(self.allocator, response) orelse return error.InvalidWebSocketUrl;
        const colon = std.mem.lastIndexOfScalar(u8, endpoint.host, ':') orelse return error.InvalidWebSocketUrl;
        try equal("127.0.0.1", endpoint.host[0..colon]);
        const port = try std.fmt.parseInt(u16, endpoint.host[colon + 1 ..], 10);
        const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", port);
        const io = self.client.io;
        const stream = try address.connect(io, .{ .mode = .stream });
        defer stream.close(io);
        var read_buffer: [4096]u8 = undefined;
        var reader = stream.reader(io, &read_buffer);
        var write_buffer: [4096]u8 = undefined;
        var writer = stream.writer(io, &write_buffer);
        var nonce: [16]u8 = undefined;
        io.random(&nonce);
        var key: [24]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&key, &nonce);
        try writer.interface.print("GET {s} HTTP/1.1\r\nHost: {s}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {s}\r\nSec-WebSocket-Version: 13\r\n\r\n", .{ endpoint.path_query, endpoint.host, key });
        try writer.interface.flush();
        try equal("HTTP/1.1 101 Switching Protocols\r\n", try reader.interface.takeDelimiterInclusive('\n'));
        var accept_hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(try std.fmt.allocPrint(self.allocator, "{s}258EAFA5-E914-47DA-95CA-C5AB0DC85B11", .{key}), &accept_hash, .{});
        var accept: [28]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&accept, &accept_hash);
        var accepted = false;
        while (true) {
            const line = try reader.interface.takeDelimiterInclusive('\n');
            if (std.mem.eql(u8, line, "\r\n")) break;
            if (std.ascii.startsWithIgnoreCase(line, "Sec-WebSocket-Accept: ")) {
                try equal(&accept, std.mem.trim(u8, line[22..], " \r\n"));
                accepted = true;
            }
        }
        try require(accepted);
        const event = try readFrame(self.allocator, &reader.interface);
        const envelope = (try slack.classifyEnvelope(self.allocator, event)) orelse return error.MissingEnvelope;
        try require(envelope.kind == .events);
        try equal("message", envelope.event_type);
        try equal(channel, envelope.channel);
        try equal(timestamp, envelope.ts);
        try equal("Example live message", envelope.text);
        if (!missing_ack) {
            const ack = try slack.buildAckBody(self.allocator, envelope.envelope_id);
            try require(ack.len < 126);
            var mask: [4]u8 = undefined;
            io.random(&mask);
            try writer.interface.writeAll(&.{ 0x81, 0x80 | @as(u8, @intCast(ack.len)) });
            try writer.interface.writeAll(&mask);
            for (ack, 0..) |byte, i| try writer.interface.writeByte(byte ^ mask[i % 4]);
            try writer.interface.flush();
        }
        try equal("ack-verified", try readFrame(self.allocator, &reader.interface));
    }
};

fn readFrame(allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]const u8 {
    try require(try reader.takeByte() == 0x81);
    const length = try reader.takeByte();
    try require(length & 0x80 == 0);
    const size: usize = if (length == 126) try reader.takeInt(u16, .big) else length;
    try require(size < 65536 and length != 127);
    return reader.readAlloc(allocator, size);
}

fn require(condition: bool) !void {
    if (!condition) return error.IntegrationAssertionFailed;
}

fn equal(expected: []const u8, actual: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("expected {s}, got {s}\n", .{ expected, actual });
        return error.IntegrationAssertionFailed;
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    try require(args.len == 4);
    var client: std.http.Client = .{ .allocator = allocator, .io = init.io };
    defer client.deinit();
    const harness = Harness{ .allocator = allocator, .client = &client, .base = args[1] };
    const scenario = args[2];
    if (std.mem.eql(u8, scenario, "list")) try harness.list() else if (std.mem.eql(u8, scenario, "history")) try harness.history() else if (std.mem.eql(u8, scenario, "send")) try harness.send() else if (std.mem.eql(u8, scenario, "live")) try harness.live(std.mem.eql(u8, args[3], "missing_ack")) else if (std.mem.eql(u8, scenario, "two_workspaces")) try harness.twoWorkspaces() else if (std.mem.eql(u8, scenario, "oauth_pkce")) try harness.oauthPkce(std.mem.eql(u8, args[3], "wrong_verifier")) else if (std.mem.eql(u8, scenario, "refresh")) try harness.refreshTokens() else return error.UnknownScenario;
}

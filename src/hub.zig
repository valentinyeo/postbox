const std = @import("std");
const bridge = @import("wa_hub.zig");
const transport = @import("transport.zig");
const messenger_view = @import("messenger_view.zig");

pub const igsh_531_hub_provider = true;
pub const Request = bridge.Request;
pub const Rows = bridge.Rows;
pub const Sse = bridge.Sse;

pub fn selected(url: []const u8) bool {
    return igsh_531_hub_provider and std.mem.trim(u8, url, " \t\r\n").len > 0;
}

pub fn chats(allocator: std.mem.Allocator, archived: bool, limit: usize) !Request {
    return .{ .path = try std.fmt.allocPrint(allocator, "/v1/wazig/chats?archived={s}&limit={d}", .{ if (archived) "true" else "false", limit }) };
}

pub fn messages(allocator: std.mem.Allocator, chat: []const u8, limit: usize, before: []const u8) !Request {
    try validId(chat);
    const c = try bridge.encode(allocator, chat);
    defer allocator.free(c);
    const b = try bridge.encode(allocator, before);
    defer allocator.free(b);
    return .{ .path = try std.fmt.allocPrint(allocator, "/v1/wazig/messages?chat={s}&limit={d}&before={s}", .{ c, limit, b }) };
}

pub fn send(allocator: std.mem.Allocator, chat: []const u8, text: []const u8, reply_to: []const u8, client_id: []const u8) !Request {
    try validWrite(chat, client_id);
    return .{ .method = "POST", .path = "/v1/wazig/send", .body = try std.json.Stringify.valueAlloc(allocator, .{ .chat = chat, .text = text, .reply_to = reply_to, .client_id = client_id }, .{}) };
}

pub fn sendFile(allocator: std.mem.Allocator, chat: []const u8, text: []const u8, reply_to: []const u8, client_id: []const u8, filename: []const u8, bytes: []const u8, ptt: bool, boundary: []const u8) !Request {
    try validWrite(chat, client_id);
    var request = try bridge.sendFile(allocator, .{ .provider = .whatsapp, .account = "hub", .id = chat }, text, reply_to, client_id, filename, bytes, ptt, boundary);
    request.path = "/v1/wazig/send";
    return request;
}

pub fn markRead(allocator: std.mem.Allocator, chat: []const u8, message_id: []const u8) !Request {
    try validId(chat);
    return .{ .method = "POST", .path = "/v1/wazig/mark-read", .body = try std.json.Stringify.valueAlloc(allocator, .{ .chat = chat, .message_id = message_id }, .{}) };
}

pub fn archive(allocator: std.mem.Allocator, chat: []const u8, archived: bool) !Request {
    try validId(chat);
    return .{ .method = "POST", .path = "/v1/wazig/archive", .body = try std.json.Stringify.valueAlloc(allocator, .{ .chat = chat, .archived = archived }, .{}) };
}

pub fn react(allocator: std.mem.Allocator, chat: []const u8, msg: []const u8, emoji: []const u8, client_id: []const u8) !Request {
    try validWrite(chat, client_id);
    try validId(msg);
    return .{ .method = "POST", .path = "/v1/wazig/react", .body = try std.json.Stringify.valueAlloc(allocator, .{ .chat = chat, .msg = msg, .emoji = emoji, .client_id = client_id }, .{}) };
}

pub fn binary(allocator: std.mem.Allocator, chat: []const u8, message_id: ?[]const u8) !Request {
    try validId(chat);
    const c = try bridge.encode(allocator, chat);
    defer allocator.free(c);
    if (message_id) |id| {
        try validId(id);
        const m = try bridge.encode(allocator, id);
        defer allocator.free(m);
        return .{ .path = try std.fmt.allocPrint(allocator, "/v1/wazig/media/{s}/{s}", .{ c, m }) };
    }
    return .{ .path = try std.fmt.allocPrint(allocator, "/v1/wazig/avatar/{s}", .{c}) };
}

pub fn events(last_event_id: []const u8) Request {
    return .{ .path = "/v1/wazig/events", .last_event_id = last_event_id };
}

pub fn normalize(allocator: std.mem.Allocator, raw: []const u8, kind: Rows, chat: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    if (parsed.value != .array or parsed.value.array.items.len > 500) return error.BadResponse;
    for (parsed.value.array.items, 0..) |*item, index| {
        if (item.* != .object) return error.BadResponse;
        const id_field: []const u8 = if (kind == .messages) "MsgID" else "jid";
        const id = string(item.object, id_field);
        try validId(id);
        for (parsed.value.array.items[0..index]) |previous| {
            if (std.mem.eql(u8, string(previous.object, id_field), id)) return error.DuplicateId;
        }
        if (kind == .chats) {
            _ = sourceProvider(item.object) orelse return error.BadProvider;
        } else if (kind == .messages) {
            if (!std.mem.eql(u8, string(item.object, "ChatJID"), chat)) return error.WrongChat;
            _ = item.object.swapRemove("LocalPath");
            _ = item.object.swapRemove("local_path");
        }
    }
    return if (kind == .messages)
        std.json.Stringify.valueAlloc(allocator, .{ .success = true, .data = .{ .messages = parsed.value } }, .{})
    else
        std.json.Stringify.valueAlloc(allocator, .{ .success = true, .data = parsed.value }, .{});
}

pub fn sourceProvider(row: std.json.ObjectMap) ?transport.Provider {
    return std.meta.stringToEnum(transport.Provider, string(row, "provider"));
}

pub fn sourceAccount(row: std.json.ObjectMap, fallback: []const u8) []const u8 {
    const account = string(row, "account");
    return if (account.len > 0) account else fallback;
}

pub fn providerForView(row: std.json.ObjectMap, view: messenger_view.View) ?transport.Provider {
    const provider = sourceProvider(row) orelse return null;
    return if (messenger_view.includes(view, provider)) provider else null;
}

fn string(row: std.json.ObjectMap, name: []const u8) []const u8 {
    const value = row.get(name) orelse return "";
    return if (value == .string) value.string else "";
}

fn validId(id: []const u8) !void {
    if (id.len == 0 or id.len > 191 or !std.unicode.utf8ValidateSlice(id)) return error.InvalidId;
    for (id) |byte| if (byte < 32 or byte == 127) return error.InvalidId;
}

fn validWrite(chat: []const u8, client_id: []const u8) !void {
    try validId(chat);
    if (client_id.len == 0 or client_id.len > 128) return error.InvalidSend;
}

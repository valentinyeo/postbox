const std = @import("std");
const chat_key = @import("chat_key.zig");
const transport = @import("transport.zig");

pub const igsh_532_hub_whatsapp = true;
pub const max_file_bytes = 64 * 1024 * 1024;

pub const Endpoint = struct {
    host: []const u8,
    port: u16,
    secure: bool,

    pub fn parse(url: []const u8, allow_loopback: bool) !Endpoint {
        const secure = std.mem.startsWith(u8, url, "https://");
        if (!secure and !std.mem.startsWith(u8, url, "http://")) return error.InvalidBridgeUrl;
        const offset: usize = if (secure) 8 else 7;
        const authority = std.mem.trimEnd(u8, url[offset..], "/");
        if (authority.len == 0 or std.mem.indexOfAny(u8, authority, "/?#@\r\n\\") != null) return error.InvalidBridgeUrl;
        const colon = std.mem.lastIndexOfScalar(u8, authority, ':');
        const host = authority[0 .. colon orelse authority.len];
        const port = if (colon) |index| std.fmt.parseInt(u16, authority[index + 1 ..], 10) catch return error.InvalidBridgeUrl else if (secure) @as(u16, 443) else 80;
        if (host.len == 0 or port == 0) return error.InvalidBridgeUrl;
        if (!secure and !(allow_loopback and std.mem.eql(u8, host, "127.0.0.1"))) return error.InsecureBridgeUrl;
        return .{ .host = host, .port = port, .secure = secure };
    }
};

pub const Request = struct {
    method: []const u8 = "GET",
    path: []const u8,
    body: []const u8 = "",
    content_type: []const u8 = "application/json; charset=utf-8",
    last_event_id: []const u8 = "",
};

pub const Account = struct {
    account: []const u8,
    jid: []const u8 = "",
    state: []const u8,
    last_event_at: []const u8 = "",
};

pub const SendReply = struct {
    client_id: []const u8,
    msg_id: []const u8 = "",
    ts: []const u8 = "",
    status: []const u8,
};

pub const Event = struct {
    id: u64,
    account: []const u8 = "",
    chat: []const u8 = "",
    ts: []const u8 = "",
    kind: []const u8,

    pub fn key(self: Event) chat_key.Key {
        return .{ .provider = .whatsapp, .account = self.account, .id = bare(self.account, self.chat) };
    }
};

pub fn accounts() Request {
    return .{ .path = "/v1/accounts" };
}

pub fn encode(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    const hex = "0123456789ABCDEF";
    for (text) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            try out.append(allocator, byte);
        } else {
            try out.appendSlice(allocator, &.{ '%', hex[byte >> 4], hex[byte & 15] });
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn chats(allocator: std.mem.Allocator, account: []const u8, archived: bool, limit: usize) !Request {
    const a = try encode(allocator, account);
    defer allocator.free(a);
    return .{ .path = try std.fmt.allocPrint(allocator, "/v1/chats?account={s}&archived={s}&limit={d}", .{ a, if (archived) "true" else "false", limit }) };
}

pub fn messages(allocator: std.mem.Allocator, key: chat_key.Key, limit: usize, before: []const u8) !Request {
    if (key.provider != .whatsapp) return error.WrongProvider;
    const a = try encode(allocator, key.account);
    defer allocator.free(a);
    const c = try encode(allocator, key.id);
    defer allocator.free(c);
    const b = try encode(allocator, before);
    defer allocator.free(b);
    return .{ .path = try std.fmt.allocPrint(allocator, "/v1/messages?account={s}&chat={s}&limit={d}&before={s}", .{ a, c, limit, b }) };
}

pub fn list(allocator: std.mem.Allocator, account: []const u8, kind: enum { groups }) !Request {
    const a = try encode(allocator, account);
    defer allocator.free(a);
    return .{ .path = try std.fmt.allocPrint(allocator, "/v1/{s}?account={s}&limit=200", .{ @tagName(kind), a }) };
}

pub fn binary(allocator: std.mem.Allocator, key: chat_key.Key, msg: ?[]const u8) !Request {
    if (key.provider != .whatsapp) return error.WrongProvider;
    const a = try encode(allocator, key.account);
    defer allocator.free(a);
    const c = try encode(allocator, key.id);
    defer allocator.free(c);
    if (msg) |id| {
        const m = try encode(allocator, bare(key.account, id));
        defer allocator.free(m);
        return .{ .path = try std.fmt.allocPrint(allocator, "/v1/media/{s}/{s}/{s}", .{ a, c, m }) };
    }
    return .{ .path = try std.fmt.allocPrint(allocator, "/v1/avatar/{s}/{s}", .{ a, c }) };
}

pub fn send(allocator: std.mem.Allocator, key: chat_key.Key, text: []const u8, reply_to: []const u8, client_id: []const u8) !Request {
    try validateSend(key, client_id);
    return .{ .method = "POST", .path = "/v1/send", .body = try std.json.Stringify.valueAlloc(allocator, .{ .account = key.account, .chat = key.id, .text = text, .reply_to = reply_to, .client_id = client_id }, .{}) };
}

fn validateSend(key: chat_key.Key, client_id: []const u8) !void {
    if (key.provider != .whatsapp) return error.WrongProvider;
    if (key.account.len == 0 or key.id.len == 0 or client_id.len == 0 or client_id.len > 128) return error.InvalidSend;
}

pub fn sendFile(allocator: std.mem.Allocator, key: chat_key.Key, text: []const u8, reply_to: []const u8, client_id: []const u8, filename: []const u8, bytes: []const u8, ptt: bool, boundary: []const u8) !Request {
    try validateSend(key, client_id);
    if (bytes.len > max_file_bytes) return error.FileTooLarge;
    if (boundary.len < 16 or boundary.len > 80) return error.InvalidBoundary;
    for (boundary) |byte| if (!std.ascii.isAlphanumeric(byte)) return error.InvalidBoundary;
    for ([_][]const u8{ bytes, text, reply_to, client_id, key.account, key.id }) |field| {
        if (std.mem.indexOf(u8, field, boundary) != null) return error.InvalidBoundary;
    }
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    const voice: []const u8 = if (ptt) "true" else "false";
    const fields = .{ .account = key.account, .chat = key.id, .text = text, .reply_to = reply_to, .client_id = client_id, .ptt = voice };
    inline for (std.meta.fields(@TypeOf(fields))) |field| {
        try out.writer.print("--{s}\r\nContent-Disposition: form-data; name=\"{s}\"\r\n\r\n{s}\r\n", .{ boundary, field.name, @field(fields, field.name) });
    }
    var safe_name = std.ArrayList(u8).empty;
    defer safe_name.deinit(allocator);
    for (filename) |byte| try safe_name.append(allocator, if (byte < 0x20 or byte == '"' or byte == '\\' or byte == '/') '_' else byte);
    try out.writer.print("--{s}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{s}\"\r\nContent-Type: {s}\r\n\r\n", .{ boundary, if (ptt) "voice.ogg" else if (safe_name.items.len > 0) safe_name.items else "attachment.bin", if (ptt) "audio/ogg" else "application/octet-stream" });
    try out.writer.writeAll(bytes);
    try out.writer.print("\r\n--{s}--\r\n", .{boundary});
    if (out.written().len > max_file_bytes) return error.FileTooLarge;
    const content_type = try std.fmt.allocPrint(allocator, "multipart/form-data; boundary={s}", .{boundary});
    errdefer allocator.free(content_type);
    return .{ .method = "POST", .path = "/v1/send", .body = try out.toOwnedSlice(), .content_type = content_type };
}

pub fn react(allocator: std.mem.Allocator, key: chat_key.Key, msg: []const u8, emoji: []const u8, client_id: []const u8) !Request {
    try validateSend(key, client_id);
    return .{ .method = "POST", .path = "/v1/react", .body = try std.json.Stringify.valueAlloc(allocator, .{ .account = key.account, .chat = key.id, .msg = msg, .emoji = emoji, .client_id = client_id }, .{}) };
}

pub fn markRead(allocator: std.mem.Allocator, key: chat_key.Key) !Request {
    if (key.provider != .whatsapp) return error.WrongProvider;
    return .{ .method = "POST", .path = "/v1/mark-read", .body = try std.json.Stringify.valueAlloc(allocator, .{ .account = key.account, .chat = key.id }, .{}) };
}

pub const ArchiveChat = struct { chat: []const u8 };

pub fn archiveBatch(allocator: std.mem.Allocator, account: []const u8, chats_to_archive: []const ArchiveChat, archived: bool) !Request {
    if (chats_to_archive.len == 0) return error.InvalidId;
    return .{ .method = "POST", .path = "/v1/archive-batch", .body = try std.json.Stringify.valueAlloc(allocator, .{ .account = account, .chats = chats_to_archive, .archived = archived }, .{}) };
}

pub fn archive(allocator: std.mem.Allocator, key: chat_key.Key, archived: bool) !Request {
    if (key.provider != .whatsapp) return error.WrongProvider;
    return .{ .method = "POST", .path = "/v1/archive", .body = try std.json.Stringify.valueAlloc(allocator, .{ .account = key.account, .chat = key.id, .archived = archived }, .{}) };
}

pub fn events(last_event_id: []const u8) Request {
    return .{ .path = "/v1/events", .last_event_id = last_event_id };
}

pub fn parseAccounts(allocator: std.mem.Allocator, raw: []const u8) !std.json.Parsed([]Account) {
    return std.json.parseFromSlice([]Account, allocator, raw, .{ .ignore_unknown_fields = true });
}

pub fn pickAccount(linked_accounts: []const Account, preferred: []const u8) ?[]const u8 {
    var first: ?[]const u8 = null;
    var personal: ?[]const u8 = null;
    for (linked_accounts) |account| {
        if (!std.mem.eql(u8, account.state, "linked") or account.account.len == 0 or account.account.len > 32) continue;
        if (std.mem.eql(u8, account.account, preferred)) return account.account;
        if (std.mem.eql(u8, account.account, "personal")) personal = account.account;
        if (first == null) first = account.account;
    }
    return personal orelse first;
}

pub fn parseSend(allocator: std.mem.Allocator, raw: []const u8) !std.json.Parsed(SendReply) {
    return std.json.parseFromSlice(SendReply, allocator, raw, .{ .ignore_unknown_fields = true });
}

pub fn bare(account: []const u8, id: []const u8) []const u8 {
    if (std.mem.startsWith(u8, id, account) and id.len > account.len and id[account.len] == ':') return id[account.len + 1 ..];
    return id;
}

pub const Rows = enum { chats, messages, groups };

pub fn normalize(allocator: std.mem.Allocator, raw: []const u8, account: []const u8, kind: Rows) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    if (parsed.value != .array) return error.BadResponse;
    for (parsed.value.array.items) |*item| {
        if (item.* != .object) return error.BadResponse;
        const fields: []const []const u8 = switch (kind) {
            .chats => &.{"jid"},
            .messages => &.{ "MsgID", "ChatJID", "ReactionToID" },
            .groups => &.{ "JID", "jid" },
        };
        for (fields) |field| {
            if (item.object.getPtr(field)) |value| {
                if (value.* != .string) return error.BadResponse;
                if (std.mem.indexOfScalar(u8, value.string, ':') != null and std.mem.eql(u8, bare(account, value.string), value.string)) return error.WrongAccount;
                value.string = bare(account, value.string);
            }
        }
    }
    return switch (kind) {
        .messages => std.json.Stringify.valueAlloc(allocator, .{ .success = true, .data = .{ .messages = parsed.value } }, .{}),
        else => std.json.Stringify.valueAlloc(allocator, .{ .success = true, .data = parsed.value }, .{}),
    };
}

pub fn chatSummary(row: std.json.ObjectMap) transport.ChatSummary {
    return .{ .id = string(row, "jid"), .name = string(row, "name"), .unread_count = if (row.get("unread_count")) |v| (if (v == .integer) @intCast(std.math.clamp(v.integer, 0, std.math.maxInt(i32))) else 0) else 0, .is_group = std.mem.endsWith(u8, string(row, "jid"), "@g.us"), .timestamp = string(row, "last_message_ts") };
}

fn string(row: std.json.ObjectMap, field: []const u8) []const u8 {
    const value = row.get(field) orelse return "";
    return if (value == .string) value.string else "";
}

pub const MediaState = enum { pending, ready, unavailable };

pub fn mediaState(status: u32) !MediaState {
    return switch (status) {
        200, 206 => .ready,
        202 => .pending,
        404, 410 => .unavailable,
        else => error.HttpFailed,
    };
}

pub fn cacheName(allocator: std.mem.Allocator, key: chat_key.Key, id: []const u8) ![]u8 {
    const account = std.hash.Wyhash.hash(0, key.account);
    const chat = std.hash.Wyhash.hash(account, key.id);
    return std.fmt.allocPrint(allocator, "{x:0>16}-{x:0>16}.bin", .{ chat, std.hash.Wyhash.hash(chat, id) });
}

pub fn mediaExtension(filename: []const u8, mime: []const u8, media_type: []const u8) []const u8 {
    if (std.mem.eql(u8, mime, "video/mp4")) return ".mp4";
    if (std.mem.eql(u8, mime, "video/quicktime")) return ".mov";
    if (std.mem.eql(u8, mime, "image/png")) return ".png";
    if (std.mem.eql(u8, mime, "image/jpeg")) return ".jpg";
    if (std.mem.eql(u8, mime, "image/webp")) return ".webp";
    if (std.mem.eql(u8, mime, "image/gif")) return ".gif";
    if (std.mem.eql(u8, mime, "audio/ogg") or std.mem.eql(u8, mime, "audio/opus")) return ".ogg";
    if (std.mem.eql(u8, mime, "audio/mpeg")) return ".mp3";
    if (std.mem.eql(u8, mime, "application/pdf")) return ".pdf";
    const extension = std.fs.path.extension(filename);
    if (extension.len > 1 and extension.len <= 12) {
        var valid = true;
        for (extension[1..]) |byte| if (!std.ascii.isAlphanumeric(byte)) {
            valid = false;
            break;
        };
        if (valid) return extension;
    }
    return if (std.mem.eql(u8, media_type, "video")) ".mp4" else ".bin";
}

pub const Sse = struct {
    frame: [64 * 1024]u8 = undefined,
    len: usize = 0,
    last_event_id: [32]u8 = @splat(0),
    id_len: usize = 0,

    pub fn lastId(self: *const Sse) []const u8 {
        return self.last_event_id[0..self.id_len];
    }

    pub fn push(self: *Sse, byte: u8) !?[]const u8 {
        if (byte == '\r') return null;
        if (self.len == self.frame.len) {
            self.len = 0;
            return error.EventTooLarge;
        }
        self.frame[self.len] = byte;
        self.len += 1;
        if (self.len >= 2 and std.mem.endsWith(u8, self.frame[0..self.len], "\n\n")) {
            const frame = self.frame[0..self.len];
            self.len = 0;
            return frame;
        }
        return null;
    }

    pub fn parse(self: *Sse, allocator: std.mem.Allocator, frame: []const u8) !?std.json.Parsed(Event) {
        var lines = std.mem.splitScalar(u8, frame, '\n');
        var data = std.ArrayList(u8).empty;
        defer data.deinit(allocator);
        var id: []const u8 = "";
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "id:")) id = std.mem.trim(u8, line[3..], " \r");
            if (std.mem.startsWith(u8, line, "data:")) {
                if (data.items.len > 0) try data.append(allocator, '\n');
                try data.appendSlice(allocator, std.mem.trimStart(u8, line[5..], " "));
            }
        }
        if (data.items.len == 0) return null;
        var parsed = try std.json.parseFromSlice(Event, allocator, data.items, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        errdefer parsed.deinit();
        if (id.len == 0 or id.len > self.last_event_id.len or (std.fmt.parseInt(u64, id, 10) catch return error.BadEventId) != parsed.value.id) return error.BadEventId;
        @memcpy(self.last_event_id[0..id.len], id);
        self.id_len = id.len;
        return parsed;
    }
};

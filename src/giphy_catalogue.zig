const std = @import("std");
const chat_key = @import("chat_key.zig");

pub const max_results = 25;
pub const max_response_bytes = 256 * 1024;
pub const max_query_bytes = 200;
pub const max_key_bytes = 256;
pub const max_offset = 4999;

fn Text(comptime capacity: usize) type {
    return struct {
        bytes: [capacity]u8 = undefined,
        len: usize = 0,

        fn set(self: *@This(), text: []const u8) !void {
            if (text.len > capacity) return error.TooLong;
            @memcpy(self.bytes[0..text.len], text);
            self.len = text.len;
        }

        pub fn slice(self: *const @This()) []const u8 {
            return self.bytes[0..self.len];
        }
    };
}

pub const Request = struct {
    bytes: [2048]u8 = undefined,
    len: usize = 0,

    fn append(self: *Request, text: []const u8) !void {
        if (text.len > self.bytes.len - self.len) return error.TooLong;
        @memcpy(self.bytes[self.len..][0..text.len], text);
        self.len += text.len;
    }

    fn encoded(self: *Request, text: []const u8) !void {
        const hex = "0123456789ABCDEF";
        for (text) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
                try self.append(&.{c});
            } else {
                try self.append(&.{ '%', hex[c >> 4], hex[c & 15] });
            }
        }
    }

    pub fn url(self: *const Request) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub fn request(key: []const u8, query: []const u8, offset: usize, limit: usize) !Request {
    if (key.len == 0) return error.NeedsKey;
    if (key.len > max_key_bytes or query.len > max_query_bytes) return error.TooLong;
    if (limit == 0 or limit > max_results or offset > max_offset or limit > max_offset + 1 - offset) return error.InvalidPage;
    if (!std.unicode.utf8ValidateSlice(query)) return error.InvalidQuery;
    var result = Request{};
    try result.append(if (query.len == 0) "https://api.giphy.com/v1/gifs/trending?api_key=" else "https://api.giphy.com/v1/gifs/search?api_key=");
    try result.encoded(key);
    if (query.len != 0) {
        try result.append("&q=");
        try result.encoded(query);
    }
    var numbers: [64]u8 = undefined;
    try result.append(try std.fmt.bufPrint(&numbers, "&limit={d}&offset={d}&rating=pg-13", .{ limit, offset }));
    return result;
}

pub const Rendition = struct {
    url: Text(512) = .{},
    width: u32 = 0,
    height: u32 = 0,
    size: u32 = 0,
};

pub const Gif = struct {
    id: Text(64) = .{},
    preview: Rendition = .{},
    original: Rendition = .{},
};

pub const Page = struct {
    items: [max_results]Gif = undefined,
    count: usize = 0,
    offset: usize = 0,
    total_count: usize = 0,
};

const RawRendition = struct { url: []const u8, width: []const u8, height: []const u8, size: []const u8 };
const RawGif = struct {
    @"type": []const u8,
    id: []const u8,
    images: struct { fixed_width: RawRendition, original: RawRendition },
};
const RawPage = struct {
    data: []const RawGif,
    pagination: struct { total_count: usize, count: usize, offset: usize },
    meta: struct { status: u16 },
};

fn validId(id: []const u8) bool {
    if (id.len == 0 or id.len > 64) return false;
    for (id) |c| if (!std.ascii.isAlphanumeric(c)) return false;
    return true;
}

fn validMediaUrl(url: []const u8, id: []const u8) bool {
    const prefix = "https://";
    if (!std.mem.startsWith(u8, url, prefix) or url.len > 512) return false;
    const rest = url[prefix.len..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return false;
    const host = rest[0..slash];
    if (!std.mem.startsWith(u8, host, "media") or !std.mem.endsWith(u8, host, ".giphy.com")) return false;
    const suffix = host[5 .. host.len - ".giphy.com".len];
    for (suffix) |c| if (!std.ascii.isDigit(c)) return false;
    const path = rest[slash..];
    if (!std.mem.startsWith(u8, path, "/media/") or !std.mem.endsWith(u8, path, ".gif")) return false;
    const tail = path[7..];
    if (!std.mem.startsWith(u8, tail, id) or tail.len <= id.len or tail[id.len] != '/') return false;
    for (tail[id.len + 1 ..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '.') return false;
    }
    return true;
}

fn rendition(raw: RawRendition, id: []const u8) !Rendition {
    if (!validMediaUrl(raw.url, id)) return error.InvalidMedia;
    const width = std.fmt.parseUnsigned(u32, raw.width, 10) catch return error.InvalidMedia;
    const height = std.fmt.parseUnsigned(u32, raw.height, 10) catch return error.InvalidMedia;
    const size = std.fmt.parseUnsigned(u32, raw.size, 10) catch return error.InvalidMedia;
    if (width == 0 or width > 4096 or height == 0 or height > 4096 or size == 0 or size > 25 * 1024 * 1024) return error.InvalidMedia;
    var result = Rendition{ .width = width, .height = height, .size = size };
    try result.url.set(raw.url);
    return result;
}

pub fn parse(allocator: std.mem.Allocator, json: []const u8, expected_offset: usize, requested_limit: usize) !Page {
    if (json.len > max_response_bytes) return error.ResponseTooLarge;
    if (requested_limit == 0 or requested_limit > max_results or expected_offset > max_offset or requested_limit > max_offset + 1 - expected_offset) return error.InvalidPage;
    var parsed = try std.json.parseFromSlice(RawPage, allocator, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const raw = parsed.value;
    if (raw.meta.status != 200) return error.ApiFailed;
    if (raw.data.len > requested_limit or raw.pagination.count != raw.data.len or raw.pagination.offset != expected_offset) return error.InvalidPage;
    var page = Page{ .offset = expected_offset, .total_count = raw.pagination.total_count };
    for (raw.data) |item| {
        if (!std.mem.eql(u8, item.@"type", "gif") or !validId(item.id)) return error.InvalidMedia;
        for (page.items[0..page.count]) |*existing| if (std.mem.eql(u8, existing.id.slice(), item.id)) return error.DuplicateId;
        var gif = Gif{};
        try gif.id.set(item.id);
        gif.preview = try rendition(item.images.fixed_width, item.id);
        gif.original = try rendition(item.images.original, item.id);
        page.items[page.count] = gif;
        page.count += 1;
    }
    return page;
}

pub const Target = struct {
    chat: chat_key.Stored = .{},
    reply_id: Text(191) = .{},
    reply_sender: Text(191) = .{},

    pub fn init(chat: chat_key.Key, reply_id: []const u8, reply_sender: []const u8) !Target {
        if (chat.account.len > chat_key.max_account_len or chat.id.len == 0 or chat.id.len > 191) return error.InvalidTarget;
        var target = Target{};
        target.chat.set(chat);
        try target.reply_id.set(reply_id);
        try target.reply_sender.set(reply_sender);
        return target;
    }

    pub fn eql(self: *const Target, other: *const Target) bool {
        return chat_key.Key.eql(self.chat.key(), other.chat.key()) and std.mem.eql(u8, self.reply_id.slice(), other.reply_id.slice()) and std.mem.eql(u8, self.reply_sender.slice(), other.reply_sender.slice());
    }
};

pub const State = struct {
    generation: u64 = 0,
    status: enum { closed, needs_key, loading, ready, failed, staged } = .closed,
    target: Target = .{},
    page: Page = .{},
    selected: ?Gif = null,

    pub fn begin(self: *State, target: Target, has_key: bool) !u64 {
        self.generation = try std.math.add(u64, self.generation, 1);
        self.target = target;
        self.page = .{};
        self.selected = null;
        self.status = if (has_key) .loading else .needs_key;
        return self.generation;
    }

    pub fn accept(self: *State, generation: u64, target: *const Target, page: Page) bool {
        if (self.status != .loading or generation != self.generation or !self.target.eql(target)) return false;
        self.page = page;
        self.status = .ready;
        return true;
    }

    pub fn fail(self: *State, generation: u64, target: *const Target) void {
        if (self.status == .loading and generation == self.generation and self.target.eql(target)) self.status = .failed;
    }

    pub fn select(self: *State, generation: u64, target: *const Target, index: usize) bool {
        if (self.status != .ready or generation != self.generation or !self.target.eql(target) or index >= self.page.count) return false;
        self.selected = self.page.items[index];
        self.page = .{};
        self.status = .staged;
        return true;
    }

    pub fn cancel(self: *State) void {
        self.page = .{};
        self.selected = null;
        self.status = .closed;
    }
};

const fixture =
    \\{"data":[{"type":"gif","id":"abc123","images":{"fixed_width":{"url":"https://media1.giphy.com/media/abc123/200.gif","width":"200","height":"100","size":"2000"},"original":{"url":"https://media.giphy.com/media/abc123/giphy.gif","width":"400","height":"200","size":"5000"}}}],"pagination":{"total_count":1,"count":1,"offset":0},"meta":{"status":200}}
;

test "requests encode credentials and query and bound pagination" {
    const search = try request("a&b", "cat & dog", 25, 25);
    try std.testing.expectEqualStrings("https://api.giphy.com/v1/gifs/search?api_key=a%26b&q=cat%20%26%20dog&limit=25&offset=25&rating=pg-13", search.url());
    const trending = try request("key", "", 0, 1);
    try std.testing.expect(std.mem.startsWith(u8, trending.url(), "https://api.giphy.com/v1/gifs/trending?"));
    try std.testing.expectError(error.NeedsKey, request("", "cat", 0, 1));
    try std.testing.expectError(error.InvalidPage, request("key", "cat", 4999, 2));
    try std.testing.expectError(error.TooLong, request("key", "x" ** 201, 0, 1));
}

test "catalogue separates preview and original" {
    const page = try parse(std.testing.allocator, fixture, 0, 25);
    try std.testing.expectEqual(@as(usize, 1), page.count);
    try std.testing.expectEqualStrings("abc123", page.items[0].id.slice());
    try std.testing.expectEqual(@as(u32, 200), page.items[0].preview.width);
    try std.testing.expectEqual(@as(u32, 400), page.items[0].original.width);
    try std.testing.expectError(error.InvalidPage, parse(std.testing.allocator, fixture, 1, 25));
    try std.testing.expectError(error.ResponseTooLarge, parse(std.testing.allocator, " " ** (max_response_bytes + 1), 0, 1));
}

test "only matching giphy GIF media is accepted" {
    try std.testing.expect(validMediaUrl("https://media0.giphy.com/media/abc123/200.gif", "abc123"));
    for ([_][]const u8{
        "http://media.giphy.com/media/abc123/giphy.gif",
        "https://media.giphy.com@evil.test/media/abc123/giphy.gif",
        "https://media.giphy.com.evil.test/media/abc123/giphy.gif",
        "https://media.giphy.com:443/media/abc123/giphy.gif",
        "https://media.giphy.com/media/other/giphy.gif",
        "https://media.giphy.com/media/abc123/giphy.gif?redirect=evil",
        "https://media.giphy.com/media/abc123/../giphy.gif",
    }) |url| try std.testing.expect(!validMediaUrl(url, "abc123"));
    try std.testing.expectError(error.InvalidMedia, rendition(.{ .url = "https://media.giphy.com/media/abc123/giphy.gif", .width = "0", .height = "5", .size = "1" }, "abc123"));
}

test "selection belongs to the request and complete target, cancellation sends nothing" {
    const first = try Target.init(.{ .provider = .whatsapp, .account = "one", .id = "chat" }, "reply", "sender");
    const other_account = try Target.init(.{ .provider = .whatsapp, .account = "two", .id = "chat" }, "reply", "sender");
    const other_reply = try Target.init(.{ .provider = .whatsapp, .account = "one", .id = "chat" }, "other", "sender");
    var state = State{};
    const old = try state.begin(first, true);
    const current = try state.begin(first, true);
    const page = try parse(std.testing.allocator, fixture, 0, 25);
    try std.testing.expect(!state.accept(old, &first, page));
    try std.testing.expect(!state.accept(current, &other_account, page));
    try std.testing.expect(state.accept(current, &first, page));
    try std.testing.expect(!state.select(current, &other_reply, 0));
    try std.testing.expect(state.select(current, &first, 0));
    try std.testing.expectEqualStrings("https://media.giphy.com/media/abc123/giphy.gif", state.selected.?.original.url.slice());
    state.cancel();
    try std.testing.expect(state.selected == null);
    try std.testing.expect(!state.select(current, &first, 0));
    const missing = try state.begin(first, false);
    try std.testing.expectEqual(.needs_key, state.status);
    try std.testing.expect(!state.accept(missing, &first, page));
}

test "duplicate IDs and malformed responses are rejected" {
    const duplicate =
        \\{"data":[{"type":"gif","id":"a","images":{"fixed_width":{"url":"https://media.giphy.com/media/a/200.gif","width":"1","height":"1","size":"1"},"original":{"url":"https://media.giphy.com/media/a/giphy.gif","width":"1","height":"1","size":"1"}}},{"type":"gif","id":"a","images":{"fixed_width":{"url":"https://media.giphy.com/media/a/200.gif","width":"1","height":"1","size":"1"},"original":{"url":"https://media.giphy.com/media/a/giphy.gif","width":"1","height":"1","size":"1"}}}],"pagination":{"total_count":2,"count":2,"offset":0},"meta":{"status":200}}
    ;
    try std.testing.expectError(error.DuplicateId, parse(std.testing.allocator, duplicate, 0, 25));
    try std.testing.expectError(error.InvalidPage, parse(std.testing.allocator, duplicate, 0, 1));
    if (parse(std.testing.allocator, "{", 0, 1)) |_| return error.TestUnexpectedResult else |_| {}
}

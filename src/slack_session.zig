const std = @import("std");
const slack = @import("slack.zig");

pub fn validToken(token: []const u8) bool {
    if (!std.mem.startsWith(u8, token, "xoxc-") or token.len == 5) return false;
    for (token) |c| if (c <= 0x20 or c >= 0x7f) return false;
    return true;
}

pub fn validCookie(cookie: []const u8) bool {
    if (!std.mem.startsWith(u8, cookie, "xoxd-") or cookie.len == 5) return false;
    for (cookie) |c| if (c <= 0x20 or c >= 0x7f or c == ';' or c == ',') return false;
    return true;
}

pub fn cookieHeader(allocator: std.mem.Allocator, cookie: []const u8) ![]u8 {
    if (!validCookie(cookie)) return error.InvalidSession;
    return std.fmt.allocPrint(allocator, "Cookie: d={s}\r\n", .{cookie});
}

pub const Request = struct {
    path: []const u8,
    body: []const u8,
};

pub fn request(allocator: std.mem.Allocator, path: []const u8, body: ?[]const u8, token: []const u8) !Request {
    if (!validToken(token)) return error.InvalidSession;
    var form: std.Io.Writer.Allocating = .init(allocator);
    const query = std.mem.indexOfScalar(u8, path, '?') orelse path.len;
    try form.writer.print("token={s}", .{try slack.percentEncode(allocator, token)});
    if (query < path.len) try form.writer.print("&{s}", .{path[query + 1 ..]});
    if (body) |json| {
        const value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, json, .{});
        if (value != .object) return error.BadArguments;
        var fields = value.object.iterator();
        while (fields.next()) |field| {
            const text = if (field.value_ptr.* == .string) field.value_ptr.string else try std.json.Stringify.valueAlloc(allocator, field.value_ptr.*, .{});
            try form.writer.print("&{s}={s}", .{ try slack.percentEncode(allocator, field.key_ptr.*), try slack.percentEncode(allocator, text) });
        }
    }
    return .{ .path = path[0..query], .body = try form.toOwnedSlice() };
}

pub fn classifyRtm(arena: std.mem.Allocator, text: []const u8, team_id: []const u8) !?slack.Envelope {
    const event = std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch return null;
    if (event != .object) return null;
    const wrapped = try std.json.Stringify.valueAlloc(arena, .{ .payload = .{ .type = "events_api", .team_id = team_id, .event = event } }, .{});
    return slack.classifyEnvelope(arena, wrapped);
}

test "IGSH-464 session form encoding and cookie reject header injection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prepared = try request(a, "/api/chat.postMessage", "{\"text\":\"Fake + & message\",\"channel\":\"CFAKE001\"}", "xoxc-fake-token");
    try std.testing.expectEqualStrings("/api/chat.postMessage", prepared.path);
    try std.testing.expect(std.mem.eql(u8, "token=xoxc-fake-token&text=Fake%20%2B%20%26%20message&channel=CFAKE001", prepared.body));
    try std.testing.expect(std.mem.eql(u8, "Cookie: d=xoxd-fake-cookie\r\n", try cookieHeader(a, "xoxd-fake-cookie")));
    try std.testing.expectError(error.InvalidSession, cookieHeader(a, "xoxd-fake\r\nInjected: yes"));
    try std.testing.expect(!validCookie("xoxd-fake; other=value"));
}

test "IGSH-464 session RTM edits and reactions reuse event parsing without ack" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const edited = (try classifyRtm(arena.allocator(),
        \\{"type":"message","subtype":"message_changed","channel":"CFAKE001","message":{"ts":"1700000000.000001","text":"Fake edit"}}
    , "TFAKE001")).?;
    try std.testing.expectEqualStrings("Fake edit", edited.text);
    try std.testing.expectEqualStrings("CFAKE001", edited.channel);
    try std.testing.expectEqualStrings("TFAKE001", edited.team_id);
    try std.testing.expectEqualStrings("", edited.envelope_id);
    const reaction = (try classifyRtm(arena.allocator(),
        \\{"type":"reaction_added","reaction":"thumbsup","item":{"channel":"CFAKE001","ts":"1700000000.000001"}}
    , "TFAKE001")).?;
    try std.testing.expectEqualStrings("CFAKE001", reaction.channel);
    try std.testing.expectEqualStrings("thumbsup", reaction.reaction);
}

const std = @import("std");

pub const Person = struct {
    name: []const u8,
    handle: []const u8 = "",
    in_chat: bool = true,
    online: bool = false,
    active: bool = true,
};

pub const Match = struct {
    index: usize,
    here: bool = false,
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[start..][0..needle.len], needle)) return true;
    }
    return false;
}

fn score(person: Person, query: []const u8) ?i32 {
    if (!person.active) return null;
    if (!contains(person.name, query) and !contains(person.handle, query)) return null;
    var value: i32 = if (person.in_chat) 100 else 40;
    if (person.online) value += 10;
    const prefix = if (query.len > 0 and person.name.len >= query.len)
        std.ascii.eqlIgnoreCase(person.name[0..query.len], query)
    else
        query.len == 0;
    if (prefix) value += 30;
    return value;
}

pub fn search(people: []const Person, query: []const u8, slack_chat: bool, out: []?Match) usize {
    var scored: [64]struct { match: Match, value: i32 } = undefined;
    var count: usize = 0;
    for (people, 0..) |person, index| {
        const value = score(person, query) orelse continue;
        if (count == scored.len) break;
        scored[count] = .{ .match = .{ .index = index }, .value = value };
        count += 1;
    }
    if (slack_chat and count < scored.len and contains("here", query) and query.len <= 4) {
        scored[count] = .{ .match = .{ .index = 0, .here = true }, .value = 60 };
        count += 1;
    }
    var i: usize = 1;
    while (i < count) : (i += 1) {
        var j = i;
        while (j > 0 and scored[j - 1].value < scored[j].value) : (j -= 1) {
            std.mem.swap(@TypeOf(scored[0]), &scored[j - 1], &scored[j]);
        }
    }
    const limit = @min(count, out.len);
    for (0..limit) |position| out[position] = scored[position].match;
    return limit;
}

pub const Provider = enum { whatsapp, slack, signal, telegram };

pub fn tokenInto(provider: Provider, person: Person, out: []u8) []const u8 {
    const handle = if (person.handle.len > 0) person.handle else person.name;
    return switch (provider) {
        .slack => std.fmt.bufPrint(out, "<@{s}>", .{handle}) catch "",
        .whatsapp => std.fmt.bufPrint(out, "@{s}", .{handle}) catch "",
        .signal, .telegram => std.fmt.bufPrint(out, "@{s}", .{person.name}) catch "",
    };
}

pub fn replaceToken(buffer: []u8, length: usize, token: Token, replacement: []const u8) usize {
    const tail_start = token.start + 1 + token.query.len;
    if (tail_start > length or length > buffer.len) return length;
    const tail = length - tail_start;
    if (token.start + replacement.len + tail > buffer.len) return length;
    std.mem.copyBackwards(u8, buffer[token.start + replacement.len ..][0..tail], buffer[tail_start..][0..tail]);
    @memcpy(buffer[token.start..][0..replacement.len], replacement);
    return token.start + replacement.len + tail;
}

pub const Token = struct {
    start: usize,
    query: []const u8,
};

pub fn activeToken(text: []const u8, caret: usize) ?Token {
    if (caret > text.len) return null;
    var start = caret;
    while (start > 0) {
        const unit = text[start - 1];
        if (unit == ' ' or unit == '\n' or unit == '\t') break;
        start -= 1;
    }
    if (start >= caret or text[start] != '@') return null;
    const query = text[start + 1 .. caret];
    if (query.len > 64) return null;
    for (query) |unit| {
        if (unit == ' ' or unit == '\n' or unit == '\t' or unit == '@') return null;
    }
    return .{ .start = start, .query = query };
}

test "a picked person becomes the provider's own mention" {
    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("<@U123>", tokenInto(.slack, .{ .name = "Paula", .handle = "U123" }, &out));
    try std.testing.expectEqualStrings("@447700900123", tokenInto(.whatsapp, .{ .name = "Paula", .handle = "447700900123" }, &out));
    try std.testing.expectEqualStrings("@Paula", tokenInto(.telegram, .{ .name = "Paula", .handle = "U123" }, &out));
}

test "picking a name swaps only its at token" {
    var buffer: [64]u8 = undefined;
    const text = "hi @pau there";
    @memcpy(buffer[0..text.len], text);
    const token = activeToken(buffer[0..text.len], 7).?;
    const length = replaceToken(&buffer, text.len, token, "@Paula");
    try std.testing.expectEqualStrings("hi @Paula there", buffer[0..length]);
}

test "the active token starts at an at sign and stops at the caret" {
    try std.testing.expect(activeToken("hello @pau", 4) == null);
    const token = activeToken("hello @pau", 10).?;
    try std.testing.expectEqual(@as(usize, 6), token.start);
    try std.testing.expectEqualStrings("pau", token.query);
    try std.testing.expectEqualStrings("", activeToken("@", 1).?.query);
    try std.testing.expect(activeToken("mail@pau", 8) == null);
    try std.testing.expect(activeToken("hello pau", 9) == null);
    try std.testing.expect(activeToken("hello @pau", 11) == null);
}

test "deactivated people never show and in-chat people rank first" {
    const people = [_]Person{
        .{ .name = "Marco Rossi", .handle = "U1" },
        .{ .name = "Marco Outside", .handle = "U2", .in_chat = false },
        .{ .name = "Gone Marco", .handle = "U3", .active = false },
        .{ .name = "Paula", .handle = "U4" },
    };
    var out: [8]?Match = @splat(null);
    const count = search(&people, "mar", false, &out);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(@as(usize, 0), out[0].?.index);
    try std.testing.expectEqual(@as(usize, 1), out[1].?.index);
}

test "an empty query lists everyone active and slack chats offer here last" {
    const people = [_]Person{ .{ .name = "Paula" }, .{ .name = "Quiet", .active = false } };
    var out: [8]?Match = @splat(null);
    try std.testing.expectEqual(@as(usize, 1), search(&people, "", false, &out));
    try std.testing.expectEqual(@as(usize, 2), search(&people, "", true, &out));
    try std.testing.expect(out[1].?.here);
    try std.testing.expectEqual(@as(usize, 1), search(&people, "her", true, &out));
    try std.testing.expect(out[0].?.here);
}

test "matches ignore case and reach the handle" {
    const people = [_]Person{.{ .name = "Paula", .handle = "U77" }};
    var out: [4]?Match = @splat(null);
    try std.testing.expectEqual(@as(usize, 1), search(&people, "U77", false, &out));
    try std.testing.expectEqual(@as(usize, 1), search(&people, "PAU", false, &out));
    try std.testing.expectEqual(@as(usize, 0), search(&people, "zzz", false, &out));
}

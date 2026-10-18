const std = @import("std");

pub const id_len = 32;
pub const max_account_len = 32;
pub const max_jid_len = 191;
pub const max_text_len = 4095;
pub const max_file_len = 519;
pub const max_client_msg_id_len = 63;
pub const max_file_id_len = 63;
pub const max_line_len = 32 * 1024;
pub const max_entries = 64;

pub const Provider = enum { whatsapp, slack };
pub const SendState = enum { queued, uploaded, failed };

pub fn Str(comptime capacity: usize) type {
    return struct {
        buf: [capacity + 1]u8 = [_]u8{0} ** (capacity + 1),
        len: usize = 0,

        pub fn slice(self: *const @This()) []const u8 {
            return self.buf[0..self.len];
        }

        pub fn set(self: *@This(), text: []const u8) void {
            self.len = @min(text.len, capacity);
            @memcpy(self.buf[0..self.len], text[0..self.len]);
            self.buf[self.len] = 0;
        }
    };
}

pub const Entry = struct {
    id: [id_len]u8 = [_]u8{'0'} ** id_len,
    provider: Provider = .whatsapp,
    account: Str(max_account_len) = .{},
    jid: Str(max_jid_len) = .{},
    text: Str(max_text_len) = .{},
    file: Str(max_file_len) = .{},
    reply_to: Str(max_jid_len) = .{},
    reply_sender: Str(max_jid_len) = .{},
    client_msg_id: Str(max_client_msg_id_len) = .{},
    attempts: u8 = 0,
    upload_file_id: Str(max_file_id_len) = .{},
    state: SendState = .queued,
    queued_unix: i64 = 0,
    ptt: bool = false,
    voice_seconds: u32 = 0,

    pub fn idSlice(self: *const Entry) []const u8 {
        return &self.id;
    }
};

pub fn validId(id: []const u8) bool {
    if (id.len != id_len) return false;
    for (id) |byte| {
        const digit = switch (byte) {
            '0'...'9' => true,
            'a'...'f' => true,
            else => false,
        };
        if (!digit) return false;
    }
    return true;
}

pub fn hexId(random: [16]u8) [id_len]u8 {
    return std.fmt.bytesToHex(random, .lower);
}

const line_fields = struct {
    id: []const u8,
    provider: []const u8,
    account: []const u8,
    jid: []const u8,
    text: []const u8,
    file: []const u8,
    reply_to: []const u8,
    reply_sender: []const u8,
    client_msg_id: []const u8,
    attempts: u8,
    upload_file_id: []const u8,
    state: []const u8,
    queued_unix: i64,
    ptt: bool,
    voice_seconds: u32,
};

pub fn writeLine(writer: *std.Io.Writer, entry: *const Entry) !void {
    try std.json.Stringify.value(line_fields{
        .id = entry.idSlice(),
        .provider = @tagName(entry.provider),
        .account = entry.account.slice(),
        .jid = entry.jid.slice(),
        .text = entry.text.slice(),
        .file = entry.file.slice(),
        .reply_to = entry.reply_to.slice(),
        .reply_sender = entry.reply_sender.slice(),
        .client_msg_id = entry.client_msg_id.slice(),
        .attempts = entry.attempts,
        .upload_file_id = entry.upload_file_id.slice(),
        .state = @tagName(entry.state),
        .queued_unix = entry.queued_unix,
        .ptt = entry.ptt,
        .voice_seconds = entry.voice_seconds,
    }, .{}, writer);
    try writer.writeByte('\n');
}

const parsed_line = struct {
    id: []const u8 = "",
    provider: []const u8 = "",
    account: []const u8 = "",
    jid: []const u8 = "",
    text: []const u8 = "",
    file: []const u8 = "",
    reply_to: []const u8 = "",
    reply_sender: []const u8 = "",
    client_msg_id: []const u8 = "",
    attempts: u8 = 0,
    upload_file_id: []const u8 = "",
    state: []const u8 = "queued",
    queued_unix: i64 = 0,
    ptt: bool = false,
    voice_seconds: u32 = 0,
};

pub fn parseLine(allocator: std.mem.Allocator, line: []const u8, out: *Entry) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0 or trimmed.len > max_line_len) return false;
    var parsed = std.json.parseFromSlice(parsed_line, allocator, trimmed, .{ .ignore_unknown_fields = true }) catch return false;
    defer parsed.deinit();
    const value = parsed.value;
    if (!validId(value.id)) return false;
    const provider = std.meta.stringToEnum(Provider, value.provider) orelse return false;
    const state = std.meta.stringToEnum(SendState, value.state) orelse return false;
    if (value.account.len > max_account_len) return false;
    if (value.jid.len == 0 or value.jid.len > max_jid_len) return false;
    if (value.text.len == 0 and value.file.len == 0) return false;
    if (value.text.len > max_text_len or value.file.len > max_file_len or
        value.reply_to.len > max_jid_len or value.reply_sender.len > max_jid_len or
        value.client_msg_id.len > max_client_msg_id_len or value.upload_file_id.len > max_file_id_len) return false;
    if (value.queued_unix < 0) return false;
    for ([_][]const u8{ value.account, value.jid, value.text, value.file, value.reply_to, value.reply_sender, value.client_msg_id, value.upload_file_id }) |field| {
        if (std.mem.indexOfScalar(u8, field, 0) != null) return false;
    }
    out.* = .{ .provider = provider, .queued_unix = value.queued_unix, .ptt = value.ptt, .voice_seconds = value.voice_seconds, .attempts = value.attempts, .state = state };
    @memcpy(&out.id, value.id);
    out.account.set(value.account);
    out.jid.set(value.jid);
    out.text.set(value.text);
    out.file.set(value.file);
    out.reply_to.set(value.reply_to);
    out.reply_sender.set(value.reply_sender);
    out.client_msg_id.set(value.client_msg_id);
    out.upload_file_id.set(value.upload_file_id);
    return true;
}

pub const Scanner = struct {
    allocator: std.mem.Allocator,
    rest: []const u8,
    seen: [max_entries][id_len]u8 = [_][id_len]u8{[_]u8{0} ** id_len} ** max_entries,
    seen_count: usize = 0,
    current: Entry = .{},

    pub fn init(allocator: std.mem.Allocator, contents: []const u8) Scanner {
        return .{ .allocator = allocator, .rest = contents };
    }

    pub fn next(self: *Scanner) ?*const Entry {
        while (self.rest.len > 0) {
            var line = self.rest;
            if (std.mem.indexOfScalar(u8, self.rest, '\n')) |newline| {
                line = self.rest[0..newline];
                self.rest = self.rest[newline + 1 ..];
            } else {
                self.rest = &.{};
            }
            if (!parseLine(self.allocator, line, &self.current)) continue;
            for (self.seen[0..self.seen_count]) |seen_id| {
                if (std.mem.eql(u8, &seen_id, self.current.idSlice())) break;
            } else {
                if (self.seen_count < self.seen.len) {
                    self.seen[self.seen_count] = self.current.id;
                    self.seen_count += 1;
                }
                return &self.current;
            }
        }
        return null;
    }
};

pub fn evictionVictim(keep: []const bool) ?usize {
    var index: usize = keep.len;
    while (index > 0) {
        index -= 1;
        if (!keep[index]) return index;
    }
    return null;
}

test "line round trip keeps every field through escapes" {
    const allocator = std.testing.allocator;
    var entry = Entry{
        .provider = .slack,
        .queued_unix = 1_700_000_000,
    };
    entry.id = hexId([_]u8{0xab} ** 16);
    entry.account.set("T01234567");
    entry.jid.set("1701234567-1234567890@us-east-1.ahoy.4-1-1.chcimbabwe-internal.slack.com");
    entry.text.set("line one\n\"quoted\" back\\slash, emoji 🎉 and unicode ünïcodé");
    entry.file.set("C:\\Users\\test\\AppData\\Local\\Messages\\paste\\paste-1.png");
    entry.reply_to.set("1700000000.000100");
    entry.reply_sender.set("U12345678");
    entry.client_msg_id.set("d9b1c0f2-6b0d-4f6a-9e1a-3c8f2d5b7a01");

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();
    try writeLine(&allocating.writer, &entry);
    const line = try allocating.toOwnedSlice();
    defer allocator.free(line);

    var parsed = Entry{};
    try std.testing.expect(parseLine(allocator, line, &parsed));
    try std.testing.expectEqual(Provider.slack, parsed.provider);
    try std.testing.expectEqualSlices(u8, entry.idSlice(), parsed.idSlice());
    try std.testing.expectEqualStrings(entry.account.slice(), parsed.account.slice());
    try std.testing.expectEqualStrings(entry.jid.slice(), parsed.jid.slice());
    try std.testing.expectEqualStrings(entry.text.slice(), parsed.text.slice());
    try std.testing.expectEqualStrings(entry.file.slice(), parsed.file.slice());
    try std.testing.expectEqualStrings(entry.reply_to.slice(), parsed.reply_to.slice());
    try std.testing.expectEqualStrings(entry.reply_sender.slice(), parsed.reply_sender.slice());
    try std.testing.expectEqualStrings(entry.client_msg_id.slice(), parsed.client_msg_id.slice());
    try std.testing.expectEqual(entry.queued_unix, parsed.queued_unix);
}

test "scanner skips corrupt lines and loads the valid ones" {
    const allocator = std.testing.allocator;
    var entry = Entry{ .provider = .whatsapp, .queued_unix = 42 };
    entry.id = hexId([_]u8{1} ** 16);
    entry.jid.set("1234567890@s.whatsapp.net");
    entry.text.set("hello");
    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();
    try writeLine(&allocating.writer, &entry);
    const good = try allocating.toOwnedSlice();
    defer allocator.free(good);

    const contents = std.fmt.allocPrint(allocator, "{s}{s}{s}{s}{s}{s}{s}{s}", .{
        "not json at all\n",
        "\n",
        "{\"id\":\"too-short\",\"provider\":\"whatsapp\",\"jid\":\"x\",\"text\":\"y\",\"queued_unix\":1}\n",
        "{\"id\":\"0123456789abcdef0123456789abcdeg\",\"provider\":\"whatsapp\",\"jid\":\"x\",\"text\":\"y\",\"queued_unix\":1}\n",
        "{\"id\":\"0123456789abcdef0123456789abcdef\",\"provider\":\"carrier-pigeon\",\"jid\":\"x\",\"text\":\"y\",\"queued_unix\":1}\n",
        "{\"id\":\"0123456789abcdef0123456789abcdef\",\"provider\":\"whatsapp\",\"jid\":\"x\",\"queued_unix\":1}\n",
        good,
        "{\"id\":\"0123456789abcdef0123456789abcde\n",
    }) catch unreachable;
    defer allocator.free(contents);

    var scanner = Scanner.init(allocator, contents);
    const first = scanner.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Provider.whatsapp, first.provider);
    try std.testing.expectEqualStrings("1234567890@s.whatsapp.net", first.jid.slice());
    try std.testing.expectEqualStrings("hello", first.text.slice());
    try std.testing.expectEqual(@as(i64, 42), first.queued_unix);
    try std.testing.expect(scanner.next() == null);
}

test "scanner collapses duplicate ids and keeps the first entry" {
    const allocator = std.testing.allocator;
    var first = Entry{};
    first.id = hexId([_]u8{2} ** 16);
    first.jid.set("1234567890@s.whatsapp.net");
    first.text.set("original");
    var duplicate = first;
    duplicate.text.set("resend from an older snapshot");
    var third = Entry{};
    third.id = hexId([_]u8{3} ** 16);
    third.jid.set("1234567890@s.whatsapp.net");
    third.text.set("after");

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();
    try writeLine(&allocating.writer, &first);
    try writeLine(&allocating.writer, &duplicate);
    try writeLine(&allocating.writer, &third);

    const whole = try allocating.toOwnedSlice();
    defer allocator.free(whole);
    var scanner = Scanner.init(allocator, whole);
    const loaded_first = scanner.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("original", loaded_first.text.slice());
    const loaded_third = scanner.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("after", loaded_third.text.slice());
    try std.testing.expect(scanner.next() == null);
}

test "evictionVictim never evicts a write and gives up when only writes remain" {
    try std.testing.expectEqual(@as(?usize, null), evictionVictim(&.{ true, true, true }));
    try std.testing.expectEqual(@as(?usize, 3), evictionVictim(&.{ true, false, false, false }));
    try std.testing.expectEqual(@as(?usize, 1), evictionVictim(&.{ true, false, true, true }));
    try std.testing.expectEqual(@as(?usize, 0), evictionVictim(&.{ false, true, true, true }));
    try std.testing.expectEqual(@as(?usize, null), evictionVictim(&.{}));
}

test "parse rejects NUL fields and negative enqueue times before Win32 use" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "account", "jid", "text", "file", "reply_to", "reply_sender", "client_msg_id" }) |field| {
        const line = try std.fmt.allocPrint(allocator, "{{\"id\":\"0123456789abcdef0123456789abcdef\",\"provider\":\"whatsapp\",\"{s}\":\"before\\u0000after\",{s}}}", .{ field, if (std.mem.eql(u8, field, "jid")) "\"text\":\"synthetic\"" else if (std.mem.eql(u8, field, "text")) "\"jid\":\"synthetic\"" else "\"jid\":\"synthetic\",\"text\":\"synthetic\"" });
        defer allocator.free(line);
        var parsed = Entry{};
        try std.testing.expect(!parseLine(allocator, line, &parsed));
    }
    var parsed = Entry{};
    try std.testing.expect(!parseLine(allocator, "{\"id\":\"0123456789abcdef0123456789abcdef\",\"provider\":\"whatsapp\",\"jid\":\"synthetic\",\"text\":\"synthetic\",\"queued_unix\":-9223372036854775808}", &parsed));
}

test "maximum escaped fields round trip and oversized fields are rejected" {
    const allocator = std.testing.allocator;
    var entry = Entry{};
    entry.jid.set(&([_]u8{'\t'} ** max_jid_len));
    entry.text.set(&([_]u8{1} ** max_text_len));
    entry.file.set(&([_]u8{'\t'} ** max_file_len));
    entry.reply_to = entry.jid;
    entry.reply_sender = entry.jid;
    entry.client_msg_id.set(&([_]u8{'\t'} ** max_client_msg_id_len));
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();
    try writeLine(&writer.writer, &entry);
    try std.testing.expect(writer.written().len <= max_line_len);
    var parsed = Entry{};
    try std.testing.expect(parseLine(allocator, writer.written(), &parsed));
    try std.testing.expectEqualStrings(entry.text.slice(), parsed.text.slice());
    const oversized = try std.fmt.allocPrint(allocator, "{{\"id\":\"0123456789abcdef0123456789abcdef\",\"provider\":\"whatsapp\",\"jid\":\"synthetic\",\"text\":\"{s}\"}}", .{[_]u8{'x'} ** (max_text_len + 1)});
    defer allocator.free(oversized);
    try std.testing.expect(!parseLine(allocator, oversized, &parsed));
}

test "slack upload state round-trips" {
    var entry = Entry{ .provider = .slack, .queued_unix = 1700000000, .attempts = 2, .state = .uploaded };
    entry.id = hexId([_]u8{0xcd} ** 16);
    entry.jid.set("C01234567");
    entry.text.set("image caption");
    entry.file.set("C:\\cache\\image.png");
    entry.upload_file_id.set("F01234567");
    var allocating = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating.deinit();
    try writeLine(&allocating.writer, &entry);
    var parsed = Entry{};
    try std.testing.expect(parseLine(std.testing.allocator, allocating.written(), &parsed));
    try std.testing.expectEqualDeep(entry, parsed);
    entry.state = .failed;
    allocating.clearRetainingCapacity();
    try writeLine(&allocating.writer, &entry);
    try std.testing.expect(parseLine(std.testing.allocator, allocating.written(), &parsed));
    try std.testing.expectEqualDeep(entry, parsed);
}

test "old line without upload fields parses" {
    const line =
        \\{"id":"0123456789abcdef0123456789abcdef","provider":"slack","jid":"C01234567","text":"hello","file":"","reply_to":"","reply_sender":"","client_msg_id":"00000000-0000-4000-8000-000000000000","queued_unix":1700000000,"ptt":false,"voice_seconds":0}
    ;
    var parsed = Entry{};
    try std.testing.expect(parseLine(std.testing.allocator, line, &parsed));
    try std.testing.expectEqual(SendState.queued, parsed.state);
    try std.testing.expectEqual(@as(u8, 0), parsed.attempts);
    try std.testing.expectEqualStrings("", parsed.upload_file_id.slice());
}

test "invalid upload fields are rejected" {
    for ([_][]const u8{
        "\"state\":\"invalid\"",
        "\"attempts\":256",
        "\"attempts\":-1",
        "\"upload_file_id\":\"F\\u0000bad\"",
        "\"upload_file_id\":\"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF\"",
    }) |field| {
        const line = try std.fmt.allocPrint(std.testing.allocator, "{{\"id\":\"0123456789abcdef0123456789abcdef\",\"provider\":\"slack\",\"jid\":\"C01234567\",\"text\":\"hello\",{s}}}", .{field});
        defer std.testing.allocator.free(line);
        var entry = Entry{};
        try std.testing.expect(!parseLine(std.testing.allocator, line, &entry));
    }
}

test "old line without account parses and keeps the send" {
    const line =
        \\{"id":"0123456789abcdef0123456789abcdef","provider":"whatsapp","jid":"4915112345678@s.whatsapp.net","text":"hello","file":"C:\\cache\\voice.ogg","reply_to":"quoted-id","reply_sender":"sender@s.whatsapp.net","client_msg_id":"client-id","attempts":2,"upload_file_id":"file-id","state":"queued","queued_unix":1700000000,"ptt":true,"voice_seconds":7}
    ;
    var parsed = Entry{};
    try std.testing.expect(parseLine(std.testing.allocator, line, &parsed));
    var expected = Entry{ .provider = .whatsapp, .attempts = 2, .queued_unix = 1700000000, .ptt = true, .voice_seconds = 7 };
    @memcpy(&expected.id, "0123456789abcdef0123456789abcdef");
    expected.jid.set("4915112345678@s.whatsapp.net");
    expected.text.set("hello");
    expected.file.set("C:\\cache\\voice.ogg");
    expected.reply_to.set("quoted-id");
    expected.reply_sender.set("sender@s.whatsapp.net");
    expected.client_msg_id.set("client-id");
    expected.upload_file_id.set("file-id");
    try std.testing.expectEqualDeep(expected, parsed);
    var scanner = Scanner.init(std.testing.allocator, line);
    try std.testing.expectEqualDeep(expected, scanner.next().?.*);
    try std.testing.expect(scanner.next() == null);
}

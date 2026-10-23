const std = @import("std");
const theme = @import("theme.zig");
const transport = @import("transport.zig");

pub const pipe_prefix = "\\\\.\\pipe\\wazig-control-";

pub const Command = enum { theme, status, chats, search, view, select, messages, archive, unarchive, @"archive-many" };
pub const Messenger = enum { whatsapp, slack, telegram, all, signal };

pub const Request = struct {
    cmd: Command,
    theme: ?theme.Choice = null,
    id: []const u8 = "",
    ids: []const []const u8 = &.{},
    text: []const u8 = "",
    messenger: ?Messenger = null,
    view_number: ?usize = null,
    provider: ?transport.Provider = null,
    account: []const u8 = "",
    archived: bool = false,
    all: bool = false,
    limit: ?u32 = null,
};

pub const CommandInfo = struct { cmd: Command, usage: []const u8, summary: []const u8 };

pub const commands = [_]CommandInfo{
    .{ .cmd = .theme, .usage = "theme <green|amoled>", .summary = "switch and save the app theme without focusing it" },
    .{ .cmd = .status, .usage = "status", .summary = "version, theme, current account view and order, selected chat, sync state, pending sends, search text" },
    .{ .cmd = .chats, .usage = "chats [--json] [--messenger all|whatsapp|slack|telegram|signal] [--archived] [--all] [--limit N]", .summary = "list chats; default is what the sidebar shows, --all ignores the search filter" },
    .{ .cmd = .search, .usage = "search <text>", .summary = "set the sidebar search text (\"\" clears it)" },
    .{ .cmd = .view, .usage = "view <N|inbox|all|whatsapp|slack|telegram|signal>", .summary = "switch to an account view or the combined inbox" },
    .{ .cmd = .select, .usage = "select <id> [--provider whatsapp|slack|telegram|signal --account ID]", .summary = "open that chat in the app" },
    .{ .cmd = .messages, .usage = "messages [<id>] [--limit N]", .summary = "recent loaded messages of the selected (or given) chat" },
    .{ .cmd = .archive, .usage = "archive <id>", .summary = "archive a chat (the app's own archive action)" },
    .{ .cmd = .unarchive, .usage = "unarchive <id>", .summary = "unarchive a chat" },
    .{ .cmd = .@"archive-many", .usage = "archive-many <id>...", .summary = "archive several chats" },
};

pub const help_text = blk: {
    var text: []const u8 =
        \\Usage: wazigctl <command> [args]
        \\
        \\Controls the running Wazig Messages app over a local pipe without
        \\focusing or showing its window. Output is one JSON line on stdout;
        \\exit code 0 on success, 1 when the app reports an error or does not
        \\answer within 45 s, 2 on bad usage, 3 when the app is not running.
        \\
        \\Nothing here sends messages, reactions or replies. Only `select`
        \\and `messages <id>` mark a chat read, as clicking it in the app does.
        \\
        \\Commands:
        \\
    ;
    for (commands) |info| text = text ++ "  " ++ info.usage ++ "\n      " ++ info.summary ++ "\n";
    break :blk text;
};

pub const ParseError = error{ Usage, OutOfMemory };

pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8, message: *[]const u8) ParseError!Request {
    if (args.len == 0) return usage(message, "missing command");
    const cmd = std.meta.stringToEnum(Command, args[0]) orelse return usage(message, "unknown command");
    var request = Request{ .cmd = cmd };
    var positional: std.ArrayList([]const u8) = .empty;
    defer positional.deinit(allocator);
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        const takes_flags = cmd == .chats or cmd == .messages or cmd == .select;
        if (takes_flags and std.mem.eql(u8, arg, "--json")) continue;
        if (cmd == .select and (std.mem.eql(u8, arg, "--provider") or std.mem.eql(u8, arg, "--account"))) {
            index += 1;
            if (index >= args.len) return usage(message, "identity option needs a value");
            if (std.mem.eql(u8, arg, "--provider")) {
                request.provider = std.meta.stringToEnum(transport.Provider, args[index]) orelse return usage(message, "unknown provider");
            } else request.account = try allocator.dupe(u8, args[index]);
            continue;
        }
        if (takes_flags and std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--limit")) {
                index += 1;
                if (index >= args.len) return usage(message, "--limit needs a number");
                const limit = std.fmt.parseInt(u32, args[index], 10) catch return usage(message, "--limit needs a positive number");
                if (limit == 0) return usage(message, "--limit needs a positive number");
                request.limit = limit;
                continue;
            }
            if (cmd == .chats and std.mem.eql(u8, arg, "--messenger")) {
                index += 1;
                if (index >= args.len) return usage(message, "--messenger needs whatsapp, slack, telegram or signal");
                request.messenger = std.meta.stringToEnum(Messenger, args[index]) orelse return usage(message, "--messenger needs whatsapp, slack, telegram or signal");
                continue;
            }
            if (cmd == .chats and std.mem.eql(u8, arg, "--archived")) {
                request.archived = true;
                continue;
            }
            if (cmd == .chats and std.mem.eql(u8, arg, "--all")) {
                request.all = true;
                continue;
            }
            return usage(message, "unknown option");
        }
        if (cmd != .search and std.mem.startsWith(u8, arg, "--")) return usage(message, "unknown option");
        try positional.append(allocator, arg);
    }
    const items = positional.items;
    switch (cmd) {
        .theme => {
            if (items.len != 1) return usage(message, "theme needs green or amoled");
            request.theme = std.meta.stringToEnum(theme.Choice, items[0]) orelse return usage(message, "theme needs green or amoled");
        },
        .status, .chats => if (items.len != 0) return usage(message, "unexpected argument"),
        .search => {
            if (items.len == 0) return usage(message, "search needs text (\"\" clears it)");
            request.text = try std.mem.join(allocator, " ", items);
        },
        .view => {
            if (items.len != 1) return usage(message, "view needs a number, inbox or provider");
            if (std.mem.eql(u8, items[0], "inbox")) {
                request.messenger = .all;
            } else if (std.meta.stringToEnum(Messenger, items[0])) |messenger| {
                request.messenger = messenger;
            } else {
                const number = std.fmt.parseInt(usize, items[0], 10) catch return usage(message, "view needs a number, inbox or provider");
                if (number == 0) return usage(message, "view numbers start at 1");
                request.view_number = number;
            }
        },
        .select, .archive, .unarchive => {
            if (items.len != 1 or items[0].len == 0) return usage(message, "needs exactly one chat id");
            request.id = try allocator.dupe(u8, items[0]);
        },
        .messages => {
            if (items.len > 1) return usage(message, "messages takes at most one chat id");
            if (items.len == 1) request.id = try allocator.dupe(u8, items[0]);
        },
        .@"archive-many" => {
            if (items.len == 0) return usage(message, "archive-many needs at least one chat id");
            for (items) |item| if (item.len == 0) return usage(message, "empty chat id");
            request.ids = try allocator.dupe([]const u8, items);
        },
    }
    return request;
}

fn usage(message: *[]const u8, text: []const u8) ParseError {
    message.* = text;
    return error.Usage;
}

pub fn writeRequest(writer: *std.Io.Writer, request: Request) !void {
    try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, writer);
    try writer.writeByte('\n');
}

pub fn parseRequest(allocator: std.mem.Allocator, line: []const u8) !std.json.Parsed(Request) {
    return std.json.parseFromSlice(Request, allocator, std.mem.trim(u8, line, " \t\r\n"), .{ .allocate = .alloc_always });
}

pub fn responseOk(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "{\"ok\":true");
}

pub fn responseError(line: []const u8) []const u8 {
    const key = "\"error\":\"";
    const start = (std.mem.indexOf(u8, line, key) orelse return "") + key.len;
    var end = start;
    while (end < line.len and line[end] != '"') : (end += 1) {
        if (line[end] == '\\') end += 1;
    }
    return line[start..@min(end, line.len)];
}

pub fn writeError(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeAll("{\"ok\":false,\"error\":");
    try writeString(writer, text);
    try writer.writeAll("}\n");
}

pub fn writeString(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    var index: usize = 0;
    while (index < text.len) {
        const byte = text[index];
        if (byte < 0x80) {
            try writeAsciiEscaped(writer, byte);
            index += 1;
            continue;
        }
        const length = std.unicode.utf8ByteSequenceLength(byte) catch {
            try writeCodepoint(writer, 0xfffd);
            index += 1;
            continue;
        };
        if (index + length > text.len) {
            try writeCodepoint(writer, 0xfffd);
            index += 1;
            continue;
        }
        const codepoint = std.unicode.utf8Decode(text[index .. index + length]) catch {
            try writeCodepoint(writer, 0xfffd);
            index += 1;
            continue;
        };
        try writeCodepoint(writer, codepoint);
        index += length;
    }
    try writer.writeByte('"');
}

pub fn writeStringUtf16(writer: *std.Io.Writer, text: []const u16) !void {
    try writer.writeByte('"');
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        const unit = text[index];
        if (unit < 0x80) {
            try writeAsciiEscaped(writer, @intCast(unit));
        } else if (unit >= 0xd800 and unit <= 0xdbff and index + 1 < text.len and text[index + 1] >= 0xdc00 and text[index + 1] <= 0xdfff) {
            try writer.print("\\u{x:0>4}\\u{x:0>4}", .{ unit, text[index + 1] });
            index += 1;
        } else if (unit >= 0xd800 and unit <= 0xdfff) {
            try writer.writeAll("\\ufffd");
        } else {
            try writer.print("\\u{x:0>4}", .{unit});
        }
    }
    try writer.writeByte('"');
}

fn writeAsciiEscaped(writer: *std.Io.Writer, byte: u8) !void {
    switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0...8, 11, 12, 14...0x1f, 0x7f => try writer.print("\\u{x:0>4}", .{byte}),
        else => try writer.writeByte(byte),
    }
}

fn writeCodepoint(writer: *std.Io.Writer, codepoint: u21) !void {
    if (codepoint < 0x80) return writeAsciiEscaped(writer, @intCast(codepoint));
    if (codepoint < 0x10000) return writer.print("\\u{x:0>4}", .{codepoint});
    const offset = codepoint - 0x10000;
    try writer.print("\\u{x:0>4}\\u{x:0>4}", .{ 0xd800 + (offset >> 10), 0xdc00 + (offset & 0x3ff) });
}

fn parseForTest(args: []const []const u8) !Request {
    var message: []const u8 = "";
    return parseArgs(std.testing.allocator, args, &message);
}

test "chats flags parse into one request" {
    const request = try parseForTest(&.{ "chats", "--messenger", "slack", "--archived", "--all", "--limit", "5" });
    try std.testing.expectEqual(Command.chats, request.cmd);
    try std.testing.expectEqual(@as(?Messenger, .slack), request.messenger);
    try std.testing.expect(request.archived and request.all);
    try std.testing.expectEqual(@as(?u32, 5), request.limit);
}

test "usage errors name the problem instead of guessing" {
    var message: []const u8 = "";
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{}, &message));
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{"send"}, &message));
    try std.testing.expectEqualStrings("unknown command", message);
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{ "chats", "--limit", "0" }, &message));
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{ "chats", "--messenger", "signal" }, &message));
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{"select"}, &message));
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{ "view", "slack", "extra" }, &message));
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{"archive-many"}, &message));
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{ "archive", "--all" }, &message));
}

test "search joins words and accepts an empty string to clear" {
    const allocator = std.testing.allocator;
    const request = try parseForTest(&.{ "search", "foo", "bar" });
    defer allocator.free(request.text);
    try std.testing.expectEqualStrings("foo bar", request.text);
    const clear = try parseForTest(&.{ "search", "" });
    defer allocator.free(clear.text);
    try std.testing.expectEqualStrings("", clear.text);
}

test "a request survives the JSON round trip over the pipe" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const ids = [_][]const u8{ "123@s.whatsapp.net", "C0123" };
    try writeRequest(&out.writer, .{ .cmd = .@"archive-many", .ids = &ids });
    const line = out.written();
    try std.testing.expect(std.mem.endsWith(u8, line, "\n"));
    const parsed = try parseRequest(allocator, line);
    defer parsed.deinit();
    try std.testing.expectEqual(Command.@"archive-many", parsed.value.cmd);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.ids.len);
    try std.testing.expectEqualStrings("C0123", parsed.value.ids[1]);
    try std.testing.expectEqual(@as(?u32, null), parsed.value.limit);
}

test "a request with a quote and a newline in the search text round trips" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeRequest(&out.writer, .{ .cmd = .search, .text = "a\"b\nc" });
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "\n"));
    const parsed = try parseRequest(allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqualStrings("a\"b\nc", parsed.value.text);
}

test "unknown commands and fields are rejected by the app side" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidEnumTag, parseRequest(allocator, "{\"cmd\":\"send\"}"));
    try std.testing.expectError(error.UnknownField, parseRequest(allocator, "{\"cmd\":\"status\",\"body\":\"hi\"}"));
}

fn escapedForTest(text: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    errdefer out.deinit();
    try writeString(&out.writer, text);
    return out.toOwnedSlice();
}

test "output escaping keeps the reply one ASCII line" {
    const allocator = std.testing.allocator;
    const plain = try escapedForTest("a\"b\\c\nd\te\x01");
    defer allocator.free(plain);
    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\\nd\\te\\u0001\"", plain);
    const unicode = try escapedForTest("\xc3\xa9\xf0\x9f\x98\x80");
    defer allocator.free(unicode);
    try std.testing.expectEqualStrings("\"\\u00e9\\ud83d\\ude00\"", unicode);
    const broken = try escapedForTest("x\xe2\x82");
    defer allocator.free(broken);
    try std.testing.expectEqualStrings("\"x\\ufffd\\ufffd\"", broken);
}

test "UTF-16 display text escapes pairs and replaces lone surrogates" {
    const allocator = std.testing.allocator;
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const text = [_]u16{ 'H', 0xe9, 0xd83d, 0xde00, 0xd800, '"' };
    try writeStringUtf16(&out.writer, &text);
    try std.testing.expectEqualStrings("\"H\\u00e9\\ud83d\\ude00\\ufffd\\\"\"", out.written());
    const parsed = try std.json.parseFromSlice([]const u8, allocator, out.written()[0..out.written().len], .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("H\xc3\xa9\xf0\x9f\x98\x80\xef\xbf\xbd\"", parsed.value);
}

test "reply helpers read ok and error" {
    try std.testing.expect(responseOk("{\"ok\":true,\"result\":{}}"));
    try std.testing.expect(!responseOk("{\"ok\":false,\"error\":\"x\"}"));
    try std.testing.expectEqualStrings("no chat \\\"x\\\"", responseError("{\"ok\":false,\"error\":\"no chat \\\"x\\\"\"}"));
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeError(&out.writer, "bad \"id\"");
    try std.testing.expectEqualStrings("{\"ok\":false,\"error\":\"bad \\\"id\\\"\"}\n", out.written());
}

test "help lists every command and says nothing sends" {
    for (commands) |info| try std.testing.expect(std.mem.indexOf(u8, help_text, info.usage) != null);
    try std.testing.expect(std.mem.indexOf(u8, help_text, "Nothing here sends messages") != null);
    try std.testing.expectEqual(@typeInfo(Command).@"enum".fields.len, commands.len);
}

test "theme accepts both choices and rejects invalid or missing choices" {
    for ([_]theme.Choice{ .green, .amoled }) |choice| {
        const request = try parseForTest(&.{ "theme", @tagName(choice) });
        try std.testing.expectEqual(Command.theme, request.cmd);
        try std.testing.expectEqual(@as(?theme.Choice, choice), request.theme);
    }
    var message: []const u8 = "";
    try std.testing.expectError(error.Usage, parseArgs(std.testing.allocator, &.{ "theme", "purple" }, &message));
    try std.testing.expectEqualStrings("theme needs green or amoled", message);
    try std.testing.expectError(error.Usage, parseArgs(std.testing.allocator, &.{"theme"}, &message));
    try std.testing.expectError(error.Usage, parseArgs(std.testing.allocator, &.{ "theme", "amoled", "extra" }, &message));
}

test "theme choice survives the control JSON round trip" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeRequest(&out.writer, .{ .cmd = .theme, .theme = .amoled });
    const parsed = try parseRequest(std.testing.allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqual(Command.theme, parsed.value.cmd);
    try std.testing.expectEqual(@as(?theme.Choice, .amoled), parsed.value.theme);
    try std.testing.expectError(error.InvalidEnumTag, parseRequest(std.testing.allocator, "{\"cmd\":\"theme\",\"theme\":\"purple\"}"));
}

test "select accepts a full workspace identity and chats accepts explicit JSON" {
    const request = try parseForTest(&.{ "select", "C0000000001", "--provider", "slack", "--account", "T0000000002" });
    defer std.testing.allocator.free(request.id);
    defer std.testing.allocator.free(request.account);
    try std.testing.expectEqual(@as(?transport.Provider, .slack), request.provider);
    try std.testing.expectEqualStrings("T0000000002", request.account);
    try std.testing.expectEqualStrings("C0000000001", request.id);
    try std.testing.expectEqual(Command.chats, (try parseForTest(&.{ "chats", "--json" })).cmd);
    try std.testing.expectEqual(@as(?Messenger, .all), (try parseForTest(&.{ "view", "all" })).messenger);
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try writeRequest(&out.writer, request);
    const parsed = try parseRequest(std.testing.allocator, out.written());
    defer parsed.deinit();
    try std.testing.expectEqualStrings(request.account, parsed.value.account);
    try std.testing.expectEqual(request.provider, parsed.value.provider);
}

test "IGSH-538 removed stories commands reject CLI and pipe requests" {
    for ([_][]const u8{ "statuses", "open-status" }) |command| {
        var message: []const u8 = "";
        try std.testing.expectError(error.Usage, parseArgs(std.testing.allocator, &.{command}, &message));
        try std.testing.expectEqualStrings("unknown command", message);
        var request = std.Io.Writer.Allocating.init(std.testing.allocator);
        defer request.deinit();
        try request.writer.print("{{\"cmd\":\"{s}\"}}", .{command});
        try std.testing.expectError(error.InvalidEnumTag, parseRequest(std.testing.allocator, request.written()));
        try std.testing.expect(std.mem.indexOf(u8, help_text, command) == null);
    }
}

test "IGSH-538 app diagnostics and messenger controls remain available" {
    try std.testing.expectEqual(Command.status, (try parseForTest(&.{"status"})).cmd);
    for ([_][]const u8{ "all", "whatsapp", "slack", "telegram", "signal" }) |messenger| {
        const request = try parseForTest(&.{ "view", messenger });
        try std.testing.expectEqual(Command.view, request.cmd);
        try std.testing.expectEqualStrings(messenger, @tagName(request.messenger.?));
    }
}

test "view accepts an account position and combined inbox while retaining provider aliases" {
    const allocator = std.testing.allocator;
    var message: []const u8 = "";
    const numbered = try parseArgs(allocator, &.{ "view", "4" }, &message);
    try std.testing.expectEqual(@as(?usize, 4), numbered.view_number);
    const inbox = try parseArgs(allocator, &.{ "view", "inbox" }, &message);
    try std.testing.expectEqual(@as(?Messenger, .all), inbox.messenger);
    const legacy = try parseArgs(allocator, &.{ "view", "slack" }, &message);
    try std.testing.expectEqual(@as(?Messenger, .slack), legacy.messenger);
    try std.testing.expectError(error.Usage, parseArgs(allocator, &.{ "view", "0" }, &message));
}

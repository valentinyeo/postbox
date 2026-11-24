const std = @import("std");
const transport = @import("transport.zig");
const chat_key = @import("chat_key.zig");

pub const scheme_prefix = "postbox://";
pub const pipe_prefix = "\\\\.\\pipe\\postbox-link-";
pub const protocol_description = "URL:Postbox Protocol";
pub const invalid_link_note = "That Postbox link is not valid.";

pub const Target = struct {
    provider: transport.Provider = .whatsapp,
    account: [chat_key.max_account_len]u8 = @splat(0),
    account_len: usize = 0,
    chat: [191]u8 = @splat(0),
    chat_len: usize = 0,
    message: [191]u8 = @splat(0),
    message_len: usize = 0,

    pub fn accountSlice(self: *const Target) []const u8 {
        return self.account[0..self.account_len];
    }

    pub fn chatSlice(self: *const Target) []const u8 {
        return self.chat[0..self.chat_len];
    }

    pub fn messageSlice(self: *const Target) []const u8 {
        return self.message[0..self.message_len];
    }
};

pub const ParseError = error{
    InvalidScheme,
    UnsupportedProvider,
    MissingAccount,
    MissingChat,
    TooManySegments,
    InvalidEncoding,
    ControlCharacter,
    TooLong,
    InvalidUtf8,
};

pub fn isPostboxUrl(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len < scheme_prefix.len) return false;
    return std.ascii.eqlIgnoreCase(trimmed[0..scheme_prefix.len], scheme_prefix);
}

pub fn missingChatNote(provider: transport.Provider) []const u8 {
    return switch (provider) {
        .whatsapp => "Could not find that WhatsApp chat.",
        .slack => "Could not find that Slack channel.",
        .telegram => "Could not find that Telegram chat.",
        .signal => "Could not find that Signal chat.",
    };
}

pub fn parse(raw: []const u8) ParseError!Target {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (!isPostboxUrl(trimmed)) return error.InvalidScheme;
    const after_scheme = trimmed[scheme_prefix.len..];
    const no_fragment = if (std.mem.indexOfScalar(u8, after_scheme, '#')) |hash| after_scheme[0..hash] else after_scheme;
    const query_start = std.mem.indexOfScalar(u8, no_fragment, '?');
    const authority_and_path = if (query_start) |q| no_fragment[0..q] else no_fragment;
    const query = if (query_start) |q| no_fragment[q + 1 ..] else "";
    const slash = std.mem.indexOfScalar(u8, authority_and_path, '/') orelse return error.MissingAccount;
    const host = authority_and_path[0..slash];
    const provider: transport.Provider = if (std.ascii.eqlIgnoreCase(host, "whatsapp"))
        .whatsapp
    else if (std.ascii.eqlIgnoreCase(host, "slack"))
        .slack
    else
        return error.UnsupportedProvider;
    const path = std.mem.trimEnd(u8, authority_and_path[slash + 1 ..], "/");
    if (path.len == 0) return error.MissingAccount;
    var segments = std.mem.splitScalar(u8, path, '/');
    const raw_account = segments.next() orelse return error.MissingAccount;
    const raw_chat = segments.next() orelse return error.MissingChat;
    const raw_path_msg = segments.next();
    if (segments.next() != null) return error.TooManySegments;
    if (raw_account.len == 0) return error.MissingAccount;
    if (raw_chat.len == 0) return error.MissingChat;

    var target = Target{ .provider = provider };
    target.account_len = try decodeField(&target.account, raw_account);
    if (target.account_len == 0) return error.MissingAccount;

    var chat_buf: [191]u8 = @splat(0);
    const chat_len = try decodeField(&chat_buf, raw_chat);
    if (chat_len == 0) return error.MissingChat;
    var chat_slice: []const u8 = chat_buf[0..chat_len];
    if (provider == .whatsapp) {
        if (stripAccountPrefix(chat_slice, target.accountSlice())) |bare| {
            if (bare.len > 0) chat_slice = bare;
        }
    }
    @memcpy(target.chat[0..chat_slice.len], chat_slice);
    target.chat_len = chat_slice.len;

    var raw_msg: []const u8 = raw_path_msg orelse "";
    if (raw_msg.len == 0 and query.len > 0) {
        raw_msg = findQueryMessage(query);
    }
    if (raw_msg.len > 0) {
        var msg_buf: [191]u8 = @splat(0);
        const msg_len = try decodeField(&msg_buf, raw_msg);
        if (msg_len > 0) {
            if (provider == .slack) {
                target.message_len = normalizeSlackTs(&target.message, msg_buf[0..msg_len]) orelse return error.TooLong;
            } else {
                @memcpy(target.message[0..msg_len], msg_buf[0..msg_len]);
                target.message_len = msg_len;
            }
        }
    }
    return target;
}

pub fn matchesChat(
    target: *const Target,
    provider: transport.Provider,
    account: []const u8,
    view_account: []const u8,
    jid: []const u8,
) bool {
    if (provider != target.provider) return false;
    const wanted_account = target.accountSlice();
    const wanted_chat = target.chatSlice();
    return switch (provider) {
        .whatsapp => blk: {
            if (splitWhatsAppJid(jid)) |parts| {
                break :blk std.mem.eql(u8, parts.account, wanted_account) and whatsAppIdMatches(parts.chat, wanted_chat);
            }
            const account_match = std.mem.eql(u8, view_account, wanted_account) or std.mem.eql(u8, account, wanted_account);
            break :blk account_match and whatsAppIdMatches(jid, wanted_chat);
        },
        .slack => blk: {
            if (splitSlackJid(jid)) |parts| {
                break :blk std.mem.eql(u8, parts.team, wanted_account) and std.mem.eql(u8, parts.channel, wanted_chat);
            }
            const account_match = std.mem.eql(u8, view_account, wanted_account) or std.mem.eql(u8, account, wanted_account);
            break :blk account_match and std.mem.eql(u8, jid, wanted_chat);
        },
        else => false,
    };
}

pub fn viewAccountFor(provider: transport.Provider, account: []const u8, jid: []const u8, fallback: []const u8) []const u8 {
    if (provider == .signal and std.mem.startsWith(u8, jid, "signal:")) return "signal";
    if (provider == .telegram and std.mem.startsWith(u8, jid, "telegram:")) return "telegram";
    if (account.len > 0) return account;
    if (provider == .whatsapp) {
        if (splitWhatsAppJid(jid)) |parts| return parts.account;
    } else if (provider == .slack) {
        if (splitSlackJid(jid)) |parts| return parts.team;
    }
    return fallback;
}

pub fn matchesMessage(target: *const Target, message_id: []const u8) bool {
    const wanted = target.messageSlice();
    if (wanted.len == 0 or message_id.len == 0) return false;
    if (std.mem.eql(u8, message_id, wanted)) return true;
    if (target.provider == .whatsapp) {
        const acct = target.accountSlice();
        const bare_msg = stripAccountPrefix(message_id, acct) orelse message_id;
        const bare_wanted = stripAccountPrefix(wanted, acct) orelse wanted;
        if (std.mem.indexOfScalar(u8, message_id, ':')) |colon| {
            if (!std.mem.eql(u8, message_id[0..colon], acct)) return false;
        }
        return std.mem.eql(u8, bare_msg, bare_wanted);
    }
    return false;
}

pub fn formatRegistryCommand(buffer: []u16, exe_path: []const u16) ?[:0]const u16 {
    const suffix = std.unicode.utf8ToUtf16LeStringLiteral("\" \"%1\"");
    const total = 1 + exe_path.len + suffix.len;
    if (total >= buffer.len) return null;
    buffer[0] = '"';
    @memcpy(buffer[1..][0..exe_path.len], exe_path);
    @memcpy(buffer[1 + exe_path.len ..][0..suffix.len], suffix);
    buffer[total] = 0;
    return buffer[0..total :0];
}

pub fn formatRegistryIcon(buffer: []u16, exe_path: []const u16) ?[:0]const u16 {
    const suffix = std.unicode.utf8ToUtf16LeStringLiteral("\",0");
    const total = 1 + exe_path.len + suffix.len;
    if (total >= buffer.len) return null;
    buffer[0] = '"';
    @memcpy(buffer[1..][0..exe_path.len], exe_path);
    @memcpy(buffer[1 + exe_path.len ..][0..suffix.len], suffix);
    buffer[total] = 0;
    return buffer[0..total :0];
}

fn findQueryMessage(query: []const u8) []const u8 {
    var pairs = std.mem.splitScalar(u8, query, '&');
    while (pairs.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const key = pair[0..eq];
        const value = pair[eq + 1 ..];
        if (value.len == 0) continue;
        if (std.ascii.eqlIgnoreCase(key, "message") or std.ascii.eqlIgnoreCase(key, "msg") or std.ascii.eqlIgnoreCase(key, "ts")) {
            return value;
        }
    }
    return "";
}

fn decodeField(out: []u8, raw: []const u8) ParseError!usize {
    var len: usize = 0;
    var index: usize = 0;
    while (index < raw.len) {
        var byte = raw[index];
        if (byte == '%') {
            if (index + 2 >= raw.len) return error.InvalidEncoding;
            const hi = hexDigit(raw[index + 1]) orelse return error.InvalidEncoding;
            const lo = hexDigit(raw[index + 2]) orelse return error.InvalidEncoding;
            byte = (@as(u8, hi) << 4) | lo;
            index += 3;
        } else {
            index += 1;
        }
        if (byte < 32 or byte == 127) return error.ControlCharacter;
        if (len >= out.len) return error.TooLong;
        out[len] = byte;
        len += 1;
    }
    if (!std.unicode.utf8ValidateSlice(out[0..len])) return error.InvalidUtf8;
    return len;
}

fn hexDigit(byte: u8) ?u4 {
    return switch (byte) {
        '0'...'9' => @intCast(byte - '0'),
        'a'...'f' => @intCast(byte - 'a' + 10),
        'A'...'F' => @intCast(byte - 'A' + 10),
        else => null,
    };
}

fn normalizeSlackTs(out: []u8, raw: []const u8) ?usize {
    if (raw.len >= 8 and (raw[0] == 'p' or raw[0] == 'P')) {
        const digits = raw[1..];
        var all_digits = true;
        for (digits) |byte| {
            if (!std.ascii.isDigit(byte)) {
                all_digits = false;
                break;
            }
        }
        if (all_digits and digits.len + 1 <= out.len) {
            const split = digits.len - 6;
            @memcpy(out[0..split], digits[0..split]);
            out[split] = '.';
            @memcpy(out[split + 1 ..][0..6], digits[split..]);
            return digits.len + 1;
        }
    }
    if (raw.len > out.len) return null;
    @memcpy(out[0..raw.len], raw);
    return raw.len;
}

fn stripAccountPrefix(value: []const u8, account: []const u8) ?[]const u8 {
    if (account.len == 0 or value.len <= account.len + 1) return null;
    if (std.mem.startsWith(u8, value, account) and value[account.len] == ':') {
        return value[account.len + 1 ..];
    }
    return null;
}

fn splitWhatsAppJid(jid: []const u8) ?struct { account: []const u8, chat: []const u8 } {
    const colon = std.mem.indexOfScalar(u8, jid, ':') orelse return null;
    if (colon == 0 or colon + 1 >= jid.len) return null;
    const prefix = jid[0..colon];
    if (std.mem.indexOfScalar(u8, prefix, '@') != null) return null;
    return .{ .account = prefix, .chat = jid[colon + 1 ..] };
}

fn splitSlackJid(jid: []const u8) ?struct { team: []const u8, channel: []const u8 } {
    if (!std.mem.startsWith(u8, jid, "slack:")) return null;
    const rest = jid["slack:".len..];
    const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    if (colon == 0 or colon + 1 >= rest.len) return null;
    return .{ .team = rest[0..colon], .channel = rest[colon + 1 ..] };
}

fn whatsAppIdMatches(chat_id: []const u8, wanted: []const u8) bool {
    if (std.mem.eql(u8, chat_id, wanted)) return true;
    if (wanted.len == 0 or std.mem.indexOfScalar(u8, wanted, '@') != null) return false;
    for (wanted) |byte| if (!std.ascii.isDigit(byte)) return false;
    const suffix = "@s.whatsapp.net";
    return chat_id.len == wanted.len + suffix.len and
        std.mem.startsWith(u8, chat_id, wanted) and
        std.mem.endsWith(u8, chat_id, suffix);
}

test "parses WhatsApp deep links with account, chat and optional message" {
    const plain = try parse("postbox://whatsapp/business/4915112345678@s.whatsapp.net");
    try std.testing.expectEqual(transport.Provider.whatsapp, plain.provider);
    try std.testing.expectEqualStrings("business", plain.accountSlice());
    try std.testing.expectEqualStrings("4915112345678@s.whatsapp.net", plain.chatSlice());
    try std.testing.expectEqualStrings("", plain.messageSlice());

    const encoded = try parse("POSTBOX://WhatsApp/personal/4915112345678%40s.whatsapp.net/MSG-42/");
    try std.testing.expectEqual(transport.Provider.whatsapp, encoded.provider);
    try std.testing.expectEqualStrings("personal", encoded.accountSlice());
    try std.testing.expectEqualStrings("4915112345678@s.whatsapp.net", encoded.chatSlice());
    try std.testing.expectEqualStrings("MSG-42", encoded.messageSlice());

    const prefixed = try parse("postbox://whatsapp/business/business%3A4915112345678%40s.whatsapp.net?message=WA-9#frag");
    try std.testing.expectEqualStrings("business", prefixed.accountSlice());
    try std.testing.expectEqualStrings("4915112345678@s.whatsapp.net", prefixed.chatSlice());
    try std.testing.expectEqualStrings("WA-9", prefixed.messageSlice());
}

test "parses Slack deep links with team, channel and message timestamp" {
    const dotted = try parse("postbox://slack/T0ALPHA1/C0LAUNCH1/1700000005.000100");
    try std.testing.expectEqual(transport.Provider.slack, dotted.provider);
    try std.testing.expectEqualStrings("T0ALPHA1", dotted.accountSlice());
    try std.testing.expectEqualStrings("C0LAUNCH1", dotted.chatSlice());
    try std.testing.expectEqualStrings("1700000005.000100", dotted.messageSlice());

    const permalink_ts = try parse("postbox://slack/T0ALPHA1/C0LAUNCH1/p1700000005000100");
    try std.testing.expectEqualStrings("1700000005.000100", permalink_ts.messageSlice());

    const query_ts = try parse("postbox://slack/T0ALPHA1/C0LAUNCH1?ts=p1700000005000100");
    try std.testing.expectEqualStrings("1700000005.000100", query_ts.messageSlice());

    const channel_only = try parse("postbox://slack/T0ALPHA1/C0LAUNCH1");
    try std.testing.expectEqualStrings("", channel_only.messageSlice());
}

test "rejects invalid or unsafe postbox deep links" {
    try std.testing.expect(!isPostboxUrl("https://example.com"));
    try std.testing.expect(isPostboxUrl("POSTBOX://slack/T1/C1"));
    try std.testing.expectError(error.InvalidScheme, parse("https://example.com"));
    try std.testing.expectError(error.UnsupportedProvider, parse("postbox://discord/a/b"));
    try std.testing.expectError(error.MissingAccount, parse("postbox://whatsapp"));
    try std.testing.expectError(error.MissingChat, parse("postbox://whatsapp/business"));
    try std.testing.expectError(error.MissingAccount, parse("postbox://whatsapp//123@s.whatsapp.net"));
    try std.testing.expectError(error.TooManySegments, parse("postbox://slack/T1/C1/1.2/extra"));
    try std.testing.expectError(error.InvalidEncoding, parse("postbox://whatsapp/personal/bad%ZZ"));
    try std.testing.expectError(error.ControlCharacter, parse("postbox://whatsapp/personal/bad%0Aid"));
    try std.testing.expectError(error.TooLong, parse("postbox://whatsapp/123456789012345678901234567890123/chat"));
}

test "chat matching separates WhatsApp accounts and Slack workspaces" {
    const wa_business = try parse("postbox://whatsapp/business/15550000001@s.whatsapp.net");
    try std.testing.expect(matchesChat(&wa_business, .whatsapp, "hub", "business", "business:15550000001@s.whatsapp.net"));
    try std.testing.expect(!matchesChat(&wa_business, .whatsapp, "hub", "personal", "personal:15550000001@s.whatsapp.net"));
    try std.testing.expect(!matchesChat(&wa_business, .slack, "business", "business", "business:15550000001@s.whatsapp.net"));

    const wa_digits = try parse("postbox://whatsapp/business/15550000001");
    try std.testing.expect(matchesChat(&wa_digits, .whatsapp, "hub", "business", "business:15550000001@s.whatsapp.net"));
    try std.testing.expect(!matchesChat(&wa_digits, .whatsapp, "hub", "personal", "personal:15550000001@s.whatsapp.net"));

    const wa_direct = try parse("postbox://whatsapp/personal/15550000001@s.whatsapp.net");
    try std.testing.expect(matchesChat(&wa_direct, .whatsapp, "personal", "personal", "15550000001@s.whatsapp.net"));
    try std.testing.expect(!matchesChat(&wa_direct, .whatsapp, "business", "business", "15550000001@s.whatsapp.net"));

    const slack_alpha = try parse("postbox://slack/T0ALPHA1/C0LAUNCH1/1700000005.000100");
    try std.testing.expect(matchesChat(&slack_alpha, .slack, "hub", "T0ALPHA1", "slack:T0ALPHA1:C0LAUNCH1"));
    try std.testing.expect(!matchesChat(&slack_alpha, .slack, "hub", "T0BETA22", "slack:T0BETA22:C0LAUNCH1"));
    try std.testing.expect(matchesChat(&slack_alpha, .slack, "T0ALPHA1", "T0ALPHA1", "C0LAUNCH1"));
    try std.testing.expect(!matchesChat(&slack_alpha, .slack, "T0BETA22", "T0BETA22", "C0LAUNCH1"));
}

test "message matching handles prefixed WhatsApp ids and Slack timestamps" {
    const wa_msg = try parse("postbox://whatsapp/personal/15550000001@s.whatsapp.net/WA-TARGET-MSG");
    try std.testing.expect(matchesMessage(&wa_msg, "WA-TARGET-MSG"));
    try std.testing.expect(matchesMessage(&wa_msg, "personal:WA-TARGET-MSG"));
    try std.testing.expect(!matchesMessage(&wa_msg, "business:WA-TARGET-MSG"));
    try std.testing.expect(!matchesMessage(&wa_msg, "personal:OTHER"));

    const slack_msg = try parse("postbox://slack/T0ALPHA1/C0LAUNCH1/p1700000005000100");
    try std.testing.expect(matchesMessage(&slack_msg, "1700000005.000100"));
    try std.testing.expect(!matchesMessage(&slack_msg, "1700000005.000200"));
}

test "registry command and icon formatting quotes the executable path" {
    const exe = std.unicode.utf8ToUtf16LeStringLiteral("C:\\Program Files\\Postbox\\Messages.exe");
    var cmd_buf: [256]u16 = undefined;
    const cmd = formatRegistryCommand(&cmd_buf, exe).?;
    const expected_cmd = std.unicode.utf8ToUtf16LeStringLiteral("\"C:\\Program Files\\Postbox\\Messages.exe\" \"%1\"");
    try std.testing.expectEqualSlices(u16, expected_cmd, cmd);

    var icon_buf: [256]u16 = undefined;
    const icon = formatRegistryIcon(&icon_buf, exe).?;
    const expected_icon = std.unicode.utf8ToUtf16LeStringLiteral("\"C:\\Program Files\\Postbox\\Messages.exe\",0");
    try std.testing.expectEqualSlices(u16, expected_icon, icon);
}

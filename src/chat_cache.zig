const std = @import("std");

pub const header = "wazig-msg-cache v2\n";
const legacy_header = "wazig-msg-cache v1\n";

pub fn envelope(allocator: std.mem.Allocator, account: []const u8, jid: []const u8, payload: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}\n{s}\n{s}", .{ header, account, jid, payload });
}

pub fn payloadFor(data: []const u8, account: []const u8, jid: []const u8) ?[]const u8 {
    var rest: []const u8 = undefined;
    if (std.mem.startsWith(u8, data, header)) {
        rest = data[header.len..];
        const account_end = std.mem.indexOfScalar(u8, rest, '\n') orelse return null;
        if (!std.mem.eql(u8, rest[0..account_end], account)) return null;
        rest = rest[account_end + 1 ..];
    } else if (std.mem.startsWith(u8, data, legacy_header)) {
        rest = data[legacy_header.len..];
    } else return null;
    const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse return null;
    if (!std.mem.eql(u8, rest[0..line_end], jid)) return null;
    return rest[line_end + 1 ..];
}

test "v2 envelope round trip returns the payload for the matching account and jid" {
    const allocator = std.testing.allocator;
    const stored = try envelope(allocator, "aaaaaaaaaaaaaaaa", "1234@g.us", "{\"data\":[]}");
    defer allocator.free(stored);
    try std.testing.expectEqualStrings("wazig-msg-cache v2\naaaaaaaaaaaaaaaa\n1234@g.us\n{\"data\":[]}", stored);
    const payload = payloadFor(stored, "aaaaaaaaaaaaaaaa", "1234@g.us") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("{\"data\":[]}", payload);
}

test "v2 payloadFor rejects a different account or jid" {
    const allocator = std.testing.allocator;
    const stored = try envelope(allocator, "aaaaaaaaaaaaaaaa", "1234@g.us", "{}");
    defer allocator.free(stored);
    try std.testing.expect(payloadFor(stored, "bbbbbbbbbbbbbbbb", "1234@g.us") == null);
    try std.testing.expect(payloadFor(stored, "aaaaaaaaaaaaaaaa", "other@g.us") == null);
}

test "v1 envelope is still read from its account directory" {
    const stored = "wazig-msg-cache v1\n1234@g.us\n{\"data\":[]}";
    try std.testing.expectEqualStrings("{\"data\":[]}", payloadFor(stored, "aaaaaaaaaaaaaaaa", "1234@g.us").?);
    try std.testing.expect(payloadFor(stored, "aaaaaaaaaaaaaaaa", "other@g.us") == null);
}

test "payloadFor rejects corrupt and empty data" {
    for ([_][]const u8{ "", "garbage", header, header ++ "account\n", legacy_header }) |data| {
        try std.testing.expect(payloadFor(data, "account", "1234@g.us") == null);
    }
}

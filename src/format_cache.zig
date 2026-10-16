//! Finished voice summaries are keyed by account, chat and message, not by
//! the downloaded media path. main.zig owns native file I/O and atomic writes.
const std = @import("std");
pub const format_request = @import("format_request.zig");

pub const max_bytes = 64 * 1024;
const header = "wazig-voice-format v1\n";

pub const Key = struct {
    account: []const u8,
    chat: []const u8,
    message: []const u8,

    pub fn valid(self: Key) bool {
        for ([_][]const u8{ self.account, self.chat, self.message }) |part| {
            if (part.len == 0 or std.mem.indexOfAny(u8, part, "\r\n") != null) return false;
        }
        return true;
    }
};

pub fn filename(allocator: std.mem.Allocator, key: Key) ![]u8 {
    if (!key.valid()) return error.InvalidKey;
    var hash = std.hash.Wyhash.init(0);
    for ([_][]const u8{ key.account, key.chat, key.message }) |part| {
        hash.update(part);
        hash.update("\n");
    }
    return std.fmt.allocPrint(allocator, "{x:0>16}.txt", .{hash.final()});
}

pub fn envelope(allocator: std.mem.Allocator, key: Key, text: []const u8) ![]u8 {
    if (!key.valid()) return error.InvalidKey;
    if (!format_request.looksFormatted(u8, text) or !std.unicode.utf8ValidateSlice(text)) return error.InvalidSummary;
    const data = try std.fmt.allocPrint(allocator, "{s}{s}\n{s}\n{s}\n{s}", .{ header, key.account, key.chat, key.message, text });
    if (data.len > max_bytes) {
        allocator.free(data);
        return error.SummaryTooLong;
    }
    return data;
}

pub fn payloadFor(data: []const u8, key: Key) ?[]const u8 {
    if (!key.valid() or data.len > max_bytes or !std.mem.startsWith(u8, data, header)) return null;
    var rest = data[header.len..];
    for ([_][]const u8{ key.account, key.chat, key.message }) |part| {
        const end = std.mem.indexOfScalar(u8, rest, '\n') orelse return null;
        if (!std.mem.eql(u8, part, rest[0..end])) return null;
        rest = rest[end + 1 ..];
    }
    if (!format_request.looksFormatted(u8, rest) or !std.unicode.utf8ValidateSlice(rest)) return null;
    return rest;
}

/// Called while building messages, before any paint or formatting scheduling.
pub fn restore(allocator: std.mem.Allocator, message: anytype, data: []const u8, key: Key) bool {
    const text = payloadFor(data, key) orelse return false;
    message.transcript.set(allocator, text);
    message.transcript_state = .ready;
    return true;
}

pub const Requests = struct {
    attempts: [512]u64 = [_]u64{0} ** 512,
    count: usize = 0,
    next: usize = 0,

    pub fn claim(self: *Requests, comptime T: type, id: []const u8, transcript: []const T) bool {
        if (id.len == 0 or transcript.len == 0 or format_request.looksFormatted(T, transcript)) return false;
        const hash = std.hash.Wyhash.hash(0, id);
        for (self.attempts[0..self.count]) |attempt| if (attempt == hash) return false;
        self.attempts[self.next % self.attempts.len] = hash;
        self.next += 1;
        self.count = @min(self.next, self.attempts.len);
        return true;
    }
};

const TestMessage = struct {
    const Text = struct {
        bytes: []const u8 = "raw transcript",
        pub fn set(self: *@This(), _: std.mem.Allocator, text: []const u8) void {
            self.bytes = text;
        }
    };
    transcript: Text = .{},
    transcript_state: enum { none, ready } = .ready,
};

const test_key = Key{ .account = "account-a", .chat = "chat-a", .message = "message-a" };
const test_summary = "1. Meeting tomorrow\n---\n# Plans\n- Meet at ten\n- Bring notes";

test "disk cache restores summary on first build after switch and restart with no request" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const name = try filename(allocator, test_key);
    defer allocator.free(name);
    const stored = try envelope(allocator, test_key, test_summary);
    defer allocator.free(stored);
    try dir.dir.writeFile(io, .{ .sub_path = name, .data = stored });
    var requests = Requests{};
    for (0..3) |build| {
        // A restart has no in-memory request history or message state.
        if (build == 2) requests = .{};
        const data = try dir.dir.readFileAlloc(io, name, allocator, .limited(max_bytes));
        defer allocator.free(data);
        var message = TestMessage{};
        try std.testing.expect(restore(allocator, &message, data, test_key));
        try std.testing.expectEqualStrings(test_summary, message.transcript.bytes);
        try std.testing.expect(!requests.claim(u8, test_key.message, message.transcript.bytes));
        try std.testing.expectEqual(@as(usize, 0), requests.count);
    }
}

test "absent cache leaves raw transcript and requests exactly once across builds" {
    var requests = Requests{};
    for (0..3) |build| {
        var message = TestMessage{};
        try std.testing.expect(!restore(std.testing.allocator, &message, "", test_key));
        try std.testing.expectEqualStrings("raw transcript", message.transcript.bytes);
        try std.testing.expectEqual(build == 0, requests.claim(u8, test_key.message, message.transcript.bytes));
    }
    try std.testing.expectEqual(@as(usize, 1), requests.count);
}

test "cache verifies account chat and message even on a filename collision" {
    const allocator = std.testing.allocator;
    const stored = try envelope(allocator, test_key, test_summary);
    defer allocator.free(stored);
    try std.testing.expect(payloadFor(stored, test_key) != null);
    const others = [_]Key{
        .{ .account = "account-b", .chat = test_key.chat, .message = test_key.message },
        .{ .account = test_key.account, .chat = "chat-b", .message = test_key.message },
        .{ .account = test_key.account, .chat = test_key.chat, .message = "message-b" },
    };
    const name = try filename(allocator, test_key);
    defer allocator.free(name);
    for (others) |other| {
        try std.testing.expect(payloadFor(stored, other) == null);
        const other_name = try filename(allocator, other);
        defer allocator.free(other_name);
        try std.testing.expect(!std.mem.eql(u8, name, other_name));
    }
    try std.testing.expect(payloadFor("wazig-voice-format v1\naccount-a\nchat-a\nmessage-a\nraw", test_key) == null);
    try std.testing.expect(payloadFor(header, test_key) == null);
    try std.testing.expectError(error.InvalidSummary, envelope(allocator, test_key, "raw"));
    try std.testing.expectError(error.InvalidSummary, envelope(allocator, test_key, "1. \xff"));
}

test "summaries larger than the old 4 KB limit survive intact" {
    const allocator = std.testing.allocator;
    const summary = try allocator.alloc(u8, 16 * 1024);
    defer allocator.free(summary);
    @memset(summary, 'a');
    @memcpy(summary[0..3], "1. ");
    const stored = try envelope(allocator, test_key, summary);
    defer allocator.free(stored);
    try std.testing.expectEqualStrings(summary, payloadFor(stored, test_key).?);
    const wide = try std.unicode.utf8ToUtf16LeAlloc(allocator, summary);
    defer allocator.free(wide);
    var requests = Requests{};
    try std.testing.expect(!requests.claim(u16, test_key.message, wide));
}

const std = @import("std");

pub const Set = struct {
    hashes: [2048]u64 = [_]u64{0} ** 2048,
    count: usize = 0,

    pub fn wasPlayed(self: *const Set, id: []const u8) bool {
        if (id.len == 0) return false;
        return self.wasPlayedRaw(std.hash.Wyhash.hash(0, id));
    }

    pub fn wasPlayedRaw(self: *const Set, hash: u64) bool {
        for (self.hashes[0..@min(self.count, self.hashes.len)]) |entry| {
            if (entry == hash) return true;
        }
        return false;
    }

    pub fn load(self: *Set, contents: []const u8) void {
        var lines = std.mem.tokenizeAny(u8, contents, "\r\n");
        while (lines.next()) |line| {
            if (line.len != 16) continue;
            const hash = std.fmt.parseInt(u64, line, 16) catch continue;
            self.hashes[self.count % self.hashes.len] = hash;
            self.count += 1;
        }
    }

    pub fn mark(self: *Set, id: []const u8, line_buffer: []u8) ?[]const u8 {
        if (id.len == 0) return null;
        return self.markRaw(std.hash.Wyhash.hash(0, id), line_buffer);
    }

    pub fn markRaw(self: *Set, hash: u64, line_buffer: []u8) ?[]const u8 {
        if (self.wasPlayedRaw(hash)) return null;
        self.hashes[self.count % self.hashes.len] = hash;
        self.count += 1;
        return std.fmt.bufPrint(line_buffer, "{x:0>16}\n", .{hash}) catch null;
    }

    pub fn pairKey(first: []const u8, second: []const u8) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(first);
        hasher.update("\x00");
        hasher.update(second);
        return hasher.final();
    }
};

test "mark and recall played ids, ignore repeats and empty ids" {
    var set: Set = .{};
    var buffer: [40]u8 = undefined;
    const line = set.mark("abc", &buffer).?;
    try std.testing.expect(set.wasPlayed("abc"));
    try std.testing.expect(!set.wasPlayed("xyz"));
    try std.testing.expect(set.mark("abc", &buffer) == null);
    try std.testing.expect(set.mark("", &buffer) == null);
    var reloaded: Set = .{};
    reloaded.load(line);
    try std.testing.expect(reloaded.wasPlayed("abc"));
}

test "markRaw and pairKey keep jids and ids separate" {
    var set: Set = .{};
    var buffer: [40]u8 = undefined;
    const key = Set.pairKey("chat1", "msg1");
    try std.testing.expect(set.markRaw(key, &buffer) != null);
    try std.testing.expect(set.markRaw(key, &buffer) == null);
    try std.testing.expect(set.wasPlayedRaw(key));
    try std.testing.expect(set.markRaw(Set.pairKey("chat2", "msg1"), &buffer) != null);
    try std.testing.expect(Set.pairKey("chat1", "msg1") != Set.pairKey("chat1", "msg2"));
}

test "load skips malformed and truncated lines" {
    var set: Set = .{};
    set.load("deadbeefdeadbeef\nzzzz\nbeef\nbeef00000000000\n");
    try std.testing.expectEqual(@as(usize, 1), set.count);
    try std.testing.expect(set.wasPlayedRaw(0xdeadbeefdeadbeef));
    try std.testing.expect(!set.wasPlayedRaw(0xbeef));
}

test "load wraps so the newest entries survive the ring capacity" {
    var set: Set = .{ .count = 2048 };
    set.hashes[0] = 0x11;
    set.load("0000000000000022\n0000000000000033\n");
    try std.testing.expectEqual(@as(usize, 2050), set.count);
    try std.testing.expect(!set.wasPlayedRaw(0x11));
    try std.testing.expect(set.wasPlayedRaw(0x22));
    try std.testing.expect(set.wasPlayedRaw(0x33));
}
// planted comment to prove the no-comments check fails

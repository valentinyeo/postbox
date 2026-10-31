//! Slack channels the user hid from the sidebar. Hiding is local to Wazig:
//! it never archives or leaves the channel in Slack. The set is stored as
//! newline-separated channel ids under Software\Messages\HiddenSlackChats.
const std = @import("std");

pub const max_hidden = 256;
pub const max_id = 31;

const Id = struct {
    buf: [max_id]u8 = undefined,
    len: u8 = 0,

    fn slice(self: *const Id) []const u8 {
        return self.buf[0..self.len];
    }
};

/// A Slack conversation id: letters and digits only, so a stored line can
/// never smuggle a separator or anything else into the list.
pub fn isValidId(id: []const u8) bool {
    if (id.len == 0 or id.len > max_id) return false;
    for (id) |char| if (!std.ascii.isAlphanumeric(char)) return false;
    return true;
}

pub const HiddenSet = struct {
    ids: [max_hidden]Id = [_]Id{.{}} ** max_hidden,
    count: usize = 0,

    pub fn contains(self: *const HiddenSet, id: []const u8) bool {
        for (self.ids[0..self.count]) |*entry| {
            if (std.mem.eql(u8, entry.slice(), id)) return true;
        }
        return false;
    }

    /// False when the id is invalid, already hidden, or the set is full.
    pub fn add(self: *HiddenSet, id: []const u8) bool {
        if (!isValidId(id) or self.count >= max_hidden or self.contains(id)) return false;
        const entry = &self.ids[self.count];
        @memcpy(entry.buf[0..id.len], id);
        entry.len = @intCast(id.len);
        self.count += 1;
        return true;
    }

    /// False when the id was not hidden. Keeps the order of the others.
    pub fn remove(self: *HiddenSet, id: []const u8) bool {
        for (self.ids[0..self.count], 0..) |*entry, index| {
            if (!std.mem.eql(u8, entry.slice(), id)) continue;
            var move = index;
            while (move + 1 < self.count) : (move += 1) self.ids[move] = self.ids[move + 1];
            self.count -= 1;
            return true;
        }
        return false;
    }

    pub fn at(self: *const HiddenSet, index: usize) []const u8 {
        return self.ids[index].slice();
    }

    /// Load from the stored text. Blank, invalid and duplicate lines are
    /// skipped, so a damaged value degrades to fewer hidden chats, never to
    /// a failed start.
    pub fn parse(text: []const u8) HiddenSet {
        var set = HiddenSet{};
        var lines = std.mem.tokenizeAny(u8, text, "\r\n");
        while (lines.next()) |line| _ = set.add(std.mem.trim(u8, line, " \t"));
        return set;
    }

    /// The stored text: ids joined by newlines. Null when `buffer` is too
    /// small, so a caller never saves a cut list.
    pub fn serialize(self: *const HiddenSet, buffer: []u8) ?[]const u8 {
        var len: usize = 0;
        for (self.ids[0..self.count], 0..) |*entry, index| {
            const needed = entry.len + @intFromBool(index > 0);
            if (len + needed > buffer.len) return null;
            if (index > 0) {
                buffer[len] = '\n';
                len += 1;
            }
            @memcpy(buffer[len..][0..entry.len], entry.slice());
            len += entry.len;
        }
        return buffer[0..len];
    }
};

test "hidden ids survive a save and load round trip in order" {
    var set = HiddenSet{};
    try std.testing.expect(set.add("C42FTMM5Z"));
    try std.testing.expect(set.add("D080X4NQG2K"));
    try std.testing.expect(set.add("C087SJEUHHR"));
    var buffer: [128]u8 = undefined;
    const text = set.serialize(&buffer).?;
    try std.testing.expectEqualStrings("C42FTMM5Z\nD080X4NQG2K\nC087SJEUHHR", text);
    const loaded = HiddenSet.parse(text);
    try std.testing.expectEqual(@as(usize, 3), loaded.count);
    try std.testing.expect(loaded.contains("D080X4NQG2K"));
    try std.testing.expectEqualStrings("C087SJEUHHR", loaded.at(2));
}

test "a damaged stored value loads the valid ids and drops the rest" {
    // Windows line endings, blanks, a duplicate, a separator smuggled into
    // an id, and one id over the length cap.
    const loaded = HiddenSet.parse("C1\r\n\r\n  C2 \nC1\nC3;rm\n" ++ "C" ** 40 ++ "\n");
    try std.testing.expectEqual(@as(usize, 2), loaded.count);
    try std.testing.expect(loaded.contains("C1"));
    try std.testing.expect(loaded.contains("C2"));
    try std.testing.expect(!loaded.contains("C3;rm"));
    try std.testing.expectEqual(@as(usize, 0), HiddenSet.parse("").count);
}

test "unhide removes only that id and keeps the rest in order" {
    var set = HiddenSet.parse("C1\nC2\nC3");
    try std.testing.expect(set.remove("C2"));
    try std.testing.expect(!set.remove("C2"));
    try std.testing.expectEqual(@as(usize, 2), set.count);
    try std.testing.expectEqualStrings("C1", set.at(0));
    try std.testing.expectEqualStrings("C3", set.at(1));
}

test "hiding the same channel twice keeps one entry; a full set refuses more" {
    var set = HiddenSet{};
    try std.testing.expect(set.add("C1"));
    try std.testing.expect(!set.add("C1"));
    try std.testing.expect(!set.add(""));
    var index: usize = 1;
    var name: [16]u8 = undefined;
    while (index < max_hidden) : (index += 1) try std.testing.expect(set.add(try std.fmt.bufPrint(&name, "C{d}", .{index})));
    try std.testing.expect(!set.add("CFULL"));
}

test "serialize refuses a buffer that would cut the list" {
    const set = HiddenSet.parse("C1\nC2");
    var small: [4]u8 = undefined;
    try std.testing.expect(set.serialize(&small) == null);
    var exact: [5]u8 = undefined;
    try std.testing.expectEqualStrings("C1\nC2", set.serialize(&exact).?);
}

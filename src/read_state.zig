const std = @import("std");
const media_age = @import("media_age.zig");

const Entry = struct {
    read: i64 = 0,
    incoming: i64 = 0,
    checked: i64 = 0,
};

pub const State = struct {
    entries: std.StringHashMapUnmanaged(Entry) = .empty,
    dirty: bool = false,
    allow_opaque: bool = false,

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        var keys = self.entries.keyIterator();
        while (keys.next()) |stored_key| allocator.free(stored_key.*);
        self.entries.deinit(allocator);
    }

    fn key(self: *const State, buffer: []u8, account: []const u8, jid: []const u8) ?[]const u8 {
        if (account.len != 16 or jid.len == 0 or jid.len > 191) return null;
        for (account) |c| if (!std.ascii.isHex(c)) return null;
        if (self.allow_opaque) {
            if (!std.unicode.utf8ValidateSlice(jid)) return null;
            for (jid) |c| if (c < 32 or c == 127) return null;
        } else {
            for (jid) |c| if (c <= ' ' or c == '/') return null;
            if (std.mem.indexOfScalar(u8, jid, '@') == null) return null;
        }
        return std.fmt.bufPrint(buffer, "{s}/{s}", .{ account, jid }) catch null;
    }

    fn get(self: *const State, account: []const u8, jid: []const u8) Entry {
        var buffer: [208]u8 = undefined;
        const k = self.key(&buffer, account, jid) orelse return .{};
        return self.entries.get(k) orelse .{};
    }

    fn entry(self: *State, allocator: std.mem.Allocator, account: []const u8, jid: []const u8) ?*Entry {
        var buffer: [208]u8 = undefined;
        const k = self.key(&buffer, account, jid) orelse return null;
        if (self.entries.getPtr(k)) |value| return value;
        const owned = allocator.dupe(u8, k) catch return null;
        const result = self.entries.getOrPut(allocator, owned) catch {
            allocator.free(owned);
            return null;
        };
        result.value_ptr.* = .{};
        return result.value_ptr;
    }

    pub fn markRead(self: *State, allocator: std.mem.Allocator, account: []const u8, jid: []const u8, timestamp: i64) void {
        if (timestamp <= 0) return;
        const value = self.entry(allocator, account, jid) orelse return;
        if (timestamp <= value.read) return;
        value.read = timestamp;
        self.dirty = true;
    }

    pub fn observeChat(self: *State, allocator: std.mem.Allocator, account: []const u8, jid: []const u8, timestamp: i64, reported_unread: bool, fresh: bool) void {
        if (fresh and !reported_unread) self.markRead(allocator, account, jid, timestamp);
    }

    pub fn isUnread(self: *const State, account: []const u8, jid: []const u8) bool {
        const value = self.get(account, jid);
        return value.incoming > value.read;
    }

    pub fn needsProbe(self: *const State, account: []const u8, jid: []const u8, timestamp: i64, reported_unread: bool) bool {
        var buffer: [208]u8 = undefined;
        if (self.key(&buffer, account, jid) == null) return false;
        const value = self.get(account, jid);
        return reported_unread and timestamp > value.read and timestamp > value.checked;
    }

    pub fn acceptProbe(self: *State, allocator: std.mem.Allocator, account: []const u8, jid: []const u8, row_timestamp: i64, raw: []const u8) bool {
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch return false;
        defer parsed.deinit();
        const root = switch (parsed.value) {
            .object => |object| object,
            else => return false,
        };
        const data = switch (root.get("data") orelse return false) {
            .object => |object| object,
            else => return false,
        };
        const messages = switch (data.get("messages") orelse return false) {
            .array => |array| array.items,
            else => return false,
        };
        var incoming: i64 = 0;
        for (messages) |message| {
            const object = switch (message) {
                .object => |value| value,
                else => return false,
            };
            const from_me = switch (object.get("FromMe") orelse return false) {
                .bool => |value| value,
                else => return false,
            };
            if (from_me) continue;
            const raw_timestamp = switch (object.get("Timestamp") orelse return false) {
                .string => |value| value,
                else => return false,
            };
            const timestamp = media_age.unixSeconds(raw_timestamp) orelse return false;
            incoming = @max(incoming, timestamp);
        }
        const value = self.entry(allocator, account, jid) orelse return false;
        value.incoming = @max(value.incoming, incoming);
        value.checked = @max(value.checked, row_timestamp);
        return true;
    }

    pub fn load(self: *State, allocator: std.mem.Allocator, contents: []const u8) void {
        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            const split = std.mem.lastIndexOfScalar(u8, line, ' ') orelse continue;
            const k = line[0..split];
            if (k.len < 18 or k[16] != '/') continue;
            const timestamp = std.fmt.parseInt(i64, line[split + 1 ..], 10) catch continue;
            self.markRead(allocator, k[0..16], k[17..], timestamp);
        }
        self.dirty = false;
    }

    pub fn encode(self: *const State, allocator: std.mem.Allocator) ![]u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(allocator);
        var entries = self.entries.iterator();
        while (entries.next()) |item| {
            if (item.value_ptr.read > 0) try result.print(allocator, "{s} {d}\n", .{ item.key_ptr.*, item.value_ptr.read });
        }
        return result.toOwnedSlice(allocator);
    }
};

const test_account = "0123456789abcdef";
const test_jid = "test@g.us";
const incoming_old = "{\"data\":{\"messages\":[{\"Timestamp\":\"2026-10-16T12:00:00Z\",\"FromMe\":false}]}}";
const incoming_new = "{\"data\":{\"messages\":[{\"Timestamp\":\"2026-10-16T12:00:01Z\",\"FromMe\":false}]}}";
const read_time = media_age.unixSeconds("2026-10-16T12:00:00Z").?;

test "read in Messages survives restart and stale unread count then new incoming becomes unread" {
    const allocator = std.testing.allocator;
    var state: State = .{};
    defer state.deinit(allocator);
    state.markRead(allocator, test_account, test_jid, read_time);
    const disk = try state.encode(allocator);
    defer allocator.free(disk);
    var reloaded: State = .{};
    defer reloaded.deinit(allocator);
    reloaded.load(allocator, disk);
    reloaded.observeChat(allocator, test_account, test_jid, read_time, true, true);
    try std.testing.expect(!reloaded.isUnread(test_account, test_jid));
    try std.testing.expect(!reloaded.needsProbe(test_account, test_jid, read_time, true));
    try std.testing.expect(reloaded.needsProbe(test_account, test_jid, read_time + 1, true));
    try std.testing.expect(reloaded.acceptProbe(allocator, test_account, test_jid, read_time + 1, incoming_new));
    try std.testing.expect(reloaded.isUnread(test_account, test_jid));
    reloaded.observeChat(allocator, test_account, test_jid, read_time, false, false);
    reloaded.observeChat(allocator, test_account, test_jid, read_time, false, true);
    try std.testing.expect(reloaded.isUnread(test_account, test_jid));
}

test "own outgoing advances the row but never resurrects an old unread count" {
    const allocator = std.testing.allocator;
    var state: State = .{};
    defer state.deinit(allocator);
    state.markRead(allocator, test_account, test_jid, read_time);
    try std.testing.expect(state.needsProbe(test_account, test_jid, read_time + 10, true));
    try std.testing.expect(state.acceptProbe(allocator, test_account, test_jid, read_time + 10, incoming_old));
    try std.testing.expect(!state.isUnread(test_account, test_jid));
    try std.testing.expect(!state.needsProbe(test_account, test_jid, read_time + 10, true));
    try std.testing.expect(state.acceptProbe(allocator, test_account, test_jid, read_time + 20, "{\"data\":{\"messages\":[{\"Timestamp\":\"2026-10-16T12:00:20Z\",\"FromMe\":true}]}}"));
    try std.testing.expect(!state.isUnread(test_account, test_jid));
}

test "phone read clears a dot and survives a stale resync or archive reload" {
    const allocator = std.testing.allocator;
    var state: State = .{};
    defer state.deinit(allocator);
    try std.testing.expect(state.acceptProbe(allocator, test_account, test_jid, read_time, incoming_old));
    try std.testing.expect(state.isUnread(test_account, test_jid));
    state.observeChat(allocator, test_account, test_jid, read_time, false, false);
    try std.testing.expect(state.isUnread(test_account, test_jid));
    state.observeChat(allocator, test_account, test_jid, read_time, false, true);
    try std.testing.expect(!state.isUnread(test_account, test_jid));
    state.observeChat(allocator, test_account, test_jid, read_time, true, true);
    try std.testing.expect(!state.isUnread(test_account, test_jid));
    try std.testing.expect(state.dirty);
}

test "watermarks are monotonic and account scoped, malformed persistence and probes are rejected" {
    const allocator = std.testing.allocator;
    var state: State = .{};
    defer state.deinit(allocator);
    state.load(allocator, "junk\n0123456789abcdef/test@g.us 100\n0123456789abcdef/test@g.us 50\n0123456789abcdef/test@g.us -2\n0123456789abcdef/bad 200\n");
    try std.testing.expectEqual(@as(i64, 100), state.get(test_account, test_jid).read);
    try std.testing.expectEqual(@as(i64, 0), state.get("fedcba9876543210", test_jid).read);
    try std.testing.expect(!state.acceptProbe(allocator, test_account, test_jid, read_time, "{}"));
    try std.testing.expect(!state.acceptProbe(allocator, test_account, test_jid, read_time, "{\"data\":{\"messages\":[{\"Timestamp\":\"bad\",\"FromMe\":false}]}}"));
    try std.testing.expect(state.needsProbe(test_account, test_jid, read_time, true));
    try std.testing.expect(!state.needsProbe("", test_jid, read_time, true));
    try std.testing.expect(state.acceptProbe(allocator, test_account, test_jid, read_time, "{\"data\":{\"messages\":[]}}"));
    try std.testing.expect(!state.needsProbe(test_account, test_jid, read_time, true));
}

test "IGSH-531 opaque hub read state survives restart with spaces and slashes" {
    const allocator = std.testing.allocator;
    const handle = "fixture/account:room +/";
    var state = State{ .allow_opaque = true };
    defer state.deinit(allocator);
    try std.testing.expect(state.needsProbe(test_account, handle, read_time, true));
    try std.testing.expect(state.acceptProbe(allocator, test_account, handle, read_time, incoming_old));
    try std.testing.expect(state.isUnread(test_account, handle));
    state.markRead(allocator, test_account, handle, read_time);
    const encoded = try state.encode(allocator);
    defer allocator.free(encoded);
    var restored = State{ .allow_opaque = true };
    defer restored.deinit(allocator);
    restored.load(allocator, encoded);
    try std.testing.expectEqual(read_time, restored.get(test_account, handle).read);
    try std.testing.expect(!restored.needsProbe(test_account, handle, read_time, true));
    var direct = State{};
    defer direct.deinit(allocator);
    direct.load(allocator, encoded);
    try std.testing.expectEqual(@as(i64, 0), direct.get(test_account, handle).read);
}

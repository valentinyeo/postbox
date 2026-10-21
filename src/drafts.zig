const std = @import("std");
const chat_key = @import("chat_key.zig");
const theme = @import("theme.zig");

pub const max_text = 64 * 1024;
pub const max_drafts = 500;
pub const max_file = max_drafts * (max_text * 6 + 1024);

pub const Identity = struct {
    provider: @import("transport.zig").Provider = .whatsapp,
    account: [32]u8 = @splat(0),
    account_len: usize = 0,
    id: [191]u8 = @splat(0),
    id_len: usize = 0,

    pub fn init(value: chat_key.Key) Identity {
        var result = Identity{ .provider = value.provider, .account_len = value.account.len, .id_len = value.id.len };
        @memcpy(result.account[0..value.account.len], value.account);
        @memcpy(result.id[0..value.id.len], value.id);
        return result;
    }

    pub fn key(self: *const Identity) chat_key.Key {
        return .{ .provider = self.provider, .account = self.account[0..self.account_len], .id = self.id[0..self.id_len] };
    }
};

const Entry = struct { identity: Identity, text: []u8 };
const Wire = struct { provider: @import("transport.zig").Provider, account: []const u8, id: []const u8, text: []const u8 };

pub const Store = struct {
    entries: std.ArrayList(Entry) = .empty,
    open: ?Identity = null,
    dirty: bool = false,

    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        for (self.entries.items) |entry| allocator.free(entry.text);
        self.entries.deinit(allocator);
        self.* = .{};
    }

    pub fn get(self: *const Store, key: chat_key.Key) []const u8 {
        for (self.entries.items) |*entry| if (chat_key.Key.eql(entry.identity.key(), key)) return entry.text;
        return "";
    }

    pub fn save(self: *Store, allocator: std.mem.Allocator, key: chat_key.Key, text: []const u8) !void {
        if (key.id.len == 0 or key.id.len > 191 or key.account.len == 0 or key.account.len > 32) return error.InvalidIdentity;
        if (text.len > max_text or !std.unicode.utf8ValidateSlice(text) or std.mem.indexOfScalar(u8, text, 0) != null) return error.DraftTooLong;
        const empty = text.len == 0;
        for (self.entries.items, 0..) |*entry, index| {
            if (!chat_key.Key.eql(entry.identity.key(), key)) continue;
            if (!empty and std.mem.eql(u8, entry.text, text)) return;
            if (empty) {
                allocator.free(entry.text);
                _ = self.entries.orderedRemove(index);
            } else {
                const copy = try allocator.dupe(u8, text);
                allocator.free(entry.text);
                entry.text = copy;
            }
            self.dirty = true;
            return;
        }
        if (empty) return;
        if (self.entries.items.len >= max_drafts) return error.TooManyDrafts;
        const copy = try allocator.dupe(u8, text);
        errdefer allocator.free(copy);
        try self.entries.append(allocator, .{ .identity = Identity.init(key), .text = copy });
        self.dirty = true;
    }

    pub fn isOpen(self: *const Store, key: chat_key.Key) bool {
        return if (self.open) |*open| chat_key.Key.eql(open.key(), key) else false;
    }

    pub fn composerMatches(self: *const Store, composer: []const u8) bool {
        const expected = if (self.open) |*open| self.get(open.key()) else "";
        return std.mem.eql(u8, expected, composer);
    }

    pub fn switchTo(self: *Store, allocator: std.mem.Allocator, next: ?chat_key.Key, composer: []const u8) ![]const u8 {
        if (next) |key| if (key.id.len == 0 or key.id.len > 191 or key.account.len == 0 or key.account.len > 32) return error.InvalidIdentity;
        if (self.open) |*old| try self.save(allocator, old.key(), composer);
        self.open = if (next) |key| Identity.init(key) else null;
        return if (next) |key| self.get(key) else "";
    }

    pub fn transcript(self: *Store, allocator: std.mem.Allocator, origin: chat_key.Key, composer: []const u8, text: []const u8) !?[]const u8 {
        return self.append(allocator, origin, composer, text, true);
    }

    pub fn append(self: *Store, allocator: std.mem.Allocator, origin: chat_key.Key, composer: []const u8, text: []const u8, separate: bool) !?[]const u8 {
        const is_open = self.isOpen(origin);
        const previous = if (is_open) composer else self.get(origin);
        const combined = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ previous, if (separate and previous.len > 0) " " else "", text });
        defer allocator.free(combined);
        try self.save(allocator, origin, combined);
        return if (is_open) self.get(origin) else null;
    }

    pub fn encode(self: *const Store, allocator: std.mem.Allocator) ![]u8 {
        var records: std.ArrayList(Wire) = .empty;
        defer records.deinit(allocator);
        for (self.entries.items) |*entry| {
            const key = entry.identity.key();
            try records.append(allocator, .{ .provider = key.provider, .account = key.account, .id = key.id, .text = entry.text });
        }
        return std.json.Stringify.valueAlloc(allocator, records.items, .{});
    }

    pub fn load(self: *Store, allocator: std.mem.Allocator, bytes: []const u8) void {
        self.deinit(allocator);
        if (bytes.len > max_file) return;
        const parsed = std.json.parseFromSlice([]Wire, allocator, bytes, .{ .allocate = .alloc_always }) catch return;
        defer parsed.deinit();
        if (parsed.value.len > max_drafts) return;
        for (parsed.value) |record| {
            const key = chat_key.Key{ .provider = record.provider, .account = record.account, .id = record.id };
            if (self.get(key).len > 0) {
                self.deinit(allocator);
                return;
            }
            self.save(allocator, key, record.text) catch {
                self.deinit(allocator);
                return;
            };
        }
        self.dirty = false;
    }
};

pub fn label(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var end = @min(text.len, 160);
    while (end > 0 and !std.unicode.utf8ValidateSlice(text[0..end])) end -= 1;
    const result = try std.fmt.allocPrint(allocator, "DRAFT: {s}", .{text[0..end]});
    for (result) |*byte| if (byte.* == '\r' or byte.* == '\n' or byte.* == '\t') {
        byte.* = ' ';
    };
    return result;
}

pub fn labelColor(palette: theme.Palette, background: u32) u32 {
    return if (theme.contrastRatio(palette.primary, background) >= 4.5) palette.primary else palette.on_surface;
}

const first = chat_key.Key{ .provider = .whatsapp, .account = "account-a", .id = "chat" };
const second = chat_key.Key{ .provider = .telegram, .account = "account-a", .id = "chat" };

test "IGSH-497 restore drafts by stable provider account and chat id" {
    const a = std.testing.allocator;
    var store = Store{};
    defer store.deinit(a);
    try std.testing.expectEqualStrings("", try store.switchTo(a, first, ""));
    try std.testing.expectEqualStrings("", try store.switchTo(a, second, "unsent one"));
    try std.testing.expectEqualStrings("unsent one", try store.switchTo(a, first, "unsent two"));
    try std.testing.expectEqualStrings("unsent two", store.get(second));
    const other = chat_key.Key{ .provider = first.provider, .account = "account-b", .id = first.id };
    try std.testing.expectEqualStrings("", store.get(other));
    _ = try store.switchTo(a, second, " \t\r\n");
    try std.testing.expectEqualStrings(" \t\r\n", store.get(first));
    try store.save(a, first, "");
    try std.testing.expectEqualStrings("", store.get(first));
    try store.save(a, second, "");
    try std.testing.expectEqualStrings("", store.get(second));
}

test "IGSH-497 dictation after switch belongs to original draft not open composer" {
    const a = std.testing.allocator;
    var store = Store{};
    defer store.deinit(a);
    _ = try store.switchTo(a, first, "");
    const origin = Identity.init(first);
    _ = try store.switchTo(a, second, "before");
    try std.testing.expect((try store.transcript(a, origin.key(), "other composer", "spoken")) == null);
    try std.testing.expectEqualStrings("before spoken", store.get(first));
    try std.testing.expectEqualStrings("", store.get(second));
    try std.testing.expectEqualStrings("before spoken", try store.switchTo(a, first, "other composer"));
    try std.testing.expectEqualStrings("edited final", (try store.transcript(a, origin.key(), "edited", "final")).?);
    try std.testing.expectEqualStrings("other composer", store.get(second));
}

test "IGSH-497 persist round trip corrupt file tolerance and limits" {
    const a = std.testing.allocator;
    var store = Store{};
    defer store.deinit(a);
    try store.save(a, first, "line one\nemoji 📝");
    try store.save(a, second, "another");
    const bytes = try store.encode(a);
    defer a.free(bytes);
    var loaded = Store{};
    defer loaded.deinit(a);
    loaded.load(a, bytes);
    try std.testing.expectEqualStrings(store.get(first), loaded.get(first));
    try std.testing.expectEqualStrings(store.get(second), loaded.get(second));
    try std.testing.expect(!loaded.dirty);
    loaded.load(a, "[{broken");
    try std.testing.expectEqual(@as(usize, 0), loaded.entries.items.len);
    loaded.load(a, "[{\"provider\":\"unknown\"}]");
    try std.testing.expectEqual(@as(usize, 0), loaded.entries.items.len);
    const huge = try a.alloc(u8, max_text + 1);
    defer a.free(huge);
    @memset(huge, 'x');
    try std.testing.expectError(error.DraftTooLong, store.save(a, first, huge));
    var id: [32]u8 = undefined;
    for (0..max_drafts) |i| try loaded.save(a, .{ .provider = .whatsapp, .account = "known", .id = try std.fmt.bufPrint(&id, "{d}", .{i}) }, "draft");
    try std.testing.expectError(error.TooManyDrafts, loaded.save(a, second, "overflow"));
}

test "IGSH-497 draft label text and colour contrast on every row theme" {
    const text = try label(std.testing.allocator, "hello\nworld");
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("DRAFT: hello world", text);
    for ([_]theme.Palette{ theme.green, theme.amoled }) |palette| {
        for ([_]u32{ palette.surface_container_low, palette.surface_container_highest, palette.primary_container }) |background| {
            try std.testing.expect(theme.contrastRatio(labelColor(palette, background), background) >= 4.5);
        }
    }
}

const Script = struct {
    store: Store = .{},
    composer: std.ArrayList(u8) = .empty,

    fn deinit(self: *Script) void {
        self.store.deinit(std.testing.allocator);
        self.composer.deinit(std.testing.allocator);
    }

    fn show(self: *Script, text: []const u8) !void {
        const copy = try std.testing.allocator.dupe(u8, text);
        defer std.testing.allocator.free(copy);
        self.composer.clearRetainingCapacity();
        try self.composer.appendSlice(std.testing.allocator, copy);
        try std.testing.expect(self.store.composerMatches(self.composer.items));
    }

    fn select(self: *Script, key: chat_key.Key) !void {
        try self.show(try self.store.switchTo(std.testing.allocator, key, self.composer.items));
    }

    fn input(self: *Script, text: []const u8) !void {
        const open = &self.store.open.?;
        const result = (try self.store.append(std.testing.allocator, open.key(), self.composer.items, text, false)).?;
        try self.show(result);
    }

    fn spoken(self: *Script, origin: chat_key.Key, text: []const u8) !void {
        if (try self.store.transcript(std.testing.allocator, origin, self.composer.items, text)) |result| try self.show(result);
        try std.testing.expect(self.store.composerMatches(self.composer.items));
    }

    fn send(self: *Script) !void {
        try self.store.save(std.testing.allocator, self.store.open.?.key(), "");
        try self.show("");
    }

    fn restart(self: *Script) !void {
        const open = self.store.open.?;
        const bytes = try self.store.encode(std.testing.allocator);
        defer std.testing.allocator.free(bytes);
        self.store.load(std.testing.allocator, bytes);
        self.composer.clearRetainingCapacity();
        try self.select(open.key());
    }
};

test "IGSH-497 paste into A then switch to B never carries clipboard or emoji text" {
    var script = Script{};
    defer script.deinit();
    try script.select(first);
    try script.input("clipboard transcript 📝");
    try script.select(second);
    try std.testing.expectEqualStrings("", script.composer.items);
    try std.testing.expectEqualStrings("clipboard transcript 📝", script.store.get(first));
    try std.testing.expect((try script.store.append(std.testing.allocator, first, script.composer.items, "🙂", false)) == null);
    try std.testing.expect(script.store.composerMatches(script.composer.items));
    try script.select(first);
    try std.testing.expectEqualStrings("clipboard transcript 📝🙂", script.composer.items);
    try script.send();
    try script.restart();
    try std.testing.expectEqualStrings("", script.composer.items);
}

test "IGSH-497 workspace switches and restart isolate equal raw ids and separate accounts" {
    var script = Script{};
    defer script.deinit();
    const keys = [_]chat_key.Key{
        first,                                                             second,
        .{ .provider = .slack, .account = first.account, .id = first.id }, .{ .provider = first.provider, .account = "account-b", .id = first.id },
        .{ .provider = .slack, .account = "workspace-b", .id = first.id },
    };
    const texts = [_][]const u8{ "whatsapp", "telegram", "slack", "second account", "second workspace" };
    for (keys, texts) |key, text| {
        try script.select(key);
        try std.testing.expectEqualStrings("", script.composer.items);
        try script.input(text);
    }
    try script.restart();
    for (keys, texts) |key, text| {
        try script.select(key);
        try std.testing.expectEqualStrings(text, script.composer.items);
    }
}

test "IGSH-497 never leaks through 10000 fixed-seed scripted input async send workspace and restart events" {
    var script = Script{};
    defer script.deinit();
    const a = std.testing.allocator;
    const keys = [_]chat_key.Key{
        first,                                                             second,
        .{ .provider = .whatsapp, .account = "account-a", .id = "other" }, .{ .provider = .slack, .account = "workspace-a", .id = "chat" },
        .{ .provider = .slack, .account = "workspace-b", .id = "chat" },
    };
    const tokens = [_][]const u8{ "A", "B", "C", "D", "E" };
    var expected: [keys.len]std.ArrayList(u8) = @splat(.empty);
    defer for (&expected) |*text| text.deinit(a);
    var selected: usize = 0;
    var origin: usize = 0;
    var counts: [9]usize = @splat(0);
    var random = std.Random.DefaultPrng.init(497);
    try script.select(keys[selected]);
    for (0..10000) |_| {
        const event = random.random().uintLessThan(usize, counts.len);
        counts[event] += 1;
        switch (event) {
            0, 7 => {
                selected = random.random().uintLessThan(usize, keys.len);
                try script.select(keys[selected]);
            },
            1, 2 => {
                try script.input(tokens[selected]);
                try expected[selected].appendSlice(a, tokens[selected]);
            },
            3 => origin = selected,
            4, 5 => {
                try script.spoken(keys[origin], tokens[origin]);
                if (expected[origin].items.len > 0) try expected[origin].append(a, ' ');
                try expected[origin].appendSlice(a, tokens[origin]);
            },
            6 => {
                try script.send();
                expected[selected].clearRetainingCapacity();
            },
            8 => try script.restart(),
            else => unreachable,
        }
        try std.testing.expect(script.store.composerMatches(script.composer.items));
        try std.testing.expectEqualStrings(expected[selected].items, script.composer.items);
        for (keys, expected) |key, text| try std.testing.expectEqualStrings(text.items, script.store.get(key));
    }
    for (counts) |count| try std.testing.expect(count > 0);
}

test "IGSH-497 delayed transcript paste never leaks into the newly open workspace" {
    var script = Script{};
    defer script.deinit();
    try script.select(first);
    try script.input("before ");
    const origin = script.store.open.?;
    const workspace = chat_key.Key{ .provider = .slack, .account = "workspace-b", .id = first.id };
    try script.select(workspace);
    try script.input("keep this");
    try std.testing.expect((try script.store.append(std.testing.allocator, origin.key(), script.composer.items, "pasted transcript 📝", false)) == null);
    try std.testing.expectEqualStrings("keep this", script.composer.items);
    try script.select(origin.key());
    try std.testing.expectEqualStrings("before pasted transcript 📝", script.composer.items);
    try script.restart();
    try std.testing.expectEqualStrings("before pasted transcript 📝", script.composer.items);
}

test "IGSH-497 restore preserves whitespace and send clears only its chat across persist" {
    var script = Script{};
    defer script.deinit();
    try script.select(first);
    try script.input(" ");
    try script.select(second);
    try script.input("second draft");
    try script.select(first);
    try std.testing.expectEqualStrings(" ", script.composer.items);
    try script.send();
    try script.restart();
    try std.testing.expectEqualStrings("", script.composer.items);
    try script.select(second);
    try std.testing.expectEqualStrings("second draft", script.composer.items);
}

test "IGSH-497 unknown account never leaks a draft into another workspace" {
    const a = std.testing.allocator;
    var store = Store{};
    defer store.deinit(a);
    _ = try store.switchTo(a, first, "");
    try store.save(a, first, "keep this");
    const unknown = chat_key.Key{ .provider = first.provider, .account = "", .id = first.id };
    try std.testing.expectError(error.InvalidIdentity, store.save(a, unknown, "unscoped"));
    try std.testing.expectError(error.InvalidIdentity, store.switchTo(a, unknown, "keep this"));
    try std.testing.expect(store.isOpen(first));
    try std.testing.expectEqualStrings("", store.get(unknown));
    const bytes = try store.encode(a);
    defer a.free(bytes);
    store.load(a, bytes);
    try std.testing.expectEqualStrings("keep this", store.get(first));
    try std.testing.expectEqualStrings("", store.get(unknown));
}

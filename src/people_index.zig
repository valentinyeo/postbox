const std = @import("std");

pub const Origin = enum { archived, contact, inbox };

pub const Entry = struct {
    jid: []const u8,
    name: []const u8,
    phone: []const u8,
    origin: Origin,
    last_message_ts: []const u8,
    provider: []const u8 = "",
    account: []const u8 = "",
    view_account: []const u8 = "",
};

pub const HubFields = struct {
    provider: []const u8,
    account: []const u8,
    view_account: []const u8,
};

pub const HubResolver = *const fn (std.json.ObjectMap) ?HubFields;

pub const Identity = struct {
    provider: []const u8,
    account: []const u8,
    id: []const u8,
};

fn providerName(entry: Entry) []const u8 {
    return if (entry.provider.len == 0) "whatsapp" else entry.provider;
}

const Set = struct {
    arena: ?std.heap.ArenaAllocator = null,
    entries: []const Entry = &.{},
    by_jid: std.StringHashMapUnmanaged(usize) = .empty,

    fn deinit(self: *Set) void {
        if (self.arena) |*arena| arena.deinit();
        self.* = .{};
    }
};

pub const Index = struct {
    allocator: std.mem.Allocator,
    archived: Set = .{},
    contacts: Set = .{},
    inbox: Set = .{},

    pub fn init(allocator: std.mem.Allocator) Index {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Index) void {
        self.archived.deinit();
        self.contacts.deinit();
        self.inbox.deinit();
    }

    pub fn replaceArchived(self: *Index, raw_json: []const u8) !void {
        try self.replace(raw_json, .archived, null);
    }

    pub fn replaceArchivedHub(self: *Index, raw_json: []const u8, resolver: HubResolver) !void {
        try self.replace(raw_json, .archived, resolver);
    }

    pub fn replaceInboxHub(self: *Index, raw_json: []const u8, resolver: HubResolver) !void {
        try self.replace(raw_json, .inbox, resolver);
    }

    pub fn replaceContacts(self: *Index, raw_json: []const u8) !void {
        try self.replace(raw_json, .contact, null);
    }

    fn replace(self: *Index, raw_json: []const u8, origin: Origin, resolver: ?HubResolver) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const allocator = arena.allocator();
        const root = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw_json, .{ .allocate = .alloc_always });
        if (root != .object) return error.InvalidPayload;
        if (root.object.get("success")) |success| {
            if (success == .bool and !success.bool) return error.InvalidPayload;
        }
        const data = root.object.get("data") orelse return error.InvalidPayload;
        if (data != .array) return error.InvalidPayload;
        const entries = try allocator.alloc(Entry, data.array.items.len);
        var count: usize = 0;
        for (data.array.items) |item| {
            if (item != .object) continue;
            const object = item.object;
            const jid = string(object, "jid");
            var name = string(object, "name");
            const phone = string(object, "phone");
            var fields: HubFields = .{ .provider = "", .account = "", .view_account = "" };
            if (resolver) |resolve| {
                fields = resolve(object) orelse continue;
            }
            const hub_row = resolver != null;
            switch (origin) {
                .archived => {
                    const archived = object.get("archived") orelse continue;
                    if (archived != .bool or !archived.bool or name.len == 0 or jid.len == 0) continue;
                    if (!hub_row and std.mem.indexOfScalar(u8, jid, '@') == null) continue;
                },
                .inbox => {
                    if (!hub_row or name.len == 0 or jid.len == 0) continue;
                    if (object.get("archived")) |archived| {
                        if (archived == .bool and archived.bool) continue;
                    }
                },
                .contact => {
                    if (!std.mem.endsWith(u8, jid, "@s.whatsapp.net")) continue;
                    for ([_][]const u8{ string(object, "alias"), string(object, "system_name"), name, phone }) |candidate| {
                        if (candidate.len == 0) continue;
                        name = candidate;
                        break;
                    }
                },
            }
            entries[count] = .{ .jid = jid, .name = name, .phone = phone, .origin = origin, .last_message_ts = if (origin == .contact) "" else string(object, "last_message_ts"), .provider = fields.provider, .account = fields.account, .view_account = fields.view_account };
            count += 1;
        }
        std.mem.sort(Entry, entries[0..count], {}, lessThan);
        var by_jid: std.StringHashMapUnmanaged(usize) = .empty;
        var unique: usize = 0;
        for (entries[0..count]) |entry| {
            const slot = try by_jid.getOrPut(allocator, entry.jid);
            if (slot.found_existing) continue;
            slot.value_ptr.* = unique;
            entries[unique] = entry;
            unique += 1;
        }
        const target = switch (origin) {
            .archived => &self.archived,
            .contact => &self.contacts,
            .inbox => &self.inbox,
        };
        target.deinit();
        target.* = .{ .arena = arena, .entries = entries[0..unique], .by_jid = by_jid };
    }

    pub fn find(self: *const Index, jid: []const u8) ?Entry {
        if (self.archived.by_jid.get(jid)) |i| return self.archived.entries[i];
        if (self.contacts.by_jid.get(jid)) |i| return self.contacts.entries[i];
        if (self.inbox.by_jid.get(jid)) |i| return self.inbox.entries[i];
        return null;
    }

    pub fn search(self: *const Index, query: []const u8, exclude: []const Identity, fallback_account: []const u8, out: []Entry, max: usize) usize {
        if (query.len == 0) return 0;
        const limit = @min(max, out.len);
        var count: usize = 0;
        for ([_][]const Entry{ self.archived.entries, self.contacts.entries, self.inbox.entries }) |entries| {
            for (entries) |entry| {
                if (count == limit) return count;
                if (entry.origin != .archived and self.archived.by_jid.contains(entry.jid)) continue;
                var excluded = false;
                for (exclude) |shown| {
                    const account = if (entry.account.len == 0) fallback_account else entry.account;
                    if (std.mem.eql(u8, shown.id, entry.jid) and std.mem.eql(u8, shown.provider, providerName(entry)) and std.mem.eql(u8, shown.account, account)) {
                        excluded = true;
                        break;
                    }
                }
                if (excluded) continue;
                const contact_match = if (entry.origin == .archived)
                    if (self.contacts.by_jid.get(entry.jid)) |i| matches(self.contacts.entries[i], query) else false
                else
                    false;
                if (!matches(entry, query) and !contact_match) continue;
                out[count] = entry;
                count += 1;
            }
        }
        return count;
    }
};

fn string(object: std.json.ObjectMap, key: []const u8) []const u8 {
    const value = object.get(key) orelse return "";
    return if (value == .string) value.string else "";
}

fn lessThan(_: void, a: Entry, b: Entry) bool {
    if (a.origin == .archived) {
        const order = std.mem.order(u8, a.last_message_ts, b.last_message_ts);
        if (order != .eq) return order == .gt;
    }
    const order = std.ascii.orderIgnoreCase(a.name, b.name);
    if (order != .eq) return order == .lt;
    return std.mem.lessThan(u8, a.jid, b.jid);
}

fn containsIgnoreCase(text: []const u8, query: []const u8) bool {
    if (query.len > text.len) return false;
    for (0..text.len - query.len + 1) |i| {
        if (std.ascii.eqlIgnoreCase(text[i..][0..query.len], query)) return true;
    }
    return false;
}

fn matches(entry: Entry, query: []const u8) bool {
    if (containsIgnoreCase(entry.name, query) or containsIgnoreCase(entry.phone, query) or containsIgnoreCase(entry.jid, query)) return true;
    for (query) |c| if (!std.ascii.isDigit(c)) return false;
    for (entry.phone, 0..) |c, start| {
        if (c != query[0]) continue;
        var matched: usize = 0;
        for (entry.phone[start..]) |digit| {
            if (digit == ' ' or digit == '+') continue;
            if (digit != query[matched]) break;
            matched += 1;
            if (matched == query.len) return true;
        }
    }
    return false;
}

const archived_payload =
    \\{"success":true,"data":[{"jid":"100@g.us","kind":"group","name":"Person Group","last_message_ts":"2026-01-02T00:00:00Z","archived":true},{"jid":"101@s.whatsapp.net","name":"Person Older","last_message_ts":"2026-01-01T00:00:00Z","archived":true},{"jid":"102@s.whatsapp.net","name":"Inbox","archived":false},{"jid":"invalid","name":"Invalid","archived":true},{"jid":"103@g.us","name":"","archived":true}]}
;
const contacts_payload =
    \\{"data":[{"jid":"101@s.whatsapp.net","phone":"+44 7700 900101","name":"Person Duplicate"},{"jid":"104@s.whatsapp.net","phone":"+44 7700 900104","name":"Original","system_name":"System","alias":"Person Alias"},{"jid":"105@s.whatsapp.net","name":"Original","system_name":"Person System"},{"jid":"106@s.whatsapp.net","name":"Person Name"},{"jid":"107@s.whatsapp.net","phone":"447700900107"},{"jid":"108@g.us","name":"Not a contact"},{"jid":"109@lid","name":"Not a phone contact"}]}
;

test "parse archived payload and keep only addressable named archived rows" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceArchived(archived_payload);
    try std.testing.expectEqual(@as(usize, 2), index.archived.entries.len);
    const entry = index.find("100@g.us").?;
    try std.testing.expectEqualStrings("Person Group", entry.name);
    try std.testing.expectEqualStrings("2026-01-02T00:00:00Z", entry.last_message_ts);
    try std.testing.expectEqual(Origin.archived, entry.origin);
}

test "parse contacts payload with display name precedence and phone jid restriction" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceContacts(contacts_payload);
    try std.testing.expectEqual(@as(usize, 5), index.contacts.entries.len);
    try std.testing.expectEqualStrings("Person Alias", index.find("104@s.whatsapp.net").?.name);
    try std.testing.expectEqualStrings("Person System", index.find("105@s.whatsapp.net").?.name);
    try std.testing.expectEqualStrings("Person Name", index.find("106@s.whatsapp.net").?.name);
    try std.testing.expectEqualStrings("447700900107", index.find("107@s.whatsapp.net").?.name);
    try std.testing.expectEqual(Origin.contact, index.find("104@s.whatsapp.net").?.origin);
}

test "archived beats contacts with newest archived first then contacts by name" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceContacts(contacts_payload);
    try index.replaceArchived(archived_payload);
    var out: [10]Entry = undefined;
    const count = index.search("pErSoN", &.{}, "", &out, out.len);
    try std.testing.expectEqual(@as(usize, 5), count);
    for ([_][]const u8{ "100@g.us", "101@s.whatsapp.net", "104@s.whatsapp.net", "106@s.whatsapp.net", "105@s.whatsapp.net" }, 0..) |jid, i| {
        try std.testing.expectEqualStrings(jid, out[i].jid);
    }
    try std.testing.expectEqual(@as(usize, 1), index.search("+44 7700 900101", &.{}, "", &out, out.len));
    try std.testing.expectEqual(Origin.archived, out[0].origin);
    try std.testing.expectEqualStrings("101@s.whatsapp.net", out[0].jid);
}

test "phone substring and digits match formatted numbers and jid" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceContacts(contacts_payload);
    var out: [10]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 2), index.search("+44 7700", &.{}, "", &out, out.len));
    try std.testing.expectEqual(@as(usize, 1), index.search("447700900104", &.{}, "", &out, out.len));
    try std.testing.expectEqualStrings("104@s.whatsapp.net", out[0].jid);
    try std.testing.expectEqual(@as(usize, 5), index.search("@S.WHATSAPP.NET", &.{}, "", &out, out.len));
}

test "exclude skips shown jids and empty query and output limits are respected" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceArchived(archived_payload);
    var out: [10]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 1), index.search("Person", &.{.{ .provider = "whatsapp", .account = "", .id = "100@g.us" }}, "", &out, out.len));
    try std.testing.expectEqualStrings("101@s.whatsapp.net", out[0].jid);
    try std.testing.expectEqual(@as(usize, 0), index.search("", &.{}, "", &out, out.len));
    try std.testing.expectEqual(@as(usize, 0), index.search("Person", &.{}, "", &out, 0));
    try std.testing.expectEqual(@as(usize, 1), index.search("Person", &.{}, "", out[0..1], 20));
}

test "replacement owns strings and preserves other origin and valid data after errors" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    const raw = try std.testing.allocator.dupe(u8, archived_payload);
    try index.replaceArchived(raw);
    @memset(raw, ' ');
    std.testing.allocator.free(raw);
    try index.replaceContacts(contacts_payload);
    try std.testing.expectError(error.InvalidPayload, index.replaceArchived("{\"data\":{}}"));
    try std.testing.expectError(error.InvalidPayload, index.replaceContacts("{\"success\":false,\"data\":[]}"));
    try std.testing.expectEqualStrings("Person Group", index.find("100@g.us").?.name);
    try index.replaceArchived("{\"data\":[]}");
    try std.testing.expect(index.find("100@g.us") == null);
    try std.testing.expectEqualStrings("Person Duplicate", index.find("101@s.whatsapp.net").?.name);
    try index.replaceContacts("{\"data\":[]}");
    try std.testing.expect(index.find("101@s.whatsapp.net") == null);
}

test "duplicate jids within each payload appear once" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceArchived(
        \\{"data":[{"jid":"100@g.us","name":"Person old","last_message_ts":"2026-01-01","archived":true},{"jid":"100@g.us","name":"Person new","last_message_ts":"2026-01-02","archived":true}]}
    );
    try index.replaceContacts(
        \\{"data":[{"jid":"101@s.whatsapp.net","name":"Person"},{"jid":"101@s.whatsapp.net","name":"Person"}]}
    );
    var out: [10]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 2), index.search("Person", &.{}, "", &out, 10));
    try std.testing.expectEqualStrings("Person new", out[0].name);
}

fn testResolver(object: std.json.ObjectMap) ?HubFields {
    const provider = object.get("provider") orelse return null;
    if (provider != .string) return null;
    if (!std.mem.eql(u8, provider.string, "telegram") and !std.mem.eql(u8, provider.string, "slack") and !std.mem.eql(u8, provider.string, "whatsapp")) return null;
    const account = object.get("account");
    return .{ .provider = provider.string, .account = if (account != null and account.? == .string) account.?.string else "", .view_account = if (std.mem.eql(u8, provider.string, "telegram")) "telegram" else "" };
}

const hub_payload =
    \\{"success":true,"data":[{"jid":"telegram:user:7001001","provider":"telegram","name":"Hub Telegram","archived":true,"last_message_ts":"2026-01-03T00:00:00Z"},{"jid":"slack:T0:C1","provider":"slack","name":"Hub Slack","archived":true,"last_message_ts":"2026-01-02T00:00:00Z"},{"jid":"personal:1@s.whatsapp.net","provider":"whatsapp","name":"Hub Phone","archived":true,"last_message_ts":"2026-01-01T00:00:00Z"},{"jid":"telegram:user:9","provider":"telegram","name":"Hub Open","archived":false},{"jid":"bare","name":"Hub Legacy Bare","archived":true},{"jid":"matrix:1","provider":"matrix","name":"Hub Unknown","archived":true}]}
;

test "hub archived rows keep ids without at sign and carry provider and view account" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceArchivedHub(hub_payload, testResolver);
    try std.testing.expectEqual(@as(usize, 3), index.archived.entries.len);
    const telegram = index.find("telegram:user:7001001").?;
    try std.testing.expectEqualStrings("telegram", telegram.provider);
    try std.testing.expectEqualStrings("telegram", telegram.view_account);
    try std.testing.expectEqual(Origin.archived, telegram.origin);
    try std.testing.expectEqualStrings("slack", index.find("slack:T0:C1").?.provider);
    try std.testing.expect(index.find("telegram:user:9") == null);
    try std.testing.expect(index.find("bare") == null);
    var out: [10]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 3), index.search("Hub", &.{}, "personal", &out, out.len));
    try std.testing.expectEqualStrings("telegram:user:7001001", out[0].jid);
}

test "legacy rows without a provider still need an at sign" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceArchived(hub_payload);
    try std.testing.expectEqual(@as(usize, 1), index.archived.entries.len);
    try std.testing.expect(index.find("telegram:user:7001001") == null);
    try std.testing.expect(index.find("personal:1@s.whatsapp.net") != null);
    try index.replaceArchived(archived_payload);
    try std.testing.expectEqual(@as(usize, 2), index.archived.entries.len);
    try std.testing.expectEqualStrings("", index.find("100@g.us").?.provider);
}

test "hub inbox rows are searchable by identity and excluded when shown" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    try index.replaceInboxHub(hub_payload, testResolver);
    try std.testing.expectEqual(@as(usize, 1), index.inbox.entries.len);
    var out: [10]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 1), index.search("Hub Open", &.{}, "personal", &out, out.len));
    try std.testing.expectEqual(Origin.inbox, out[0].origin);
    try std.testing.expectEqual(@as(usize, 0), index.search("Hub Open", &.{.{ .provider = "telegram", .account = "personal", .id = "telegram:user:9" }}, "personal", &out, out.len));
    try std.testing.expectEqual(@as(usize, 1), index.search("Hub Open", &.{.{ .provider = "signal", .account = "personal", .id = "telegram:user:9" }}, "personal", &out, out.len));
}

test "build 5000 archived and 3000 contacts and search within a second" {
    const start = std.Io.Clock.cpu_thread.now(std.testing.io);
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    var archived: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer archived.deinit();
    var contacts: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer contacts.deinit();
    try archived.writer.writeAll("{\"data\":[");
    for (0..5000) |i| {
        if (i > 0) try archived.writer.writeByte(',');
        try archived.writer.print("{{\"jid\":\"{d}@g.us\",\"name\":\"Person {d}\",\"last_message_ts\":\"2026-01-01T00:00:00Z\",\"archived\":true}}", .{ i, i });
    }
    try archived.writer.writeAll("]}");
    try contacts.writer.writeAll("{\"data\":[");
    for (0..3000) |i| {
        if (i > 0) try contacts.writer.writeByte(',');
        try contacts.writer.print("{{\"jid\":\"4470000{d:0>4}@s.whatsapp.net\",\"name\":\"Contact {d}\",\"phone\":\"+44 70000 {d:0>4}\"}}", .{ i, i, i });
    }
    try contacts.writer.writeAll("]}");
    try index.replaceArchived(archived.written());
    try index.replaceContacts(contacts.written());
    try std.testing.expectEqual(@as(usize, 5000), index.archived.entries.len);
    try std.testing.expectEqual(@as(usize, 3000), index.contacts.entries.len);
    var out: [20]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 1), index.search("Person 4321", &.{}, "", &out, 20));
    try std.testing.expectEqualStrings("4321@g.us", out[0].jid);
    const elapsed = start.durationTo(std.Io.Clock.cpu_thread.now(std.testing.io)).toNanoseconds();
    try std.testing.expect(elapsed < std.time.ns_per_s);
}

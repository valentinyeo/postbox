const std = @import("std");
const media_age = @import("media_age.zig");
const control = @import("control.zig");

pub const max_rows = 200;
pub const refresh_ms = 5 * 60 * 1000;
pub const broadcast = "status@broadcast";

pub const Row = struct {
    msg_id: []const u8 = "",
    ts: i64 = 0,
    from_me: bool = false,
    sender_jid: []const u8 = "",
    sender_name: []const u8 = "",
    text: []const u8 = "",
    media_type: []const u8 = "",
    media_caption: []const u8 = "",
    mime_type: []const u8 = "",
    background_color: []const u8 = "",
    font: i64 = 0,
    local_path: []const u8 = "",

    pub fn quote(self: Row) []const u8 {
        if (self.media_caption.len > 0) return self.media_caption;
        if (self.text.len > 0) return self.text;
        return if (std.mem.eql(u8, self.media_type, "video")) "Video" else "Photo";
    }

    pub fn name(self: Row) []const u8 {
        return if (self.sender_name.len > 0) self.sender_name else self.sender_jid;
    }
};

fn string(object: std.json.ObjectMap, key: []const u8) []const u8 {
    return switch (object.get(key) orelse return "") {
        .string => |value| value,
        else => "",
    };
}

pub const List = struct {
    parsed: std.json.Parsed(std.json.Value),
    rows: std.ArrayList(Row) = .empty,

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.rows.deinit(allocator);
        self.parsed.deinit();
    }

    pub fn parse(allocator: std.mem.Allocator, raw: []const u8, now: i64) !List {
        var result = List{ .parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{ .allocate = .alloc_always }) };
        errdefer result.deinit(allocator);
        const root = switch (result.parsed.value) {
            .object => |value| value,
            else => return error.InvalidStatusList,
        };
        if (root.get("success")) |success| {
            if (success != .bool or !success.bool) return error.InvalidStatusList;
        }
        const data = switch (root.get("data") orelse return error.InvalidStatusList) {
            .object => |value| value,
            else => return error.InvalidStatusList,
        };
        const rows = switch (data.get("statuses") orelse return error.InvalidStatusList) {
            .array => |value| value.items,
            else => return error.InvalidStatusList,
        };
        for (rows) |value| {
            if (result.rows.items.len == max_rows) break;
            const object = switch (value) {
                .object => |item| item,
                else => continue,
            };
            const ts: i64 = switch (object.get("ts") orelse continue) {
                .integer => |number| number,
                .float => |number| if (std.math.isFinite(number) and number >= 0 and number < 9223372036854775808.0) @intFromFloat(number) else continue,
                .string => |text| media_age.unixSeconds(text) orelse continue,
                else => continue,
            };
            const id = string(object, "msg_id");
            const jid = string(object, "sender_jid");
            if (id.len == 0 or jid.len == 0 or ts <= now - 86400 or ts > now) continue;
            var duplicate = false;
            for (result.rows.items) |row| {
                if (std.mem.eql(u8, row.msg_id, id)) duplicate = true;
            }
            if (duplicate) continue;
            try result.rows.append(allocator, .{
                .msg_id = id,
                .ts = ts,
                .sender_jid = jid,
                .sender_name = string(object, "sender_name"),
                .text = string(object, "text"),
                .media_type = string(object, "media_type"),
                .media_caption = string(object, "media_caption"),
                .mime_type = string(object, "mime_type"),
                .background_color = string(object, "background_color"),
                .local_path = string(object, "local_path"),
                .from_me = if (object.get("from_me")) |v| v == .bool and v.bool else false,
                .font = if (object.get("font")) |v| if (v == .integer) v.integer else 0 else 0,
            });
        }
        std.mem.sort(Row, result.rows.items, {}, struct {
            fn less(_: void, a: Row, b: Row) bool {
                if (a.ts != b.ts) return a.ts > b.ts;
                return std.mem.order(u8, a.msg_id, b.msg_id) == .lt;
            }
        }.less);
        return result;
    }
};

pub const Viewed = struct {
    entries: std.StringHashMapUnmanaged(i64) = .empty,
    dirty: bool = false,

    pub fn deinit(self: *Viewed, allocator: std.mem.Allocator) void {
        var keys = self.entries.keyIterator();
        while (keys.next()) |key| allocator.free(key.*);
        self.entries.deinit(allocator);
    }

    pub fn contains(self: *const Viewed, id: []const u8) bool {
        return self.entries.contains(id);
    }

    pub fn mark(self: *Viewed, allocator: std.mem.Allocator, id: []const u8, ts: i64) !void {
        if (id.len == 0 or id.len > 191 or std.mem.indexOfAny(u8, id, " \t\r\n") != null) return;
        if (self.entries.contains(id)) return;
        const key = try allocator.dupe(u8, id);
        errdefer allocator.free(key);
        try self.entries.put(allocator, key, ts);
        self.dirty = true;
    }

    pub fn prune(self: *Viewed, allocator: std.mem.Allocator, now: i64) void {
        while (true) {
            var expired: ?[]const u8 = null;
            var it = self.entries.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* <= now - 48 * 3600 or entry.value_ptr.* > now) {
                    expired = entry.key_ptr.*;
                    break;
                }
            }
            const key = expired orelse break;
            _ = self.entries.remove(key);
            allocator.free(key);
            self.dirty = true;
        }
    }

    pub fn load(self: *Viewed, allocator: std.mem.Allocator, data: []const u8, now: i64) !void {
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, "\r");
            const split = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
            const ts = std.fmt.parseInt(i64, line[split + 1 ..], 10) catch continue;
            try self.mark(allocator, line[0..split], ts);
        }
        self.dirty = false;
        self.prune(allocator, now);
    }

    pub fn encode(self: *Viewed, allocator: std.mem.Allocator, now: i64) ![]u8 {
        self.prune(allocator, now);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        var it = self.entries.iterator();
        while (it.next()) |entry| try out.print(allocator, "{s} {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        return out.toOwnedSlice(allocator);
    }
};

pub const Contact = struct { newest: usize, unseen: bool };
pub const Groups = struct {
    contacts: [max_rows]Contact = undefined,
    count: usize = 0,
    recent: usize = 0,
};

pub fn group(rows: []const Row, viewed: *const Viewed) Groups {
    var result: Groups = .{};
    for (rows, 0..) |row, index| {
        if (row.from_me) continue;
        var found: ?usize = null;
        for (result.contacts[0..result.count], 0..) |contact, i| {
            if (std.mem.eql(u8, rows[contact.newest].sender_jid, row.sender_jid)) {
                found = i;
                break;
            }
        }
        if (found) |i| {
            result.contacts[i].unseen = result.contacts[i].unseen or !viewed.contains(row.msg_id);
            if (row.ts > rows[result.contacts[i].newest].ts) result.contacts[i].newest = index;
        } else if (result.count < max_rows) {
            result.contacts[result.count] = .{ .newest = index, .unseen = !viewed.contains(row.msg_id) };
            result.count += 1;
        }
    }
    const Context = struct { rows: []const Row };
    std.mem.sort(Contact, result.contacts[0..result.count], Context{ .rows = rows }, struct {
        fn less(ctx: Context, a: Contact, b: Contact) bool {
            if (a.unseen != b.unseen) return a.unseen;
            const ra = ctx.rows[a.newest];
            const rb = ctx.rows[b.newest];
            if (ra.ts != rb.ts) return ra.ts > rb.ts;
            return std.mem.order(u8, ra.sender_jid, rb.sender_jid) == .lt;
        }
    }.less);
    for (result.contacts[0..result.count]) |contact| {
        if (contact.unseen) result.recent += 1;
    }
    return result;
}

pub const Navigation = struct {
    order: [max_rows]usize = undefined,
    starts: [max_rows]usize = undefined,
    first_unseen: [max_rows]usize = undefined,
    contact_count: usize = 0,
    count: usize = 0,
    cursor: usize = 0,

    pub fn init(rows: []const Row, viewed: *const Viewed, groups: Groups, contact_index: usize) Navigation {
        var result: Navigation = .{};
        for (groups.contacts[0..groups.count], 0..) |contact, c| {
            result.starts[c] = result.count;
            const start = result.count;
            for (rows, 0..) |row, i| {
                if (!row.from_me and std.mem.eql(u8, row.sender_jid, rows[contact.newest].sender_jid) and result.count < max_rows) {
                    result.order[result.count] = i;
                    result.count += 1;
                }
            }
            std.mem.sort(usize, result.order[start..result.count], rows, struct {
                fn less(items: []const Row, a: usize, b: usize) bool {
                    if (items[a].ts != items[b].ts) return items[a].ts < items[b].ts;
                    return std.mem.order(u8, items[a].msg_id, items[b].msg_id) == .lt;
                }
            }.less);
            result.first_unseen[c] = start;
            for (result.order[start..result.count], start..) |i, position| {
                if (!viewed.contains(rows[i].msg_id)) {
                    result.first_unseen[c] = position;
                    break;
                }
            }
        }
        result.contact_count = groups.count;
        if (contact_index < groups.count) result.cursor = result.first_unseen[contact_index];
        return result;
    }

    pub fn refreshed(self: *const Navigation, old_rows: []const Row, rows: []const Row, viewed: *const Viewed) Navigation {
        var groups = group(rows, viewed);
        var ordered: Groups = .{};
        for (self.starts[0..self.contact_count]) |start| {
            const jid = old_rows[self.order[start]].sender_jid;
            for (groups.contacts[0..groups.count]) |contact| {
                if (std.mem.eql(u8, rows[contact.newest].sender_jid, jid)) {
                    ordered.contacts[ordered.count] = contact;
                    ordered.count += 1;
                    break;
                }
            }
        }
        for (groups.contacts[0..groups.count]) |contact| {
            var found = false;
            for (ordered.contacts[0..ordered.count]) |existing| {
                if (std.mem.eql(u8, rows[existing.newest].sender_jid, rows[contact.newest].sender_jid)) found = true;
            }
            if (!found) {
                ordered.contacts[ordered.count] = contact;
                ordered.count += 1;
            }
        }
        var selected: usize = 0;
        if (self.current()) |index| {
            for (ordered.contacts[0..ordered.count], 0..) |contact, c| {
                if (std.mem.eql(u8, rows[contact.newest].sender_jid, old_rows[index].sender_jid)) selected = c;
            }
        }
        var result = init(rows, viewed, ordered, selected);
        if (self.current()) |index| {
            for (result.order[0..result.count], 0..) |row_index, cursor| {
                if (std.mem.eql(u8, rows[row_index].msg_id, old_rows[index].msg_id)) result.cursor = cursor;
            }
        }
        return result;
    }

    pub fn current(self: *const Navigation) ?usize {
        return if (self.cursor < self.count) self.order[self.cursor] else null;
    }

    pub fn step(self: *Navigation, direction: i32) bool {
        if (direction < 0) {
            if (self.cursor == 0) return false;
            self.cursor -= 1;
            return true;
        }
        if (self.cursor + 1 >= self.count) return false;
        self.cursor += 1;
        for (self.starts[0..self.contact_count], 0..) |start, c| {
            if (start == self.cursor) {
                self.cursor = self.first_unseen[c];
                break;
            }
        }
        return true;
    }
};

pub fn mayRefresh(last: ?u64, now: u64) bool {
    return if (last) |time| now -| time >= refresh_ms else true;
}

pub fn backgroundColor(text: []const u8) u32 {
    if ((text.len != 7 and text.len != 9) or text[0] != '#') return 0x003b2c22;
    const value = std.fmt.parseInt(u32, text[1..], 16) catch return 0x003b2c22;
    return ((value & 0xff) << 16) | (value & 0xff00) | ((value >> 16) & 0xff);
}

pub fn writeStatuses(writer: *std.Io.Writer, rows: []const Row, viewed: *const Viewed) !void {
    try writer.writeAll("{\"ok\":true,\"result\":{\"statuses\":[");
    for (rows, 0..) |row, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeAll("{\"msg_id\":");
        try control.writeString(writer, row.msg_id);
        try writer.writeAll(",\"sender_jid\":");
        try control.writeString(writer, row.sender_jid);
        try writer.writeAll(",\"sender_name\":");
        try control.writeString(writer, row.sender_name);
        try writer.print(",\"ts\":{d},\"from_me\":{},\"viewed\":{},\"media_type\":", .{ row.ts, row.from_me, viewed.contains(row.msg_id) });
        try control.writeString(writer, row.media_type);
        try writer.writeAll(",\"local_path\":");
        try control.writeString(writer, row.local_path);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}}\n");
}

const fixture = "{\"success\":true,\"data\":{\"statuses\":[{\"msg_id\":\"old\",\"ts\":100000,\"sender_jid\":\"a@s.whatsapp.net\"},{\"msg_id\":\"new\",\"ts\":\"1970-01-02T04:03:20Z\",\"sender_jid\":\"a@s.whatsapp.net\",\"text\":\"hello\"},{\"msg_id\":\"b\",\"ts\":102000,\"sender_jid\":\"b@s.whatsapp.net\",\"media_type\":\"video\"},{\"msg_id\":\"own\",\"ts\":103000,\"sender_jid\":\"me\",\"from_me\":true},{\"msg_id\":\"cut\",\"ts\":23600,\"sender_jid\":\"c\"},{\"msg_id\":\"future\",\"ts\":110001,\"sender_jid\":\"c\"},{\"msg_id\":\"missing\"},{\"ts\":105000,\"sender_jid\":\"c\"},null]},\"error\":null}";

test "parse contract both timestamp forms missing fields and exact rolling 24 hour cut" {
    var list = try List.parse(std.testing.allocator, fixture, 110000);
    defer list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), list.rows.items.len);
    try std.testing.expectEqual(@as(i64, 101000), list.rows.items[2].ts);
    try std.testing.expectEqualStrings("", list.rows.items[2].local_path);
    try std.testing.expectEqualStrings("hello", list.rows.items[2].text);
    try std.testing.expectError(error.InvalidStatusList, List.parse(std.testing.allocator, "{\"data\":{}}", 110000));
    try std.testing.expectError(error.InvalidStatusList, List.parse(std.testing.allocator, "{\"success\":false,\"data\":{\"statuses\":[]}}", 110000));
}

test "group contacts once recent before viewed newest first ignoring own updates" {
    const a = std.testing.allocator;
    var viewed: Viewed = .{};
    defer viewed.deinit(a);
    var list = try List.parse(a, fixture, 110000);
    defer list.deinit(a);
    var groups = group(list.rows.items, &viewed);
    try std.testing.expectEqual(@as(usize, 2), groups.count);
    try std.testing.expectEqual(@as(usize, 2), groups.recent);
    try std.testing.expectEqualStrings("b", list.rows.items[groups.contacts[0].newest].msg_id);
    try viewed.mark(a, "b", 102000);
    groups = group(list.rows.items, &viewed);
    try std.testing.expectEqual(@as(usize, 1), groups.recent);
    try std.testing.expectEqualStrings("new", list.rows.items[groups.contacts[0].newest].msg_id);
    try viewed.mark(a, "new", 101000);
    try std.testing.expectEqual(@as(usize, 1), group(list.rows.items, &viewed).recent);
    try viewed.mark(a, "old", 100000);
    try std.testing.expectEqual(@as(usize, 0), group(list.rows.items, &viewed).recent);
}

test "navigation starts oldest unseen and moves both directions across contacts without regrouping" {
    const a = std.testing.allocator;
    var viewed: Viewed = .{};
    defer viewed.deinit(a);
    var list = try List.parse(a, fixture, 110000);
    defer list.deinit(a);
    try viewed.mark(a, "old", 100000);
    var nav = Navigation.init(list.rows.items, &viewed, group(list.rows.items, &viewed), 1);
    try std.testing.expectEqualStrings("new", list.rows.items[nav.current().?].msg_id);
    try std.testing.expect(nav.step(-1));
    try std.testing.expectEqualStrings("old", list.rows.items[nav.current().?].msg_id);
    try std.testing.expect(nav.step(-1));
    try std.testing.expectEqualStrings("b", list.rows.items[nav.current().?].msg_id);
    try std.testing.expect(!nav.step(-1));
    try std.testing.expect(nav.step(1));
    try std.testing.expectEqualStrings("new", list.rows.items[nav.current().?].msg_id);
    try std.testing.expect(!nav.step(1));
}

test "viewed file round trip prunes 48 hours malformed lines and future times" {
    const a = std.testing.allocator;
    var viewed: Viewed = .{};
    defer viewed.deinit(a);
    try viewed.load(a, "old 27200\nkeep 27201\r\nnew 200000\nfuture 200001\nbad x\nmissing\n", 200000);
    try std.testing.expect(viewed.dirty);
    try std.testing.expectEqual(@as(usize, 2), viewed.entries.count());
    try std.testing.expect(viewed.contains("keep"));
    const disk = try viewed.encode(a, 200000);
    defer a.free(disk);
    var loaded: Viewed = .{};
    defer loaded.deinit(a);
    try loaded.load(a, disk, 200000);
    try std.testing.expect(!loaded.dirty);
    try std.testing.expect(loaded.contains("new"));
    const pruned = try loaded.encode(a, 400000);
    defer a.free(pruned);
    try std.testing.expectEqualStrings("", pruned);
}

test "refresh cadence color quote and control response use actual status model" {
    try std.testing.expect(mayRefresh(null, 0));
    try std.testing.expect(!mayRefresh(100, 300099));
    try std.testing.expect(mayRefresh(100, 300100));
    try std.testing.expectEqual(@as(u32, 0x00332211), backgroundColor("#ff112233"));
    try std.testing.expectEqual(@as(u32, 0x00332211), backgroundColor("#112233"));
    try std.testing.expectEqualStrings("Video", (Row{ .media_type = "video" }).quote());
    try std.testing.expectEqualStrings("caption", (Row{ .media_caption = "caption", .text = "body" }).quote());
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var viewed: Viewed = .{};
    defer viewed.deinit(std.testing.allocator);
    try viewed.mark(std.testing.allocator, "x", 1);
    try writeStatuses(&out.writer, &.{.{ .msg_id = "x", .local_path = "C:\\media\\x.jpg" }}, &viewed);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out.written(), .{});
    defer parsed.deinit();
    const row = parsed.value.object.get("result").?.object.get("statuses").?.array.items[0].object;
    try std.testing.expect(row.get("viewed").?.bool);
    try std.testing.expectEqualStrings("C:\\media\\x.jpg", row.get("local_path").?.string);
}

test "all contract fields survive owned parsing and media replies choose caption then text then kind" {
    const a = std.testing.allocator;
    const raw = "{\"success\":true,\"data\":{\"statuses\":[{\"msg_id\":\"image\",\"ts\":\"1970-01-02T04:03:20.125Z\",\"from_me\":false,\"sender_jid\":\"fixture@s.whatsapp.net\",\"sender_name\":\"Fixture\",\"text\":\"body\",\"media_type\":\"image\",\"media_caption\":\"caption\",\"mime_type\":\"image/jpeg\",\"background_color\":\"#AA112233\",\"font\":3,\"local_path\":\"C:\\\\cache\\\\fixture.jpg\"}]},\"error\":null}";
    const buffer = try a.dupe(u8, raw);
    var list = try List.parse(a, buffer, 110000);
    a.free(buffer);
    defer list.deinit(a);
    const row = list.rows.items[0];
    try std.testing.expectEqualStrings("image", row.msg_id);
    try std.testing.expectEqualStrings("fixture@s.whatsapp.net", row.sender_jid);
    try std.testing.expectEqualStrings("Fixture", row.name());
    try std.testing.expectEqualStrings("caption", row.quote());
    try std.testing.expectEqualStrings("image/jpeg", row.mime_type);
    try std.testing.expectEqualStrings("#AA112233", row.background_color);
    try std.testing.expectEqual(@as(i64, 3), row.font);
    try std.testing.expect(row.local_path.len > 0);
    try std.testing.expectEqualStrings("Photo", (Row{ .media_type = "image" }).quote());
    try std.testing.expectEqualStrings("body", (Row{ .text = "body", .media_type = "video" }).quote());
}

test "navigation preserves chronological updates and skips viewed prefixes only on contact entry" {
    const a = std.testing.allocator;
    const rows = [_]Row{
        .{ .msg_id = "a3", .sender_jid = "a", .ts = 30 },
        .{ .msg_id = "b3", .sender_jid = "b", .ts = 29 },
        .{ .msg_id = "c1", .sender_jid = "c", .ts = 28 },
        .{ .msg_id = "a2", .sender_jid = "a", .ts = 20 },
        .{ .msg_id = "b2", .sender_jid = "b", .ts = 19 },
        .{ .msg_id = "a1", .sender_jid = "a", .ts = 10 },
        .{ .msg_id = "b1", .sender_jid = "b", .ts = 9 },
    };
    var viewed: Viewed = .{};
    defer viewed.deinit(a);
    try viewed.mark(a, "a1", 10);
    try viewed.mark(a, "b1", 9);
    const groups = group(&rows, &viewed);
    var nav = Navigation.init(&rows, &viewed, groups, 0);
    try std.testing.expectEqualStrings("a2", rows[nav.current().?].msg_id);
    try viewed.mark(a, "a2", 20);
    try std.testing.expect(nav.step(1));
    try std.testing.expectEqualStrings("a3", rows[nav.current().?].msg_id);
    try std.testing.expect(nav.step(1));
    try std.testing.expectEqualStrings("b2", rows[nav.current().?].msg_id);
    try std.testing.expect(nav.step(-1));
    try std.testing.expectEqualStrings("b1", rows[nav.current().?].msg_id);
    try std.testing.expect(nav.step(-1));
    try std.testing.expectEqualStrings("a3", rows[nav.current().?].msg_id);
    try std.testing.expect(nav.step(1));
    try std.testing.expect(nav.step(1));
    try std.testing.expect(nav.step(1));
    try std.testing.expectEqualStrings("c1", rows[nav.current().?].msg_id);
    try std.testing.expect(!nav.step(1));
}

test "media refresh retains session contact order and current item as viewed sections change" {
    const a = std.testing.allocator;
    const rows = [_]Row{
        .{ .msg_id = "a", .sender_jid = "a", .ts = 30 },
        .{ .msg_id = "b", .sender_jid = "b", .ts = 20 },
    };
    var viewed: Viewed = .{};
    defer viewed.deinit(a);
    const navigation = Navigation.init(&rows, &viewed, group(&rows, &viewed), 0);
    try viewed.mark(a, "a", 30);
    const refreshed_rows = [_]Row{
        rows[1],
        .{ .msg_id = "a", .sender_jid = "a", .ts = 30, .local_path = "cached.jpg" },
    };
    var next = navigation.refreshed(&rows, &refreshed_rows, &viewed);
    try std.testing.expectEqualStrings("a", refreshed_rows[next.current().?].msg_id);
    try std.testing.expect(next.step(1));
    try std.testing.expectEqualStrings("b", refreshed_rows[next.current().?].msg_id);
    const expired = next.refreshed(&refreshed_rows, &.{rows[0]}, &viewed);
    try std.testing.expectEqual(@as(usize, 1), expired.count);
    const empty = next.refreshed(&refreshed_rows, &.{}, &viewed);
    try std.testing.expectEqual(@as(?usize, null), empty.current());
}

test "unix seconds JSON numbers may use floating point notation" {
    const a = std.testing.allocator;
    var list = try List.parse(a, "{\"data\":{\"statuses\":[{\"msg_id\":\"number\",\"sender_jid\":\"fixture\",\"ts\":100000.0}]}}", 100001);
    defer list.deinit(a);
    try std.testing.expectEqual(@as(i64, 100000), list.rows.items[0].ts);
}

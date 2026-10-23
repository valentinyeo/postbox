const std = @import("std");
const Provider = @import("transport.zig").Provider;

pub const View = enum { whatsapp, slack, telegram, all, signal };

const chat_key = @import("chat_key.zig");

pub const Account = struct {
    key: chat_key.Stored = .{},
    label_buf: [256]u8 = @splat(0),
    label_len: usize = 0,
    selected: chat_key.Stored = .{},

    pub fn init(provider: Provider, account: []const u8, name: []const u8) Account {
        var result = Account{};
        result.key.set(.{ .provider = provider, .account = account, .id = "" });
        const text = std.fmt.bufPrint(&result.label_buf, "{s} {s}", .{ label(providerView(provider)), if (provider == .signal) "" else if (name.len > 0) name else account }) catch {
            const fallback = label(providerView(provider));
            @memcpy(result.label_buf[0..fallback.len], fallback);
            result.label_len = fallback.len;
            return result;
        };
        result.label_len = std.mem.trimEnd(u8, text, " ").len;
        return result;
    }

    pub fn labelText(self: *const Account) []const u8 {
        return self.label_buf[0..self.label_len];
    }
};

pub fn providerView(provider: Provider) View {
    return switch (provider) {
        .whatsapp => .whatsapp,
        .slack => .slack,
        .telegram => .telegram,
        .signal => .signal,
    };
}

pub fn label(view: View) []const u8 {
    return switch (view) {
        .all => "combined inbox",
        .whatsapp => "WhatsApp",
        .slack => "Slack",
        .telegram => "Telegram",
        .signal => "Signal",
    };
}

pub fn forNumber(number: usize, views: []const Account) ?usize {
    return if (number > 0 and number <= views.len) number - 1 else null;
}

pub fn accountMatches(view: View, account: []const u8, key: chat_key.Key) bool {
    return includes(view, key.provider) and (account.len == 0 or std.mem.eql(u8, account, key.account));
}

fn savedKey(entry: []const u8) ?chat_key.Key {
    const colon = std.mem.indexOfScalar(u8, entry, ':') orelse return null;
    const provider = std.meta.stringToEnum(Provider, entry[0..colon]) orelse return null;
    if (colon + 1 == entry.len) return null;
    return .{ .provider = provider, .account = entry[colon + 1 ..], .id = "" };
}

pub fn mergeOrder(allocator: std.mem.Allocator, saved: []const u8, known: []const Account) !std.ArrayList(Account) {
    var result: std.ArrayList(Account) = .empty;
    errdefer result.deinit(allocator);
    var entries = std.mem.tokenizeAny(u8, saved, "\r\n");
    while (entries.next()) |entry| {
        const key = savedKey(entry) orelse continue;
        for (known) |item| {
            if (!chat_key.Key.eql(item.key.key(), key)) continue;
            try appendUnique(allocator, &result, item);
            break;
        }
    }
    for ([_]Provider{ .whatsapp, .slack, .telegram, .signal }) |provider| {
        for (known) |item| {
            if (item.key.provider == provider) try appendUnique(allocator, &result, item);
        }
    }
    return result;
}

pub fn appendUnique(allocator: std.mem.Allocator, list: *std.ArrayList(Account), item: Account) !void {
    for (list.items) |existing| if (chat_key.Key.eql(existing.key.key(), item.key.key())) return;
    try list.append(allocator, item);
}

pub fn saveOrder(allocator: std.mem.Allocator, saved: []const u8, views: []const Account) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var entries = std.mem.tokenizeAny(u8, saved, "\r\n");
    var next: usize = 0;
    var seen: std.ArrayList(chat_key.Stored) = .empty;
    defer seen.deinit(allocator);
    while (entries.next()) |entry| {
        const key = savedKey(entry) orelse continue;
        var duplicate = false;
        for (seen.items) |item| {
            if (chat_key.Key.eql(item.key(), key)) duplicate = true;
        }
        if (duplicate) continue;
        var stored = chat_key.Stored{};
        stored.set(key);
        try seen.append(allocator, stored);
        var present = false;
        for (views) |item| {
            if (chat_key.Key.eql(item.key.key(), key)) present = true;
        }
        if (present) {
            const replacement = views[next].key.key();
            try output.print(allocator, "{s}:{s}\n", .{ @tagName(replacement.provider), replacement.account });
            next += 1;
        } else {
            try output.print(allocator, "{s}\n", .{entry});
        }
    }
    for (views[next..]) |item| {
        const key = item.key.key();
        try output.print(allocator, "{s}:{s}\n", .{ @tagName(key.provider), key.account });
    }
    return output.toOwnedSlice(allocator);
}

pub fn inboxMoveUp(by_time: std.math.Order, key_order: std.math.Order) bool {
    return by_time == .lt or (by_time == .eq and key_order == .gt);
}

test "account view order merges saved missing and new accounts without losing absent entries" {
    const allocator = std.testing.allocator;
    const known = [_]Account{
        Account.init(.slack, "slack-a", "Workspace A"),
        Account.init(.whatsapp, "wa-a", "Account A"),
        Account.init(.slack, "slack-b", "Workspace B"),
        Account.init(.whatsapp, "wa-b", "Account B"),
    };
    const saved = "slack:slack-b\nwhatsapp:absent\nwhatsapp:wa-a\n";
    var merged = try mergeOrder(allocator, saved, &known);
    defer merged.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 4), merged.items.len);
    try std.testing.expectEqualStrings("slack-b", merged.items[0].key.key().account);
    try std.testing.expectEqualStrings("wa-a", merged.items[1].key.key().account);
    try std.testing.expectEqualStrings("wa-b", merged.items[2].key.key().account);
    try std.testing.expectEqualStrings("slack-a", merged.items[3].key.key().account);
    std.mem.swap(Account, &merged.items[0], &merged.items[1]);
    const stored = try saveOrder(allocator, saved, merged.items);
    defer allocator.free(stored);
    try std.testing.expectEqualStrings("whatsapp:wa-a\nwhatsapp:absent\nslack:slack-b\nwhatsapp:wa-b\nslack:slack-a\n", stored);
    var restarted = try mergeOrder(allocator, stored, &known);
    defer restarted.deinit(allocator);
    for (merged.items, restarted.items) |left, right| try std.testing.expect(chat_key.Key.eql(left.key.key(), right.key.key()));
    var returned: [known.len + 1]Account = undefined;
    @memcpy(returned[0..known.len], &known);
    returned[known.len] = Account.init(.whatsapp, "absent", "Account Returned");
    var restored = try mergeOrder(allocator, stored, &returned);
    defer restored.deinit(allocator);
    try std.testing.expectEqualStrings("absent", restored.items[1].key.key().account);
    try std.testing.expectEqual(@as(usize, returned.len), restored.items.len);
}

test "Alt+N maps saved account positions including two WhatsApp accounts" {
    const views = [_]Account{ Account.init(.whatsapp, "wa-b", "Account B"), Account.init(.whatsapp, "wa-a", "Account A"), Account.init(.slack, "slack-a", "Workspace A") };
    try std.testing.expectEqual(@as(?usize, 0), forNumber(1, &views));
    try std.testing.expectEqual(@as(?usize, 1), forNumber(2, &views));
    try std.testing.expectEqual(@as(?usize, 2), forNumber(3, &views));
    try std.testing.expectEqual(@as(?usize, null), forNumber(4, &views));
    try std.testing.expectEqual(@as(?usize, null), forNumber(0, &views));
    try std.testing.expect(accountMatches(.whatsapp, "wa-b", .{ .provider = .whatsapp, .account = "wa-b", .id = "shared-contact" }));
    try std.testing.expect(!accountMatches(.whatsapp, "wa-b", .{ .provider = .whatsapp, .account = "wa-a", .id = "shared-contact" }));
}

test "combined inbox sorts activity across accounts without prioritizing old pins" {
    const Row = struct { key: chat_key.Stored, timestamp: u32, pinned: bool };
    var first = chat_key.Stored{};
    first.set(.{ .provider = .whatsapp, .account = "wa-a", .id = "shared-contact" });
    var second = chat_key.Stored{};
    second.set(.{ .provider = .whatsapp, .account = "wa-b", .id = "shared-contact" });
    var rows = [_]Row{ .{ .key = first, .timestamp = 1, .pinned = true }, .{ .key = second, .timestamp = 2, .pinned = false } };
    if (inboxMoveUp(std.math.order(rows[0].timestamp, rows[1].timestamp), chat_key.order(rows[0].key.key(), rows[1].key.key()))) std.mem.swap(Row, &rows[0], &rows[1]);
    try std.testing.expectEqual(@as(u32, 2), rows[0].timestamp);
    try std.testing.expect(!rows[0].pinned);
    try std.testing.expect(!chat_key.Key.eql(rows[0].key.key(), rows[1].key.key()));
}

pub fn includes(view: View, provider: Provider) bool {
    return view == .all or std.mem.eql(u8, @tagName(view), @tagName(provider));
}

pub fn matches(view: View, provider: Provider, unread_only: bool, unread: bool, query: []const u8, name: []const u8, id: []const u8) bool {
    return includes(view, provider) and (!unread_only or unread) and
        (query.len == 0 or contains(name, query) or contains(id, query));
}

fn contains(text: []const u8, query: []const u8) bool {
    if (query.len > text.len) return false;
    for (0..text.len - query.len + 1) |index| {
        if (std.ascii.eqlIgnoreCase(text[index..][0..query.len], query)) return true;
    }
    return false;
}

pub fn merge(comptime T: type, output: []T, count: *usize, store: []const T) void {
    const key = @import("chat_key.zig");
    for (store) |item| {
        if (key.indexOf(T, output[0..count.*], key.of(&item))) |index| {
            output[index] = item;
        } else if (count.* < output.len) {
            output[count.*] = item;
            count.* += 1;
        }
    }
}

test "two WhatsApp account views isolate a shared contact in projection search selection and sending" {
    const Text = struct {
        value: []const u8,
        pub fn slice(self: *const @This()) []const u8 {
            return self.value;
        }
    };
    const Row = struct { provider: Provider = .whatsapp, account: Text, jid: Text };
    const rows = [_]Row{
        .{ .account = .{ .value = "wa-a" }, .jid = .{ .value = "shared-contact" } },
        .{ .account = .{ .value = "wa-b" }, .jid = .{ .value = "shared-contact" } },
    };
    var output: [2]Row = undefined;
    var count: usize = 0;
    merge(Row, &output, &count, &rows);
    try std.testing.expectEqual(@as(usize, 2), count);
    for (&rows, 0..) |*row, index| {
        const key = chat_key.of(row);
        try std.testing.expect(accountMatches(.whatsapp, key.account, chat_key.of(&output[index])));
        try std.testing.expect(!accountMatches(.whatsapp, key.account, chat_key.of(&output[1 - index])));
        try std.testing.expect(matches(.whatsapp, key.provider, false, false, "shared", "Verification Shared", key.id));
        try std.testing.expectEqual(@as(?usize, index), chat_key.indexOf(Row, &output, key));
        try std.testing.expectEqual(@as(?usize, null), chat_key.indexOf(Row, output[1 - index .. 2 - index], key));
    }
}

test "All projection rebuild preserves WhatsApp and isolates colliding Slack workspaces" {
    const Text = struct {
        value: []const u8,
        pub fn slice(self: *const @This()) []const u8 {
            return self.value;
        }
    };
    const Row = struct { provider: Provider, account: Text, jid: Text, unread: bool = false };
    const wa = [_]Row{.{ .provider = .whatsapp, .account = .{ .value = "default" }, .jid = .{ .value = "123@s.whatsapp.net" } }};
    var slack_rows = [_]Row{
        .{ .provider = .slack, .account = .{ .value = "T0000000001" }, .jid = .{ .value = "C0000000001" } },
        .{ .provider = .slack, .account = .{ .value = "T0000000002" }, .jid = .{ .value = "C0000000001" } },
    };
    var output: [3]Row = undefined;
    var count: usize = 0;
    merge(Row, &output, &count, &wa);
    merge(Row, &output, &count, &slack_rows);
    slack_rows[1].unread = true;
    count = 0;
    merge(Row, &output, &count, &wa);
    merge(Row, &output, &count, &slack_rows);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(Provider.whatsapp, output[0].provider);
    try std.testing.expect(!output[1].unread and output[2].unread);
}

test "All search and unread filter apply across every provider" {
    for ([_]Provider{ .whatsapp, .slack, .telegram, .signal }) |provider| {
        try std.testing.expect(matches(.all, provider, true, true, "EXAMPLE", "Example chat", "id"));
        try std.testing.expect(!matches(.all, provider, true, false, "", "Example chat", "id"));
        try std.testing.expect(!matches(.all, provider, false, true, "missing", "Example chat", "id"));
        try std.testing.expect(matches(.all, provider, false, false, "ID", "Example chat", "id"));
    }
    try std.testing.expect(!matches(.whatsapp, .slack, false, true, "", "chat", "id"));
}

test "bulk selection separates matching channel ids in different workspaces" {
    const Key = @import("chat_key.zig").Key;
    var selected = @import("archive_rules.zig").Selection(4){};
    const first = Key{ .provider = .slack, .account = "T0000000001", .id = "C0000000001" };
    const second = Key{ .provider = .slack, .account = "T0000000002", .id = "C0000000001" };
    selected.addKey(first);
    try std.testing.expect(selected.containsKey(first));
    try std.testing.expect(!selected.containsKey(second));
    try std.testing.expect(Key.eql(first, selected.atKey(Key, 0)));
}

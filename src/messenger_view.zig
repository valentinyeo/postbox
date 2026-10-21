const std = @import("std");
const Provider = @import("transport.zig").Provider;

pub const View = enum { whatsapp, slack, telegram, all };

const order = [_]View{ .whatsapp, .slack, .telegram };

fn configured(provider: View, slack: bool, telegram: bool) bool {
    return switch (provider) {
        .whatsapp, .all => true,
        .slack => slack,
        .telegram => telegram,
    };
}

pub fn forNumber(number: usize, slack: bool, telegram: bool) ?View {
    if (number == 0) return .all;
    var seen: usize = 0;
    for (order) |provider| {
        if (!configured(provider, slack, telegram)) continue;
        seen += 1;
        if (seen == number) return provider;
    }
    return null;
}

pub fn numberFor(provider: View, slack: bool, telegram: bool) ?usize {
    if (provider == .all) return 0;
    var seen: usize = 0;
    for (order) |candidate| {
        if (!configured(candidate, slack, telegram)) continue;
        seen += 1;
        if (candidate == provider) return seen;
    }
    return null;
}

pub fn effective(wanted: View, slack: bool, telegram: bool) View {
    return if (configured(wanted, slack, telegram)) wanted else .all;
}

pub fn label(provider: View) []const u8 {
    return switch (provider) {
        .all => "All",
        .whatsapp => "WhatsApp",
        .slack => "Slack",
        .telegram => "Telegram",
    };
}

test "Alt+N numbers only configured messengers, in a fixed order" {
    try std.testing.expectEqual(@as(?View, .whatsapp), forNumber(1, false, false));
    try std.testing.expectEqual(@as(?View, null), forNumber(2, false, false));
    try std.testing.expectEqual(@as(?View, .slack), forNumber(2, true, false));
    try std.testing.expectEqual(@as(?View, .telegram), forNumber(2, false, true));
    try std.testing.expectEqual(@as(?View, .telegram), forNumber(3, true, true));
    try std.testing.expectEqual(@as(?usize, 3), numberFor(.telegram, true, true));
    try std.testing.expectEqual(@as(?usize, null), numberFor(.slack, false, true));
    try std.testing.expectEqual(@as(?View, .all), forNumber(0, true, true));
}

test "a remembered view that is not set up falls back to All" {
    try std.testing.expectEqual(View.all, effective(.slack, false, false));
    try std.testing.expectEqual(View.slack, effective(.slack, true, false));
    try std.testing.expectEqual(View.all, effective(.telegram, true, false));
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
    for ([_]Provider{ .whatsapp, .slack, .telegram }) |provider| {
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

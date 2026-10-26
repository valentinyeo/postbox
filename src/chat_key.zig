const std = @import("std");
const transport = @import("transport.zig");

pub const max_account_len = 32;

pub const Key = struct {
    provider: transport.Provider,
    account: []const u8,
    id: []const u8,

    pub fn eql(a: Key, b: Key) bool {
        return a.provider == b.provider and std.mem.eql(u8, a.account, b.account) and std.mem.eql(u8, a.id, b.id);
    }
};

pub fn providerOfId(id: []const u8) ?transport.Provider {
    if (std.mem.startsWith(u8, id, "telegram:")) return .telegram;
    if (std.mem.startsWith(u8, id, "signal:")) return .signal;
    return null;
}

pub const Stored = struct {
    provider: transport.Provider = .whatsapp,
    account: [max_account_len]u8 = @splat(0),
    account_len: usize = 0,
    id: [191]u8 = @splat(0),
    id_len: usize = 0,

    pub fn set(self: *Stored, value: Key) void {
        self.provider = value.provider;
        self.account_len = @min(value.account.len, self.account.len);
        self.id_len = @min(value.id.len, self.id.len);
        @memcpy(self.account[0..self.account_len], value.account[0..self.account_len]);
        @memcpy(self.id[0..self.id_len], value.id[0..self.id_len]);
    }

    pub fn key(self: *const Stored) Key {
        return .{ .provider = self.provider, .account = self.account[0..self.account_len], .id = self.id[0..self.id_len] };
    }
};

pub fn order(a: Key, b: Key) std.math.Order {
    const provider = std.math.order(@intFromEnum(a.provider), @intFromEnum(b.provider));
    if (provider != .eq) return provider;
    const account = std.mem.order(u8, a.account, b.account);
    return if (account != .eq) account else std.mem.order(u8, a.id, b.id);
}

pub fn of(item: anytype) Key {
    if (@typeInfo(@TypeOf(item)) != .pointer) @compileError("chat_key.of needs a pointer so key slices retain their owner");
    return .{ .provider = std.meta.stringToEnum(transport.Provider, @tagName(item.provider)).?, .account = item.account.slice(), .id = item.jid.slice() };
}

pub fn displayed(app: anytype) Key {
    return .{ .provider = std.meta.stringToEnum(transport.Provider, @tagName(app.displayed_provider)).?, .account = app.displayed_account.slice(), .id = app.displayed_jid.slice() };
}

pub fn indexOf(comptime T: type, items: []const T, key: Key) ?usize {
    for (items, 0..) |*item, index| {
        if (Key.eql(of(item), key)) return index;
    }
    return null;
}

test "two WhatsApp accounts that share a contact keep their chats apart" {
    const Text = struct {
        value: []const u8,
        pub fn slice(self: *const @This()) []const u8 {
            return self.value;
        }
    };
    const Chat = struct { provider: transport.Provider, account: Text, jid: Text };
    const jid = Text{ .value = "4915112345678@s.whatsapp.net" };
    const chats = [_]Chat{
        .{ .provider = .whatsapp, .account = .{ .value = "aaaaaaaaaaaaaaaa" }, .jid = jid },
        .{ .provider = .whatsapp, .account = .{ .value = "bbbbbbbbbbbbbbbb" }, .jid = jid },
    };
    const PendingSend = struct { provider: transport.Provider, account: Text, jid: Text, text: Text };
    const pending = PendingSend{ .provider = .whatsapp, .account = chats[1].account, .jid = jid, .text = .{ .value = "hello" } };
    try std.testing.expectEqual(@as(?usize, 1), indexOf(Chat, &chats, of(&pending)));
    try std.testing.expectEqual(@as(?usize, null), indexOf(Chat, chats[0..1], of(&pending)));
    try std.testing.expectEqual(@as(?usize, null), indexOf(Chat, &chats, .{ .provider = .whatsapp, .account = "unknown", .id = jid.slice() }));
    try std.testing.expect(!Key.eql(of(&chats[0]), of(&chats[1])));
    try std.testing.expect(!Key.eql(of(&pending), .{ .provider = .slack, .account = pending.account.slice(), .id = jid.slice() }));
    try std.testing.expect(Key.eql(of(&pending), of(&chats[1])));
}

test "stored selection and pin keys retain provider account and id" {
    var first = Stored{};
    first.set(.{ .provider = .slack, .account = "T0000000001", .id = "C0000000001" });
    var second = first;
    second.set(.{ .provider = .slack, .account = "T0000000002", .id = "C0000000001" });
    try std.testing.expect(!Key.eql(first.key(), second.key()));
    try std.testing.expectEqual(std.math.Order.lt, order(first.key(), second.key()));
    try std.testing.expect(Key.eql(first.key(), first.key()));
}

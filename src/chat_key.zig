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

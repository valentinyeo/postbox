const std = @import("std");

pub fn linkedJid(value: std.json.Value) ?[]const u8 {
    const holder = switch (value) {
        .object => |object| object.get("data") orelse value,
        else => return null,
    };
    const object = switch (holder) {
        .object => |object| object,
        else => return null,
    };
    return switch (object.get("linked_jid") orelse return null) {
        .string => |jid| jid,
        else => null,
    };
}

test "linked jid parses both the flat and the data-wrapped auth status shape" {
    const wrapped = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"success":true,"data":{"authenticated":true,"linked_jid":"1234@s.whatsapp.net"}}
    , .{});
    defer wrapped.deinit();
    try std.testing.expectEqualStrings("1234@s.whatsapp.net", linkedJid(wrapped.value).?);

    const flat = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"linked_jid":"5678@s.whatsapp.net"}
    , .{});
    defer flat.deinit();
    try std.testing.expectEqualStrings("5678@s.whatsapp.net", linkedJid(flat.value).?);

    const unlinked = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"success":true,"data":{"authenticated":false}}
    , .{});
    defer unlinked.deinit();
    try std.testing.expect(linkedJid(unlinked.value) == null);
}

pub fn unauthenticated(value: std.json.Value) ?bool {
    const holder = switch (value) {
        .object => |object| object.get("data") orelse value,
        else => return null,
    };
    const object = switch (holder) {
        .object => |object| object,
        else => return null,
    };
    return switch (object.get("authenticated") orelse return null) {
        .bool => |authenticated| !authenticated,
        else => null,
    };
}

pub fn syncLineLoggedOut(allocator: std.mem.Allocator, line: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch return false;
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |object| object,
        else => return false,
    };
    const event = switch (object.get("event") orelse return false) {
        .string => |text| text,
        else => return false,
    };
    if (std.mem.eql(u8, event, "logged_out")) return true;
    if (!std.mem.eql(u8, event, "error")) return false;
    const data = switch (object.get("data") orelse return false) {
        .object => |data| data,
        else => return false,
    };
    const message = switch (data.get("message") orelse return false) {
        .string => |text| text,
        else => return false,
    };
    return std.mem.indexOf(u8, message, "not authenticated") != null;
}

test "auth status reports unauthenticated only on an explicit false" {
    const cases = [_]struct { json: []const u8, want: ?bool }{
        .{ .json = "{\"success\":true,\"data\":{\"authenticated\":false},\"error\":null}", .want = true },
        .{ .json = "{\"authenticated\":false}", .want = true },
        .{ .json = "{\"success\":true,\"data\":{\"authenticated\":true,\"linked_jid\":\"1@s.whatsapp.net\"}}", .want = false },
        .{ .json = "{\"success\":false,\"error\":\"store locked\"}", .want = null },
        .{ .json = "{\"data\":{\"authenticated\":\"no\"}}", .want = null },
        .{ .json = "[]", .want = null },
    };
    for (cases) |case| {
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, case.json, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(case.want, unauthenticated(parsed.value));
    }
}

test "sync lines that mean the WhatsApp session is gone" {
    try std.testing.expect(syncLineLoggedOut(std.testing.allocator,
        \\{"event":"error","data":{"message":"not authenticated; run `wacli auth`"},"ts":1790506466370}
    ));
    try std.testing.expect(syncLineLoggedOut(std.testing.allocator,
        \\{"event":"logged_out","data":{"reason":"401: logged out from another device"},"ts":1}
    ));
    try std.testing.expect(!syncLineLoggedOut(std.testing.allocator,
        \\{"event":"error","data":{"message":"429 rate-overlimit"},"ts":1}
    ));
    try std.testing.expect(!syncLineLoggedOut(std.testing.allocator,
        \\{"event":"error","data":{"message":"store is locked by another wacli process"},"ts":1}
    ));
    try std.testing.expect(!syncLineLoggedOut(std.testing.allocator,
        \\{"event":"connected","data":{},"ts":1}
    ));
    try std.testing.expect(!syncLineLoggedOut(std.testing.allocator,
        \\{"event":"message","data":{"text":"{\"event\":\"logged_out\"} not authenticated"},"ts":1}
    ));
    try std.testing.expect(!syncLineLoggedOut(std.testing.allocator, "warning: not authenticated"));
}

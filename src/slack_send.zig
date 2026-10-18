const std = @import("std");

pub const Decision = union(enum) { retry: u64, give_up };

pub fn retryDecision(error_name: []const u8, http_status: u32, slack_error: []const u8, attempts: u8) Decision {
    for ([_][]const u8{ "ReadFailed", "BadArguments", "UploadNotSupported" }) |permanent| {
        if (std.mem.eql(u8, error_name, permanent)) return .give_up;
    }
    for ([_][]const u8{ "invalid_auth", "not_authed", "account_inactive", "token_revoked", "not_in_channel", "channel_not_found", "is_archived", "file_too_large", "msg_too_long", "no_text", "restricted_action" }) |permanent| {
        if (std.mem.eql(u8, slack_error, permanent)) return .give_up;
    }
    if (http_status >= 400 and http_status < 500 and http_status != 429) return .give_up;
    var transient = http_status == 0 or http_status == 429 or (http_status >= 500 and http_status <= 599);
    for ([_][]const u8{ "HttpFailed", "Timeout", "TimedOut", "ConnectionTimedOut", "ConnectionResetByPeer", "ConnectionRefused", "ConnectionFailed", "ConnectionReset", "ConnectionClosed", "TimeoutFailed", "NetworkFailed", "ConnectionAborted", "NetworkUnreachable", "HostUnreachable" }) |name| {
        if (std.mem.eql(u8, error_name, name)) transient = true;
    }
    for ([_][]const u8{ "ratelimited", "internal_error", "service_unavailable", "request_timeout", "fatal_error" }) |name| {
        if (std.mem.eql(u8, slack_error, name)) transient = true;
    }
    if (!transient) return .give_up;
    return switch (attempts) {
        1 => .{ .retry = 3_000 },
        2 => .{ .retry = 10_000 },
        3 => .{ .retry = 30_000 },
        else => .give_up,
    };
}

pub const ShareCheck = enum { shared, not_shared, missing, unknown };

pub fn sharedIn(allocator: std.mem.Allocator, files_info_body: []const u8, channel: []const u8) ShareCheck {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, files_info_body, .{}) catch return .unknown;
    defer parsed.deinit();
    const root = switch (parsed.value) {
        .object => |object| object,
        else => return .unknown,
    };
    const ok = root.get("ok") orelse return .unknown;
    if (ok != .bool) return .unknown;
    if (!ok.bool) {
        const err = root.get("error") orelse return .unknown;
        if (err == .string and (std.mem.eql(u8, err.string, "file_not_found") or std.mem.eql(u8, err.string, "file_deleted"))) return .missing;
        return .unknown;
    }
    const file = root.get("file") orelse return .unknown;
    if (file != .object) return .unknown;
    for ([_][]const u8{ "channels", "groups", "ims" }) |key| {
        if (file.object.get(key)) |ids| {
            if (ids != .array) return .unknown;
            for (ids.array.items) |id| {
                if (id != .string) return .unknown;
                if (std.mem.eql(u8, id.string, channel)) return .shared;
            }
        }
    }
    if (file.object.get("shares")) |shares| {
        if (shares != .object) return .unknown;
        for ([_][]const u8{ "public", "private" }) |key| {
            if (shares.object.get(key)) |channels| {
                if (channels != .object) return .unknown;
                if (channels.object.contains(channel)) return .shared;
            }
        }
    }
    return .not_shared;
}

test "transient failure retries then gives up" {
    for ([_]u32{ 0, 429, 500, 503, 599 }) |status| {
        for ([_]u64{ 3_000, 10_000, 30_000 }, 1..) |delay, attempt| {
            const decision = retryDecision("SlackRejected", status, "", @intCast(attempt));
            try std.testing.expectEqual(delay, decision.retry);
        }
        try std.testing.expectEqual(Decision.give_up, retryDecision("SlackRejected", status, "", 4));
    }
    for ([_][]const u8{ "HttpFailed", "TimedOut", "Timeout", "ConnectionTimedOut", "ConnectionResetByPeer", "NetworkFailed", "ConnectionRefused", "ConnectionFailed", "ConnectionReset", "ConnectionClosed", "TimeoutFailed", "ConnectionAborted", "NetworkUnreachable", "HostUnreachable" }) |name| {
        try std.testing.expectEqual(@as(u64, 3_000), retryDecision(name, 200, "", 1).retry);
    }
    for ([_][]const u8{ "ratelimited", "internal_error", "service_unavailable", "request_timeout", "fatal_error" }) |name| {
        try std.testing.expectEqual(@as(u64, 3_000), retryDecision("SlackRejected", 200, name, 1).retry);
    }
}

test "permanent failure gives up at once" {
    for ([_][]const u8{ "invalid_auth", "not_authed", "account_inactive", "token_revoked", "not_in_channel", "channel_not_found", "is_archived", "file_too_large", "msg_too_long", "no_text", "restricted_action" }) |name| {
        try std.testing.expectEqual(Decision.give_up, retryDecision("SlackRejected", 200, name, 1));
        try std.testing.expectEqual(Decision.give_up, retryDecision("HttpFailed", 0, name, 1));
    }
    try std.testing.expectEqual(Decision.give_up, retryDecision("ReadFailed", 0, "", 1));
    for ([_]u32{ 400, 401, 403, 404, 413, 499 }) |status| {
        try std.testing.expectEqual(Decision.give_up, retryDecision("HttpFailed", status, "", 1));
    }
    try std.testing.expectEqual(Decision.give_up, retryDecision("SlackRejected", 200, "unexpected_error", 1));
}

test "files.info share in channel counts as done" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        "{\"ok\":true,\"file\":{\"id\":\"F01234567\",\"channels\":[\"C01234567\"],\"groups\":[],\"ims\":[]}}",
        "{\"ok\":true,\"file\":{\"id\":\"F01234567\",\"channels\":[],\"groups\":[\"C01234567\"],\"ims\":[]}}",
        "{\"ok\":true,\"file\":{\"id\":\"F01234567\",\"ims\":[\"C01234567\"]}}",
        "{\"ok\":true,\"file\":{\"id\":\"F01234567\",\"shares\":{\"public\":{\"C01234567\":[{\"ts\":\"1700000000.000100\"}]}}}}",
        "{\"ok\":true,\"file\":{\"id\":\"F01234567\",\"shares\":{\"private\":{\"C01234567\":[{\"ts\":\"1700000000.000100\"}]}}}}",
    }) |body| {
        try std.testing.expectEqual(ShareCheck.shared, sharedIn(allocator, body, "C01234567"));
        try std.testing.expectEqual(ShareCheck.not_shared, sharedIn(allocator, body, "C99999999"));
    }
}

test "files.info missing unshared and malformed responses" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(ShareCheck.missing, sharedIn(allocator, "{\"ok\":false,\"error\":\"file_not_found\"}", "C01234567"));
    try std.testing.expectEqual(ShareCheck.missing, sharedIn(allocator, "{\"ok\":false,\"error\":\"file_deleted\"}", "C01234567"));
    try std.testing.expectEqual(ShareCheck.not_shared, sharedIn(allocator, "{\"ok\":true,\"file\":{\"id\":\"F01234567\",\"channels\":[],\"shares\":{}}}", "C01234567"));
    for ([_][]const u8{ "not json", "{}", "[]", "{\"ok\":true}", "{\"ok\":false,\"error\":\"internal_error\"}", "{\"ok\":true,\"file\":null}", "{\"ok\":true,\"file\":{\"channels\":null}}" }) |body| {
        try std.testing.expectEqual(ShareCheck.unknown, sharedIn(allocator, body, "C01234567"));
    }
}

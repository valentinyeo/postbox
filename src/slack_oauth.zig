const std = @import("std");

pub const redirect_uri = "http://localhost:53682/slack/oauth/callback";
pub const user_scopes = "channels:read,channels:history,groups:read,groups:history,im:read,im:history,mpim:read,mpim:history,users:read,chat:write,files:read,files:write,reactions:read,channels:write,groups:write,im:write,mpim:write";
const authorize_endpoint = "https://slack.com/oauth/v2/authorize";
const Sha256 = std.crypto.hash.sha2.Sha256;
const base64 = std.base64.url_safe_no_pad.Encoder;

pub const Attempt = struct {
    state: [43]u8,
    code_verifier: [43]u8,
    code_challenge: [43]u8,
};

pub fn generate(io: std.Io) !Attempt {
    var entropy: [64]u8 = undefined;
    try io.randomSecure(&entropy);
    var attempt: Attempt = undefined;
    _ = base64.encode(&attempt.state, entropy[0..32]);
    _ = base64.encode(&attempt.code_verifier, entropy[32..]);
    attempt.code_challenge = try challenge(&attempt.code_verifier);
    return attempt;
}

fn unreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~';
}

pub fn challenge(verifier: []const u8) ![43]u8 {
    if (verifier.len < 43 or verifier.len > 128) return error.InvalidVerifier;
    for (verifier) |c| if (!unreserved(c)) return error.InvalidVerifier;
    var digest: [32]u8 = undefined;
    Sha256.hash(verifier, &digest, .{});
    var result: [43]u8 = undefined;
    _ = base64.encode(&result, &digest);
    return result;
}

fn form(allocator: std.mem.Allocator, fields: []const struct { []const u8, []const u8 }) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    const hex = "0123456789ABCDEF";
    for (fields, 0..) |field, index| {
        if (index != 0) try out.append(allocator, '&');
        try out.appendSlice(allocator, field[0]);
        try out.append(allocator, '=');
        for (field[1]) |c| {
            if (unreserved(c)) {
                try out.append(allocator, c);
            } else {
                try out.appendSlice(allocator, &.{ '%', hex[c >> 4], hex[c & 15] });
            }
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn buildAuthorizeUrl(allocator: std.mem.Allocator, client_id: []const u8, attempt: Attempt) ![]u8 {
    const query = try form(allocator, &.{
        .{ "client_id", client_id },
        .{ "user_scope", user_scopes },
        .{ "redirect_uri", redirect_uri },
        .{ "state", &attempt.state },
        .{ "code_challenge", &attempt.code_challenge },
        .{ "code_challenge_method", "S256" },
    });
    defer allocator.free(query);
    return std.fmt.allocPrint(allocator, "{s}?{s}", .{ authorize_endpoint, query });
}

pub fn buildAccessBody(allocator: std.mem.Allocator, client_id: []const u8, code: []const u8, verifier: []const u8) ![]u8 {
    _ = try challenge(verifier);
    return form(allocator, &.{
        .{ "client_id", client_id },
        .{ "code", code },
        .{ "code_verifier", verifier },
        .{ "redirect_uri", redirect_uri },
        .{ "grant_type", "authorization_code" },
    });
}

pub fn buildRefreshBody(allocator: std.mem.Allocator, client_id: []const u8, refresh_token: []const u8) ![]u8 {
    return form(allocator, &.{ .{ "grant_type", "refresh_token" }, .{ "client_id", client_id }, .{ "refresh_token", refresh_token } });
}

fn decode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < encoded.len) : (i += 1) {
        var c = encoded[i];
        if (c == '%') {
            if (i + 2 >= encoded.len) return error.InvalidCallback;
            c = std.fmt.parseInt(u8, encoded[i + 1 ..][0..2], 16) catch return error.InvalidCallback;
            i += 2;
        } else if (c == '+') c = ' ';
        if (c < 0x20 or c == 0x7f) return error.InvalidCallback;
        try out.append(allocator, c);
    }
    return out.toOwnedSlice(allocator);
}

pub fn parseCallback(allocator: std.mem.Allocator, request_line: []const u8, expected_state: []const u8) ![]u8 {
    const line = if (std.mem.endsWith(u8, request_line, "\r\n")) request_line[0 .. request_line.len - 2] else request_line;
    var parts = std.mem.splitScalar(u8, line, ' ');
    if (!std.mem.eql(u8, parts.next() orelse "", "GET")) return error.InvalidCallback;
    const target = parts.next() orelse return error.InvalidCallback;
    const version = parts.next() orelse return error.InvalidCallback;
    if ((!std.mem.eql(u8, version, "HTTP/1.1") and !std.mem.eql(u8, version, "HTTP/1.0")) or parts.next() != null) return error.InvalidCallback;
    const prefix = "/slack/oauth/callback?";
    if (!std.mem.startsWith(u8, target, prefix) or std.mem.indexOfScalar(u8, target, '#') != null) return error.InvalidCallback;
    var code: ?[]u8 = null;
    defer if (code) |value| allocator.free(value);
    var state: ?[]u8 = null;
    defer if (state) |value| allocator.free(value);
    var oauth_error: ?[]u8 = null;
    defer if (oauth_error) |value| allocator.free(value);
    var query = std.mem.splitScalar(u8, target[prefix.len..], '&');
    while (query.next()) |field| {
        const eq = std.mem.indexOfScalar(u8, field, '=') orelse return error.InvalidCallback;
        const key = try decode(allocator, field[0..eq]);
        defer allocator.free(key);
        const slot = if (std.mem.eql(u8, key, "code")) &code else if (std.mem.eql(u8, key, "state")) &state else if (std.mem.eql(u8, key, "error")) &oauth_error else null;
        if (slot) |value| {
            if (value.* != null) return error.InvalidCallback;
            value.* = try decode(allocator, field[eq + 1 ..]);
        }
    }
    const received_state = state orelse return error.StateMismatch;
    if (expected_state.len == 0 or received_state.len == 0) return error.StateMismatch;
    var expected_hash: [32]u8 = undefined;
    var received_hash: [32]u8 = undefined;
    Sha256.hash(expected_state, &expected_hash, .{});
    Sha256.hash(received_state, &received_hash, .{});
    if (!std.crypto.timing_safe.eql([32]u8, expected_hash, received_hash)) return error.StateMismatch;
    if (oauth_error) |value| {
        if (code != null) return error.InvalidCallback;
        if (std.mem.eql(u8, value, "access_denied")) return error.AccessDenied;
        return error.AuthorizationFailed;
    }
    const result = code orelse return error.InvalidCallback;
    if (result.len == 0) return error.InvalidCallback;
    code = null;
    return result;
}

pub const TokenResponse = struct {
    team_id: []const u8,
    team_name: []const u8,
    user_id: []const u8,
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: u64,
    scope: []const u8,
};

fn string(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.InvalidResponse;
    if (value != .string or value.string.len == 0) return error.InvalidResponse;
    return value.string;
}

pub fn parseResponse(arena: std.mem.Allocator, body: []const u8) !TokenResponse {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{ .allocate = .alloc_always }) catch return error.InvalidResponse;
    if (root != .object) return error.InvalidResponse;
    const ok = root.object.get("ok") orelse return error.InvalidResponse;
    if (ok != .bool) return error.InvalidResponse;
    if (!ok.bool) return error.OAuthFailed;
    const team = root.object.get("team") orelse return error.InvalidResponse;
    const user = root.object.get("authed_user") orelse return error.InvalidResponse;
    if (team != .object or user != .object) return error.InvalidResponse;
    const expires = user.object.get("expires_in") orelse std.json.Value{ .integer = 0 };
    if (expires != .integer or expires.integer < 0) return error.InvalidResponse;
    return .{
        .team_id = try string(team.object, "id"),
        .team_name = try string(team.object, "name"),
        .user_id = try string(user.object, "id"),
        .access_token = try string(user.object, "access_token"),
        .refresh_token = if (user.object.contains("refresh_token")) try string(user.object, "refresh_token") else "",
        .expires_in = @intCast(expires.integer),
        .scope = try string(user.object, "scope"),
    };
}

test "RFC 7636 S256 vector and verifier bounds" {
    const result = try challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk");
    try std.testing.expectEqualStrings("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", &result);
    try std.testing.expectError(error.InvalidVerifier, challenge("short"));
    try std.testing.expectError(error.InvalidVerifier, challenge(&(@as([129]u8, @splat('a')))));
    try std.testing.expectError(error.InvalidVerifier, challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjX!"));
    _ = try challenge(&(@as([128]u8, @splat('~'))));
}

test "secure independent state and verifier produce a user-only authorize URL" {
    const a = try generate(std.testing.io);
    const b = try generate(std.testing.io);
    try std.testing.expect(!std.mem.eql(u8, &a.state, &b.state));
    try std.testing.expect(!std.mem.eql(u8, &a.state, &a.code_verifier));
    for (a.code_verifier ++ a.state) |c| try std.testing.expect(unreserved(c));
    try std.testing.expectEqualSlices(u8, &try challenge(&a.code_verifier), &a.code_challenge);
    const url = try buildAuthorizeUrl(std.testing.allocator, "client&= +", a);
    defer std.testing.allocator.free(url);
    try std.testing.expect(std.mem.startsWith(u8, url, authorize_endpoint ++ "?client_id=client%26%3D%20%2B&user_scope=channels%3Aread%2C"));
    try std.testing.expect(std.mem.indexOf(u8, url, "&scope=") == null);
    try std.testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2Flocalhost%3A53682%2Fslack%2Foauth%2Fcallback") != null);
    try std.testing.expect(std.mem.endsWith(u8, url, "&code_challenge_method=S256"));
}

test "callback validates state before accepting code or denial and rejects ambiguity" {
    const a = std.testing.allocator;
    const code = try parseCallback(a, "GET /slack/oauth/callback?code=a%2B%26%3D+z&state=s%2B HTTP/1.1\r\n", "s+");
    defer a.free(code);
    try std.testing.expectEqualStrings("a+&= z", code);
    try std.testing.expectError(error.StateMismatch, parseCallback(a, "GET /slack/oauth/callback?code=x&state=bad HTTP/1.1", "good"));
    try std.testing.expectError(error.StateMismatch, parseCallback(a, "GET /slack/oauth/callback?error=access_denied&state=bad HTTP/1.1", "good"));
    try std.testing.expectError(error.AccessDenied, parseCallback(a, "GET /slack/oauth/callback?error=access_denied&state=s HTTP/1.1", "s"));
    try std.testing.expectError(error.AuthorizationFailed, parseCallback(a, "GET /slack/oauth/callback?error=other&state=s HTTP/1.1", "s"));
    for ([_][]const u8{
        "POST /slack/oauth/callback?code=x&state=s HTTP/1.1",
        "GET /other?code=x&state=s HTTP/1.1",
        "GET /slack/oauth/callback?code=x&state=s&%73tate=s HTTP/1.1",
        "GET /slack/oauth/callback?code=x&code=y&state=s HTTP/1.1",
        "GET /slack/oauth/callback?code=%ZZ&state=s HTTP/1.1",
        "GET /slack/oauth/callback?code=%00&state=s HTTP/1.1",
        "GET /slack/oauth/callback?code=x&state=s#ignored HTTP/1.1",
        "GET /slack/oauth/callback?state=s HTTP/1.1",
        "GET /slack/oauth/callback?code=&state=s HTTP/1.1",
        "GET /slack/oauth/callback?code=x&error=access_denied&state=s HTTP/1.1",
        "GET /slack/oauth/callback?code=x&state=s HTTP/1.1 extra",
    }) |line| try std.testing.expectError(error.InvalidCallback, parseCallback(a, line, "s"));
    try std.testing.expectError(error.StateMismatch, parseCallback(a, "GET /slack/oauth/callback?code=x HTTP/1.1", "s"));
}

test "access and refresh forms escape reserved characters without a client secret" {
    const a = std.testing.allocator;
    const verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    const access = try buildAccessBody(a, "client&", "code=+", verifier);
    defer a.free(access);
    try std.testing.expectEqualStrings("client_id=client%26&code=code%3D%2B&code_verifier=" ++ verifier ++ "&redirect_uri=http%3A%2F%2Flocalhost%3A53682%2Fslack%2Foauth%2Fcallback&grant_type=authorization_code", access);
    const refresh = try buildRefreshBody(a, "client&", "refresh+/=");
    defer a.free(refresh);
    try std.testing.expectEqualStrings("grant_type=refresh_token&client_id=client%26&refresh_token=refresh%2B%2F%3D", refresh);
}

test "response selects the authorized user token rather than the bot token" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const response = try parseResponse(arena.allocator(),
        \\{"ok":true,"team":{"id":"T0000000001","name":"Example"},"access_token":"bot-fixture","authed_user":{"id":"U0000000001","access_token":"user-fixture","refresh_token":"refresh-fixture","expires_in":3600,"scope":"chat:write"}}
    );
    try std.testing.expectEqualStrings("T0000000001", response.team_id);
    try std.testing.expectEqualStrings("Example", response.team_name);
    try std.testing.expectEqualStrings("U0000000001", response.user_id);
    try std.testing.expectEqualStrings("user-fixture", response.access_token);
    try std.testing.expectEqualStrings("refresh-fixture", response.refresh_token);
    try std.testing.expectEqual(@as(u64, 3600), response.expires_in);
    try std.testing.expectEqualStrings("chat:write", response.scope);
    try std.testing.expectError(error.OAuthFailed, parseResponse(arena.allocator(), "{\"ok\":false,\"error\":\"invalid_code\"}"));
    for ([_][]const u8{
        "{}", "[]", "not json", "{\"ok\":true,\"access_token\":\"bot-fixture\"}",
        \\{"ok":true,"team":{"id":"T0000000001","name":"Example"},"access_token":"bot-fixture"}
        ,
        \\{"ok":true,"team":{"id":"T0000000001","name":"Example"},"authed_user":null}
        ,
        \\{"ok":true,"team":{"id":"T0000000001","name":"Example"},"authed_user":{"id":"U0000000001"}}
        ,
        \\{"ok":true,"team":{"id":"T0000000001","name":"Example"},"authed_user":{"id":"U0000000001","access_token":"user-fixture","scope":"chat:write","expires_in":-1}}
        ,
    }) |body| try std.testing.expectError(error.InvalidResponse, parseResponse(arena.allocator(), body));
}

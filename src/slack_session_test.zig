const std = @import("std");
const builtin = @import("builtin");
const slack = @import("slack.zig");
const session = @import("slack_session.zig");
const transport = @import("slack_win.zig");
const win = if (builtin.os.tag == .windows) @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
}) else struct {};

fn registryHandle(address: usize) win.HKEY {
    @setRuntimeSafety(false);
    return @ptrFromInt(address);
}

fn context() !transport.JobContext {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const port = try std.process.Environ.getAlloc(std.testing.environ, std.testing.allocator, "WAZIG_VERIFY_SLACK_PORT");
    defer std.testing.allocator.free(port);
    transport.verification_port = try std.fmt.parseInt(u16, port, 10);
    return .{ .host = "slack.com", .user_token = "xoxc-fake-session-token", .cookie = "xoxd-fake-shared-cookie", .is_bridge = false, .media_dir = "", .io = std.testing.io };
}

fn object(a: std.mem.Allocator, raw: []const u8) !std.json.ObjectMap {
    const root = try std.json.parseFromSliceLeaky(std.json.Value, a, raw, .{});
    try std.testing.expect(root == .object);
    return root.object;
}

test "IGSH-464 session list uses form token and Cookie header through WinHTTP" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = try transport.runJob(a, try context(), .workspace, &.{});
    try std.testing.expect(slack.responseIsOk(a, raw));
    const root = try object(a, raw);
    const channel = slack.workspaceChannel(root.get("channels").?.array.items[0].object).?;
    try std.testing.expectEqualStrings("CFAKE001", channel.id);
    try std.testing.expectEqualStrings("fake-slack-chat", channel.name);
    const users = try transport.runJob(a, try context(), .users, &.{});
    try std.testing.expect(slack.responseIsOk(a, users));
}

test "IGSH-464 session read history and replies reuse the shared worker" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]transport.JobKind{ .history, .replies }) |kind| {
        const raw = try transport.runJob(a, try context(), kind, &.{ "CFAKE001", "1700000000.000001" });
        try std.testing.expect(slack.responseIsOk(a, raw));
        const item = slack.readHistoryItem((try object(a, raw)).get("messages").?.array.items[0]).?;
        try std.testing.expectEqualStrings("Fake Slack history", item.text);
    }
    const marked = try transport.runJob(a, try context(), .mark, &.{ "CFAKE001", "1700000000.000001" });
    try std.testing.expect(slack.responseIsOk(a, marked));
}

test "IGSH-464 session send preserves text and client message id" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = try transport.runJob(a, try context(), .send_text, &.{ "CFAKE001", "Fake + & outgoing", "", "00000000-0000-4000-8000-000000000464" });
    try std.testing.expectEqualStrings("1700000001.000001", slack.parseSentTs(a, raw).?);
    const history = try transport.runJob(a, try context(), .history, &.{"CFAKE001"});
    const messages = (try object(a, history)).get("messages").?.array.items;
    var found = false;
    for (messages) |value| {
        if (std.mem.eql(u8, slack.objectStringField(value.object, "client_msg_id"), "00000000-0000-4000-8000-000000000464")) {
            try std.testing.expectEqualStrings("Fake + & outgoing", slack.objectStringField(value.object, "text"));
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "IGSH-464 session live receive over fake RTM socket sends Cookie without envelope ack" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ctx = try context();
    const raw = try transport.connectRtm(a, ctx.user_token, ctx.cookie);
    const endpoint = slack.parseWsUrl(a, raw).?;
    const socket = try transport.socketConnect(a, endpoint, ctx.cookie);
    defer transport.socketClose(socket);
    var stop: std.atomic.Value(bool) = .init(false);
    var buffer: [4096]u8 = undefined;
    const hello = try transport.socketReceive(socket, &buffer, &stop);
    try std.testing.expectEqualStrings("hello", slack.objectStringField(try object(a, hello), "type"));
    try transport.socketSend(a, socket, "{\"type\":\"ping\",\"id\":1}");
    const event = (try session.classifyRtm(a, try transport.socketReceive(socket, &buffer, &stop), "TFAKE001")).?;
    try std.testing.expectEqualStrings("Fake Slack incoming", event.text);
    try std.testing.expectEqualStrings("TFAKE001", event.team_id);
    try std.testing.expectEqualStrings("", event.envelope_id);
    const built = transport.buildEvent(event).?;
    defer transport.destroyEvent(built);
    try std.testing.expectEqualStrings("CFAKE001", built.channelSlice());
}

test "IGSH-464 session rejected auth requires sign-in without OAuth refresh" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ctx = try context();
    ctx.user_token = "xoxc-fake-rejected";
    try std.testing.expectError(error.SlackRejected, transport.runJob(a, ctx, .auth, &.{}));
    try std.testing.expectEqualStrings("invalid_auth", std.mem.sliceTo(&transport.last_error, 0));
    try std.testing.expectError(error.SignInRequired, transport.connectRtm(a, ctx.user_token, ctx.cookie));
    try std.testing.expect(transport.sessionRejected(a, "{\"ok\":false,\"error\":\"not_authed\"}"));
}

test "IGSH-464 session import file consumed and deleted with DPAPI workspace isolation" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const a = std.testing.allocator;
    const io = std.testing.io;
    const registry = std.unicode.utf8ToUtf16LeStringLiteral("Software\\WazigFakeSlackSessionTests");
    var key: win.HKEY = null;
    const hkcu = registryHandle(@bitCast(@as(isize, -2147483647)));
    try std.testing.expectEqual(@as(win.LSTATUS, 0), win.RegCreateKeyExW(hkcu, registry, 0, null, 0, win.KEY_ALL_ACCESS, null, &key, null));
    defer _ = win.RegDeleteTreeW(hkcu, registry);
    defer _ = win.RegCloseKey(key);
    try std.testing.expectEqual(@as(win.LSTATUS, 0), win.RegOverridePredefKey(hkcu, key));
    defer _ = win.RegOverridePredefKey(hkcu, null);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path_len = try tmp.dir.realPath(io, &path_buffer);
    const path = path_buffer[0..path_len];
    try tmp.dir.writeFile(io, .{ .sub_path = "slack-session-import.json", .data =
        \\{"xoxd":"xoxd-fake-shared-cookie","workspaces":{"TFAKE001":{"xoxc":"xoxc-fake-session-token","team":"Fake Workspace","url":"https://fake-workspace.invalid","user_id":"UFAKE001"},"TFAKE002":{"xoxc":"xoxc-fake-second-token","team":"Fake Second","url":"https://fake-second.invalid","user_id":"UFAKE002"}}}
    });
    try std.testing.expectEqual(transport.ImportResult.imported, transport.importSessions(a, io, path));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(io, "slack-session-import.json", .{}));
    for ([_][]const u8{ "TFAKE001", "TFAKE002" }) |team| {
        const saved = transport.loadInstallation(a, team).?;
        defer saved.deinit();
        try std.testing.expect(saved.value.mode == .session);
        try std.testing.expectEqualStrings("xoxd-fake-shared-cookie", saved.value.cookie);
        try std.testing.expectEqualStrings(if (std.mem.eql(u8, team, "TFAKE001")) "xoxc-fake-session-token" else "xoxc-fake-second-token", saved.value.user_token);
    }
    var value_type: win.DWORD = 0;
    var size: win.DWORD = 0;
    try std.testing.expectEqual(@as(win.LSTATUS, 0), win.RegGetValueW(hkcu, std.unicode.utf8ToUtf16LeStringLiteral("Software\\Messages"), std.unicode.utf8ToUtf16LeStringLiteral("SlackInstallation-TFAKE001"), win.RRF_RT_ANY, &value_type, null, &size));
    try std.testing.expectEqual(@as(win.DWORD, win.REG_BINARY), value_type);
    const encrypted = try a.alloc(u8, size);
    defer a.free(encrypted);
    try std.testing.expectEqual(@as(win.LSTATUS, 0), win.RegGetValueW(hkcu, std.unicode.utf8ToUtf16LeStringLiteral("Software\\Messages"), std.unicode.utf8ToUtf16LeStringLiteral("SlackInstallation-TFAKE001"), win.RRF_RT_REG_BINARY, null, encrypted.ptr, &size));
    try std.testing.expect(std.mem.indexOf(u8, encrypted, "xoxc-fake-session-token") == null);
    try std.testing.expect(std.mem.indexOf(u8, encrypted, "xoxd-fake-shared-cookie") == null);
    for ([_][]const u8{ "", "not json", "{}", "{\"xoxd\":\"xoxd-fake-cookie\",\"workspaces\":{}}" }) |invalid| {
        try tmp.dir.writeFile(io, .{ .sub_path = "slack-session-import.json", .data = invalid });
        try std.testing.expectEqual(transport.ImportResult.invalid, transport.importSessions(a, io, path));
        try std.testing.expectError(error.FileNotFound, tmp.dir.access(io, "slack-session-import.json", .{}));
    }
    try std.testing.expectEqual(transport.ImportResult.absent, transport.importSessions(a, io, path));
    try std.testing.expect(transport.saveInstallation(.{ .team_id = "TFAKE003", .team_name = "Fake OAuth Workspace", .user_id = "UFAKE003", .user_token = "xoxp-00000000000000000003" }));
    const oauth = transport.loadInstallation(a, "TFAKE003").?;
    defer oauth.deinit();
    try std.testing.expect(oauth.value.mode == .oauth and oauth.value.cookie.len == 0);
}

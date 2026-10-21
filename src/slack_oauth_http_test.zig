const std = @import("std");
const oauth = @import("slack_oauth.zig");
const slack_win = @import("slack_win.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2) return error.BadArguments;
    const port = try std.fmt.parseInt(u16, args[1], 10);
    const body = try oauth.buildRefreshBody(allocator, "desktop-fixture", "refresh-fixture-1");
    const response = try slack_win.exchangeOAuthAt(allocator, "127.0.0.1", port, false, body);
    const rotated = try oauth.parseRefreshResponse(allocator, response);
    if (!std.mem.eql(u8, rotated.access_token, "xoxe.xoxp-00000000000000000002") or
        !std.mem.eql(u8, rotated.refresh_token, "refresh-fixture-rotated") or rotated.expires_in != 3600) return error.BadRotation;
    const installation = slack_win.Installation{
        .team_id = "T0000000001",
        .team_name = "Example Workspace",
        .user_id = "U0000000001",
        .user_token = rotated.access_token,
        .refresh_token = rotated.refresh_token,
        .expires_at = 4600,
    };
    if (!slack_win.saveInstallation(installation)) return error.SaveFailed;
    defer slack_win.deleteInstallation(installation.team_id);
    const stored = slack_win.loadInstallation(allocator, installation.team_id) orelse return error.LoadFailed;
    defer stored.deinit();
    if (!std.mem.eql(u8, stored.value.user_token, rotated.access_token) or
        !std.mem.eql(u8, stored.value.refresh_token, rotated.refresh_token) or stored.value.expires_at != 4600) return error.BadStoredRotation;
    std.debug.print("SLACK_WINHTTP_OK refresh\n", .{});
}

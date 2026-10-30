const std = @import("std");
const outbox = @import("outbox.zig");
const unified_snapshot = @import("unified_snapshot.zig");
const win = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
});
const wa_hub = struct { const max_file_bytes = 64 * 1024 * 1024; };
const max_pending_sends = 32;
const verification_fixture = false;
const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    io: std.Io = std.testing.io,
    avatar_dir: []const u8,
    wa_bridge_url: []const u8 = "https://example.invalid",
    unified_snapshot_path: []const u8,
    unified_snapshot: ?*unified_snapshot.Snapshot = null,
    unified_candidate: ?*unified_snapshot.Snapshot = null,
    unified_write_fault: enum { none, open, write, flush, close, replace } = .none,
    unified_storage_blocked: bool = false,
    unified_imports_clean: bool = true,
    outbox_load_failed: bool = false,
};
fn refreshUnifiedViews(_: *App) void {}

fn sharedPath(a: *App, source_name: []const u8, entry: *const outbox.Entry) ![]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(source_name);
    h.update(&.{0});
    h.update(entry.idSlice());
    h.update(&.{0});
    h.update(entry.file.slice());
    var digest: [32]u8 = undefined;
    h.final(&digest);
    const token = std.fmt.bytesToHex(digest, .lower);
    const root = messagesDirPath(a, "unified-journal-v2/imports-files") orelse return error.MissingMessagesDirectory;
    defer a.allocator.free(root);
    return std.fs.path.join(a.allocator, &.{ root, &token, "payload" });
}

fn checkPaths(long_profile: bool) !void {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var path_buf: [2048]u8 = undefined;
    const path_len = try temp.dir.realPath(std.testing.io, &path_buf);
    var base = path_buf[0..path_len];
    if (std.mem.startsWith(u8, base, "\\\\?\\")) base = base[4..];
    const pad = [_]u8{'p'} ** 64;
    const messages = if (long_profile)
        try std.fs.path.join(std.testing.allocator, &.{ base, &pad, &pad, "Users", "Valentin", "AppData", "Local", "Messages" })
    else
        try std.fs.path.join(std.testing.allocator, &.{ base, "Users", "Valentin", "AppData", "Local", "Messages" });
    defer std.testing.allocator.free(messages);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, messages);
    const avatar = try std.fs.path.join(std.testing.allocator, &.{ messages, "avatars" });
    defer std.testing.allocator.free(avatar);
    const snapshot_path = try std.fs.path.join(std.testing.allocator, &.{ messages, "unified-journal-v2", "0123456789abcdef", "snapshot.v2" });
    defer std.testing.allocator.free(snapshot_path);
    const live = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(live);
    const candidate = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(candidate);
    live.* = .{};
    candidate.* = .{};
    live.backend.set("https://example.invalid:443");
    candidate.backend = live.backend;
    var app = App{ .avatar_dir = avatar, .unified_snapshot_path = snapshot_path, .unified_snapshot = live, .unified_candidate = candidate };
    try unifiedPrivateDirectory(&app, std.fs.path.dirname(snapshot_path).?);

    var filename: [230]u8 = @splat('x');
    @memcpy(filename[226..], ".png");
    const original = try std.fs.path.join(std.testing.allocator, &.{ messages, &filename });
    defer std.testing.allocator.free(original);
    try std.testing.expect(original.len > 260);
    const bytes = "private image payload";
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = original, .data = bytes });
    var entries = [_]outbox.Entry{.{}};
    entries[0].provider = .slack;
    entries[0].account.set("workspace-a");
    entries[0].jid.set("slack:workspace-a:channel");
    entries[0].text.set("caption");
    entries[0].file.set(original);
    try acceptUnifiedSends(&app, &entries, null);
    const accepted = &app.unified_snapshot.?.records[0];
    try std.testing.expectEqualStrings(&filename, accepted.wire_filename.slice());
    try std.testing.expectEqualStrings("payload", std.fs.path.basename(accepted.owned_file.slice()));
    const accepted_bytes = (try unifiedReadAttachment(&app, accepted.owned_file.slice())).?;
    defer app.allocator.free(accepted_bytes);
    try std.testing.expectEqualStrings(bytes, accepted_bytes);
    if (long_profile) try std.testing.expect(accepted.owned_file.len > 260);

    const tag = std.hash.Wyhash.hash(std.hash.Wyhash.hash(0, app.wa_bridge_url), "hub");
    const token_a = [_]u8{'a'} ** 32;
    const token_b = [_]u8{'b'} ** 32;
    const matching = try std.fmt.allocPrint(app.allocator, "hub-{x:0>16}-outbox.jsonl.{s}.pending", .{ tag, &token_a });
    defer app.allocator.free(matching);
    const foreign = try std.fmt.allocPrint(app.allocator, "hub-{x:0>16}-outbox.jsonl.{s}.pending", .{ @as(u64, 7), &token_a });
    defer app.allocator.free(foreign);
    const overflow = try std.fmt.allocPrint(app.allocator, "hub-{x:0>16}-outbox.jsonl.{s}.pending", .{ @as(u64, 7), &token_b });
    defer app.allocator.free(overflow);
    try std.testing.expect(unifiedSourceMatches(&app, matching));
    try std.testing.expect(!unifiedSourceMatches(&app, foreign));
    const imported = try unifiedImportRecord(&app, matching, &entries[0], true);
    try std.testing.expectEqualStrings(&filename, imported.wire_filename.slice());
    try std.testing.expect(unified_snapshot.sameIntent(accepted, &imported));
    try std.testing.expectEqualStrings("payload", std.fs.path.basename(imported.owned_file.slice()));
    const owned_bytes = (try unifiedReadAttachment(&app, imported.owned_file.slice())).?;
    defer app.allocator.free(owned_bytes);
    try std.testing.expectEqualStrings(bytes, owned_bytes);
    _ = try unifiedImportRecord(&app, foreign, &entries[0], false);
    _ = try unifiedImportRecord(&app, overflow, &entries[0], false);
    for ([_][]const u8{ matching, foreign, overflow }) |source| {
        const shared = try sharedPath(&app, source, &entries[0]);
        defer app.allocator.free(shared);
        const protected = (try unifiedReadAttachment(&app, shared)).?;
        defer app.allocator.free(protected);
        try std.testing.expectEqualStrings(bytes, protected);
        if (long_profile) try std.testing.expect(shared.len > 260);
    }
    const original_bytes = (try unifiedReadAttachment(&app, original)).?;
    defer app.allocator.free(original_bytes);
    try std.testing.expectEqualStrings(bytes, original_bytes);
    const persisted = (try unifiedReadAttachment(&app, snapshot_path)).?;
    defer app.allocator.free(persisted);
    const decoded = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(decoded);
    try unified_snapshot.decode(app.allocator, persisted, "https://example.invalid:443", decoded);
    try std.testing.expectEqualStrings(&filename, decoded.records[0].wire_filename.slice());
    try std.testing.expectEqualSlices(u8, &accepted.file_sha256, &decoded.records[0].file_sha256);
    try std.testing.expectEqual(@as(u64, bytes.len), decoded.records[0].file_bytes);
}

test "Windows private paths preserve normal profile imports and long filename" {
    try checkPaths(false);
}

test "Windows private paths preserve bytes beyond MAX_PATH" {
    try checkPaths(true);
}

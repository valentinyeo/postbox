const std = @import("std");
const unified_snapshot = @import("unified_snapshot.zig");
var verification_fixture = true;
var disk: [unified_snapshot.max_document_bytes]u8 = undefined;
var disk_len: usize = 0;
var temp: [unified_snapshot.max_document_bytes]u8 = undefined;
var temp_len: usize = 0;

const App = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    unified_snapshot: ?*unified_snapshot.Snapshot = null,
    unified_candidate: ?*unified_snapshot.Snapshot = null,
    unified_snapshot_path: []const u8 = "C:\\profile\\snapshot.v2",
    unified_write_fault: enum { none, open, write, flush, close, replace } = .none,
};

const win = struct {
    const DWORD = u32;
    const INVALID_HANDLE_VALUE: ?usize = 99;
    const GENERIC_WRITE = 1;
    const CREATE_ALWAYS = 2;
    const FILE_ATTRIBUTE_NORMAL = 0;
    const MOVEFILE_REPLACE_EXISTING = 1;
    const MOVEFILE_WRITE_THROUGH = 2;
    fn CreateFileW(_: [*:0]const u16, _: u32, _: u32, _: ?usize, _: u32, _: u32, _: ?usize) ?usize {
        temp_len = 0;
        return 1;
    }
    fn WriteFile(_: ?usize, data: [*]const u8, length: u32, written: *DWORD, _: ?usize) u32 {
        const n = @min(length, 17);
        @memcpy(temp[temp_len..][0..n], data[0..n]);
        temp_len += n;
        written.* = n;
        return 1;
    }
    fn FlushFileBuffers(_: ?usize) u32 { return 1; }
    fn CloseHandle(_: ?usize) u32 { return 1; }
    fn DeleteFileW(_: [*:0]const u16) u32 { return 1; }
    fn MoveFileExW(_: [*:0]const u16, _: [*:0]const u16, flags: u32) u32 {
        if (flags != (MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) return 0;
        @memcpy(disk[0..temp_len], temp[0..temp_len]);
        disk_len = temp_len;
        return 1;
    }
};

test "candidate becomes live only after checked replacement" {
    const live = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(live);
    const candidate = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(candidate);
    live.* = .{};
    candidate.* = .{};
    live.backend.set("https://example.invalid:443");
    candidate.backend = live.backend;
    const record = &candidate.records[0];
    record.entry.id = [_]u8{'a'} ** 32;
    record.entry.account.set("account");
    record.entry.jid.set("chat");
    record.entry.text.set("message");
    candidate.count = 1;
    var app = App{ .unified_snapshot = live, .unified_candidate = candidate };
    const original = "old snapshot";
    @memcpy(disk[0..original.len], original);
    disk_len = original.len;
    inline for (.{ .open, .write, .flush, .close, .replace }) |stage| {
        app.unified_write_fault = stage;
        try std.testing.expect(!saveUnifiedCandidate(&app));
        try std.testing.expect(app.unified_snapshot.? == live);
        try std.testing.expect(app.unified_candidate.? == candidate);
        try std.testing.expectEqualStrings(original, disk[0..disk_len]);
    }
    verification_fixture = false;
    app.unified_write_fault = .open;
    defer verification_fixture = true;
    try std.testing.expect(saveUnifiedCandidate(&app));
    try std.testing.expect(app.unified_snapshot.? == candidate);
    try std.testing.expect(app.unified_candidate.? == live);
    const decoded = try std.testing.allocator.create(unified_snapshot.Snapshot);
    defer std.testing.allocator.destroy(decoded);
    try unified_snapshot.decode(std.testing.allocator, disk[0..disk_len], live.backend.slice(), decoded);
    try std.testing.expectEqual(@as(usize, 1), decoded.count);
}

test "private Win32 paths are extended and normalize separators" {
    const path = try unifiedNativePath(std.testing.allocator, "C:/Users/Valentin/AppData/Local/Messages/unified-journal-v2/a/files/payload");
    defer std.testing.allocator.free(path);
    const decoded = try std.unicode.utf16LeToUtf8Alloc(std.testing.allocator, path);
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("\\\\?\\C:\\Users\\Valentin\\AppData\\Local\\Messages\\unified-journal-v2\\a\\files\\payload", decoded);
    try std.testing.expectError(error.UnsafeAttachmentPath, unifiedNativePath(std.testing.allocator, "relative/payload"));
}

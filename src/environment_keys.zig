const std = @import("std");

pub fn choose(registry_value: ?[]const u8, process_value: ?[]const u8) []const u8 {
    if (registry_value) |value| if (value.len > 0) return value;
    return process_value orelse "";
}

pub fn shouldRetry(failure: anyerror, retried: bool, previous: []const u8, saved: ?[]const u8) bool {
    if (failure != error.Unauthorized or retried) return false;
    const value = saved orelse return false;
    return value.len > 0 and !std.mem.eql(u8, previous, value);
}

fn registryHandle(value: usize) @import("win32.zig").c.HKEY {
    @setRuntimeSafety(false);
    return @ptrFromInt(value);
}

pub fn readUser(allocator: std.mem.Allocator, comptime name: []const u8) ?[]u8 {
    const win = @import("win32.zig").c;
    const hkcu = registryHandle(@bitCast(@as(isize, -2147483647)));
    const subkey = std.unicode.utf8ToUtf16LeStringLiteral("Environment");
    const value_name = std.unicode.utf8ToUtf16LeStringLiteral(name);
    const flags = win.RRF_RT_REG_SZ | win.RRF_RT_REG_EXPAND_SZ;
    var size: win.DWORD = 0;
    if (win.RegGetValueW(hkcu, subkey, value_name, flags, null, null, &size) != win.ERROR_SUCCESS or size < 2 or size > 64 * 1024) return null;
    const wide = allocator.alloc(u16, size / 2) catch return null;
    defer allocator.free(wide);
    if (win.RegGetValueW(hkcu, subkey, value_name, flags, null, wide.ptr, &size) != win.ERROR_SUCCESS) return null;
    const length = std.mem.indexOfScalar(u16, wide, 0) orelse return null;
    if (length == 0) return null;
    return std.unicode.utf16LeToUtf8Alloc(allocator, wide[0..length]) catch null;
}

pub fn load(allocator: std.mem.Allocator, comptime name: []const u8, process_value: ?[]const u8) ![]u8 {
    const saved = readUser(allocator, name);
    defer if (saved) |value| allocator.free(value);
    return allocator.dupe(u8, choose(saved, process_value));
}

test "ISSUE-517 saved user key wins over a stale inherited key" {
    try std.testing.expectEqualStrings("saved-value", choose("saved-value", "inherited-value"));
    try std.testing.expectEqualStrings("saved-value", choose("saved-value", null));
}

test "ISSUE-517 empty and missing user keys fall back to the process" {
    try std.testing.expectEqualStrings("inherited-value", choose("", "inherited-value"));
    try std.testing.expectEqualStrings("inherited-value", choose(null, "inherited-value"));
    try std.testing.expectEqualStrings("", choose(null, null));
    try std.testing.expectEqualStrings("", choose("", ""));
}

test "ISSUE-517 Unauthorized retries once only for a changed saved key" {
    try std.testing.expect(shouldRetry(error.Unauthorized, false, "previous-value", "saved-value"));
    try std.testing.expect(!shouldRetry(error.Unauthorized, true, "previous-value", "saved-value"));
    try std.testing.expect(!shouldRetry(error.Unauthorized, false, "saved-value", "saved-value"));
    try std.testing.expect(!shouldRetry(error.Unauthorized, false, "previous-value", ""));
    try std.testing.expect(!shouldRetry(error.Unauthorized, false, "previous-value", null));
    try std.testing.expect(!shouldRetry(error.NetworkFailed, false, "previous-value", "saved-value"));
}

test "ISSUE-517 saved user keys expand inside the overridden fixture registry" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const win = @import("win32.zig").c;
    const allocator = std.testing.allocator;
    const hkcu = registryHandle(@bitCast(@as(isize, -2147483647)));
    const fixture_path = std.unicode.utf8ToUtf16LeStringLiteral("Software\\MessagesKeyVerification");
    var fixture: win.HKEY = null;
    var disposition: win.DWORD = 0;
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegCreateKeyExW(hkcu, fixture_path, 0, null, 0, win.KEY_ALL_ACCESS, null, &fixture, &disposition));
    defer _ = win.RegCloseKey(fixture);
    try std.testing.expectEqual(win.REG_CREATED_NEW_KEY, disposition);
    defer _ = win.RegDeleteTreeW(hkcu, fixture_path);
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegOverridePredefKey(hkcu, fixture));
    defer _ = win.RegOverridePredefKey(hkcu, null);
    try std.testing.expect(readUser(allocator, "DEEPGRAM_API_KEY") == null);
    var environment: win.HKEY = null;
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegCreateKeyExW(hkcu, std.unicode.utf8ToUtf16LeStringLiteral("Environment"), 0, null, 0, win.KEY_ALL_ACCESS, null, &environment, null));
    defer _ = win.RegCloseKey(environment);
    const value_name = std.unicode.utf8ToUtf16LeStringLiteral("DEEPGRAM_API_KEY");
    const empty = std.unicode.utf8ToUtf16LeStringLiteral("");
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegSetValueExW(environment, value_name, 0, win.REG_SZ, @ptrCast(empty), 2));
    const fallback = try load(allocator, "DEEPGRAM_API_KEY", "inherited-value");
    defer allocator.free(fallback);
    try std.testing.expectEqualStrings("inherited-value", fallback);
    const variable = std.unicode.utf8ToUtf16LeStringLiteral("WAZIG_KEY_VERIFICATION_VALUE");
    try std.testing.expect(win.SetEnvironmentVariableW(variable, std.unicode.utf8ToUtf16LeStringLiteral("expanded-value")) != 0);
    defer _ = win.SetEnvironmentVariableW(variable, null);
    const expandable = std.unicode.utf8ToUtf16LeStringLiteral("%WAZIG_KEY_VERIFICATION_VALUE%");
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegSetValueExW(environment, value_name, 0, win.REG_EXPAND_SZ, @ptrCast(expandable), @sizeOf(@TypeOf(expandable.*))));
    const selected = try load(allocator, "DEEPGRAM_API_KEY", "inherited-value");
    defer allocator.free(selected);
    try std.testing.expectEqualStrings("expanded-value", selected);
}

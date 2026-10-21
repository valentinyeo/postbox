const std = @import("std");
const slack_win = @import("slack_win.zig");

pub fn choose(registry_value: ?[]const u8, process_value: ?[]const u8) []const u8 {
    if (registry_value) |value| if (value.len > 0) return value;
    return process_value orelse "";
}

fn registryHandle(value: usize) @import("win32.zig").c.HKEY {
    @setRuntimeSafety(false);
    return @ptrFromInt(value);
}

pub fn load(allocator: std.mem.Allocator, comptime name: []const u8, process_value: ?[]const u8) ![]u8 {
    const saved = slack_win.loadUserEnvironment(allocator, std.unicode.utf8ToUtf16LeStringLiteral(name));
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
    try std.testing.expect(disposition == win.REG_CREATED_NEW_KEY);
    defer _ = win.RegDeleteTreeW(hkcu, fixture_path);
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegOverridePredefKey(hkcu, fixture));
    defer _ = win.RegOverridePredefKey(hkcu, null);
    try std.testing.expect(slack_win.loadUserEnvironment(allocator, std.unicode.utf8ToUtf16LeStringLiteral("DEEPGRAM_API_KEY")) == null);
    const missing = try slack_win.loadDeepgramKey(allocator);
    defer allocator.free(missing.key);
    try std.testing.expectEqual(.none, missing.action);
    try std.testing.expectEqual(@as(usize, 0), missing.key.len);
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
    const seeded = try slack_win.loadDeepgramKey(allocator);
    defer allocator.free(seeded.key);
    try std.testing.expectEqual(.save, seeded.action);
    try std.testing.expect(seeded.seed_saved);
    try std.testing.expectEqualStrings("expanded-value", seeded.key);
    const replacement = std.unicode.utf8ToUtf16LeStringLiteral("replacement-value");
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegSetValueExW(environment, value_name, 0, win.REG_SZ, @ptrCast(replacement), @sizeOf(@TypeOf(replacement.*))));
    const refreshed = try slack_win.loadDeepgramKey(allocator);
    defer allocator.free(refreshed.key);
    try std.testing.expectEqual(.update, refreshed.action);
    try std.testing.expect(refreshed.seed_saved);
    try std.testing.expectEqualStrings("replacement-value", refreshed.key);
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegDeleteValueW(environment, value_name));
    const stored = try slack_win.loadDeepgramKey(allocator);
    defer allocator.free(stored.key);
    try std.testing.expectEqual(.load, stored.action);
    try std.testing.expectEqual(.encrypted, stored.stored_outcome.?);
    try std.testing.expectEqualStrings("replacement-value", stored.key);
    const openrouter_name = std.unicode.utf8ToUtf16LeStringLiteral("OPENROUTER_API_KEY");
    try std.testing.expectEqual(win.ERROR_SUCCESS, win.RegSetValueExW(environment, openrouter_name, 0, win.REG_SZ, @ptrCast(replacement), @sizeOf(@TypeOf(replacement.*))));
    const openrouter = try load(allocator, "OPENROUTER_API_KEY", "inherited-value");
    defer allocator.free(openrouter);
    try std.testing.expectEqualStrings("replacement-value", openrouter);
}

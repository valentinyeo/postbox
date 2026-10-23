const std = @import("std");

pub fn zipPrefixFor(arm64: bool) []const u8 {
    return if (arm64) "Messages_arm64-" else "Messages-";
}

pub const zip_asset_prefix = zipPrefixFor(@import("builtin").cpu.arch == .aarch64);

pub fn isZipAssetNameFor(name: []const u8, arm64: bool) bool {
    return std.mem.startsWith(u8, name, zipPrefixFor(arm64)) and std.mem.endsWith(u8, name, ".zip");
}

pub fn isZipAssetName(name: []const u8) bool {
    return isZipAssetNameFor(name, @import("builtin").cpu.arch == .aarch64);
}

test "channel pick: each CPU takes only its own zip" {
    try std.testing.expect(isZipAssetNameFor("Messages-0.9.92.zip", false));
    try std.testing.expect(!isZipAssetNameFor("Messages_arm64-0.9.92.zip", false));
    try std.testing.expect(isZipAssetNameFor("Messages_arm64-0.9.92.zip", true));
    try std.testing.expect(!isZipAssetNameFor("Messages-0.9.92.zip", true));
    try std.testing.expect(!isZipAssetNameFor("Messages-0.9.92.zip.sig", false));
}

pub fn effectiveCurrent(real: Version, fake_text: ?[]const u8) Version {
    const text = fake_text orelse return real;
    const fake = parseVersion(text) orelse return real;
    if (isNewerVersion(real, fake)) return fake;
    return real;
}

fn isNewerVersion(latest: Version, current: Version) bool {
    if (latest.major != current.major) return latest.major > current.major;
    if (latest.minor != current.minor) return latest.minor > current.minor;
    return latest.patch > current.patch;
}

test effectiveCurrent {
    const real = Version{ .major = 0, .minor = 9, .patch = 92 };
    try std.testing.expectEqual(real, effectiveCurrent(real, null));
    try std.testing.expectEqual(Version{ .major = 0, .minor = 0, .patch = 1 }, effectiveCurrent(real, "0.0.1"));
    try std.testing.expectEqual(real, effectiveCurrent(real, "9.9.9"));
    try std.testing.expectEqual(real, effectiveCurrent(real, "garbage"));
    try std.testing.expectEqual(real, effectiveCurrent(real, "v0.9.92"));
}

pub const StageMarker = struct { tag: []const u8, inner_root: []const u8 };

pub fn parseStageMarker(text: []const u8) ?StageMarker {
    var lines = std.mem.splitScalar(u8, text, '\n');
    const tag = std.mem.trimEnd(u8, lines.next() orelse return null, "\r");
    if (parseVersion(tag) == null) return null;
    const inner = std.mem.trimEnd(u8, lines.next() orelse "", "\r");
    return .{ .tag = tag, .inner_root = inner };
}

test parseStageMarker {
    const m = parseStageMarker("v0.9.92\nMessages\n").?;
    try std.testing.expectEqualStrings("v0.9.92", m.tag);
    try std.testing.expectEqualStrings("Messages", m.inner_root);
    try std.testing.expectEqualStrings("", parseStageMarker("v0.9.92\n\n").?.inner_root);
    try std.testing.expectEqualStrings("", parseStageMarker("v0.9.92").?.inner_root);
    try std.testing.expect(parseStageMarker("") == null);
    try std.testing.expect(parseStageMarker("junk\nx") == null);
}

pub fn percent(done: u64, total: u64) u32 {
    if (total == 0) return 0;
    return @intCast(@min(100, done * 100 / total));
}

test percent {
    try std.testing.expectEqual(@as(u32, 0), percent(5, 0));
    try std.testing.expectEqual(@as(u32, 50), percent(50, 100));
    try std.testing.expectEqual(@as(u32, 100), percent(300, 100));
}

pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
};

pub const Asset = struct {
    tag: []const u8,
    version: Version,
    url: []const u8,
    size: u64,
    digest: []const u8,
};

pub fn parseVersion(tag: []const u8) ?Version {
    var rest = tag;
    if (rest.len > 0 and rest[0] == 'v') rest = rest[1..];
    var parts: [3]u32 = undefined;
    var iter = std.mem.splitScalar(u8, rest, '.');
    for (&parts) |*part| {
        const chunk = iter.next() orelse return null;
        if (chunk.len == 0 or chunk.len > 9) return null;
        for (chunk) |c| if (c < '0' or c > '9') return null;
        part.* = std.fmt.parseInt(u32, chunk, 10) catch return null;
    }
    if (iter.next() != null) return null;
    return .{ .major = parts[0], .minor = parts[1], .patch = parts[2] };
}

pub fn isNewer(latest_tag: []const u8, current: Version) bool {
    const latest = parseVersion(latest_tag) orelse return false;
    if (latest.major != current.major) return latest.major > current.major;
    if (latest.minor != current.minor) return latest.minor > current.minor;
    return latest.patch > current.patch;
}

pub fn isNewOffer(pending_tag: ?[]const u8, found_tag: []const u8) bool {
    const pending = pending_tag orelse return true;
    return !std.mem.eql(u8, pending, found_tag);
}

test isNewOffer {
    try std.testing.expect(isNewOffer(null, "v0.9.44"));
    try std.testing.expect(isNewOffer("v0.9.43", "v0.9.44"));
    try std.testing.expect(!isNewOffer("v0.9.44", "v0.9.44"));
}

pub fn digestMatches(data: []const u8, digest_field: []const u8) bool {
    const prefix = "sha256:";
    if (digest_field.len != prefix.len + 64) return false;
    if (!std.mem.startsWith(u8, digest_field, prefix)) return false;
    var expected: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&expected, digest_field[prefix.len..]) catch return false;
    var actual: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &actual, .{});
    return std.crypto.timing_safe.eql([32]u8, expected, actual);
}

pub fn releaseBody(root: std.json.Value) []const u8 {
    if (root != .object) return "";
    const body = root.object.get("body") orelse return "";
    return if (body == .string) body.string else "";
}

test releaseBody {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"tag_name": "v1.0.0", "body": "Fixes and speed"}
    , .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Fixes and speed", releaseBody(parsed.value));
    const empty = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{}", .{});
    defer empty.deinit();
    try std.testing.expectEqualStrings("", releaseBody(empty.value));
}

pub const Release = struct {
    tag: []const u8,
    body: []const u8,
};

pub fn releaseFromValue(root: std.json.Value) ?Release {
    if (root != .object) return null;
    if (flagTrue(root.object.get("draft")) or flagTrue(root.object.get("prerelease"))) return null;
    const tag = root.object.get("tag_name") orelse return null;
    if (tag != .string or parseVersion(tag.string) == null) return null;
    return .{ .tag = tag.string, .body = releaseBody(root) };
}

pub const fallback_note = "Small fixes and speed improvements";

pub fn isCardLine(text: []const u8) bool {
    const length = std.unicode.utf8CountCodepoints(text) catch return false;
    if (length == 0 or length > 80) return false;
    if (std.mem.indexOf(u8, text, "://") != null or std.mem.indexOf(u8, text, "www.") != null) return false;
    for (text, 0..) |c, i| {
        if (c == '#' and i + 1 < text.len and std.ascii.isDigit(text[i + 1])) return false;
        if (c == '.' and i > 0 and i + 1 < text.len and std.ascii.isAlphanumeric(text[i - 1]) and std.ascii.isAlphabetic(text[i + 1])) return false;
        if (c == '-' and i > 0 and i + 1 < text.len and std.ascii.isDigit(text[i + 1])) {
            var start = i;
            while (start > 0 and std.ascii.isAlphanumeric(text[start - 1])) start -= 1;
            if (start < i and std.ascii.isAlphabetic(text[start])) return false;
        }
    }
    return true;
}

pub fn appendBodyLines(allocator: std.mem.Allocator, body: []const u8, lines: *std.ArrayList([]const u8)) !void {
    var iter = std.mem.splitScalar(u8, body, '\n');
    while (iter.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "- ")) continue;
        const text = std.mem.trim(u8, line[2..], " \t");
        if (isCardLine(text)) try lines.append(allocator, text);
    }
}

pub fn notesForReleases(allocator: std.mem.Allocator, releases: []const Release, current: Version, latest: Version) ![]u8 {
    const ordered = try allocator.dupe(Release, releases);
    defer allocator.free(ordered);
    std.mem.sort(Release, ordered, {}, struct {
        fn lessThan(_: void, a: Release, b: Release) bool {
            const av = parseVersion(a.tag) orelse return false;
            const bv = parseVersion(b.tag) orelse return true;
            return isNewerVersion(av, bv);
        }
    }.lessThan);
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);
    for (ordered) |release| {
        const version = parseVersion(release.tag) orelse continue;
        if (!isNewerVersion(version, current) or isNewerVersion(version, latest)) continue;
        try appendBodyLines(allocator, release.body, &lines);
    }
    if (lines.items.len == 0) try lines.append(allocator, fallback_note);
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    for (lines.items[0..@min(5, lines.items.len)], 0..) |line, i| {
        if (i > 0) try result.append(allocator, '\n');
        try result.appendSlice(allocator, "- ");
        try result.appendSlice(allocator, line);
    }
    if (lines.items.len > 5) {
        const more = try std.fmt.allocPrint(allocator, "\n+{d} more", .{lines.items.len - 5});
        defer allocator.free(more);
        try result.appendSlice(allocator, more);
    }
    return result.toOwnedSlice(allocator);
}

test "update notes combine skipped versions newest first and cap five changes" {
    const releases = [_]Release{
        .{ .tag = "v1.0.1", .body = "- Older change\n- Another change\n- Sixth change\n- Seventh change" },
        .{ .tag = "v1.0.0", .body = "- Already installed" },
        .{ .tag = "v1.0.2", .body = "- Newest change\n- Second change\n- Third change" },
        .{ .tag = "v1.0.3", .body = "- Not offered yet" },
    };
    const notes = try notesForReleases(std.testing.allocator, &releases, parseVersion("1.0.0").?, parseVersion("1.0.2").?);
    defer std.testing.allocator.free(notes);
    try std.testing.expectEqualStrings("- Newest change\n- Second change\n- Third change\n- Older change\n- Another change\n+2 more", notes);
}

test "update notes ignore developer bullets and handle empty bodies" {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(std.testing.allocator);
    try appendBodyLines(std.testing.allocator, "Heading\n- IGSH-715: inbox slots (#346)\n- Fix main.zig\n- See https://example.com\n- Alt+1 stays WhatsApp after you empty it\r\n", &lines);
    try std.testing.expectEqual(@as(usize, 1), lines.items.len);
    try std.testing.expectEqualStrings("Alt+1 stays WhatsApp after you empty it", lines.items[0]);
    const releases = [_]Release{.{ .tag = "v1.0.1", .body = "" }};
    const notes = try notesForReleases(std.testing.allocator, &releases, parseVersion("1.0.0").?, parseVersion("1.0.1").?);
    defer std.testing.allocator.free(notes);
    try std.testing.expectEqualStrings("- Small fixes and speed improvements", notes);
}

test "update notes with exactly five changes have no overflow line" {
    const releases = [_]Release{.{ .tag = "v1.0.1", .body = "- One\n- Two\n- Three\n- Four\n- Five" }};
    const notes = try notesForReleases(std.testing.allocator, &releases, parseVersion("1.0.0").?, parseVersion("1.0.1").?);
    defer std.testing.allocator.free(notes);
    try std.testing.expectEqualStrings(releases[0].body, notes);
}

test "release history excludes drafts prereleases and malformed versions" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\[null, {}, {"tag_name":"bad"}, {"tag_name":"v1.0.1","draft":true}, {"tag_name":"v1.0.1","prerelease":true}, {"tag_name":"v1.0.1","body":"- Chat search is faster"}]
    , .{});
    defer parsed.deinit();
    for (parsed.value.array.items[0..5]) |value| try std.testing.expect(releaseFromValue(value) == null);
    const release = releaseFromValue(parsed.value.array.items[5]).?;
    try std.testing.expectEqualStrings("v1.0.1", release.tag);
    try std.testing.expectEqualStrings("- Chat search is faster", release.body);
}

fn flagTrue(value: ?std.json.Value) bool {
    const v = value orelse return false;
    return v == .bool and v.bool;
}

pub fn pickAsset(
    allocator: std.mem.Allocator,
    json_text: []const u8,
    parsed: *std.json.Parsed(std.json.Value),
) !?Asset {
    parsed.* = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    return findAsset(parsed.value);
}

fn findAsset(root: std.json.Value) ?Asset {
    var matched: ?Asset = null;
    if (root != .object) return null;
    const obj = root.object;
    if (flagTrue(obj.get("draft")) or flagTrue(obj.get("prerelease"))) return null;
    const tag_value = obj.get("tag_name") orelse return null;
    if (tag_value != .string) return null;
    const tag = tag_value.string;
    const version = parseVersion(tag) orelse return null;
    const assets_value = obj.get("assets") orelse return null;
    if (assets_value != .array) return null;
    for (assets_value.array.items) |asset_value| {
        if (asset_value != .object) continue;
        const asset = asset_value.object;
        const name = asset.get("name") orelse continue;
        if (name != .string or !isZipAssetName(name.string)) continue;
        const url = asset.get("browser_download_url") orelse continue;
        if (url != .string) continue;
        const digest = asset.get("digest") orelse continue;
        if (digest != .string) continue;
        const size_value = asset.get("size") orelse continue;
        if (size_value != .integer) continue;
        if (size_value.integer < 0) continue;
        if (matched != null) return null;
        matched = .{
            .tag = tag,
            .version = version,
            .url = url.string,
            .size = @intCast(size_value.integer),
            .digest = digest.string,
        };
    }
    return matched;
}

test parseVersion {
    try std.testing.expectEqual(Version{ .major = 1, .minor = 2, .patch = 3 }, parseVersion("v1.2.3").?);
    try std.testing.expectEqual(Version{ .major = 0, .minor = 10, .patch = 0 }, parseVersion("0.10.0").?);
    try std.testing.expect(parseVersion("1.2") == null);
    try std.testing.expect(parseVersion("v1.2.3-rc1") == null);
    try std.testing.expect(parseVersion("v1.2.3+build") == null);
    try std.testing.expect(parseVersion("latest") == null);
    try std.testing.expect(parseVersion("v1.2.x") == null);
    try std.testing.expect(parseVersion("") == null);
    try std.testing.expect(parseVersion("v9999999999.0.0") == null);
}

test isNewer {
    const current: Version = .{ .major = 0, .minor = 1, .patch = 0 };
    try std.testing.expect(isNewer("v0.1.1", current));
    try std.testing.expect(isNewer("v0.2.0", current));
    try std.testing.expect(isNewer("v1.0.0", current));
    try std.testing.expect(!isNewer("v0.1.0", current));
    try std.testing.expect(!isNewer("v0.0.9", current));
    try std.testing.expect(!isNewer("v0.1.0-rc1", current));
    try std.testing.expect(!isNewer("garbage", current));
}

test digestMatches {
    var data: [11]u8 = "hello world".*;
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&data, &hash, .{});
    const hex = std.fmt.bytesToHex(hash, .lower);
    var field: [71]u8 = undefined;
    @memcpy(field[0..7], "sha256:");
    @memcpy(field[7..], &hex);
    try std.testing.expect(digestMatches(&data, &field));
    field[7] ^= 0xff;
    try std.testing.expect(!digestMatches(&data, &field));
    try std.testing.expect(!digestMatches(&data, "sha256:00"));
    try std.testing.expect(!digestMatches(&data, "md5:"));
}

test pickAsset {
    const body =
        \\{
        \\  "tag_name": "v0.2.0",
        \\  "draft": false,
        \\  "prerelease": false,
        \\  "assets": [
        \\    {
        \\      "name": "Messages-windows-x86_64.zip",
        \\      "browser_download_url": "https://github.com/valentinyeo/wazig/releases/download/v0.2.0/Messages-windows-x86_64.zip",
        \\      "size": 12345,
        \\      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        \\    }
        \\  ]
        \\}
    ;
    var parsed: std.json.Parsed(std.json.Value) = undefined;
    const asset = (try pickAsset(std.testing.allocator, body, &parsed)).?;
    defer parsed.deinit();
    try std.testing.expectEqualStrings("v0.2.0", asset.tag);
    try std.testing.expectEqual(12345, asset.size);
    try std.testing.expect(asset.url.len > 0);

    const draft =
        \\{
        \\  "tag_name": "v0.2.0",
        \\  "draft": false,
        \\  "prerelease": true,
        \\  "assets": [
        \\    {
        \\      "name": "Messages-windows-x86_64.zip",
        \\      "browser_download_url": "https://github.com/valentinyeo/wazig/releases/download/v0.2.0/Messages-windows-x86_64.zip",
        \\      "size": 12345,
        \\      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        \\    }
        \\  ]
        \\}
    ;
    var parsed2: std.json.Parsed(std.json.Value) = undefined;
    try std.testing.expectEqual(@as(?Asset, null), try pickAsset(std.testing.allocator, draft, &parsed2));
    parsed2.deinit();

    const no_digest =
        \\{
        \\  "tag_name": "v0.2.0",
        \\  "draft": false,
        \\  "prerelease": false,
        \\  "assets": [
        \\    {
        \\      "name": "Messages-windows-x86_64.zip",
        \\      "browser_download_url": "https://github.com/valentinyeo/wazig/releases/download/v0.2.0/Messages-windows-x86_64.zip",
        \\      "size": 12345
        \\    }
        \\  ]
        \\}
    ;
    var parsed3: std.json.Parsed(std.json.Value) = undefined;
    try std.testing.expectEqual(@as(?Asset, null), try pickAsset(std.testing.allocator, no_digest, &parsed3));
    parsed3.deinit();

    var parsed4: std.json.Parsed(std.json.Value) = undefined;
    try std.testing.expectError(error.SyntaxError, pickAsset(std.testing.allocator, "not json", &parsed4));
    var parsed5: std.json.Parsed(std.json.Value) = undefined;
    try std.testing.expectEqual(@as(?Asset, null), try pickAsset(std.testing.allocator, "{}", &parsed5));
    parsed5.deinit();

    const no_size =
        \\{
        \\  "tag_name": "v0.2.0",
        \\  "draft": false,
        \\  "prerelease": false,
        \\  "assets": [
        \\    {
        \\      "name": "Messages-windows-x86_64.zip",
        \\      "browser_download_url": "https://github.com/valentinyeo/wazig/releases/download/v0.2.0/Messages-windows-x86_64.zip",
        \\      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        \\    }
        \\  ]
        \\}
    ;
    var parsed6: std.json.Parsed(std.json.Value) = undefined;
    try std.testing.expectEqual(@as(?Asset, null), try pickAsset(std.testing.allocator, no_size, &parsed6));
    parsed6.deinit();

    const two_assets =
        \\{
        \\  "tag_name": "v0.2.0",
        \\  "draft": false,
        \\  "prerelease": false,
        \\  "assets": [
        \\    {
        \\      "name": "Messages-windows-x86_64.zip",
        \\      "browser_download_url": "https://github.com/valentinyeo/wazig/releases/download/v0.2.0/Messages-windows-x86_64.zip",
        \\      "size": 12345,
        \\      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        \\    },
        \\    {
        \\      "name": "Messages-hotfix.zip",
        \\      "browser_download_url": "https://github.com/valentinyeo/wazig/releases/download/v0.2.0/Messages-hotfix.zip",
        \\      "size": 234,
        \\      "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        \\    }
        \\  ]
        \\}
    ;
    var parsed7: std.json.Parsed(std.json.Value) = undefined;
    try std.testing.expectEqual(@as(?Asset, null), try pickAsset(std.testing.allocator, two_assets, &parsed7));
    parsed7.deinit();
}

test isZipAssetName {
    try std.testing.expect(isZipAssetName("Messages-v0.0.0.zip"));
    try std.testing.expect(isZipAssetName("Messages-windows-x86_64.zip"));
    try std.testing.expect(!isZipAssetName("Messages-v0.0.0"));
    try std.testing.expect(!isZipAssetName("SHA256SUMS.txt"));
    try std.testing.expect(!isZipAssetName("Other-v1.0.0.zip"));
    if (@import("builtin").cpu.arch != .aarch64) try std.testing.expect(!isZipAssetName("Messages_arm64-v0.0.0.zip"));
}

pub const wait_abandoned: u32 = 0x80;

pub const MutexWait = enum { acquired, busy, failed };

pub fn classifyMutexWait(result: u32) MutexWait {
    if (result == 0 or result == wait_abandoned) return .acquired;
    if (result == 0xFFFFFFFF) return .failed;
    return .busy;
}

pub const orphan_min_age_seconds: u64 = 5 * 60;

pub fn isStaleOrphan(self_pid: u32, pid: u32, has_visible_window: bool, age_seconds: u64) bool {
    return pid != self_pid and !has_visible_window and age_seconds >= orphan_min_age_seconds;
}

pub const RestoreSource = enum { replacement, backup };

pub fn restoreSource(new_present: bool, old_present: bool) ?RestoreSource {
    if (new_present) return .replacement;
    if (old_present) return .backup;
    return null;
}

test restoreSource {
    try std.testing.expectEqual(RestoreSource.replacement, restoreSource(true, true).?);
    try std.testing.expectEqual(RestoreSource.backup, restoreSource(false, true).?);
    try std.testing.expect(restoreSource(false, false) == null);
}

pub fn replacementVerified(staged_size: u64, temp_size: ?u64) bool {
    const size = temp_size orelse return false;
    return size == staged_size and size > 0;
}

test replacementVerified {
    try std.testing.expect(replacementVerified(100, 100));
    try std.testing.expect(!replacementVerified(100, null));
    try std.testing.expect(!replacementVerified(100, 99));
    try std.testing.expect(!replacementVerified(0, 0));
}

test classifyMutexWait {
    try std.testing.expectEqual(MutexWait.acquired, classifyMutexWait(0));
    try std.testing.expectEqual(MutexWait.acquired, classifyMutexWait(0x80));
    try std.testing.expectEqual(MutexWait.busy, classifyMutexWait(0x102));
    try std.testing.expectEqual(MutexWait.busy, classifyMutexWait(7));
    try std.testing.expectEqual(MutexWait.failed, classifyMutexWait(0xFFFFFFFF));
}

test isStaleOrphan {
    try std.testing.expect(!isStaleOrphan(100, 100, true, 0));
    try std.testing.expect(!isStaleOrphan(100, 200, true, 0));
    try std.testing.expect(!isStaleOrphan(100, 200, false, 60));
    try std.testing.expect(isStaleOrphan(100, 200, false, orphan_min_age_seconds));
}

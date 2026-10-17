const std = @import("std");

pub const wazi_130 = true;

const alias_suffix = ".mp4";
const mp4_shaped = [_][]const u8{ ".f4v", ".f4p" };

pub fn needsAlias(media_type: []const u8, mime: []const u8, path: []const u8) bool {
    if (!wazi_130 or path.len == 0) return false;
    const video = std.ascii.eqlIgnoreCase(media_type, "video") or std.ascii.eqlIgnoreCase(media_type, "gif") or
        (mime.len >= 6 and std.ascii.eqlIgnoreCase(mime[0..6], "video/"));
    if (!video) return false;
    const ext = std.fs.path.extension(path);
    for (mp4_shaped) |shape| if (std.ascii.eqlIgnoreCase(ext, shape)) return true;
    return false;
}

pub fn aliasPath(buffer: []u8, path: []const u8) ?[]const u8 {
    return std.fmt.bufPrint(buffer, "{s}{s}", .{ path, alias_suffix }) catch null;
}

test "f4v videos get an mp4 alias" {
    try std.testing.expect(needsAlias("video", "video/mp4", "C:\\media\\message-AC0A.f4v"));
    try std.testing.expect(needsAlias("video", "", "C:\\media\\clip.F4V"));
    try std.testing.expect(needsAlias("", "video/mp4", "C:\\media\\clip.f4v"));
    try std.testing.expect(needsAlias("gif", "video/mp4", "C:\\media\\loop.f4v"));
}

test "playable or non-video files keep their path" {
    try std.testing.expect(!needsAlias("video", "video/mp4", "C:\\media\\clip.mp4"));
    try std.testing.expect(!needsAlias("video", "video/quicktime", "C:\\media\\clip.mov"));
    try std.testing.expect(!needsAlias("document", "application/pdf", "C:\\media\\doc.f4v"));
    try std.testing.expect(!needsAlias("video", "video/mp4", ""));
}

test "alias appends mp4" {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("C:\\m\\a.f4v.mp4", aliasPath(&buffer, "C:\\m\\a.f4v").?);
    var tiny: [4]u8 = undefined;
    try std.testing.expect(aliasPath(&tiny, "C:\\m\\a.f4v") == null);
}

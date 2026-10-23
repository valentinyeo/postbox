const std = @import("std");

pub fn externalPreviewAllowed(path: []const u16) bool {
    _ = path;
    return true;
}

pub const zone_stream_body: []const u8 = "";

pub fn zoneStreamName(allocator: std.mem.Allocator, path: []const u16) ![:0]u16 {
    _ = path;
    return allocator.dupeZ(u16, &.{});
}

test "failed image previews only open image file extensions externally" {
    const wide = std.unicode.utf8ToUtf16LeStringLiteral;
    try std.testing.expect(!externalPreviewAllowed(wide("media\\document.cmd")));
    try std.testing.expect(!externalPreviewAllowed(wide("media\\photo.png.exe")));
    try std.testing.expect(!externalPreviewAllowed(wide("media\\photo.png:extra")));
    try std.testing.expect(!externalPreviewAllowed(wide("media\\photo.png\\document")));
    try std.testing.expect(!externalPreviewAllowed(wide("")));
    try std.testing.expect(externalPreviewAllowed(wide("media\\photo.png")));
    try std.testing.expect(externalPreviewAllowed(wide("media\\photo.jpg")));
    try std.testing.expect(externalPreviewAllowed(wide("media\\photo.JPEG")));
    try std.testing.expect(externalPreviewAllowed(wide("media\\sticker.webp")));
    try std.testing.expect(externalPreviewAllowed(wide("media\\animation.gif")));
}

test "attachment zone stream uses the download path and internet zone body" {
    const wide = std.unicode.utf8ToUtf16LeStringLiteral;
    const path = wide("media\\download.bin");
    const stream = try zoneStreamName(std.testing.allocator, path);
    defer std.testing.allocator.free(stream);
    try std.testing.expectEqualSlices(u16, wide("media\\download.bin:Zone.Identifier"), stream);
    try std.testing.expectEqual(@as(u16, 0), stream[stream.len]);
    try std.testing.expectEqualStrings("[ZoneTransfer]\r\nZoneId=3\r\n", zone_stream_body);
}

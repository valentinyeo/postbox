const std = @import("std");

pub const Bitmap = struct {
    width: u32,
    height: u32,
    pixels: []u8,
};

pub fn dibToBitmap(allocator: std.mem.Allocator, dib: []const u8) ?Bitmap {
    if (dib.len < 40) return null;
    const header_size = std.mem.readInt(u32, dib[0..4], .little);
    if (header_size < 40 or header_size > dib.len) return null;
    const width = std.mem.readInt(i32, dib[4..8], .little);
    const raw_height = std.mem.readInt(i32, dib[8..12], .little);
    const planes = std.mem.readInt(u16, dib[12..14], .little);
    const bpp = std.mem.readInt(u16, dib[14..16], .little);
    const compression = std.mem.readInt(u32, dib[16..20], .little);
    const colors_used = std.mem.readInt(u32, dib[32..36], .little);
    if (width <= 0 or raw_height == 0 or raw_height == std.math.minInt(i32) or planes != 1) return null;
    const top_down = raw_height < 0;
    const height: u32 = @intCast(if (top_down) -raw_height else raw_height);

    const bi_bitfields: u32 = 3;
    const supported = (bpp == 32 and (compression == 0 or compression == bi_bitfields)) or
        (bpp == 24 and compression == 0);
    if (!supported) return null;
    var pixel_offset: usize = header_size;
    if (compression == bi_bitfields and header_size == 40) pixel_offset += 12;
    const palette_entries: usize = if (colors_used != 0)
        colors_used
    else if (bpp <= 8) @as(usize, 1) << @intCast(bpp) else 0;
    pixel_offset += palette_entries * 4;

    if (width == 0 or height == 0) return null;
    if (width > 1 << 15 or height > 1 << 15) return null;

    const stride: usize = ((@as(usize, @intCast(width)) * bpp + 31) / 32) * 4;
    if (bpp != 32 and bpp != 24) return null;
    const w: usize = @intCast(width);
    const h: usize = height;
    if (pixel_offset >= dib.len) return null;
    const source = dib[pixel_offset..];
    if (source.len < stride * h) return null;

    const out = allocator.alloc(u8, w * h * 4) catch return null;
    errdefer allocator.free(out);
    var row: usize = 0;
    while (row < h) : (row += 1) {
        const source_row = if (top_down) row else h - 1 - row;
        const src = source[source_row * stride ..][0 .. w * bpp / 8];
        const dst = out[row * w * 4 ..][0 .. w * 4];
        if (bpp == 32) {
            @memcpy(dst, src[0 .. w * 4]);
            var x: usize = 0;
            while (x < w) : (x += 1) dst[x * 4 + 3] = 255;
        } else {
            var x: usize = 0;
            while (x < w) : (x += 1) {
                dst[x * 4] = src[x * 3];
                dst[x * 4 + 1] = src[x * 3 + 1];
                dst[x * 4 + 2] = src[x * 3 + 2];
                dst[x * 4 + 3] = 255;
            }
        }
    }
    return .{ .width = @intCast(width), .height = height, .pixels = out };
}

test "parses 32bpp bottom-up DIB and flips rows" {
    const allocator = std.testing.allocator;
    var dib: [40 + 2 * 4 * 2]u8 = undefined;
    @memset(&dib, 0);
    std.mem.writeInt(u32, dib[0..4], 40, .little);
    std.mem.writeInt(i32, dib[4..8], 2, .little);
    std.mem.writeInt(i32, dib[8..12], 2, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 32, .little);
    dib[40] = 255;
    dib[44 + 2] = 255;
    const bitmap = dibToBitmap(allocator, &dib) orelse return error.TestUnexpectedResult;
    defer allocator.free(bitmap.pixels);
    try std.testing.expectEqual(@as(u32, 2), bitmap.width);
    try std.testing.expectEqual(@as(u32, 2), bitmap.height);
    try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[3]);
    try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[8]);
    try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[14]);
}

test "parses 24bpp top-down DIB" {
    const allocator = std.testing.allocator;
    var dib: [40 + 2 * 8]u8 = undefined;
    @memset(&dib, 0);
    std.mem.writeInt(u32, dib[0..4], 40, .little);
    std.mem.writeInt(i32, dib[4..8], 2, .little);
    std.mem.writeInt(i32, dib[8..12], -2, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 24, .little);
    dib[40 + 1] = 128;
    const bitmap = dibToBitmap(allocator, &dib) orelse return error.TestUnexpectedResult;
    defer allocator.free(bitmap.pixels);
    try std.testing.expectEqual(@as(u8, 128), bitmap.pixels[1]);
    try std.testing.expectEqual(@as(u8, 255), bitmap.pixels[3]);
}

test "rejects unsupported and truncated formats" {
    var dib: [40]u8 = undefined;
    @memset(&dib, 0);
    std.mem.writeInt(u32, dib[0..4], 40, .little);
    std.mem.writeInt(i32, dib[4..8], 2, .little);
    std.mem.writeInt(i32, dib[8..12], 2, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 8, .little);
    try std.testing.expect(dibToBitmap(std.testing.allocator, &dib) == null);
    std.mem.writeInt(u16, dib[14..16], 32, .little);
    try std.testing.expect(dibToBitmap(std.testing.allocator, dib[0..30]) == null);
}

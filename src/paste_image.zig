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

    const bitfields = compression == 3 or compression == 6;
    const supported = (bpp == 32 and (compression == 0 or bitfields)) or
        (bpp == 24 and compression == 0);
    if (!supported) return null;
    var pixel_offset: usize = header_size;
    var masks = [_]u32{ 0x00ff0000, 0x0000ff00, 0x000000ff, 0 };
    if (bitfields) {
        const mask_bytes: usize = if (compression == 6) 16 else 12;
        if (header_size == 40) {
            pixel_offset += mask_bytes;
        } else if (header_size < 40 + mask_bytes) return null;
        if (dib.len < pixel_offset) return null;
        for (masks[0..3], 0..) |*mask, index| {
            mask.* = std.mem.readInt(u32, dib[40 + index * 4 ..][0..4], .little);
        }
        if (header_size >= 56 or compression == 6) masks[3] = std.mem.readInt(u32, dib[52..56], .little);
        var used: u32 = 0;
        for (masks, 0..) |mask, index| {
            if (mask == 0) {
                if (index < 3 or compression == 6) return null;
                continue;
            }
            const normalized = mask >> @intCast(@ctz(mask));
            if ((normalized & (normalized +% 1)) != 0 or (used & mask) != 0) return null;
            used |= mask;
        }
    }
    const palette_bytes = std.math.mul(usize, colors_used, 4) catch return null;
    pixel_offset = std.math.add(usize, pixel_offset, palette_bytes) catch return null;
    const w: usize = @intCast(width);
    const h: usize = height;
    const row_bits = std.math.mul(usize, w, bpp) catch return null;
    const aligned_bits = std.math.add(usize, row_bits, 31) catch return null;
    const stride = std.math.mul(usize, aligned_bits / 32, 4) catch return null;
    const source_bytes = std.math.mul(usize, stride, h) catch return null;
    const output_bytes = std.math.mul(usize, std.math.mul(usize, w, h) catch return null, 4) catch return null;
    if (pixel_offset > dib.len or source_bytes > dib.len - pixel_offset) return null;
    const source = dib[pixel_offset..];

    const out = allocator.alloc(u8, output_bytes) catch return null;
    var row: usize = 0;
    while (row < h) : (row += 1) {
        const source_row = if (top_down) row else h - 1 - row;
        const src = source[source_row * stride ..][0 .. w * bpp / 8];
        const dst = out[row * w * 4 ..][0 .. w * 4];
        if (bpp == 32 and masks[0] == 0x00ff0000 and masks[1] == 0x0000ff00 and masks[2] == 0x000000ff and (masks[3] == 0 or masks[3] == 0xff000000)) {
            @memcpy(dst, src);
            if (masks[3] == 0) {
                var x: usize = 0;
                while (x < w) : (x += 1) dst[x * 4 + 3] = 255;
            }
        } else if (bpp == 32) {
            var x: usize = 0;
            while (x < w) : (x += 1) {
                const pixel = std.mem.readInt(u32, src[x * 4 ..][0..4], .little);
                dst[x * 4] = channel(pixel, masks[2]);
                dst[x * 4 + 1] = channel(pixel, masks[1]);
                dst[x * 4 + 2] = channel(pixel, masks[0]);
                dst[x * 4 + 3] = if (masks[3] != 0) channel(pixel, masks[3]) else 255;
            }
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

fn channel(pixel: u32, mask: u32) u8 {
    const shift: u5 = @intCast(@ctz(mask));
    const maximum = mask >> shift;
    const value = (pixel & mask) >> shift;
    return @intCast((@as(u64, value) * 255 + maximum / 2) / maximum);
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

test "IGSH-679 V5 bitfields preserve alpha and both row orientations" {
    for ([_]i32{ 2, -2 }) |raw_height| {
        var dib = [_]u8{0} ** (124 + 16);
        std.mem.writeInt(u32, dib[0..4], 124, .little);
        std.mem.writeInt(i32, dib[4..8], 2, .little);
        std.mem.writeInt(i32, dib[8..12], raw_height, .little);
        std.mem.writeInt(u16, dib[12..14], 1, .little);
        std.mem.writeInt(u16, dib[14..16], 32, .little);
        std.mem.writeInt(u32, dib[16..20], 3, .little);
        std.mem.writeInt(u32, dib[40..44], 0x00ff0000, .little);
        std.mem.writeInt(u32, dib[44..48], 0x0000ff00, .little);
        std.mem.writeInt(u32, dib[48..52], 0x000000ff, .little);
        std.mem.writeInt(u32, dib[52..56], 0xff000000, .little);
        const top = [_]u8{ 48, 96, 224, 128, 8, 16, 32, 0 };
        const bottom = [_]u8{ 192, 96, 64, 255, 12, 24, 48, 64 };
        @memcpy(dib[124..132], if (raw_height < 0) &top else &bottom);
        @memcpy(dib[132..140], if (raw_height < 0) &bottom else &top);
        const bitmap = dibToBitmap(std.testing.allocator, &dib) orelse return error.TestUnexpectedResult;
        defer std.testing.allocator.free(bitmap.pixels);
        try std.testing.expectEqualSlices(u8, &top, bitmap.pixels[0..8]);
        try std.testing.expectEqualSlices(u8, &bottom, bitmap.pixels[8..16]);
    }
}

test "IGSH-679 bitfield channels are scaled by their masks" {
    var dib = [_]u8{0} ** (56 + 4);
    std.mem.writeInt(u32, dib[0..4], 56, .little);
    std.mem.writeInt(i32, dib[4..8], 1, .little);
    std.mem.writeInt(i32, dib[8..12], -1, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 32, .little);
    std.mem.writeInt(u32, dib[16..20], 3, .little);
    std.mem.writeInt(u32, dib[40..44], 0x000003ff, .little);
    std.mem.writeInt(u32, dib[44..48], 0x000ffc00, .little);
    std.mem.writeInt(u32, dib[48..52], 0x3ff00000, .little);
    std.mem.writeInt(u32, dib[52..56], 0xc0000000, .little);
    std.mem.writeInt(u32, dib[56..60], 1023 | (512 << 10) | (256 << 20) | (2 << 30), .little);
    const bitmap = dibToBitmap(std.testing.allocator, &dib) orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(bitmap.pixels);
    try std.testing.expectEqualSlices(u8, &.{ 64, 128, 255, 170 }, bitmap.pixels);
}

test "IGSH-679 external bitfields support opaque RGB and explicit alpha" {
    for ([_]u32{ 3, 6 }) |compression| {
        var dib = [_]u8{0} ** (40 + 16 + 4);
        const offset: usize = if (compression == 3) 52 else 56;
        std.mem.writeInt(u32, dib[0..4], 40, .little);
        std.mem.writeInt(i32, dib[4..8], 1, .little);
        std.mem.writeInt(i32, dib[8..12], 1, .little);
        std.mem.writeInt(u16, dib[12..14], 1, .little);
        std.mem.writeInt(u16, dib[14..16], 32, .little);
        std.mem.writeInt(u32, dib[16..20], compression, .little);
        std.mem.writeInt(u32, dib[40..44], 0x000000ff, .little);
        std.mem.writeInt(u32, dib[44..48], 0x0000ff00, .little);
        std.mem.writeInt(u32, dib[48..52], 0x00ff0000, .little);
        if (compression == 6) std.mem.writeInt(u32, dib[52..56], 0xff000000, .little);
        @memcpy(dib[offset..][0..4], &[_]u8{ 224, 96, 48, 128 });
        const bitmap = dibToBitmap(std.testing.allocator, dib[0 .. offset + 4]) orelse return error.TestUnexpectedResult;
        defer std.testing.allocator.free(bitmap.pixels);
        try std.testing.expectEqualSlices(u8, &.{ 48, 96, 224 }, bitmap.pixels[0..3]);
        try std.testing.expectEqual(@as(u8, if (compression == 6) 128 else 255), bitmap.pixels[3]);
    }
}

test "IGSH-679 full-screen and 4K screenshots retain their complete dimensions" {
    const allocator = std.testing.allocator;
    for ([_][2]u32{ .{ 1920, 1032 }, .{ 3840, 2160 }, .{ 32769, 1 } }) |size| {
        const bytes: usize = @as(usize, size[0]) * size[1] * 4;
        const dib = try allocator.alloc(u8, 124 + bytes);
        defer allocator.free(dib);
        @memset(dib, 0);
        std.mem.writeInt(u32, dib[0..4], 124, .little);
        std.mem.writeInt(i32, dib[4..8], @intCast(size[0]), .little);
        std.mem.writeInt(i32, dib[8..12], -@as(i32, @intCast(size[1])), .little);
        std.mem.writeInt(u16, dib[12..14], 1, .little);
        std.mem.writeInt(u16, dib[14..16], 32, .little);
        std.mem.writeInt(u32, dib[16..20], 3, .little);
        std.mem.writeInt(u32, dib[40..44], 0x00ff0000, .little);
        std.mem.writeInt(u32, dib[44..48], 0x0000ff00, .little);
        std.mem.writeInt(u32, dib[48..52], 0x000000ff, .little);
        std.mem.writeInt(u32, dib[52..56], 0xff000000, .little);
        @memcpy(dib[124..128], &[_]u8{ 48, 96, 224, 128 });
        @memcpy(dib[dib.len - 4 ..], &[_]u8{ 192, 96, 64, 255 });
        const bitmap = dibToBitmap(allocator, dib) orelse return error.TestUnexpectedResult;
        defer allocator.free(bitmap.pixels);
        try std.testing.expectEqual(size[0], bitmap.width);
        try std.testing.expectEqual(size[1], bitmap.height);
        try std.testing.expectEqual(bytes, bitmap.pixels.len);
        try std.testing.expectEqualSlices(u8, dib[124..128], bitmap.pixels[0..4]);
        try std.testing.expectEqualSlices(u8, dib[dib.len - 4 ..], bitmap.pixels[bytes - 4 ..]);
        try std.testing.expect(dibToBitmap(allocator, dib[0 .. dib.len - 1]) == null);
    }
}

test "IGSH-679 rejects invalid bitfields and impossible buffer layouts" {
    var dib = [_]u8{0} ** (124 + 4);
    std.mem.writeInt(u32, dib[0..4], 124, .little);
    std.mem.writeInt(i32, dib[4..8], 1, .little);
    std.mem.writeInt(i32, dib[8..12], 1, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 32, .little);
    std.mem.writeInt(u32, dib[16..20], 3, .little);
    std.mem.writeInt(u32, dib[40..44], 0x00ff0000, .little);
    std.mem.writeInt(u32, dib[44..48], 0x0000ff00, .little);
    std.mem.writeInt(u32, dib[48..52], 0x000000ff, .little);
    const allocator = std.testing.allocator;
    for ([_]u32{ 0, 0x00ff0000, 0x00000055 }) |bad_blue| {
        std.mem.writeInt(u32, dib[48..52], bad_blue, .little);
        try std.testing.expect(dibToBitmap(allocator, &dib) == null);
    }
    std.mem.writeInt(u32, dib[48..52], 0x000000ff, .little);
    std.mem.writeInt(u32, dib[32..36], std.math.maxInt(u32), .little);
    try std.testing.expect(dibToBitmap(allocator, &dib) == null);
    std.mem.writeInt(u32, dib[32..36], 0, .little);
    std.mem.writeInt(i32, dib[4..8], std.math.maxInt(i32), .little);
    std.mem.writeInt(i32, dib[8..12], std.math.maxInt(i32), .little);
    try std.testing.expect(dibToBitmap(allocator, &dib) == null);
    std.mem.writeInt(i32, dib[8..12], std.math.minInt(i32), .little);
    try std.testing.expect(dibToBitmap(allocator, &dib) == null);
    std.mem.writeInt(u32, dib[0..4], 40, .little);
    std.mem.writeInt(i32, dib[4..8], 1, .little);
    std.mem.writeInt(i32, dib[8..12], 1, .little);
    try std.testing.expect(dibToBitmap(allocator, dib[0..51]) == null);
}

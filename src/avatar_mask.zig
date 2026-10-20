const std = @import("std");

pub fn alphaAt(x: usize, y: usize, size: usize) u8 {
    const radius: f32 = @as(f32, @floatFromInt(size)) / 2.0;
    const px = @as(f32, @floatFromInt(x)) + 0.5;
    const py = @as(f32, @floatFromInt(y)) + 0.5;
    const dx = px - radius;
    const dy = py - radius;
    const dist = @sqrt(dx * dx + dy * dy);
    const coverage = std.math.clamp(radius - dist + 0.5, 0.0, 1.0);
    return @intFromFloat(coverage * 255.0);
}

pub fn applyMask(pixels: []u8, size: usize) void {
    var y: usize = 0;
    while (y < size) : (y += 1) {
        var x: usize = 0;
        while (x < size) : (x += 1) {
            const a: u16 = alphaAt(x, y, size);
            const i = (y * size + x) * 4;
            pixels[i + 0] = @intCast(@as(u16, pixels[i + 0]) * a / 255);
            pixels[i + 1] = @intCast(@as(u16, pixels[i + 1]) * a / 255);
            pixels[i + 2] = @intCast(@as(u16, pixels[i + 2]) * a / 255);
            pixels[i + 3] = @intCast(@as(u16, pixels[i + 3]) * a / 255);
        }
    }
}

pub fn scaleCircle(source: []const u8, source_size: usize, target: []u8, target_size: usize) void {
    if (source_size == target_size) {
        @memcpy(target, source);
        applyMask(target, target_size);
        return;
    }
    for (0..target_size) |y| {
        const sy = std.math.clamp((@as(f32, @floatFromInt(y)) + 0.5) * @as(f32, @floatFromInt(source_size)) / @as(f32, @floatFromInt(target_size)) - 0.5, 0, @as(f32, @floatFromInt(source_size - 1)));
        const y0: usize = @intFromFloat(sy);
        const y1 = @min(y0 + 1, source_size - 1);
        const fy = sy - @as(f32, @floatFromInt(y0));
        for (0..target_size) |x| {
            const sx = std.math.clamp((@as(f32, @floatFromInt(x)) + 0.5) * @as(f32, @floatFromInt(source_size)) / @as(f32, @floatFromInt(target_size)) - 0.5, 0, @as(f32, @floatFromInt(source_size - 1)));
            const x0: usize = @intFromFloat(sx);
            const x1 = @min(x0 + 1, source_size - 1);
            const fx = sx - @as(f32, @floatFromInt(x0));
            for (0..4) |channel| {
                const top = @as(f32, @floatFromInt(source[(y0 * source_size + x0) * 4 + channel])) * (1 - fx) + @as(f32, @floatFromInt(source[(y0 * source_size + x1) * 4 + channel])) * fx;
                const bottom = @as(f32, @floatFromInt(source[(y1 * source_size + x0) * 4 + channel])) * (1 - fx) + @as(f32, @floatFromInt(source[(y1 * source_size + x1) * 4 + channel])) * fx;
                target[(y * target_size + x) * 4 + channel] = @intFromFloat(@round(std.math.clamp(top * (1 - fy) + bottom * fy, 0, 255)));
            }
        }
    }
    applyMask(target, target_size);
}

pub fn fillCircle(pixels: []u8, size: usize, r: u8, g: u8, b: u8) void {
    var y: usize = 0;
    while (y < size) : (y += 1) {
        var x: usize = 0;
        while (x < size) : (x += 1) {
            const a: u16 = alphaAt(x, y, size);
            const i = (y * size + x) * 4;
            pixels[i + 0] = @intCast(@as(u16, b) * a / 255);
            pixels[i + 1] = @intCast(@as(u16, g) * a / 255);
            pixels[i + 2] = @intCast(@as(u16, r) * a / 255);
            pixels[i + 3] = @intCast(a);
        }
    }
}

test "circle mask is transparent in corners and opaque in the middle" {
    const size = 42;
    try std.testing.expectEqual(@as(u8, 0), alphaAt(0, 0, size));
    try std.testing.expectEqual(@as(u8, 0), alphaAt(size - 1, size - 1, size));
    try std.testing.expectEqual(@as(u8, 255), alphaAt(size / 2, size / 2, size));
    const edge = alphaAt(size - 1, size / 2, size);
    try std.testing.expect(edge > 0 and edge < 255);
}

test "fillCircle premultiplies color" {
    const size = 8;
    var pixels = [_]u8{0} ** (size * size * 4);
    fillCircle(&pixels, size, 255, 128, 0);
    const i = (1 * size + 0) * 4;
    try std.testing.expect(pixels[i + 3] > 0 and pixels[i + 3] < 255);
    try std.testing.expectEqual(pixels[i + 3], pixels[i + 2]);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(pixels[i + 1])), @as(f32, @floatFromInt(pixels[i + 3])) * 128.0 / 255.0, 1.5);
    try std.testing.expectEqual(@as(u8, 0), pixels[0 + 3]);
}

test "applyMask premultiplies an opaque buffer" {
    const size = 8;
    var pixels = [_]u8{255} ** (size * size * 4);
    applyMask(&pixels, size);
    const i = (1 * size + 0) * 4;
    try std.testing.expect(pixels[i + 3] > 0 and pixels[i + 3] < 255);
    try std.testing.expect(pixels[i + 2] <= pixels[i + 3]);
    try std.testing.expectEqual(@as(u8, 255), pixels[((size / 2) * size + (size / 2)) * 4 + 3]);
}

test "circle coverage stays symmetric and partially transparent at both display scales" {
    for ([_]usize{ 42, 63 }) |size| {
        try std.testing.expectEqual(@as(u8, 255), alphaAt(size / 2, size / 2, size));
        var partial: usize = 0;
        for (0..size) |y| {
            for (0..size) |x| {
                const alpha = alphaAt(x, y, size);
                try std.testing.expectEqual(alpha, alphaAt(size - 1 - x, y, size));
                try std.testing.expectEqual(alpha, alphaAt(x, size - 1 - y, size));
                if (alpha > 0 and alpha < 255) partial += 1;
            }
        }
        try std.testing.expect(partial >= size);
    }
}

test "mask preserves premultiplied source transparency" {
    const size = 8;
    var pixels = [_]u8{128} ** (size * size * 4);
    applyMask(&pixels, size);
    for (0..size * size) |i| {
        try std.testing.expectEqual(pixels[i * 4], pixels[i * 4 + 3]);
        try std.testing.expect(pixels[i * 4 + 3] <= 128);
    }
    try std.testing.expectEqual(@as(u8, 128), pixels[((size / 2) * size + size / 2) * 4 + 3]);
}

test "resized avatars use destination pixel coverage and retain premultiplied colours" {
    const source = [_]u8{255} ** (42 * 42 * 4);
    for ([_]usize{ 30, 42, 45, 63 }) |size| {
        var pixels: [63 * 63 * 4]u8 = undefined;
        const target = pixels[0 .. size * size * 4];
        scaleCircle(&source, 42, target, size);
        for (0..size) |y| {
            for (0..size) |x| {
                const i = (y * size + x) * 4;
                try std.testing.expectEqual(alphaAt(x, y, size), target[i + 3]);
                try std.testing.expectEqual(target[i + 3], target[i]);
            }
        }
    }
}

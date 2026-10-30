const std = @import("std");

pub fn level(bytes: []const u8, bits: u16, float_samples: bool) u8 {
    const width: usize = bits / 8;
    if (width == 0 or width > 4) return 0;
    var peak: f64 = 0;
    var offset: usize = 0;
    while (offset + width <= bytes.len) : (offset += width) {
        const sample: f64 = if (float_samples and bits == 32) value: {
            const raw: f32 = @bitCast(std.mem.readInt(u32, bytes[offset..][0..4], .little));
            break :value if (std.math.isFinite(raw)) @abs(raw) else 0;
        } else if (!float_samples) value: {
            var raw: u32 = 0;
            for (bytes[offset..][0..width], 0..) |byte, index| raw |= @as(u32, byte) << @as(u5, @intCast(index * 8));
            if (bits == 8) break :value @as(f64, @floatFromInt(@abs(@as(i32, @intCast(raw)) - 128))) / 128;
            const shifted: i32 = @bitCast(raw << @as(u5, @intCast(32 - bits)));
            break :value @as(f64, @floatFromInt(@abs(@as(i64, shifted)))) / 2147483648.0;
        } else 0;
        peak = @max(peak, sample);
    }
    return @intFromFloat(@min(255, peak * 510));
}

test "dictation waveform follows silent integer and floating point microphone samples" {
    try std.testing.expectEqual(@as(u8, 0), level(&.{ 0, 0 }, 16, false));
    try std.testing.expectEqual(@as(u8, 255), level(&.{ 0, 64 }, 16, false));
    try std.testing.expectEqual(@as(u8, 255), level(&.{ 0, 0, 0, 63 }, 32, true));
    try std.testing.expectEqual(@as(u8, 0), level(&.{ 0, 0, 128, 127 }, 32, true));
    try std.testing.expectEqual(@as(u8, 0), level(&.{128}, 8, false));
    try std.testing.expectEqual(@as(u8, 0), level(&.{}, 16, false));
}

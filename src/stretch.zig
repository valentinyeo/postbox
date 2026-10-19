const std = @import("std");

pub const window_frames = 960;
pub const overlap_frames = 240;
pub const search_frames = 240;
pub const max_channels = 2;

pub const hop_frames = window_frames - overlap_frames;

pub const lookahead_frames = 2 * search_frames + window_frames;

pub const Stretch = struct {
    channels: u32,
    percent: u32 = 100,
    pos_scaled: u64 = 0,
    pending: [overlap_frames * max_channels]f32 = [_]f32{0} ** (overlap_frames * max_channels),
    tail: [overlap_frames * max_channels]f32 = [_]f32{0} ** (overlap_frames * max_channels),
    has_tail: bool = false,

    pub fn sourceFramesConsumed(self: *const Stretch) u64 {
        return self.pos_scaled / 100;
    }

    pub fn reset(self: *Stretch, pos_frames: u64) void {
        self.pos_scaled = pos_frames * 100;
        self.has_tail = false;
        @memset(&self.pending, 0);
    }

    pub fn canEmit(self: *const Stretch, in_base: u64, in_frames: u64) bool {
        return self.relFrames(in_base) +| lookahead_frames <= in_frames;
    }

    pub fn emitWindow(self: *Stretch, in: []const f32, in_base: u64, in_frames: u64, out: []f32) void {
        const ch = self.channels;
        std.debug.assert(in_frames >= self.relFrames(in_base) + lookahead_frames);
        std.debug.assert(out.len >= hop_frames * ch);
        const rel_pos: usize = @intCast(@min(self.relFrames(in_base), in_frames - lookahead_frames));

        var best_off: usize = 0;
        if (self.has_tail) {
            var best_err: f64 = std.math.floatMax(f64);
            for (0..2 * search_frames + 1) |off| {
                const start = rel_pos + off;
                var err: f64 = 0;
                var i: usize = 0;
                while (i < overlap_frames) : (i += 4) {
                    const d = in[(start + i) * ch] - self.tail[i * ch];
                    err += @floatCast(d * d);
                }
                if (err < best_err) {
                    best_err = err;
                    best_off = off;
                }
            }
        }
        const src = rel_pos + best_off;
        const inv: f32 = 1.0 / @as(f32, overlap_frames);

        if (self.has_tail) {
            for (0..overlap_frames) |i| {
                const t: f32 = @as(f32, @floatFromInt(i)) * inv;
                for (0..ch) |c| {
                    out[i * ch + c] = self.pending[i * ch + c] + in[(src + i) * ch + c] * t;
                }
            }
        } else {
            self.has_tail = true;
            for (0..overlap_frames) |i| {
                for (0..ch) |c| {
                    out[i * ch + c] = in[(src + i) * ch + c];
                }
            }
        }
        const rest = (src + overlap_frames) * ch;
        @memcpy(out[overlap_frames * ch .. hop_frames * ch], in[rest .. rest + (hop_frames - overlap_frames) * ch]);

        const tail_src = (src + hop_frames) * ch;
        for (0..overlap_frames) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) * inv;
            for (0..ch) |c| {
                self.tail[i * ch + c] = in[tail_src + i * ch + c];
                self.pending[i * ch + c] = self.tail[i * ch + c] * (1 - t);
            }
        }

        self.pos_scaled += @as(u64, hop_frames) * self.percent;
    }

    fn relFrames(self: *const Stretch, in_base: u64) u64 {
        return self.pos_scaled / 100 -| in_base;
    }
};

test "stretch 150 consumes about two thirds of the input" {
    var st: Stretch = .{ .channels = 1, .percent = 150 };
    const frames = 48000 * 10;
    const in = try std.testing.allocator.alloc(f32, frames);
    defer std.testing.allocator.free(in);
    for (in, 0..) |*s, i| {
        s.* = @sin(@as(f32, @floatFromInt(i)) * 2 * std.math.pi * 440 / 48000);
    }
    const blocks = 100;
    const out = try std.testing.allocator.alloc(f32, blocks * hop_frames);
    defer std.testing.allocator.free(out);
    for (0..blocks) |w| {
        st.emitWindow(in, 0, frames, out[w * hop_frames ..][0..hop_frames]);
    }
    const consumed = st.sourceFramesConsumed();
    try std.testing.expect(consumed > 104000 and consumed < 112000);
    for (out[hop_frames..]) |s| {
        try std.testing.expect(s > -1.1 and s < 1.1);
    }
    var crossings: u32 = 0;
    var prev = out[0];
    for (out[1..]) |s| {
        if (prev <= 0 and s > 0) crossings += 1;
        prev = s;
    }
    try std.testing.expectApproxEqAbs(@as(f64, 660), @as(f64, @floatFromInt(crossings)), 30);
}

test "stretch 200 consumes about half of the input" {
    var st: Stretch = .{ .channels = 1, .percent = 200 };
    const frames = 48000;
    const in = try std.testing.allocator.alloc(f32, frames);
    defer std.testing.allocator.free(in);
    for (in, 0..) |*s, i| {
        s.* = @sin(@as(f32, @floatFromInt(i)) * 2 * std.math.pi * 300 / 48000);
    }
    const out = try std.testing.allocator.alloc(f32, hop_frames);
    defer std.testing.allocator.free(out);
    var blocks: usize = 0;
    while (st.canEmit(0, frames)) : (blocks += 1) {
        st.emitWindow(in, 0, frames, out);
    }
    try std.testing.expect(blocks > 28 and blocks < 38);
}

test "stretched output has no sample discontinuities beyond the input slope" {
    var st: Stretch = .{ .channels = 1, .percent = 150 };
    const frames = 48000 * 12;
    const in = try std.testing.allocator.alloc(f32, frames);
    defer std.testing.allocator.free(in);
    for (in, 0..) |*s, i| {
        const t = @as(f32, @floatFromInt(i)) / 48000.0;
        const vib = 1.0 + 0.01 * @sin(t * 2 * std.math.pi * 5.0);
        s.* = @sin(t * 2 * std.math.pi * 180 * vib) * 0.5 +
            @sin(t * 2 * std.math.pi * 360 * vib) * 0.25 +
            @sin(t * 2 * std.math.pi * 540 * vib) * 0.125;
    }
    var in_slope: f32 = 0;
    for (1..in.len) |i| in_slope = @max(in_slope, @abs(in[i] - in[i - 1]));
    const blocks = 300;
    const out = try std.testing.allocator.alloc(f32, blocks * hop_frames);
    defer std.testing.allocator.free(out);
    for (0..blocks) |w| {
        st.emitWindow(in, 0, frames, out[w * hop_frames ..][0..hop_frames]);
    }
    for (1..out.len) |i| {
        const step = @abs(out[i] - out[i - 1]);
        try std.testing.expect(step <= 4 * in_slope);
    }
}

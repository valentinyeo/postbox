const std = @import("std");

pub const ReaderBackground: u32 = 0x101010;
pub const ReaderCard: u32 = 0x1E1E1E;
pub const ReaderUserCard: u32 = 0x3A3A3A;
pub const ReaderControl: u32 = 0x1F1F1F;
pub const ReaderOutline: u32 = 0x2E2E2E;
pub const ReaderRaised: u32 = 0x353535;
pub const ReaderForeground: u32 = 0xF2F2F2;
pub const ReaderHint: u32 = 0x8A8A8A;
pub const ReaderPanel: u32 = 0x181818;

pub fn cornerRadius(w: i32, h: i32, want: i32) i32 {
    return @max(0, @min(want, @divTrunc(@min(w, h), 2)));
}
pub fn argb(c: u32) u32 {
    return 0xFF000000 | ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF);
}
fn channelShift(v: u32, delta: i32) u32 {
    return @intCast(std.math.clamp(@as(i32, @intCast(v)) + delta, 0, 255));
}
pub fn shift(c: u32, delta: i32) u32 {
    return channelShift(c & 0xFF, delta) | (channelShift((c >> 8) & 0xFF, delta) << 8) | (channelShift((c >> 16) & 0xFF, delta) << 16);
}
pub fn isDark(c: u32) bool {
    const lum = (2126 * (c & 0xFF) + 7152 * ((c >> 8) & 0xFF) + 722 * ((c >> 16) & 0xFF)) / 10000;
    return lum < 128;
}
pub fn scrollThumbColor(bg: u32) u32 {
    return shift(bg, if (isDark(bg)) 44 else -60);
}
pub const BubbleColors = struct { user: u32, agent: u32, injected: u32 };
pub fn bubbleColors(bg: u32) BubbleColors {
    if (bg == ReaderBackground) return .{ .user = ReaderUserCard, .agent = ReaderCard, .injected = 0x4F2F1E };
    if (isDark(bg)) return .{ .user = shift(bg, 53), .agent = shift(bg, 36), .injected = 0x4F2F1E };
    return .{ .user = shift(bg, -26), .agent = shift(bg, -11), .injected = 0xF7E6D6 };
}
pub const BubbleLook = struct { top: u32, bottom: u32, outline: u32 };
pub const BUBBLE_GRADIENT_STEPS = 8;
pub fn bubbleLook(fill: u32) BubbleLook {
    if (fill == ReaderCard or fill == ReaderUserCard) return .{ .top = shift(fill, 8), .bottom = fill, .outline = shift(fill, 16) };
    if (isDark(fill)) return .{ .top = shift(fill, 8), .bottom = fill, .outline = shift(fill, 12) };
    return .{ .top = shift(fill, 6), .bottom = fill, .outline = shift(fill, -22) };
}
fn lerpChannel(a: u32, b: u32, num: u32, den: u32) u32 {
    const av: i32 = @intCast(a);
    const bv: i32 = @intCast(b);
    return @intCast(av + @divTrunc((bv - av) * @as(i32, @intCast(num)), @as(i32, @intCast(den))));
}
pub fn gradientColor(look: BubbleLook, step: u32, steps: u32) u32 {
    if (steps <= 1) return look.bottom;
    const num = @min(step, steps - 1);
    const den = steps - 1;
    return lerpChannel(look.top & 0xFF, look.bottom & 0xFF, num, den) |
        (lerpChannel((look.top >> 8) & 0xFF, (look.bottom >> 8) & 0xFF, num, den) << 8) |
        (lerpChannel((look.top >> 16) & 0xFF, (look.bottom >> 16) & 0xFF, num, den) << 16);
}

pub const font_face = "IBM Plex Sans";
pub const body_size: i32 = 15;
pub const body_weight: i32 = 400;
pub const column_width: i32 = 920;
pub const bubble_radius: i32 = 20;
pub const button_size: i32 = 32;
pub const mic_width: i32 = 116;
pub const field_radius: i32 = 20;
pub const row_radius: i32 = 10;
pub const menu_radius: i32 = 16;
pub const menu_row_height: i32 = 32;

pub const Rect = extern struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
};

pub fn scaled(value: i32, dpi: i32) i32 {
    return @divTrunc(value * dpi + 48, 96);
}

pub fn roundButton(canvas: anytype, rect: Rect, fill: u32) void {
    canvas.roundRect(rect, @divTrunc(@min(rect.right - rect.left, rect.bottom - rect.top), 2), fill);
}

pub fn field(canvas: anytype, rect: Rect, radius: i32, edge: i32, fill: u32, outline: u32) void {
    canvas.roundRect(rect, radius, outline);
    const inner = Rect{ .left = rect.left + edge, .top = rect.top + edge, .right = rect.right - edge, .bottom = rect.bottom - edge };
    if (inner.right > inner.left and inner.bottom > inner.top) canvas.roundRect(inner, @max(0, radius - edge), fill);
}

pub fn row(canvas: anytype, rect: Rect, radius: i32, fill: u32) void {
    canvas.roundRect(rect, radius, fill);
}

pub fn wave(canvas: anytype, rect: Rect, dpi: i32, ink: u32, bars: [8]u8) void {
    const slot = @divTrunc(rect.right - rect.left, 8);
    if (slot < 2) return;
    const width = @max(1, @divTrunc(slot * 2, 3));
    const mid = @divTrunc(rect.top + rect.bottom, 2);
    const maximum = @max(1, @divTrunc(rect.bottom - rect.top, 2));
    const minimum = @min(maximum, @max(1, scaled(2, dpi)));
    for (bars, 0..) |level, index| {
        const half = minimum + @divTrunc((maximum - minimum) * @as(i32, level), 255);
        const left = rect.left + @as(i32, @intCast(index)) * slot + @divTrunc(slot - width, 2);
        canvas.roundRect(.{ .left = left, .top = mid - half, .right = left + width, .bottom = mid + half }, @divTrunc(width, 2), ink);
    }
}

pub fn elapsedText(buffer: *[16]u16, elapsed: u64) []const u16 {
    var bytes: [16]u8 = undefined;
    const text = std.fmt.bufPrint(&bytes, "{d}:{d:0>2}", .{ elapsed / 60, elapsed % 60 }) catch return &.{};
    for (text, 0..) |byte, index| buffer[index] = byte;
    return buffer[0..text.len];
}

pub fn micPill(canvas: anytype, rect: Rect, dpi: i32, ink: u32, fill: u32, elapsed: u64, bars: [8]u8) void {
    const height = rect.bottom - rect.top;
    if (height <= 0 or rect.right <= rect.left) return;
    roundButton(canvas, rect, fill);
    const saved = canvas.clip(rect);
    defer canvas.restore(saved);
    const square = @max(scaled(8, dpi), @divTrunc(height * 34, 100));
    const left = rect.left + @divTrunc(height - square, 2);
    const top = rect.top + @divTrunc(height - square, 2);
    canvas.roundRect(.{ .left = left, .top = top, .right = left + square, .bottom = top + square }, scaled(2, dpi), ink);
    const text_left = left + square + scaled(8, dpi);
    const text_right = @min(rect.right, text_left + scaled(34, dpi));
    var digits: [16]u16 = undefined;
    const label = elapsedText(&digits, elapsed);
    canvas.label(.{ .left = text_left, .top = rect.top, .right = text_right, .bottom = rect.bottom }, label, @max(scaled(10, dpi), @divTrunc(height * 40, 100)), ink);
    wave(canvas, .{ .left = text_right + scaled(6, dpi), .top = rect.top + scaled(6, dpi), .right = rect.right - @divTrunc(height, 2), .bottom = rect.bottom - scaled(6, dpi) }, dpi, ink, bars);
}

pub fn bubble(canvas: anytype, rect: Rect, radius: i32, edge: i32, fill: u32, round_top: bool, round_bottom: bool, span: [2]i32) void {
    if (rect.right <= rect.left or rect.bottom <= rect.top) return;
    const look = bubbleLook(fill);
    canvas.bubbleFill(rect, radius, look.outline, round_top, round_bottom);
    const inner = Rect{ .left = rect.left + edge, .top = rect.top + (if (round_top) edge else 0), .right = rect.right - edge, .bottom = rect.bottom - (if (round_bottom) edge else 0) };
    if (inner.right <= inner.left or inner.bottom <= inner.top) return;
    const height = @max(1, span[1] - span[0]);
    const steps: i32 = BUBBLE_GRADIENT_STEPS;
    var step: i32 = 0;
    while (step < steps) : (step += 1) {
        const y0 = if (step == 0) inner.top else @max(inner.top, span[0] + @divTrunc(height * step, steps));
        const y1 = if (step == steps - 1) inner.bottom else @min(inner.bottom, span[0] + @divTrunc(height * (step + 1), steps));
        if (y1 <= y0) continue;
        const saved = canvas.clip(.{ .left = inner.left, .top = y0, .right = inner.right, .bottom = y1 });
        canvas.bubbleFill(inner, @max(0, radius - edge), gradientColor(look, @intCast(step), BUBBLE_GRADIENT_STEPS), round_top, round_bottom);
        canvas.restore(saved);
    }
}

const Recorder = struct {
    rects: [32]Rect = undefined,
    colors: [32]u32 = undefined,
    count: usize = 0,
    text: [16]u16 = @splat(0),
    text_len: usize = 0,
    clips: usize = 0,

    pub fn roundRect(self: *@This(), rect: Rect, _: i32, color: u32) void {
        self.rects[self.count] = rect;
        self.colors[self.count] = color;
        self.count += 1;
    }
    pub fn clip(self: *@This(), _: Rect) usize {
        self.clips += 1;
        return self.clips;
    }
    pub fn restore(self: *@This(), _: usize) void {
        self.clips -= 1;
    }
    pub fn label(self: *@This(), _: Rect, text: []const u16, _: i32, _: u32) void {
        @memcpy(self.text[0..text.len], text);
        self.text_len = text.len;
    }
    pub fn bubbleFill(self: *@This(), rect: Rect, radius: i32, color: u32, _: bool, _: bool) void {
        self.roundRect(rect, radius, color);
    }
};

test "approved shared values retain the reader palette and Figma geometry" {
    try std.testing.expectEqual(@as(u32, 0xF2F2F2), ReaderForeground);
    try std.testing.expectEqual(@as(u32, 0x353535), ReaderRaised);
    try std.testing.expectEqual(@as(u32, 0x3A3A3A), ReaderUserCard);
    try std.testing.expectEqual(@as(u32, 0x8A8A8A), ReaderHint);
    try std.testing.expectEqual(@as(i32, 15), body_size);
    try std.testing.expectEqual(@as(i32, 920), column_width);
    try std.testing.expectEqual(@as(i32, 20), bubble_radius);
    try std.testing.expectEqual(@as(i32, 32), button_size);
}

test "active pill paints white stop timer and eight bounded level bars at every DPI" {
    for ([_]i32{ 96, 120, 144, 192 }) |dpi| {
        var canvas = Recorder{};
        const rect = Rect{ .right = scaled(mic_width, dpi), .bottom = scaled(button_size, dpi) };
        micPill(&canvas, rect, dpi, ReaderForeground, ReaderRaised, 64, .{ 0, 32, 64, 128, 255, 128, 64, 32 });
        try std.testing.expectEqual(@as(usize, 10), canvas.count);
        try std.testing.expectEqual(ReaderRaised, canvas.colors[0]);
        for (canvas.colors[1..canvas.count]) |color| try std.testing.expectEqual(ReaderForeground, color);
        try std.testing.expectEqualSlices(u16, &.{ '1', ':', '0', '4' }, canvas.text[0..canvas.text_len]);
        for (canvas.rects[0..canvas.count]) |shape| {
            try std.testing.expect(shape.left >= rect.left and shape.right <= rect.right);
            try std.testing.expect(shape.top >= rect.top and shape.bottom <= rect.bottom);
        }
        try std.testing.expectEqual(@as(usize, 0), canvas.clips);
    }
}

test "shared bubble preserves gradient outline and balanced clipping" {
    var canvas = Recorder{};
    bubble(&canvas, .{ .right = 300, .bottom = 100 }, bubble_radius, 1, ReaderCard, true, true, .{ 0, 100 });
    try std.testing.expectEqual(@as(usize, 9), canvas.count);
    try std.testing.expectEqual(shift(ReaderCard, 16), canvas.colors[0]);
    try std.testing.expectEqual(shift(ReaderCard, 8), canvas.colors[1]);
    try std.testing.expectEqual(ReaderCard, canvas.colors[8]);
    try std.testing.expectEqual(@as(usize, 0), canvas.clips);
}

pub fn hex(value: u24) u32 {
    const rgb: u32 = value;
    return ((rgb & 0xff0000) >> 16) | (rgb & 0x00ff00) | ((rgb & 0x0000ff) << 16);
}

pub const provider_colors = struct {
    pub const youtube = hex(0xC52828);
    pub const instagram = hex(0xE1306C);
    pub const facebook = hex(0x1877F2);
    pub const signal = hex(0x3A76F0);
    pub const telegram = hex(0x2AABEE);
    pub const whatsapp = hex(0x25D366);
};

pub const SenderColor = struct { r: u8, g: u8, b: u8 };

pub const sender_palette = [_]SenderColor{
    .{ .r = 0, .g = 168, .b = 132 },
    .{ .r = 83, .g = 189, .b = 235 },
    .{ .r = 235, .g = 140, .b = 84 },
    .{ .r = 178, .g = 132, .b = 235 },
    .{ .r = 235, .g = 195, .b = 84 },
    .{ .r = 235, .g = 110, .b = 150 },
};

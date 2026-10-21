const std = @import("std");

pub const class_name = "MessagesDirectWriteEdit";
pub const d2d_write: u32 = 0x01000000;
pub const advanced_input: u32 = 0x20000000;
pub const multiline: u32 = 2;
pub const word_wrap: u32 = 0x400;

pub fn propertyBits(multi: bool, enabled: bool) u32 {
    return d2d_write | advanced_input | 0x40 | (if (multi) multiline | word_wrap else @as(u32, 0)) | (if (enabled) @as(u32, 0) else 4);
}

pub fn fontTwips(pixel_height: i32) i32 {
    return @as(i32, @intCast(@max(1, @abs(pixel_height)))) * 15;
}

pub fn himetric(pixels: i32) i32 {
    return @divTrunc(pixels * 2540 + @as(i32, if (pixels >= 0) 48 else -48), 96);
}

pub fn contentHeight(natural: i32, top: i32, bottom: i32, minimum: i32) i32 {
    return @max(minimum, @max(0, natural) + @max(0, top) + @max(0, bottom));
}

pub fn wordStart(text: []const u16, caret: usize) usize {
    var start = @min(caret, text.len);
    while (start > 0 and wordBreak(text[start - 1])) start -= 1;
    while (start > 0 and !wordBreak(text[start - 1])) start -= 1;
    return start;
}

fn wordBreak(unit: u16) bool {
    return unit == ' ' or unit == '\t' or unit == '\r' or unit == '\n';
}

pub fn dictationPadding(text: []const u16, start: usize, end: usize) struct { before: bool, after: bool } {
    const first = @min(start, text.len);
    const last = @min(@max(first, end), text.len);
    return .{ .before = first > 0 and !wordBreak(text[first - 1]), .after = last < text.len and !wordBreak(text[last]) };
}

pub const MessageRoute = enum { font, text, cue, rectangle, margins, limit, position, native };

pub fn messageRoute(message: u32) MessageRoute {
    return switch (message) {
        0x30, 0x31 => .font,
        0x0c, 0x0d, 0x0e => .text,
        0x1501, 0x1502 => .cue,
        0xb2, 0xb3, 0xb4 => .rectangle,
        0xd3, 0xd4 => .margins,
        0xc5 => .limit,
        0xd6 => .position,
        else => .native,
    };
}

fn wide(comptime text: []const u8) []const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

test "IGSH-466 DirectWrite is mandatory for single and multiline editing including disabled drafts" {
    for ([_]bool{ false, true }) |multi| {
        for ([_]bool{ false, true }) |enabled| {
            const bits = propertyBits(multi, enabled);
            try std.testing.expect(bits & d2d_write != 0);
            try std.testing.expect(bits & advanced_input != 0);
            try std.testing.expectEqual(multi, bits & multiline != 0);
            try std.testing.expectEqual(multi, bits & word_wrap != 0);
            try std.testing.expectEqual(!enabled, bits & 4 != 0);
        }
    }
}

test "IGSH-466 every legacy edit message has a native or adapted route" {
    inline for (.{ 0x30, 0x31 }) |msg| try std.testing.expectEqual(MessageRoute.font, messageRoute(msg));
    inline for (.{ 0x0c, 0x0d, 0x0e }) |msg| try std.testing.expectEqual(MessageRoute.text, messageRoute(msg));
    inline for (.{ 0x1501, 0x1502 }) |msg| try std.testing.expectEqual(MessageRoute.cue, messageRoute(msg));
    inline for (.{ 0xb2, 0xb3, 0xb4 }) |msg| try std.testing.expectEqual(MessageRoute.rectangle, messageRoute(msg));
    inline for (.{ 0xd3, 0xd4 }) |msg| try std.testing.expectEqual(MessageRoute.margins, messageRoute(msg));
    try std.testing.expectEqual(MessageRoute.limit, messageRoute(0xc5));
    try std.testing.expectEqual(MessageRoute.position, messageRoute(0xd6));
    inline for (.{ 0xb0, 0xb1, 0xc2, 0xcd, 0xb7, 0xba, 0xce, 0xb6, 0xc7, 0xc6, 0x304, 0x450, 0x300, 0x301, 0x302, 0x303, 0x100, 0x102, 0x10d, 0x10e, 0x10f, 0x201, 0x202, 0x200 }) |msg| {
        try std.testing.expectEqual(MessageRoute.native, messageRoute(msg));
    }
}

test "IGSH-466 font twips preserve the body pixel size at every saved scale and DPI" {
    for ([_]i32{ 75, 82, 100, 125, 150, 200 }) |scale| {
        for ([_]i32{ 96, 120, 144, 192 }) |dpi| {
            const height = -@divTrunc(17 * scale * dpi + 4800, 9600);
            try std.testing.expectEqual(-height, @divTrunc(fontTwips(height), 15));
        }
    }
}

test "IGSH-466 DirectWrite natural height grows shrinks and keeps composer padding" {
    try std.testing.expectEqual(@as(i32, 2540), himetric(96));
    try std.testing.expectEqual(@as(i32, 212), himetric(8));
    try std.testing.expectEqual(@as(i32, -212), himetric(-8));
    try std.testing.expectEqual(@as(i32, 0), himetric(0));
    try std.testing.expectEqual(@as(i32, 44), contentHeight(20, 8, 8, 44));
    try std.testing.expectEqual(@as(i32, 76), contentHeight(60, 8, 8, 44));
    try std.testing.expectEqual(@as(i32, 44), contentHeight(0, 8, 8, 44));
    try std.testing.expectEqual(@as(i32, 80), contentHeight(80, -1, -2, 44));
}

test "IGSH-466 Ctrl Backspace deletes whitespace and the previous word without splitting UTF16" {
    try std.testing.expectEqual(@as(usize, 0), wordStart(wide(""), 0));
    try std.testing.expectEqual(@as(usize, 0), wordStart(wide("one"), 0));
    try std.testing.expectEqual(@as(usize, 4), wordStart(wide("one two  \r\n"), 11));
    try std.testing.expectEqual(@as(usize, 4), wordStart(wide("one two"), 6));
    try std.testing.expectEqual(@as(usize, 0), wordStart(wide("  \t"), 3));
    try std.testing.expectEqual(@as(usize, 4), wordStart(wide("one 😀"), 6));
}

test "IGSH-466 composer search palette and emoji create the DirectWrite host" {
    const source = @embedFile("main.zig");
    inline for (.{ "a.compose", "a.search", "a.palette_edit", "a.emoji_edit" }) |name| {
        try std.testing.expect(std.mem.indexOf(u8, source, name ++ " = directwrite_edit.create(") != null);
        try std.testing.expect(std.mem.indexOf(u8, source, name ++ " = win.CreateWindowExW(0, lit(\"EDIT\")") == null);
    }
}

test "IGSH-466 dictation inserts at the caret with word separation and preserves surrounding text" {
    const text = wide("one two");
    const start = dictationPadding(text, 0, 0);
    try std.testing.expect(!start.before and start.after);
    const middle = dictationPadding(text, 3, 4);
    try std.testing.expect(middle.before and middle.after);
    const end = dictationPadding(text, text.len, text.len);
    try std.testing.expect(end.before and !end.after);
    const empty = dictationPadding(wide(""), 0, 0);
    try std.testing.expect(!empty.before and !empty.after);
    const space = dictationPadding(wide("one  two"), 4, 4);
    try std.testing.expect(!space.before and !space.after);
}

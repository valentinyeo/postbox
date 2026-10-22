const std = @import("std");

pub fn pasteShortcut(key: u32, control: bool, shift: bool, alt: bool) bool {
    return !alt and ((control and key == 'V') or (!control and shift and key == 0x2d));
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

fn wide(comptime text: []const u8) []const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

test "IGSH-466 both composer paste shortcuts are consumed before native key and char dispatch" {
    try std.testing.expect(pasteShortcut('V', true, false, false));
    try std.testing.expect(pasteShortcut('V', true, true, false));
    try std.testing.expect(pasteShortcut(0x2d, false, true, false));
    try std.testing.expect(!pasteShortcut('V', false, false, false));
    try std.testing.expect(!pasteShortcut('V', true, false, true));
    try std.testing.expect(!pasteShortcut(0x2d, true, false, false));
    try std.testing.expect(!pasteShortcut(0x2d, false, false, false));
}

test "IGSH-466 Ctrl Backspace deletes whitespace and the previous word without splitting UTF16" {
    try std.testing.expectEqual(@as(usize, 0), wordStart(wide(""), 0));
    try std.testing.expectEqual(@as(usize, 0), wordStart(wide("one"), 0));
    try std.testing.expectEqual(@as(usize, 4), wordStart(wide("one two  \r\n"), 11));
    try std.testing.expectEqual(@as(usize, 4), wordStart(wide("one two"), 6));
    try std.testing.expectEqual(@as(usize, 0), wordStart(wide("  \t"), 3));
    try std.testing.expectEqual(@as(usize, 4), wordStart(wide("one 😀"), 6));
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

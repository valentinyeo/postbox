const std = @import("std");

pub const Prefix = struct { marker: usize, text: usize };

pub fn prefix(line: []const u16) ?Prefix {
    var marker: usize = 0;
    while (marker < line.len and line[marker] == ' ') : (marker += 1) {}
    if (marker == line.len) return null;
    var end = marker;
    if (line[end] == 0x2022 or line[end] == '-' or line[end] == '*') {
        end += 1;
    } else {
        while (end < line.len and line[end] >= '0' and line[end] <= '9') : (end += 1) {}
        if (end == marker or end == line.len or line[end] != '.') return null;
        end += 1;
    }
    if (end == line.len or line[end] != ' ') return null;
    while (end < line.len and line[end] == ' ') : (end += 1) {}
    return .{ .marker = marker, .text = end };
}

pub const Span = struct {
    start: usize,
    len: usize,
    word_start: usize,
    word_end: usize,
    x: i32,
    y: i32,
    space: bool = false,
};

pub const Layout = struct {
    text: []const u16,
    width: i32,
    line_height: i32,
    lists: bool,
    index: usize = 0,
    word_start: usize = 0,
    word_end: usize = 0,
    word_width: i32 = 0,
    emitted: usize = 0,
    x: i32 = 0,
    y: i32 = 0,
    line_left: i32 = 0,
    last_right: i32 = 0,
    paragraph: bool = true,
    word: bool = false,
    done: bool = false,
    fenced: bool = false,

    fn newline(self: *Layout) void {
        self.y += self.line_height;
        self.x = self.line_left;
        self.last_right = self.line_left;
    }

    pub fn height(self: Layout) i32 {
        return self.y + self.line_height;
    }

    pub fn next(self: *Layout, metrics: anytype) ?Span {
        while (!self.done) {
            if (self.paragraph) {
                self.paragraph = false;
                self.line_left = 0;
                self.x = 0;
                if (self.lists) {
                    const end = std.mem.indexOfScalarPos(u16, self.text, self.index, '\n') orelse self.text.len;
                    const line = self.text[self.index..end];
                    const trimmed = std.mem.trimStart(u16, line, &.{' '});
                    if (std.mem.startsWith(u16, trimmed, &.{ '`', '`', '`' })) self.fenced = !self.fenced;
                    if (!self.fenced) if (prefix(line)) |p| {
                        const start = self.index + p.marker;
                        const text_start = self.index + p.text;
                        const marker_x = metrics.width(self.text[self.index..start]);
                        self.line_left = marker_x + metrics.width(self.text[start..text_start]);
                        self.x = self.line_left;
                        self.last_right = self.line_left;
                        self.index = text_start;
                        return .{ .start = start, .len = p.text - p.marker, .word_start = start, .word_end = text_start, .x = marker_x, .y = self.y };
                    };
                }
            }
            if (!self.word) {
                self.word_start = self.index;
                self.word_end = self.index;
                while (self.word_end < self.text.len and self.text[self.word_end] != ' ' and self.text[self.word_end] != '\n') : (self.word_end += 1) {}
                self.emitted = self.word_start;
                self.word = true;
                self.word_width = metrics.width(self.text[self.word_start..self.word_end]);
                if (self.x > self.line_left and self.x + self.word_width > self.width) self.newline();
            }
            if (self.emitted < self.word_end) {
                const remaining = self.text[self.emitted..self.word_end];
                const available = @max(1, self.width - self.line_left);
                var count = remaining.len;
                if (self.word_width > available) count = metrics.fit(remaining, available);
                count = @max(1, @min(count, remaining.len));
                const span = Span{ .start = self.emitted, .len = count, .word_start = self.word_start, .word_end = self.word_end, .x = self.x, .y = self.y };
                self.x += if (count == self.word_end - self.word_start) self.word_width else metrics.width(remaining[0..count]);
                self.last_right = self.x;
                self.emitted += count;
                if (self.emitted < self.word_end) self.newline();
                return span;
            }
            self.word = false;
            self.index = self.word_end;
            if (self.index == self.text.len) {
                self.done = true;
            } else if (self.text[self.index] == '\n') {
                self.index += 1;
                self.line_left = 0;
                self.newline();
                self.paragraph = true;
            } else {
                const span = Span{ .start = self.index, .len = 1, .word_start = self.index, .word_end = self.index + 1, .x = self.x, .y = self.y, .space = true };
                self.index += 1;
                self.x += metrics.width(&.{' '});
                return span;
            }
        }
        return null;
    }
};

const TestMetrics = struct {
    unit: i32,
    pub fn width(self: TestMetrics, text: []const u16) i32 {
        return @as(i32, @intCast(text.len)) * self.unit;
    }
    pub fn fit(self: TestMetrics, text: []const u16, available: i32) usize {
        return @min(text.len, @as(usize, @intCast(@max(1, @divTrunc(available, self.unit)))));
    }
};

test "IGSH-829 six long bullets and nested lists keep every continuation under its text" {
    const text = comptime blk: {
        @setEvalBranchQuota(100000);
        break :blk std.unicode.utf8ToUtf16LeStringLiteral(
            "• alpha words fill several wrapped lines in the chat bubble at every tested width\n" ++
                "- bravo words fill several wrapped lines in the chat bubble at every tested width\n" ++
                "* charlie words fill several wrapped lines in the chat bubble at every tested width\n" ++
                "1. delta words fill several wrapped lines in the chat bubble at every tested width\n" ++
                "10. echo words fill several wrapped lines in the chat bubble at every tested width\n" ++
                "• foxtrot words fill several wrapped lines in the chat bubble at every tested width\n" ++
                "  • nested words fill several wrapped lines in the chat bubble at every tested width\n" ++
                "    1. deeper words fill several wrapped lines in the chat bubble at every tested width",
        );
    };
    for ([_]i32{ 1, 2, 4 }) |unit| {
        for ([_]i32{ 24, 40, 60 }) |columns| {
            const metrics = TestMetrics{ .unit = unit };
            var layout = Layout{ .text = text, .width = columns * unit, .line_height = 5 * unit, .lists = true };
            var item: usize = 0;
            var marker_x: i32 = 0;
            var text_x: i32 = 0;
            var previous_y: i32 = -1;
            var first = false;
            var wraps: [8]usize = @splat(0);
            var text_positions: [8]i32 = undefined;
            while (layout.next(metrics)) |span| {
                if (span.space) continue;
                const is_marker = prefix(text[span.start..span.word_end]) != null;
                if (is_marker) {
                    if (item > 0) try std.testing.expect(wraps[item - 1] > 0);
                    marker_x = span.x;
                    first = true;
                    item += 1;
                } else if (first) {
                    text_x = span.x;
                    text_positions[item - 1] = text_x;
                    try std.testing.expect(text_x > marker_x);
                    first = false;
                } else if (span.y != previous_y) {
                    try std.testing.expectEqual(text_x, span.x);
                    try std.testing.expect(span.x > marker_x);
                    wraps[item - 1] += 1;
                }
                previous_y = span.y;
                try std.testing.expect(span.x + metrics.width(text[span.start..][0..span.len]) <= layout.width);
            }
            try std.testing.expectEqual(@as(usize, 8), item);
            for (wraps) |count| try std.testing.expect(count > 0);
            try std.testing.expect(text_positions[6] > text_positions[5]);
            try std.testing.expect(text_positions[7] > text_positions[6]);
            try std.testing.expectEqual(previous_y + layout.line_height, layout.height());
        }
    }
}

test "IGSH-829 list detection leaves prose alone and long words still advance at narrow widths" {
    for ([_][]const u16{
        std.unicode.utf8ToUtf16LeStringLiteral("plain text"),
        std.unicode.utf8ToUtf16LeStringLiteral("*bold* text"),
        std.unicode.utf8ToUtf16LeStringLiteral("---"),
        std.unicode.utf8ToUtf16LeStringLiteral("1.not a list"),
    }) |text| try std.testing.expectEqual(@as(?Prefix, null), prefix(text));
    const text = std.unicode.utf8ToUtf16LeStringLiteral("- abcdefghijklmnopqrstuvwxyz\nplain\n");
    var layout = Layout{ .text = text, .width = 4, .line_height = 1, .lists = true };
    var count: usize = 0;
    while (layout.next(TestMetrics{ .unit = 1 })) |span| {
        count += 1;
        try std.testing.expect(count <= text.len);
        if (span.start >= 2 and span.start < 28) try std.testing.expectEqual(@as(i32, 2), span.x);
        if (span.start == 29) try std.testing.expectEqual(@as(i32, 0), span.x);
    }
    try std.testing.expect(layout.done);
    try std.testing.expectEqual(layout.y + 1, layout.height());
}

test "IGSH-829 fenced code keeps literal list-looking text" {
    const text = std.unicode.utf8ToUtf16LeStringLiteral("```\n- literal code words wrap without list indentation\n```\n- actual list words wrap with hanging indentation");
    var layout = Layout{ .text = text, .width = 12, .line_height = 1, .lists = true };
    var code_wrap = false;
    var list_wrap = false;
    while (layout.next(TestMetrics{ .unit = 1 })) |span| {
        if (span.space) continue;
        if (span.start > 6 and span.start < 53 and span.x == 0) code_wrap = true;
        if (span.start > 58 and span.x == 2) list_wrap = true;
    }
    try std.testing.expect(code_wrap and list_wrap);
}

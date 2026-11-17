const std = @import("std");
const chat_list_layout = @import("chat_list_layout.zig");

pub const Body = struct { height: i32, overflow: bool };

pub fn measureBody(text: []const u16, width: i32, line_height: i32, max_lines: i32, metrics: anytype) Body {
    if (text.len == 0) return .{ .height = 0, .overflow = false };
    var measure = chat_list_layout.Layout{ .text = text, .width = width, .line_height = line_height, .lists = false };
    var overflow = false;
    while (measure.next(metrics)) |span| {
        if (span.y >= line_height * max_lines) {
            overflow = true;
            break;
        }
    }
    return .{ .height = @min(measure.height(), line_height * max_lines), .overflow = overflow };
}

pub fn blockHeight(vertical_pad: i32, name_height: i32, body_height: i32, after_gap: i32) i32 {
    return vertical_pad + name_height + body_height + after_gap;
}

const TestMetrics = struct {
    unit: i32,

    pub fn width(self: TestMetrics, text: []const u16) i32 {
        return @as(i32, @intCast(text.len)) * self.unit;
    }

    pub fn fit(self: TestMetrics, text: []const u16, available: i32) usize {
        return @min(text.len, @as(usize, @intCast(@max(1, @divTrunc(available, self.unit)))));
    }
};

test "quote body respects line cap across widths and scales" {
    const word = std.unicode.utf8ToUtf16LeStringLiteral("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz");
    const max_lines: i32 = 2;
    for ([_]i32{ 100, 125, 150, 200 }) |scale| {
        const metrics = TestMetrics{ .unit = @divTrunc(8 * scale, 100) };
        const line_height = @divTrunc(20 * scale, 100);
        var previous_height: i32 = 0;
        var width: i32 = 600;
        while (width >= 120) : (width -= 10) {
            const body = measureBody(word, width, line_height, max_lines, metrics);
            const units_per_line = @divTrunc(width, metrics.unit);
            const lines = @divTrunc(@as(i32, @intCast(word.len)) + units_per_line - 1, units_per_line);
            try std.testing.expectEqual(@min(lines, max_lines) * line_height, body.height);
            try std.testing.expectEqual(lines > max_lines, body.overflow);
            try std.testing.expect(body.height <= line_height * max_lines);
            try std.testing.expect(body.height >= previous_height);
            previous_height = body.height;
            try std.testing.expectEqual(Body{ .height = 0, .overflow = false }, measureBody(&.{}, width, line_height, max_lines, metrics));
        }
        const wrapped = measureBody(word, 120, line_height, max_lines, metrics);
        try std.testing.expectEqual(line_height * max_lines, wrapped.height);
        try std.testing.expect(wrapped.overflow);
    }
}

test "quote body counts explicit lines and block spacing" {
    const metrics = TestMetrics{ .unit = 8 };
    const one = std.unicode.utf8ToUtf16LeStringLiteral("one");
    const two = std.unicode.utf8ToUtf16LeStringLiteral("one\ntwo");
    const three = std.unicode.utf8ToUtf16LeStringLiteral("one\ntwo\nthree");
    try std.testing.expectEqual(Body{ .height = 20, .overflow = false }, measureBody(one, 120, 20, 2, metrics));
    try std.testing.expectEqual(Body{ .height = 40, .overflow = false }, measureBody(two, 120, 20, 2, metrics));
    try std.testing.expectEqual(Body{ .height = 40, .overflow = true }, measureBody(three, 120, 20, 2, metrics));
    try std.testing.expectEqual(@as(i32, 72), blockHeight(6, 20, 40, 6));
}

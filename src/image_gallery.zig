const std = @import("std");

pub const Selection = struct {
    index: usize,
    position: usize,
    total: usize,
    previous: ?usize = null,
    next: ?usize = null,
};

pub fn select(messages: anytype, current: usize, comptime isImage: anytype) ?Selection {
    if (current >= messages.len or !isImage(&messages[current])) return null;
    var result = Selection{ .index = current, .position = 0, .total = 0 };
    for (messages, 0..) |*message, index| {
        if (!isImage(message)) continue;
        result.total += 1;
        if (index < current) result.previous = index;
        if (index == current) result.position = result.total;
        if (index > current and result.next == null) result.next = index;
    }
    return result;
}

pub const Direction = enum { previous, next };

pub fn neighbour(selection: Selection, direction: Direction) ?usize {
    return switch (direction) {
        .previous => selection.previous,
        .next => selection.next,
    };
}

const Kind = enum { text, image, audio, video, document };
fn image(kind: *const Kind) bool {
    return kind.* == .image;
}

test "images follow message order and skip every non-image kind" {
    const messages = [_]Kind{ .text, .image, .audio, .video, .image, .document, .image, .text };
    const middle = select(&messages, 4, image).?;
    try std.testing.expectEqual(@as(usize, 4), middle.index);
    try std.testing.expectEqual(@as(usize, 2), middle.position);
    try std.testing.expectEqual(@as(usize, 3), middle.total);
    try std.testing.expectEqual(@as(?usize, 1), neighbour(middle, .previous));
    try std.testing.expectEqual(@as(?usize, 6), neighbour(middle, .next));
    try std.testing.expect(select(&messages, 3, image) == null);
}

test "ends stop without wrapping" {
    const messages = [_]Kind{ .text, .image, .audio, .image, .document };
    const first = select(&messages, 1, image).?;
    const last = select(&messages, 3, image).?;
    try std.testing.expect(neighbour(first, .previous) == null);
    try std.testing.expectEqual(@as(?usize, 3), neighbour(first, .next));
    try std.testing.expectEqual(@as(?usize, 1), neighbour(last, .previous));
    try std.testing.expect(neighbour(last, .next) == null);
    try std.testing.expectEqual(@as(usize, 1), first.position);
    try std.testing.expectEqual(last.total, last.position);
}

test "empty, single-image and invalid selections" {
    const empty = [_]Kind{};
    const text = [_]Kind{ .text, .audio };
    const single = [_]Kind{ .text, .image, .video };
    try std.testing.expect(select(&empty, 0, image) == null);
    try std.testing.expect(select(&text, 0, image) == null);
    try std.testing.expect(select(&single, single.len, image) == null);
    const selected = select(&single, 1, image).?;
    try std.testing.expectEqual(@as(usize, 1), selected.position);
    try std.testing.expectEqual(@as(usize, 1), selected.total);
    try std.testing.expect(selected.previous == null and selected.next == null);
}

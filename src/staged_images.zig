const std = @import("std");

pub const capacity = 16;
pub const Capability = enum { single_file, multiple_files };
pub const Send = struct {
    first: usize,
    count: usize,
    text: []const u8,
};
pub const Plan = struct {
    items: [capacity]Send = undefined,
    count: usize = 0,
};

pub fn List(comptime Image: type) type {
    return struct {
        const Self = @This();
        items: [capacity]Image = [_]Image{.{}} ** capacity,
        count: usize = 0,

        pub fn add(self: *Self, image: Image) bool {
            if (self.count == capacity) return false;
            self.items[self.count] = image;
            self.count += 1;
            return true;
        }

        pub fn remove(self: *Self, index: usize) ?Image {
            if (index >= self.count) return null;
            const image = self.items[index];
            for (index..self.count - 1) |i| self.items[i] = self.items[i + 1];
            self.count -= 1;
            self.items[self.count] = .{};
            return image;
        }

        pub fn clear(self: *Self) void {
            self.* = .{};
        }

        pub fn sendPlan(self: *const Self, text: []const u8, capability: Capability) Plan {
            var plan = Plan{};
            if (self.count == 0) return plan;
            if (capability == .multiple_files) {
                plan.items[0] = .{ .first = 0, .count = self.count, .text = text };
                plan.count = 1;
            } else {
                for (0..self.count) |index| plan.items[index] = .{ .first = index, .count = 1, .text = if (index == 0) text else "" };
                plan.count = self.count;
            }
            return plan;
        }
    };
}

const Fixture = struct { id: usize = 0 };

test "staged images append in order" {
    var images = List(Fixture){};
    try std.testing.expect(images.add(.{ .id = 1 }));
    try std.testing.expect(images.add(.{ .id = 2 }));
    try std.testing.expectEqual(@as(usize, 2), images.count);
    try std.testing.expectEqual(@as(usize, 1), images.items[0].id);
    try std.testing.expectEqual(@as(usize, 2), images.items[1].id);
}

test "staged remove first preserves remaining order" {
    var images = List(Fixture){};
    for (1..4) |id| try std.testing.expect(images.add(.{ .id = id }));
    try std.testing.expectEqual(@as(usize, 1), images.remove(0).?.id);
    try std.testing.expectEqual(@as(usize, 2), images.items[0].id);
    try std.testing.expectEqual(@as(usize, 3), images.items[1].id);
    try std.testing.expect(images.remove(2) == null);
    try std.testing.expectEqual(@as(usize, 3), images.remove(1).?.id);
}

test "staged clear permits reuse without old images" {
    var images = List(Fixture){};
    try std.testing.expect(images.add(.{ .id = 1 }));
    images.clear();
    try std.testing.expectEqual(@as(usize, 0), images.count);
    try std.testing.expectEqual(@as(usize, 0), images.items[0].id);
    try std.testing.expect(images.add(.{ .id = 2 }));
    try std.testing.expectEqual(@as(usize, 2), images.items[0].id);
}

test "staged capacity failure retains every image" {
    var images = List(Fixture){};
    for (0..capacity) |id| try std.testing.expect(images.add(.{ .id = id }));
    try std.testing.expect(!images.add(.{ .id = capacity }));
    try std.testing.expectEqual(@as(usize, capacity), images.count);
    for (0..capacity) |id| try std.testing.expectEqual(id, images.items[id].id);
}

test "staged single file plan captions only the first image" {
    var images = List(Fixture){};
    for (1..4) |id| try std.testing.expect(images.add(.{ .id = id }));
    const plan = images.sendPlan("caption", .single_file);
    try std.testing.expectEqual(images.count, plan.count);
    for (plan.items[0..plan.count], 0..) |send, index| {
        try std.testing.expectEqual(index, send.first);
        try std.testing.expectEqual(@as(usize, 1), send.count);
        try std.testing.expectEqualStrings(if (index == 0) "caption" else "", send.text);
    }
}

test "staged multi file plan groups images and empty plan sends nothing" {
    var images = List(Fixture){};
    try std.testing.expectEqual(@as(usize, 0), images.sendPlan("caption", .single_file).count);
    try std.testing.expectEqual(@as(usize, 0), images.sendPlan("caption", .multiple_files).count);
    for (1..4) |id| try std.testing.expect(images.add(.{ .id = id }));
    const plan = images.sendPlan("caption", .multiple_files);
    try std.testing.expectEqual(@as(usize, 1), plan.count);
    try std.testing.expectEqual(@as(usize, 0), plan.items[0].first);
    try std.testing.expectEqual(images.count, plan.items[0].count);
    try std.testing.expectEqualStrings("caption", plan.items[0].text);
    const empty_caption = images.sendPlan("", .single_file);
    for (empty_caption.items[0..empty_caption.count]) |send| try std.testing.expectEqualStrings("", send.text);
}

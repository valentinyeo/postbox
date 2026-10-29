const std = @import("std");
const theme = @import("theme.zig");

pub const PreferredAppMode = enum(i32) {
    default = 0,
    force_dark = 2,
};

pub fn preferredAppMode(choice: theme.Choice) PreferredAppMode {
    return switch (choice) {
        .amoled => .force_dark,
    };
}

test "IGSH-505 AMOLED forces dark native menus" {
    try std.testing.expectEqual(PreferredAppMode.force_dark, preferredAppMode(.amoled));
    try std.testing.expectEqual(@as(i32, 2), @intFromEnum(preferredAppMode(.amoled)));
}

test "saved light menu choices migrate to dark graphite menus" {
    try std.testing.expectEqual(PreferredAppMode.force_dark, preferredAppMode(theme.choiceFromSaved(0)));
}

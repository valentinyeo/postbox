const std = @import("std");
const theme = @import("theme.zig");

pub const PreferredAppMode = enum(i32) {
    default = 0,
    force_dark = 2,
};

pub fn preferredAppMode(choice: theme.Choice) PreferredAppMode {
    _ = choice;
    return .default;
}

test "IGSH-505 AMOLED forces dark native menus" {
    try std.testing.expectEqual(PreferredAppMode.force_dark, preferredAppMode(.amoled));
    try std.testing.expectEqual(@as(i32, 2), @intFromEnum(preferredAppMode(.amoled)));
}

test "IGSH-505 Green keeps default native menus" {
    try std.testing.expectEqual(PreferredAppMode.default, preferredAppMode(.green));
    try std.testing.expectEqual(@as(i32, 0), @intFromEnum(preferredAppMode(.green)));
}

test "IGSH-505 switching back from AMOLED restores default native menus" {
    for ([_]theme.Choice{ .amoled, .green, .amoled, .green }) |choice| {
        const expected: PreferredAppMode = if (choice == .amoled) .force_dark else .default;
        try std.testing.expectEqual(expected, preferredAppMode(choice));
    }
}

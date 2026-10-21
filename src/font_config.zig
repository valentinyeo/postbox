const std = @import("std");

pub const body_weight: i32 = 500;
pub const files = [_][]const u8{
    "IBMPlexSans-Regular.ttf",
    "IBMPlexSans-Medium.ttf",
    "IBMPlexSans-SemiBold.ttf",
    "IBMPlexSans-Bold.ttf",
};

test "WAZI-161 bundled font list includes all four weights" {
    const expected = [_][]const u8{ "IBMPlexSans-Regular.ttf", "IBMPlexSans-Medium.ttf", "IBMPlexSans-SemiBold.ttf", "IBMPlexSans-Bold.ttf" };
    try std.testing.expectEqual(expected.len, files.len);
    for (expected, files) |want, actual| try std.testing.expectEqualStrings(want, actual);
}

test "WAZI-161 body text uses Medium weight" {
    try std.testing.expectEqual(@as(i32, 500), body_weight);
}

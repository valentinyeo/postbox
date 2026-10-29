const std = @import("std");
const pin = @import("pin_icon.zig");
const theme = @import("theme.zig");

test "shared pin and unpin are distinct Fluent glyphs at the approved size" {
    try std.testing.expectEqual(@as(u16, 0xE718), pin.pinned);
    try std.testing.expectEqual(@as(u16, 0xE77A), pin.unpinned);
    try std.testing.expect(pin.pinned != pin.unpinned);
    try std.testing.expectEqual(@as(i32, 16), theme.icon_size);
}

test "pin colours remain visible on normal selected and bulk rows" {
    for ([_]u32{ theme.amoled.surface_container_low, theme.amoled.surface_container_highest }) |background| {
        try std.testing.expect(theme.contrastRatio(theme.amoled.on_surface_variant, background) >= 3);
    }
    try std.testing.expect(theme.contrastRatio(theme.amoled.on_primary_container, theme.amoled.primary_container) >= 3);
}

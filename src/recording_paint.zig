const std = @import("std");

pub const tick_interval_ms = 100;

pub fn tickDirtyRect(client: anytype, strip: @TypeOf(client)) ?struct { rect: @TypeOf(client), erase: bool } {
    const rect = @TypeOf(client){
        .left = @max(client.left, strip.left),
        .top = @max(client.top, strip.top),
        .right = @min(client.right, strip.right),
        .bottom = @min(client.bottom, strip.bottom),
    };
    if (rect.right <= rect.left or rect.bottom <= rect.top) return null;
    if (std.meta.eql(rect, client)) return null;
    return .{ .rect = rect, .erase = false };
}

const Rect = struct { left: i32, top: i32, right: i32, bottom: i32 };

test "IGSH-482 every tick dirty rectangle stays inside the strip and client without erase" {
    for ([_]i32{ 96, 120, 144, 192 }) |dpi| {
        const client = Rect{ .left = 0, .top = 0, .right = @divTrunc(1200 * dpi, 96), .bottom = @divTrunc(800 * dpi, 96) };
        const strip = Rect{ .left = client.right - @divTrunc(444 * dpi, 96), .top = client.bottom - @divTrunc(55 * dpi, 96), .right = client.right - @divTrunc(244 * dpi, 96), .bottom = client.bottom - @divTrunc(11 * dpi, 96) };
        const dirty = tickDirtyRect(client, strip).?;
        try std.testing.expectEqualDeep(strip, dirty.rect);
        try std.testing.expect(!dirty.erase);
        try std.testing.expect(!std.meta.eql(client, dirty.rect));
    }
}

test "IGSH-482 clipped and degenerate strips cannot dirty the whole client" {
    const client = Rect{ .left = 0, .top = 0, .right = 300, .bottom = 200 };
    const strip = Rect{ .left = -20, .top = 150, .right = 80, .bottom = 220 };
    const dirty = tickDirtyRect(client, strip).?;
    try std.testing.expectEqualDeep(Rect{ .left = 0, .top = 150, .right = 80, .bottom = 200 }, dirty.rect);
    try std.testing.expect(dirty.rect.left >= strip.left and dirty.rect.top >= strip.top);
    try std.testing.expect(dirty.rect.right <= strip.right and dirty.rect.bottom <= strip.bottom);
    try std.testing.expect(!dirty.erase);
    for ([_]Rect{
        client,
        .{ .left = -10, .top = -10, .right = 310, .bottom = 210 },
        .{ .left = 0, .top = 0, .right = 0, .bottom = 20 },
        .{ .left = 310, .top = 150, .right = 400, .bottom = 180 },
        .{ .left = 10, .top = 20, .right = 5, .bottom = 15 },
    }) |invalid| try std.testing.expect(tickDirtyRect(client, invalid) == null);
}

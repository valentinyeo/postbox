const std = @import("std");
const compose_layout = @import("compose_layout.zig");
const theme = @import("theme.zig");

const win = struct {
    const HDC = ?*anyopaque;
    const HBITMAP = ?*anyopaque;
    const HGDIOBJ = ?*anyopaque;
    const RECT = struct { left: i32, top: i32, right: i32, bottom: i32 };
    const ERROR = 0;
    const SRCCOPY = 0x00cc0020;
    var failure: enum { none, dc, bitmap, selection, viewport, clip } = .none;
    var dc_count: usize = 0;
    var bitmap_count: usize = 0;
    var blits: usize = 0;
    var clipped: ?RECT = null;
    var copied: ?RECT = null;
    var bitmap_size: ?[2]i32 = null;
    var bitmap_bytes: usize = 0;
    var origin: ?[2]i32 = null;
    var calls: [8]u8 = undefined;
    var call_count: usize = 0;
    var selected: HGDIOBJ = @ptrFromInt(4);

    fn reset() void {
        failure = .none;
        dc_count = 0;
        bitmap_count = 0;
        blits = 0;
        clipped = null;
        copied = null;
        bitmap_size = null;
        bitmap_bytes = 0;
        origin = null;
        call_count = 0;
        selected = @ptrFromInt(4);
    }

    fn CreateCompatibleDC(_: HDC) HDC {
        if (failure == .dc) return null;
        dc_count += 1;
        return @ptrFromInt(2);
    }

    fn CreateCompatibleBitmap(_: HDC, width: i32, height: i32) HBITMAP {
        std.debug.assert(width > 0 and height > 0);
        if (failure == .bitmap) return null;
        bitmap_count += 1;
        bitmap_size = .{ width, height };
        bitmap_bytes = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * 4;
        return @ptrFromInt(3);
    }

    fn SelectObject(_: HDC, object: HGDIOBJ) HGDIOBJ {
        if (failure == .selection and object == @as(HGDIOBJ, @ptrFromInt(3))) return null;
        const previous = selected;
        selected = object;
        return previous;
    }

    fn SetViewportOrgEx(_: HDC, x: i32, y: i32, _: ?*anyopaque) i32 {
        if (failure == .viewport) return 0;
        origin = .{ x, y };
        calls[call_count] = 'v';
        call_count += 1;
        return 1;
    }

    fn IntersectClipRect(_: HDC, left: i32, top: i32, right: i32, bottom: i32) i32 {
        if (failure == .clip) return ERROR;
        calls[call_count] = 'c';
        call_count += 1;
        clipped = .{ .left = left, .top = top, .right = right, .bottom = bottom };
        return 2;
    }

    fn BitBlt(target: HDC, left: i32, top: i32, width: i32, height: i32, source: HDC, x: i32, y: i32, mode: u32) i32 {
        std.debug.assert(target == @as(HDC, @ptrFromInt(1)));
        std.debug.assert(source == @as(HDC, @ptrFromInt(2)));
        std.debug.assert(x == left and y == top and mode == SRCCOPY);
        copied = .{ .left = left, .top = top, .right = left + width, .bottom = top + height };
        blits += 1;
        return 1;
    }

    fn DeleteObject(object: HGDIOBJ) i32 {
        std.debug.assert(selected != object);
        bitmap_count -= 1;
        return 1;
    }

    fn DeleteDC(_: HDC) i32 {
        dc_count -= 1;
        return 1;
    }
};

const App = struct {
    dpi: u32 = 96,
    compose_client_width: i32 = 1200,
    compose_client_height: i32 = 800,
    compose_dragged: i32 = 0,
    content_height: i32 = 44,
    compose_strip_top: i32 = 734,
    compose_pill: struct { top: i32 } = .{ .top = 745 },
    staged_image: struct { path: struct { len: usize = 0 } = .{} } = .{},
    layouts: usize = 0,
    saves: usize = 0,
    shortcodes: usize = 0,
};

fn composerContentHeight(a: *App) i32 {
    return a.content_height;
}

fn px(a: *const App, value: i32) i32 {
    return @divTrunc(value * @as(i32, @intCast(a.dpi)) + 48, 96);
}

fn layout(a: *App, width: i32, height: i32) void {
    layoutRegion(a, width, height, null);
}

fn layoutRegion(a: *App, width: i32, height: i32, dirty: ?*const win.RECT) void {
    if (dirty) |rect| {
        std.debug.assert(rect.left > 0 and rect.top >= 0 and rect.right == width and rect.bottom == height);
    }
    std.debug.assert(width == a.compose_client_width and height == a.compose_client_height);
    a.layouts += 1;
    const sizes = compose_layout.computeScaled(a.compose_dragged, a.content_height, height, a.staged_image.path.len > 0, @intCast(a.dpi));
    a.compose_strip_top = height - sizes.strip_height;
    a.compose_pill.top = height - px(a, 11) - sizes.edit_height;
}

fn saveComposerDraft(a: *App) void {
    a.saves += 1;
}

fn shortcodeUpdate(a: *App) void {
    a.shortcodes += 1;
}

test "IGSH-510 repeated typing requests zero layouts on AMOLED and Green" {
    const previous = theme.choice;
    defer theme.set(previous);
    for ([_]theme.Choice{ .amoled, .green }) |choice| {
        theme.set(choice);
        for ([_]u32{ 96, 120, 144, 192 }) |dpi| {
            var a = App{ .dpi = dpi };
            a.content_height = px(&a, 44);
            layout(&a, a.compose_client_width, a.compose_client_height);
            a.layouts = 0;
            for (0..100) |_| composeChanged(&a);
            try std.testing.expectEqual(@as(usize, 0), a.layouts);
            try std.testing.expectEqual(@as(usize, 100), a.saves);
            try std.testing.expectEqual(@as(usize, 100), a.shortcodes);
            std.debug.print("IGSH-510 typing {s} dpi={d}: edits=100 layouts={d}\n", .{ @tagName(choice), dpi, a.layouts });
        }
    }
}

test "IGSH-510 composer still grows shrinks and respects dragged height and previews" {
    var a = App{};
    a.content_height = 88;
    composeChanged(&a);
    try std.testing.expectEqual(@as(usize, 1), a.layouts);
    try std.testing.expectEqual(@as(i32, 690), a.compose_strip_top);
    composeChanged(&a);
    try std.testing.expectEqual(@as(usize, 1), a.layouts);
    a.content_height = 44;
    composeChanged(&a);
    try std.testing.expectEqual(@as(usize, 2), a.layouts);
    a.compose_dragged = 320;
    composeChanged(&a);
    try std.testing.expectEqual(@as(i32, 458), a.compose_strip_top);
    a.staged_image.path.len = 1;
    composeChanged(&a);
    try std.testing.expectEqual(@as(i32, 404), a.compose_strip_top);
}

test "IGSH-510 dirty painting clips and presents only changed pixels once on both themes" {
    const previous = theme.choice;
    defer theme.set(previous);
    const client = win.RECT{ .left = 0, .top = 0, .right = 1200, .bottom = 800 };
    for ([_]theme.Choice{ .amoled, .green }) |choice| {
        theme.set(choice);
        for ([_]win.RECT{
            .{ .left = 400, .top = 700, .right = 1100, .bottom = 790 },
            .{ .left = 1188, .top = 0, .right = 1200, .bottom = 700 },
            .{ .left = 0, .top = 112, .right = 380, .bottom = 176 },
        }) |dirty| {
            win.reset();
            var buffer = Buffer.init(@ptrFromInt(1), client, dirty);
            try std.testing.expect(buffer.hdc != buffer.target);
            try std.testing.expectEqualDeep(dirty, win.clipped.?);
            try std.testing.expectEqual(@as(usize, 0), win.blits);
            buffer.deinit();
            try std.testing.expectEqualDeep(dirty, win.copied.?);
            try std.testing.expectEqual(@as(usize, 1), win.blits);
            try std.testing.expectEqual(@as(usize, 0), win.dc_count);
            try std.testing.expectEqual(@as(usize, 0), win.bitmap_count);
        }
    }
}

test "IGSH-510 exposure paints fully while empty and outside dirty regions allocate nothing" {
    const client = win.RECT{ .left = 0, .top = 0, .right = 1200, .bottom = 800 };
    win.reset();
    var buffer = Buffer.init(@ptrFromInt(1), client, client);
    buffer.deinit();
    try std.testing.expectEqualDeep(client, win.copied.?);
    win.reset();
    buffer = Buffer.init(@ptrFromInt(1), client, .{ .left = -20, .top = 780, .right = 40, .bottom = 850 });
    buffer.deinit();
    try std.testing.expectEqualDeep(win.RECT{ .left = 0, .top = 780, .right = 40, .bottom = 800 }, win.copied.?);
    win.reset();
    buffer = Buffer.init(@ptrFromInt(1), client, .{ .left = 1300, .top = 0, .right = 1400, .bottom = 10 });
    buffer.deinit();
    try std.testing.expectEqual(@as(usize, 0), win.blits);
    try std.testing.expectEqual(@as(usize, 0), win.dc_count);
}

test "IGSH-510 allocation selection and clipping failures clean up and retain the paint DC" {
    const client = win.RECT{ .left = 0, .top = 0, .right = 1200, .bottom = 800 };
    inline for (.{ .dc, .bitmap, .selection, .viewport, .clip }) |failure| {
        win.reset();
        win.failure = failure;
        var buffer = Buffer.init(@ptrFromInt(1), client, client);
        try std.testing.expectEqual(buffer.target, buffer.hdc);
        buffer.deinit();
        try std.testing.expectEqual(@as(usize, 0), win.dc_count);
        try std.testing.expectEqual(@as(usize, 0), win.bitmap_count);
        try std.testing.expectEqual(@as(usize, 0), win.blits);
    }
}

test "ISSUE_545 dirty-rect sizing bounds bitmap memory by the row and not the window" {
    const row_height = 64 * 2;
    for ([_]win.RECT{
        .{ .left = 0, .top = 0, .right = 1200, .bottom = 800 },
        .{ .left = 0, .top = 0, .right = 3840, .bottom = 2160 },
        .{ .left = 0, .top = 0, .right = 7680, .bottom = 4320 },
    }) |client| {
        const row = win.RECT{ .left = 0, .top = 5 * row_height, .right = 760, .bottom = 6 * row_height };
        win.reset();
        var buffer = Buffer.init(@ptrFromInt(1), client, row);
        try std.testing.expectEqual([2]i32{ 760, row_height }, win.bitmap_size.?);
        try std.testing.expectEqual(@as(usize, 760 * row_height * 4), win.bitmap_bytes);
        var rows: usize = 0;
        var total: usize = 0;
        while (rows < 15) : (rows += 1) total += win.bitmap_bytes;
        try std.testing.expect(total < 6 * 1024 * 1024);
        buffer.deinit();
        try std.testing.expectEqual(@as(usize, 0), win.bitmap_count);
        std.debug.print("ISSUE_545 client {d}x{d} row bitmap {d}x{d} = {d} bytes, 15 rows {d} bytes\n", .{ client.right, client.bottom, win.bitmap_size.?[0], win.bitmap_size.?[1], win.bitmap_bytes, total });
    }
}

test "ISSUE_545 viewport offset keeps window coordinates for drawing clipping and presenting" {
    const client = win.RECT{ .left = 0, .top = 0, .right = 3840, .bottom = 2160 };
    for ([_]win.RECT{
        .{ .left = 0, .top = 640, .right = 760, .bottom = 768 },
        .{ .left = 1200, .top = 1900, .right = 3840, .bottom = 2160 },
        .{ .left = -40, .top = 2100, .right = 100, .bottom = 2400 },
    }) |dirty| {
        win.reset();
        var buffer = Buffer.init(@ptrFromInt(1), client, dirty);
        const rect = buffer.rect;
        try std.testing.expectEqual([2]i32{ rect.right - rect.left, rect.bottom - rect.top }, win.bitmap_size.?);
        try std.testing.expectEqual([2]i32{ -rect.left, -rect.top }, win.origin.?);
        try std.testing.expectEqualSlices(u8, "vc", win.calls[0..win.call_count]);
        try std.testing.expectEqualDeep(rect, win.clipped.?);
        buffer.deinit();
        try std.testing.expectEqualDeep(rect, win.copied.?);
        try std.testing.expectEqual(@as(usize, 1), win.blits);
    }
}

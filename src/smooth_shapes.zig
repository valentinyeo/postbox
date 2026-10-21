const std = @import("std");
const win = @import("win32.zig").c;
const geometry = @import("smooth_geometry.zig");

const Handle = ?*anyopaque;
const Status = c_int;
const StartupInput = extern struct {
    version: u32 = 1,
    debug_callback: ?*anyopaque = null,
    suppress_thread: win.BOOL = 0,
    suppress_codecs: win.BOOL = 0,
};
const Api = struct {
    GdipCreateFromHDC: *const fn (win.HDC, *Handle) callconv(.winapi) Status,
    GdipGetDC: *const fn (Handle, *win.HDC) callconv(.winapi) Status,
    GdipReleaseDC: *const fn (Handle, win.HDC) callconv(.winapi) Status,
    GdipSaveGraphics: *const fn (Handle, *u32) callconv(.winapi) Status,
    GdipRestoreGraphics: *const fn (Handle, u32) callconv(.winapi) Status,
    GdipSetClipRect: *const fn (Handle, f32, f32, f32, f32, c_int) callconv(.winapi) Status,
    GdipDeleteGraphics: *const fn (Handle) callconv(.winapi) Status,
    GdipSetSmoothingMode: *const fn (Handle, c_int) callconv(.winapi) Status,
    GdipSetPixelOffsetMode: *const fn (Handle, c_int) callconv(.winapi) Status,
    GdipCreatePath: *const fn (c_int, *Handle) callconv(.winapi) Status,
    GdipDeletePath: *const fn (Handle) callconv(.winapi) Status,
    GdipAddPathArc: *const fn (Handle, f32, f32, f32, f32, f32, f32) callconv(.winapi) Status,
    GdipAddPathLine: *const fn (Handle, f32, f32, f32, f32) callconv(.winapi) Status,
    GdipClosePathFigure: *const fn (Handle) callconv(.winapi) Status,
    GdipCreateSolidFill: *const fn (u32, *Handle) callconv(.winapi) Status,
    GdipDeleteBrush: *const fn (Handle) callconv(.winapi) Status,
    GdipCreatePen1: *const fn (u32, f32, c_int, *Handle) callconv(.winapi) Status,
    GdipDeletePen: *const fn (Handle) callconv(.winapi) Status,
    GdipFillPath: *const fn (Handle, Handle, Handle) callconv(.winapi) Status,
    GdipDrawPath: *const fn (Handle, Handle, Handle) callconv(.winapi) Status,
    GdipFillEllipse: *const fn (Handle, Handle, f32, f32, f32, f32) callconv(.winapi) Status,
    GdipDrawArc: *const fn (Handle, Handle, f32, f32, f32, f32, f32, f32) callconv(.winapi) Status,
    GdipDrawEllipse: *const fn (Handle, Handle, f32, f32, f32, f32) callconv(.winapi) Status,
};

var api: ?Api = null;
var token: usize = 0;
var once = std.mem.zeroes(win.INIT_ONCE);

fn loadOnce(_: win.PINIT_ONCE, _: win.PVOID, _: [*c]win.PVOID) callconv(.winapi) win.BOOL {
    load();
    return win.TRUE;
}

fn load() void {
    const module = win.LoadLibraryW(std.unicode.utf8ToUtf16LeStringLiteral("gdiplus.dll")) orelse return;
    var loaded = false;
    defer if (!loaded) {
        _ = win.FreeLibrary(module);
    };
    const startup: *const fn (*usize, *const StartupInput, ?*anyopaque) callconv(.winapi) Status = @ptrCast(win.GetProcAddress(module, "GdiplusStartup") orelse return);
    var functions: Api = undefined;
    inline for (@typeInfo(Api).@"struct".fields) |field| {
        @field(functions, field.name) = @ptrCast(win.GetProcAddress(module, field.name ++ "\x00") orelse return);
    }
    if (startup(&token, &.{}, null) != 0) return;
    api = functions;
    loaded = true;
}

fn argb(color: win.COLORREF) u32 {
    return 0xff000000 | ((color & 0xff) << 16) | (color & 0xff00) | ((color >> 16) & 0xff);
}

pub const Context = struct {
    hdc: win.HDC,
    graphics: Handle = null,

    pub fn init(hdc: win.HDC) Context {
        _ = win.InitOnceExecuteOnce(&once, loadOnce, null, null);
        var result = Context{ .hdc = hdc };
        if (api) |f| {
            if (f.GdipCreateFromHDC(hdc, &result.graphics) == 0 and result.graphics != null) {
                if (f.GdipSetSmoothingMode(result.graphics, 4) == 0 and f.GdipSetPixelOffsetMode(result.graphics, 4) == 0) return result;
                _ = f.GdipDeleteGraphics(result.graphics);
            }
        }
        result.graphics = null;
        return result;
    }

    pub fn deinit(self: *Context) void {
        if (self.graphics) |graphics| _ = api.?.GdipDeleteGraphics(graphics);
        self.graphics = null;
    }
};

fn roundPath(rect: win.RECT, corner_width: i32, corner_height: i32) Handle {
    const f = api.?;
    var path: Handle = null;
    if (f.GdipCreatePath(0, &path) != 0 or path == null) return null;
    const l: f32 = @floatFromInt(rect.left);
    const t: f32 = @floatFromInt(rect.top);
    const r: f32 = @floatFromInt(rect.right);
    const b: f32 = @floatFromInt(rect.bottom);
    const w: f32 = @floatFromInt(std.math.clamp(corner_width, 0, rect.right - rect.left));
    const h: f32 = @floatFromInt(std.math.clamp(corner_height, 0, rect.bottom - rect.top));
    const status = if (w == 0 or h == 0)
        f.GdipAddPathLine(path, l, t, r, t) | f.GdipAddPathLine(path, r, t, r, b) | f.GdipAddPathLine(path, r, b, l, b) | f.GdipAddPathLine(path, l, b, l, t)
    else
        f.GdipAddPathArc(path, l, t, w, h, 180, 90) | f.GdipAddPathArc(path, r - w, t, w, h, 270, 90) | f.GdipAddPathArc(path, r - w, b - h, w, h, 0, 90) | f.GdipAddPathArc(path, l, b - h, w, h, 90, 90);
    if (status != 0 or f.GdipClosePathFigure(path) != 0) {
        _ = f.GdipDeletePath(path);
        return null;
    }
    return path;
}

fn draw(ctx: *const Context, rect: win.RECT, corner_width: i32, corner_height: i32, color: win.COLORREF, stroke: ?i32, ellipse: bool) void {
    if (rect.right <= rect.left or rect.bottom <= rect.top) return;
    if (ctx.graphics) |graphics| {
        const f = api.?;
        var shape = rect;
        if (stroke != null) {
            shape.right -= 1;
            shape.bottom -= 1;
        }
        var resource: Handle = null;
        const status = if (stroke) |width| f.GdipCreatePen1(argb(color), @floatFromInt(@max(1, width)), 2, &resource) else f.GdipCreateSolidFill(argb(color), &resource);
        if (status == 0 and resource != null) {
            defer {
                if (stroke != null) _ = f.GdipDeletePen(resource) else _ = f.GdipDeleteBrush(resource);
            }
            if (ellipse) {
                const x: f32 = @floatFromInt(shape.left);
                const y: f32 = @floatFromInt(shape.top);
                const w: f32 = @floatFromInt(shape.right - shape.left);
                const h: f32 = @floatFromInt(shape.bottom - shape.top);
                const drawn = if (stroke != null) f.GdipDrawEllipse(graphics, resource, x, y, w, h) else f.GdipFillEllipse(graphics, resource, x, y, w, h);
                if (drawn == 0) return;
            } else if (roundPath(shape, corner_width, corner_height)) |path| {
                defer _ = f.GdipDeletePath(path);
                const drawn = if (stroke != null) f.GdipDrawPath(graphics, resource, path) else f.GdipFillPath(graphics, resource, path);
                if (drawn == 0) return;
            }
        }
    }
    const brush = if (stroke == null) win.CreateSolidBrush(color) orelse return else null;
    defer if (brush) |b| {
        _ = win.DeleteObject(b);
    };
    const pen = if (stroke) |width| win.CreatePen(win.PS_SOLID, @max(1, width), color) orelse return else null;
    defer if (pen) |p| {
        _ = win.DeleteObject(p);
    };
    const old_brush = win.SelectObject(ctx.hdc, if (brush) |b| @ptrCast(b) else win.GetStockObject(win.NULL_BRUSH));
    const old_pen = win.SelectObject(ctx.hdc, if (pen) |p| @ptrCast(p) else win.GetStockObject(win.NULL_PEN));
    defer {
        _ = win.SelectObject(ctx.hdc, old_brush);
        _ = win.SelectObject(ctx.hdc, old_pen);
    }
    if (ellipse) {
        _ = win.Ellipse(ctx.hdc, rect.left, rect.top, rect.right, rect.bottom);
    } else {
        _ = win.RoundRect(ctx.hdc, rect.left, rect.top, rect.right, rect.bottom, corner_width, corner_height);
    }
}

fn fillHybrid(ctx: *const Context, rect: win.RECT, corner_width: i32, corner_height: i32, color: win.COLORREF, parts: geometry.Partition) bool {
    const f = api.?;
    const graphics = ctx.graphics.?;
    const brush = win.CreateSolidBrush(color) orelse return false;
    defer _ = win.DeleteObject(brush);
    var aa_brush: Handle = null;
    if (f.GdipCreateSolidFill(argb(color), &aa_brush) != 0 or aa_brush == null) return false;
    defer _ = f.GdipDeleteBrush(aa_brush);
    {
        var dc: win.HDC = null;
        if (f.GdipGetDC(graphics, &dc) != 0 or dc == null) return false;
        defer _ = f.GdipReleaseDC(graphics, dc);
        for (parts.bands) |band| {
            if (band.right == band.left or band.bottom == band.top) continue;
            const bounds: win.RECT = @bitCast(band);
            if (win.FillRect(dc, &bounds, brush) == 0) return false;
        }
        _ = win.GdiFlush();
    }
    const w: f32 = @floatFromInt(std.math.clamp(corner_width, 0, rect.right - rect.left));
    const h: f32 = @floatFromInt(std.math.clamp(corner_height, 0, rect.bottom - rect.top));
    for (parts.corners, 0..) |box, orientation| {
        if (box.right == box.left or box.bottom == box.top) continue;
        var state: u32 = 0;
        if (f.GdipSaveGraphics(graphics, &state) != 0) return false;
        defer _ = f.GdipRestoreGraphics(graphics, state);
        if (f.GdipSetClipRect(graphics, @floatFromInt(box.left), @floatFromInt(box.top), @floatFromInt(box.right - box.left), @floatFromInt(box.bottom - box.top), 1) != 0) return false;
        var path: Handle = null;
        if (f.GdipCreatePath(0, &path) != 0 or path == null) return false;
        defer _ = f.GdipDeletePath(path);
        const right = orientation == 1 or orientation == 2;
        const bottom = orientation >= 2;
        const ax = if (right) @as(f32, @floatFromInt(rect.right)) - w else @as(f32, @floatFromInt(rect.left));
        const ay = if (bottom) @as(f32, @floatFromInt(rect.bottom)) - h else @as(f32, @floatFromInt(rect.top));
        const ix: f32 = @floatFromInt(if (right) box.left - 1 else box.right + 1);
        const iy: f32 = @floatFromInt(if (bottom) box.top - 1 else box.bottom + 1);
        const ex = ax + w / 2;
        const ey = if (bottom) ay + h else ay;
        const sx = if (right) ax + w else ax;
        const sy = ay + h / 2;
        const start = ([_]f32{ 180, 270, 0, 90 })[orientation];
        if (f.GdipAddPathArc(path, ax, ay, w, h, start, 90) != 0) return false;
        const status = if (orientation == 0 or orientation == 2)
            f.GdipAddPathLine(path, ex, ey, ix, ey) | f.GdipAddPathLine(path, ix, ey, ix, iy) | f.GdipAddPathLine(path, ix, iy, sx, iy) | f.GdipAddPathLine(path, sx, iy, sx, sy)
        else
            f.GdipAddPathLine(path, sx, sy, sx, iy) | f.GdipAddPathLine(path, sx, iy, ix, iy) | f.GdipAddPathLine(path, ix, iy, ix, ey) | f.GdipAddPathLine(path, ix, ey, ex, ey);
        if (status != 0 or f.GdipClosePathFigure(path) != 0 or f.GdipFillPath(graphics, aa_brush, path) != 0) return false;
    }
    return true;
}

pub fn fillRoundRect(ctx: *const Context, rect: win.RECT, corner_width: i32, corner_height: i32, color: win.COLORREF) void {
    if (ctx.graphics != null) {
        if (geometry.partition(@bitCast(rect), corner_width, corner_height)) |parts| {
            if (fillHybrid(ctx, rect, corner_width, corner_height, color, parts)) return;
        }
    }
    draw(ctx, rect, corner_width, corner_height, color, null, false);
}

pub fn strokeRoundRect(ctx: *const Context, rect: win.RECT, corner_width: i32, corner_height: i32, color: win.COLORREF, width: i32) void {
    draw(ctx, rect, corner_width, corner_height, color, width, false);
}

pub fn fillEllipse(ctx: *const Context, rect: win.RECT, color: win.COLORREF) void {
    draw(ctx, rect, 0, 0, color, null, true);
}

pub fn strokeEllipse(ctx: *const Context, rect: win.RECT, color: win.COLORREF, width: i32) void {
    draw(ctx, rect, 0, 0, color, width, true);
}

pub fn strokeArc(ctx: *const Context, rect: win.RECT, start: f32, sweep: f32, color: win.COLORREF, width: i32) void {
    if (ctx.graphics) |graphics| {
        const f = api.?;
        var pen: Handle = null;
        if (f.GdipCreatePen1(argb(color), @floatFromInt(@max(1, width)), 2, &pen) == 0 and pen != null) {
            defer _ = f.GdipDeletePen(pen);
            if (f.GdipDrawArc(graphics, pen, @floatFromInt(rect.left), @floatFromInt(rect.top), @floatFromInt(rect.right - rect.left - 1), @floatFromInt(rect.bottom - rect.top - 1), start, sweep) == 0) return;
        }
    }
    const pen = win.CreatePen(win.PS_SOLID, @max(1, width), color) orelse return;
    defer _ = win.DeleteObject(pen);
    const previous = win.SelectObject(ctx.hdc, pen);
    defer _ = win.SelectObject(ctx.hdc, previous);
    const direction = win.SetArcDirection(ctx.hdc, if (sweep > 0) win.AD_CLOCKWISE else win.AD_COUNTERCLOCKWISE);
    defer _ = win.SetArcDirection(ctx.hdc, direction);
    const cx: f32 = @as(f32, @floatFromInt(rect.left + rect.right - 1)) / 2;
    const cy: f32 = @as(f32, @floatFromInt(rect.top + rect.bottom - 1)) / 2;
    const rx: f32 = @as(f32, @floatFromInt(rect.right - rect.left)) / 2;
    const ry: f32 = @as(f32, @floatFromInt(rect.bottom - rect.top)) / 2;
    const a = start * std.math.pi / 180;
    const b = (start + sweep) * std.math.pi / 180;
    _ = win.Arc(ctx.hdc, rect.left, rect.top, rect.right, rect.bottom, @intFromFloat(cx + rx * @cos(a)), @intFromFloat(cy + ry * @sin(a)), @intFromFloat(cx + rx * @cos(b)), @intFromFloat(cy + ry * @sin(b)));
}

test "rounded shapes preserve solid colours and bounds with partial edge coverage at both scales" {
    const size = 192;
    const dc = win.CreateCompatibleDC(null) orelse return error.CreateDCFailed;
    defer _ = win.DeleteDC(dc);
    var info = std.mem.zeroes(win.BITMAPINFO);
    info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    info.bmiHeader.biWidth = size;
    info.bmiHeader.biHeight = -size;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    var bits: ?*anyopaque = null;
    const bitmap = win.CreateDIBSection(dc, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse return error.CreateBitmapFailed;
    defer _ = win.DeleteObject(bitmap);
    const old = win.SelectObject(dc, bitmap);
    defer _ = win.SelectObject(dc, old);
    const pixels: []u32 = @as([*]u32, @ptrCast(@alignCast(bits.?)))[0 .. size * size];
    var ctx = Context.init(dc);
    defer ctx.deinit();
    try std.testing.expect(ctx.graphics != null);
    const color = 0x00332211;
    const expected = argb(color) & 0xffffff;
    for ([_]i32{ 2, 3 }) |scale| {
        const rect = win.RECT{ .left = 10 * scale, .top = 10 * scale, .right = 60 * scale, .bottom = 40 * scale };
        for ([_]enum { rounded, ellipse, arc }{ .rounded, .ellipse, .arc }) |kind| {
            for ([_]?i32{ null, scale }) |stroke| {
                if (kind == .arc and stroke == null) continue;
                var reference_bounds: ?win.RECT = null;
                for ([_]bool{ false, true }) |antialias| {
                    @memset(pixels, 0xffffffff);
                    const fallback = Context{ .hdc = dc };
                    const context = if (antialias) &ctx else &fallback;
                    if (kind == .arc) strokeArc(context, rect, 180, 180, color, stroke.?) else draw(context, rect, 12 * scale, 12 * scale, color, stroke, kind == .ellipse);
                    _ = win.GdiFlush();
                    var bounds = win.RECT{ .left = size, .top = size, .right = 0, .bottom = 0 };
                    var partial: usize = 0;
                    var solid: usize = 0;
                    for (pixels, 0..) |pixel, i| {
                        const rgb = pixel & 0xffffff;
                        if (rgb == 0xffffff) continue;
                        const x: i32 = @intCast(i % size);
                        const y: i32 = @intCast(i / size);
                        bounds.left = @min(bounds.left, x);
                        bounds.top = @min(bounds.top, y);
                        bounds.right = @max(bounds.right, x + 1);
                        bounds.bottom = @max(bounds.bottom, y + 1);
                        if (rgb == expected) solid += 1 else partial += 1;
                    }
                    try std.testing.expect(solid > 0);
                    if (antialias) {
                        if (partial == 0) std.debug.print("no AA coverage: kind={s} scale={d} stroke={any} solid={d}\n", .{ @tagName(kind), scale, stroke, solid });
                        try std.testing.expect(partial > 0);
                        const reference = reference_bounds.?;
                        try std.testing.expect(@abs(bounds.left - reference.left) <= 1);
                        try std.testing.expect(@abs(bounds.top - reference.top) <= 1);
                        try std.testing.expect(@abs(bounds.right - reference.right) <= 1);
                        try std.testing.expect(@abs(bounds.bottom - reference.bottom) <= 1);
                    } else {
                        try std.testing.expectEqual(@as(usize, 0), partial);
                        reference_bounds = bounds;
                    }
                }
            }
        }
    }
}

test "hybrid fills match full paths at edges and exactly inside with odd corners clipping and overlaps" {
    const size = 256;
    const dc = win.CreateCompatibleDC(null) orelse return error.CreateDCFailed;
    defer _ = win.DeleteDC(dc);
    var info = std.mem.zeroes(win.BITMAPINFO);
    info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    info.bmiHeader.biWidth = size;
    info.bmiHeader.biHeight = -size;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    var bits: ?*anyopaque = null;
    const bitmap = win.CreateDIBSection(dc, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse return error.CreateBitmapFailed;
    defer _ = win.DeleteObject(bitmap);
    const old = win.SelectObject(dc, bitmap);
    defer _ = win.SelectObject(dc, old);
    const pixels = @as([*]u32, @ptrCast(@alignCast(bits.?)))[0 .. size * size];
    var reference: [size * size]u32 = undefined;
    const colors = [_]win.COLORREF{ 0x00332211, 0x00b4d8ed };
    for ([_]i32{ 2, 3 }) |scale| {
        for ([_][4]i32{
            .{ 150, 50, 32, 32 },
            .{ 150, 90, 32, 32 },
            .{ 120, 40, 32, 32 },
            .{ 31, 47, 15, 21 },
            .{ 9, 60, 9, 9 },
            .{ 60, 9, 9, 9 },
            .{ 9, 60, 99, 9 },
            .{ 21, 21, 21, 21 },
            .{ 22, 22, 20, 20 },
            .{ 120, 40, 0, 0 },
        }) |dimensions| {
            for ([_]bool{ false, true }) |clipped| {
                for ([_]u32{ 0xffffffff, 0xff304050 }) |background| {
                    for ([_]bool{ false, true }) |hybrid| {
                        @memset(pixels, background);
                        const saved = win.SaveDC(dc);
                        try std.testing.expect(saved != 0);
                        defer _ = win.RestoreDC(dc, saved);
                        if (clipped) _ = win.IntersectClipRect(dc, 25, 22, 210, 180);
                        var ctx = Context.init(dc);
                        defer ctx.deinit();
                        try std.testing.expect(ctx.graphics != null);
                        for (colors, 0..) |color, i| {
                            const offset: i32 = @intCast(i * 13);
                            const rect = win.RECT{ .left = 8 + offset, .top = 11 + offset, .right = 8 + offset + @divTrunc(dimensions[0] * scale, 2), .bottom = 11 + offset + @divTrunc(dimensions[1] * scale, 2) };
                            const cw = @divTrunc(dimensions[2] * scale, 2);
                            const ch = @divTrunc(dimensions[3] * scale, 2);
                            if (hybrid) {
                                if (geometry.partition(@bitCast(rect), cw, ch)) |parts| {
                                    try std.testing.expect(fillHybrid(&ctx, rect, cw, ch, color, parts));
                                } else fillRoundRect(&ctx, rect, cw, ch, color);
                            } else draw(&ctx, rect, cw, ch, color, null, false);
                        }
                        draw(&ctx, .{ .left = 2, .top = 2, .right = 35, .bottom = 35 }, 4, 4, 0x00806040, null, false);
                        ctx.deinit();
                        _ = win.GdiFlush();
                        if (!hybrid) {
                            @memcpy(&reference, pixels);
                            continue;
                        }
                        for (reference, pixels, 0..) |expected, actual, index| {
                            const solid = for (colors) |color| {
                                if ((expected & 0xffffff) == (argb(color) & 0xffffff)) break true;
                            } else false;
                            inline for (.{ 0, 8, 16 }) |shift| {
                                const a: i32 = @intCast((actual >> shift) & 255);
                                const b: i32 = @intCast((expected >> shift) & 255);
                                if (@abs(a - b) > @as(u32, if (solid) 0 else 1)) {
                                    std.debug.print("scale={d} dimensions={any} clipped={} background={x} pixel={d},{d} expected={x} actual={x}\n", .{ scale, dimensions, clipped, background, index % size, index / size, expected, actual });
                                    return error.HybridPixelMismatch;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

test "scrollbar fill keeps the pixel bounds of an uncompensated GDI rounded region" {
    const size = 96;
    const dc = win.CreateCompatibleDC(null) orelse return error.CreateDCFailed;
    defer _ = win.DeleteDC(dc);
    var info = std.mem.zeroes(win.BITMAPINFO);
    info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    info.bmiHeader.biWidth = size;
    info.bmiHeader.biHeight = -size;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    var bits: ?*anyopaque = null;
    const bitmap = win.CreateDIBSection(dc, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse return error.CreateBitmapFailed;
    defer _ = win.DeleteObject(bitmap);
    const old = win.SelectObject(dc, bitmap);
    defer _ = win.SelectObject(dc, old);
    const pixels = @as([*]u32, @ptrCast(@alignCast(bits.?)))[0 .. size * size];
    const color = 0x00332211;
    const brush = win.CreateSolidBrush(color) orelse return error.CreateBrushFailed;
    defer _ = win.DeleteObject(brush);
    for ([_]i32{ 6, 9 }) |width| {
        const rect = win.RECT{ .left = 10, .top = 12, .right = 10 + width, .bottom = 60 };
        const region = win.CreateRoundRectRgn(rect.left, rect.top, rect.right, rect.bottom, width, width) orelse return error.CreateRegionFailed;
        defer _ = win.DeleteObject(region);
        var reference: win.RECT = undefined;
        try std.testing.expect(win.GetRgnBox(region, &reference) != win.ERROR);
        for ([_]bool{ false, true }) |antialias| {
            @memset(pixels, 0xffffffff);
            if (antialias) {
                var ctx = Context.init(dc);
                defer ctx.deinit();
                try std.testing.expect(ctx.graphics != null);
                fillRoundRect(&ctx, .{ .left = rect.left, .top = rect.top, .right = rect.right - 1, .bottom = rect.bottom - 1 }, width, width, color);
            } else try std.testing.expect(win.FillRgn(dc, region, brush) != 0);
            _ = win.GdiFlush();
            var bounds = win.RECT{ .left = size, .top = size, .right = 0, .bottom = 0 };
            for (pixels, 0..) |pixel, i| {
                if (pixel & 0xffffff == 0xffffff) continue;
                const x: i32 = @intCast(i % size);
                const y: i32 = @intCast(i / size);
                bounds.left = @min(bounds.left, x);
                bounds.top = @min(bounds.top, y);
                bounds.right = @max(bounds.right, x + 1);
                bounds.bottom = @max(bounds.bottom, y + 1);
            }
            try std.testing.expectEqualDeep(reference, bounds);
            try std.testing.expectEqual(width - 1, bounds.right - bounds.left);
            try std.testing.expectEqual(rect.bottom - rect.top - 1, bounds.bottom - bounds.top);
        }
    }
}

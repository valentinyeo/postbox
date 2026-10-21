const std = @import("std");
const win = @import("win32.zig").c;
const geometry = @import("smooth_geometry.zig");
const coverage = @import("smooth_coverage.zig");

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
    GdipSetPenLineJoin: *const fn (Handle, c_int) callconv(.winapi) Status,
    GdipSetPenStartCap: *const fn (Handle, c_int) callconv(.winapi) Status,
    GdipSetPenEndCap: *const fn (Handle, c_int) callconv(.winapi) Status,
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
                var clip: win.RECT = undefined;
                const kind = win.GetClipBox(hdc, &clip);
                if (kind != win.ERROR and
                    f.GdipSetClipRect(result.graphics, @floatFromInt(clip.left), @floatFromInt(clip.top), @floatFromInt(@max(0, clip.right - clip.left)), @floatFromInt(@max(0, clip.bottom - clip.top)), 0) == 0 and
                    f.GdipSetSmoothingMode(result.graphics, 4) == 0 and f.GdipSetPixelOffsetMode(result.graphics, 4) == 0) return result;
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
    fillCoverage(ctx, .{ .rect = @bitCast(rect), .corner_width = corner_width, .corner_height = corner_height, .ellipse = ellipse, .stroke = stroke }, color);
}

pub fn strokePolyline(ctx: *const Context, points: []const [2]f32, color: win.COLORREF, width: f32) void {
    if (points.len < 2) return;
    const stroke = @max(1, width);
    if (ctx.graphics) |graphics| {
        const f = api.?;
        var path: Handle = null;
        if (f.GdipCreatePath(0, &path) == 0 and path != null) {
            defer _ = f.GdipDeletePath(path);
            var status: Status = 0;
            for (points[0 .. points.len - 1], points[1..]) |start, end| {
                status |= f.GdipAddPathLine(path, start[0], start[1], end[0], end[1]);
            }
            var pen: Handle = null;
            if (status == 0 and f.GdipCreatePen1(argb(color), stroke, 2, &pen) == 0 and pen != null) {
                defer _ = f.GdipDeletePen(pen);
                status |= f.GdipSetPenLineJoin(pen, 2) | f.GdipSetPenStartCap(pen, 2) | f.GdipSetPenEndCap(pen, 2);
                if (status == 0 and f.GdipDrawPath(graphics, pen, path) == 0) return;
            }
        }
    }
    var low = points[0];
    var high = points[0];
    for (points[1..]) |point| {
        inline for (0..2) |axis| {
            low[axis] = @min(low[axis], point[axis]);
            high[axis] = @max(high[axis], point[axis]);
        }
    }
    const padding = stroke / 2 + 1;
    const box = geometry.Rect{
        .left = @intFromFloat(@floor(low[0] - padding)),
        .top = @intFromFloat(@floor(low[1] - padding)),
        .right = @intFromFloat(@ceil(high[0] + padding)),
        .bottom = @intFromFloat(@ceil(high[1] + padding)),
    };
    var dc = ctx.hdc;
    if (ctx.graphics) |graphics| {
        if (api.?.GdipGetDC(graphics, &dc) != 0 or dc == null) return;
    }
    defer if (ctx.graphics) |graphics| {
        _ = api.?.GdipReleaseDC(graphics, dc);
    };
    blendCoverage(dc, box, coverage.Polyline{ .points = points, .width = stroke }, color);
}

fn blendCoverage(dc: win.HDC, box: geometry.Rect, shape: anytype, color: win.COLORREF) void {
    const width = box.right - box.left;
    const height = box.bottom - box.top;
    if (width <= 0 or height <= 0) return;
    const memory = win.CreateCompatibleDC(dc) orelse return;
    defer _ = win.DeleteDC(memory);
    var info = std.mem.zeroes(win.BITMAPINFO);
    info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    var bits: ?*anyopaque = null;
    const bitmap = win.CreateDIBSection(memory, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse return;
    defer _ = win.DeleteObject(bitmap);
    const previous = win.SelectObject(memory, bitmap);
    defer _ = win.SelectObject(memory, previous);
    const pixels: [*]u32 = @ptrCast(@alignCast(bits orelse return));
    var y: i32 = 0;
    while (y < height) : (y += 1) {
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            pixels[@intCast(y * width + x)] = coverage.premultiplied(color, shape.alphaAt(box.left + x, box.top + y));
        }
    }
    _ = win.AlphaBlend(dc, box.left, box.top, width, height, memory, 0, 0, width, height, .{ .BlendOp = win.AC_SRC_OVER, .BlendFlags = 0, .SourceConstantAlpha = 255, .AlphaFormat = win.AC_SRC_ALPHA });
}

fn fillCoverage(ctx: *const Context, shape: coverage.Shape, color: win.COLORREF) void {
    if (shape.rect.right <= shape.rect.left or shape.rect.bottom <= shape.rect.top) return;
    var dc = ctx.hdc;
    if (ctx.graphics) |graphics| {
        if (api.?.GdipGetDC(graphics, &dc) != 0 or dc == null) return;
    }
    defer if (ctx.graphics) |graphics| {
        _ = api.?.GdipReleaseDC(graphics, dc);
    };
    if (shape.stroke == null and !shape.ellipse) {
        if (shape.corner_width <= 0 or shape.corner_height <= 0) {
            const brush = win.CreateSolidBrush(color) orelse return;
            defer _ = win.DeleteObject(brush);
            const bounds: win.RECT = @bitCast(shape.rect);
            _ = win.FillRect(dc, &bounds, brush);
            return;
        }
        if (geometry.partition(shape.rect, shape.corner_width, shape.corner_height)) |parts| {
            const brush = win.CreateSolidBrush(color) orelse return;
            defer _ = win.DeleteObject(brush);
            for (parts.bands) |band| {
                const bounds: win.RECT = @bitCast(band);
                _ = win.FillRect(dc, &bounds, brush);
            }
            for (parts.corners) |corner| blendCoverage(dc, corner, shape, color);
            return;
        }
    }
    var box = shape.rect;
    if (shape.stroke) |stroke| {
        const padding = @divTrunc(@max(1, stroke) + 1, 2);
        box.left -= padding;
        box.top -= padding;
        box.right += padding;
        box.bottom += padding;
    }
    blendCoverage(dc, box, shape, color);
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
    fillCoverage(ctx, .{ .rect = @bitCast(rect), .ellipse = true, .stroke = width, .arc = .{ .start = start, .sweep = sweep } }, color);
}

test "rounded shapes and forced fallback preserve solid colours and bounds with partial edge coverage at both scales" {
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
                    try std.testing.expect(partial > 0);
                    if (antialias) {
                        const reference = reference_bounds.?;
                        try std.testing.expect(@abs(bounds.left - reference.left) <= 1);
                        try std.testing.expect(@abs(bounds.top - reference.top) <= 1);
                        try std.testing.expect(@abs(bounds.right - reference.right) <= 1);
                        try std.testing.expect(@abs(bounds.bottom - reference.bottom) <= 1);
                    } else {
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

test "scrollbar fill keeps the exclusive pixel bounds at both scales" {
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
    for ([_]i32{ 6, 9 }) |width| {
        const rect = win.RECT{ .left = 10, .top = 12, .right = 10 + width, .bottom = 60 };
        const reference = win.RECT{ .left = rect.left, .top = rect.top, .right = rect.right - 1, .bottom = rect.bottom - 1 };
        for ([_]bool{ false, true }) |antialias| {
            @memset(pixels, 0xffffffff);
            var ctx = if (antialias) Context.init(dc) else Context{ .hdc = dc };
            defer ctx.deinit();
            fillRoundRect(&ctx, reference, width, width, color);
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

test "forced GDI fallback preserves solid pixels edge bands coverage area and every curved edge" {
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
    const pixels = @as([*]u32, @ptrCast(@alignCast(bits.?)))[0 .. size * size];
    var reference: [size * size]u32 = undefined;
    var failed = false;
    for ([_]i32{ 2, 3 }) |scale| {
        const rect = win.RECT{ .left = 10 * scale, .top = 10 * scale, .right = 50 * scale, .bottom = 40 * scale };
        for ([_]enum { rounded, ellipse, arc }{ .rounded, .ellipse, .arc }) |kind| {
            for ([_]i32{ 4, 12, 21 }) |diameter| {
                if (kind != .rounded and diameter != 12) continue;
                for ([_]?i32{ null, 1, scale }) |stroke| {
                    if (kind == .arc and stroke == null) continue;
                    for ([_]bool{ false, true }) |fallback| {
                        @memset(pixels, 0xff000000);
                        var ctx = if (fallback) Context{ .hdc = dc } else Context.init(dc);
                        defer ctx.deinit();
                        if (!fallback) try std.testing.expect(ctx.graphics != null);
                        if (kind == .arc) strokeArc(&ctx, rect, 183.814075, -187.628150, 0x00ffffff, stroke.?) else if (kind == .ellipse) {
                            if (stroke) |width| strokeEllipse(&ctx, rect, 0x00ffffff, width) else fillEllipse(&ctx, rect, 0x00ffffff);
                        } else if (stroke) |width| strokeRoundRect(&ctx, rect, diameter * scale, diameter * scale, 0x00ffffff, width) else fillRoundRect(&ctx, rect, diameter * scale, diameter * scale, 0x00ffffff);
                        ctx.deinit();
                        _ = win.GdiFlush();
                        if (!fallback) @memcpy(&reference, pixels);
                    }
                    var native_area: u64 = 0;
                    var fallback_area: u64 = 0;
                    var solid_mismatches: usize = 0;
                    var off_edge: usize = 0;
                    var different: usize = 0;
                    var partial_edges = [_]usize{0} ** 8;
                    const inset: f32 = if (stroke != null) 1 else 0;
                    const w = @as(f32, @floatFromInt(rect.right - rect.left)) - inset;
                    const h = @as(f32, @floatFromInt(rect.bottom - rect.top)) - inset;
                    const rx = if (kind == .rounded) @as(f32, @floatFromInt(diameter * scale)) / 2 else w / 2;
                    const ry = if (kind == .rounded) rx else h / 2;
                    for (reference, pixels, 0..) |expected, actual, i| {
                        const a = actual & 255;
                        const b = expected & 255;
                        native_area += b;
                        fallback_area += a;
                        if ((a >= 250 and b >= 250 or a <= 5 and b <= 5) and (actual & 0xffffff) != (expected & 0xffffff)) {
                            solid_mismatches += 1;
                        }
                        if ((actual & 0xffffff) != (expected & 0xffffff)) {
                            different += 1;
                            const x: i32 = @intCast(i % size);
                            const y: i32 = @intCast(i / size);
                            var edge = false;
                            for ([_]i32{ -1, 0, 1 }) |dy| {
                                for ([_]i32{ -1, 0, 1 }) |dx| {
                                    const nx = x + dx;
                                    const ny = y + dy;
                                    if (nx < 0 or ny < 0 or nx >= size or ny >= size) continue;
                                    const j: usize = @intCast(ny * size + nx);
                                    const na = pixels[j] & 255;
                                    const nb = reference[j] & 255;
                                    if (na > 0 and na < 255 or nb > 0 and nb < 255) edge = true;
                                }
                            }
                            if (!edge) off_edge += 1;
                        }
                        if (a > 0 and a < 255) {
                            const px = @as(f32, @floatFromInt(i % size)) + 0.5 - @as(f32, @floatFromInt(rect.left)) - w / 2;
                            const py = @as(f32, @floatFromInt(i / size)) + 0.5 - @as(f32, @floatFromInt(rect.top)) - h / 2;
                            const qx = @abs(px) - (w / 2 - rx);
                            const qy = @abs(py) - (h / 2 - ry);
                            if (kind == .rounded and (qx <= 0 or qy <= 0)) continue;
                            const inside = qx * qx / (rx * rx) + qy * qy / (ry * ry) < 1;
                            const quadrant: usize = @as(usize, if (px >= 0) 1 else 0) + @as(usize, if (kind != .arc and py >= 0) 2 else 0);
                            const edge_index = quadrant * @as(usize, if (stroke != null) 2 else 1) + @as(usize, if (stroke != null and inside) 1 else 0);
                            partial_edges[edge_index] += 1;
                        }
                    }
                    const edge_count: usize = @as(usize, if (kind == .arc) 2 else 4) * @as(usize, if (stroke != null) 2 else 1);
                    const min_partial = std.mem.min(usize, partial_edges[0..edge_count]);
                    const area_difference = @abs(@as(i64, @intCast(fallback_area)) - @as(i64, @intCast(native_area)));
                    std.debug.print("scale={d}% kind={s} diameter={d} stroke={any} native={d} fallback={d} area_error={d:.3}% solid_mismatch={d} off_edge={d} different={d} min_partial={d}\n", .{ scale * 50, @tagName(kind), diameter * scale, stroke, native_area, fallback_area, @as(f64, @floatFromInt(area_difference)) * 100 / @as(f64, @floatFromInt(native_area)), solid_mismatches, off_edge, different, min_partial });
                    if (solid_mismatches != 0 or off_edge != 0 or native_area == 0 or area_difference * 100 > native_area * 2 or min_partial == 0) failed = true;
                }
            }
        }
    }
    try std.testing.expect(!failed);
}

const Ink = struct {
    dc: win.HDC,
    bitmap: win.HBITMAP,
    previous: win.HGDIOBJ,
    pixels: []u32,

    fn init(size: i32) !Ink {
        const dc = win.CreateCompatibleDC(null) orelse return error.CreateDCFailed;
        var info = std.mem.zeroes(win.BITMAPINFO);
        info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
        info.bmiHeader.biWidth = size;
        info.bmiHeader.biHeight = -size;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        var bits: ?*anyopaque = null;
        const bitmap = win.CreateDIBSection(dc, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse {
            _ = win.DeleteDC(dc);
            return error.CreateBitmapFailed;
        };
        const count: usize = @intCast(size * size);
        const pixels = @as([*]u32, @ptrCast(@alignCast(bits.?)))[0..count];
        @memset(pixels, 0x00123456);
        return .{ .dc = dc, .bitmap = bitmap, .previous = win.SelectObject(dc, bitmap), .pixels = pixels };
    }

    fn deinit(self: *Ink) void {
        _ = win.SelectObject(self.dc, self.previous);
        _ = win.DeleteObject(self.bitmap);
        _ = win.DeleteDC(self.dc);
    }
};

fn paintIssue545Row(dc: win.HDC, row: win.RECT, antialias: bool) !void {
    var smooth_context = Context.init(dc);
    defer smooth_context.deinit();
    if (antialias) try std.testing.expect(smooth_context.graphics != null);
    const fallback = Context{ .hdc = dc };
    const ctx = if (antialias) &smooth_context else &fallback;
    const background = win.CreateSolidBrush(0x00141210) orelse return error.BrushFailed;
    defer _ = win.DeleteObject(background);
    _ = win.FillRect(dc, &row, background);
    fillRoundRect(ctx, .{ .left = row.left + 8, .top = row.top + 2, .right = row.right - 8, .bottom = row.bottom - 2 }, 24, 24, 0x00403a36);
    fillEllipse(ctx, .{ .left = row.left + 12, .top = row.top + 10, .right = row.left + 54, .bottom = row.top + 52 }, 0x00b0e0a0);
    strokeArc(ctx, .{ .left = row.left + 70, .top = row.top + 8, .right = row.left + 110, .bottom = row.top + 48 }, 180, 180, 0x0060c0ff, 3);
    strokePolyline(ctx, &.{ .{ @floatFromInt(row.left + 130), @floatFromInt(row.top + 12) }, .{ @floatFromInt(row.left + 160), @floatFromInt(row.top + 40) } }, 0x00f0f0f0, 2);
    fillRoundRect(ctx, .{ .left = row.left - 20, .top = row.top - 10, .right = row.left + 30, .bottom = row.top + 20 }, 16, 16, 0x000000ff);
    _ = win.GdiFlush();
}

test "ISSUE-545 row-sized buffer places GDI and GDI+ pixels where unbuffered painting does" {
    const paint_buffer = @import("paint_buffer.zig");
    const size = 256;
    const client = win.RECT{ .left = 0, .top = 0, .right = size, .bottom = size };
    for ([_]win.RECT{
        .{ .left = 0, .top = 128, .right = 220, .bottom = 192 },
        .{ .left = 37, .top = 61, .right = 251, .bottom = 125 },
        .{ .left = 200, .top = 230, .right = 300, .bottom = 300 },
    }) |dirty| {
        for ([_]bool{ true, false }) |antialias| {
            var direct = try Ink.init(size);
            defer direct.deinit();
            var buffered = try Ink.init(size);
            defer buffered.deinit();
            const saved = win.SaveDC(direct.dc);
            _ = win.IntersectClipRect(direct.dc, dirty.left, dirty.top, dirty.right, dirty.bottom);
            try paintIssue545Row(direct.dc, dirty, antialias);
            _ = win.RestoreDC(direct.dc, saved);
            {
                var surface = paint_buffer.Buffer.init(buffered.dc, client, dirty);
                defer surface.deinit();
                try std.testing.expect(surface.hdc != buffered.dc);
                var bitmap: win.BITMAP = undefined;
                const selected = win.GetCurrentObject(surface.hdc, win.OBJ_BITMAP) orelse return error.NoBitmap;
                try std.testing.expect(win.GetObjectW(selected, @sizeOf(win.BITMAP), &bitmap) != 0);
                try std.testing.expectEqual(surface.rect.right - surface.rect.left, bitmap.bmWidth);
                try std.testing.expectEqual(surface.rect.bottom - surface.rect.top, bitmap.bmHeight);
                try paintIssue545Row(surface.hdc, dirty, antialias);
            }
            _ = win.GdiFlush();
            var ink: usize = 0;
            var mismatched: usize = 0;
            for (direct.pixels, buffered.pixels, 0..) |want, got, i| {
                if (want & 0xffffff != got & 0xffffff) {
                    if (mismatched < 8) std.debug.print("ISSUE-545 mismatch antialias={} dirty={any} at ({d},{d}): want {x} got {x}\n", .{ antialias, dirty, i % size, i / size, want, got });
                    mismatched += 1;
                }
                if (want & 0xffffff != 0x123456) ink += 1;
            }
            try std.testing.expect(ink > 0);
            try std.testing.expectEqual(@as(usize, 0), mismatched);
        }
    }
}

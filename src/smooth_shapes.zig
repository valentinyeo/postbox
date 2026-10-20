const std = @import("std");
const win = @import("win32.zig").c;

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

pub fn fillRoundRect(ctx: *const Context, rect: win.RECT, corner_width: i32, corner_height: i32, color: win.COLORREF) void {
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

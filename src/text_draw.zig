const std = @import("std");
const builtin = @import("builtin");
const win = @import("win32.zig").c;
const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cDefine("COBJMACROS", "1");
    @cInclude("dwrite_3.h");
    @cInclude("d2d1.h");
});

const Flags = struct {
    const center = 0x1;
    const right = 0x2;
    const vcenter = 0x4;
    const bottom = 0x8;
    const wordbreak = 0x10;
    const singleline = 0x20;
    const noclip = 0x100;
    const calcrect = 0x400;
    const noprefix = 0x800;
    const word_ellipsis = 0x40000;
    const end_ellipsis = 0x8000;
};
const Options = struct {
    wrap: bool,
    alignment: u32,
    vertical: enum { top, center, bottom },
    trimming: u32,
    clip: bool,
};
fn options(flags: u32) Options {
    return .{
        .wrap = flags & Flags.wordbreak != 0 and flags & Flags.singleline == 0,
        .alignment = if (flags & Flags.right != 0) 1 else if (flags & Flags.center != 0) 2 else 0,
        .vertical = if (flags & Flags.bottom != 0) .bottom else if (flags & Flags.vcenter != 0 and flags & Flags.singleline != 0) .center else .top,
        .trimming = if (flags & Flags.word_ellipsis != 0) 2 else if (flags & Flags.end_ellipsis != 0) 1 else 0,
        .clip = flags & Flags.noclip == 0,
    };
}
fn stripPrefix(text: []const u16, out: []u16) []u16 {
    var i: usize = 0;
    var n: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '&') {
            i += 1;
            if (i == text.len) break;
        }
        out[n] = text[i];
        n += 1;
    }
    return out[0..n];
}
fn updateRect(rect: anytype, width: f32, height: f32) i32 {
    const h: i32 = @intFromFloat(@ceil(height));
    rect.right = rect.left + @as(i32, @intFromFloat(@ceil(width)));
    rect.bottom = rect.top + h;
    return h;
}
const FormatKey = struct {
    family: [32]u16 = [_]u16{0} ** 32,
    height: i32 = 17,
    weight: i32 = 400,
    italic: bool = false,
    underline: bool = false,

    fn eql(a: FormatKey, b: FormatKey) bool {
        return std.mem.eql(u16, &a.family, &b.family) and a.height == b.height and a.weight == b.weight and a.italic == b.italic and a.underline == b.underline;
    }
};

pub var directwrite = false;
var failed = false;
var initialized = false;
var dll_write: win.HMODULE = null;
var dll_draw: win.HMODULE = null;
var factory: ?*c.IDWriteFactory = null;
var d2d: ?*c.ID2D1Factory = null;
var target: ?*c.ID2D1DCRenderTarget = null;
var collection: ?*c.IDWriteFontCollection = null;
var rendering: ?*c.IDWriteRenderingParams = null;
var brush: ?*c.ID2D1SolidColorBrush = null;
var backdrop: ?*c.ID2D1Bitmap = null;
var backdrop_dc: win.HDC = null;
var backdrop_bitmap: win.HBITMAP = null;
var backdrop_old: win.HGDIOBJ = null;
var backdrop_bits: ?*anyopaque = null;
var backdrop_width: i32 = 0;
var backdrop_height: i32 = 0;
var files: [4]?*c.IDWriteFontFile = .{null} ** 4;
var paths: [4][1024:0]u16 = .{std.mem.zeroes([1024:0]u16)} ** 4;
var path_count: usize = 0;
var registered_loader = false;
var collection_key: u64 = 0;
const FormatEntry = struct { key: FormatKey = .{}, format: ?*c.IDWriteTextFormat = null, ellipsis: ?*c.IDWriteInlineObject = null };
var formats: [32]FormatEntry = .{FormatEntry{}} ** 32;
var next_format: usize = 0;
var collection_backend: enum { none, font_set, loader } = .none;
var last_failure: ?anyerror = null;

const LayoutEntry = struct {
    key: FormatKey = .{},
    width: i32 = 0,
    height: i32 = 0,
    flags: u32 = 0,
    hash: u64 = 0,
    text: [1024]u16 = undefined,
    len: usize = 0,
    used: u64 = 0,
    layout: ?*c.IDWriteTextLayout = null,
    metrics: c.DWRITE_TEXT_METRICS = undefined,
    overhang: c.DWRITE_OVERHANG_METRICS = undefined,
};
const Layout = struct {
    object: *c.IDWriteTextLayout,
    metrics: c.DWRITE_TEXT_METRICS,
    overhang: c.DWRITE_OVERHANG_METRICS,
};
var layouts: [64]LayoutEntry = .{LayoutEntry{}} ** 64;
var layout_clock: u64 = 0;
var reference_render = false;

fn clearLayouts() void {
    for (&layouts) |*entry| {
        release(entry.layout);
        entry.layout = null;
    }
    layout_clock = 0;
}

const ProfileStage = enum { font, string, format, layout, metrics, bounds, bind, backdrop, begin, draw, end };
const Profile = struct {
    enabled: bool = false,
    ticks: [@typeInfo(ProfileStage).@"enum".fields.len]i64 = @splat(0),
    calls: usize = 0,
    hits: usize = 0,
    misses: usize = 0,
};
var profile: Profile = .{};
fn timestamp() i64 {
    if (!builtin.is_test or !profile.enabled) return 0;
    var value: win.LARGE_INTEGER = undefined;
    _ = win.QueryPerformanceCounter(&value);
    return value.QuadPart;
}
fn mark(stage: ProfileStage, previous: *i64) void {
    if (!builtin.is_test or !profile.enabled) return;
    const now = timestamp();
    profile.ticks[@intFromEnum(stage)] += now - previous.*;
    previous.* = now;
}
fn printProfile(label: []const u8, elapsed: i64, frequency: i64) void {
    const scale = 1000000 / @as(f64, @floatFromInt(frequency)) / @as(f64, @floatFromInt(profile.calls));
    std.debug.print("text bench {s}: {d} calls, {d:.2} us/call, hits={d} misses={d}\n", .{ label, profile.calls, @as(f64, @floatFromInt(elapsed)) * scale, profile.hits, profile.misses });
    inline for (@typeInfo(ProfileStage).@"enum".fields, 0..) |field, i| {
        std.debug.print("  {s}: {d:.2} us/call\n", .{ field.name, @as(f64, @floatFromInt(profile.ticks[i])) * scale });
    }
}
fn windowsPathsEqual(a: []const u16, b: []const u16) bool {
    if (a.len != b.len or a.len > 1024) return false;
    var left: [1024]u16 = undefined;
    var right: [1024]u16 = undefined;
    for (a, b, 0..) |x, y, i| {
        left[i] = if (x == '/') '\\' else x;
        right[i] = if (y == '/') '\\' else y;
    }
    return c.CompareStringOrdinal(&left, @intCast(a.len), &right, @intCast(b.len), 1) == c.CSTR_EQUAL;
}

fn wide(comptime text: []const u8) [:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
fn guid(comptime text: []const u8) c.GUID {
    var result: c.GUID = undefined;
    result.Data1 = std.fmt.parseInt(u32, text[0..8], 16) catch unreachable;
    result.Data2 = std.fmt.parseInt(u16, text[9..13], 16) catch unreachable;
    result.Data3 = std.fmt.parseInt(u16, text[14..18], 16) catch unreachable;
    const positions = [_]usize{ 19, 21, 24, 26, 28, 30, 32, 34 };
    for (positions, 0..) |p, i| result.Data4[i] = std.fmt.parseInt(u8, text[p..][0..2], 16) catch unreachable;
    return result;
}
const iid_factory = guid("b859ee5a-d838-4b5b-a2e8-1adc7d93db48");
const iid_factory3 = guid("9a1b41c3-d3bb-466a-87fc-fe67556a3b65");
const iid_factory5 = guid("958db99a-be2a-4f09-af7d-65189803d1d3");
const iid_d2d = guid("06152247-6f50-465a-9245-118bfd3b6007");
const iid_unknown = guid("00000000-0000-0000-c000-000000000046");
const iid_loader = guid("cca920e4-52f0-492b-bfa8-29c72ee0a468");
const iid_enumerator = guid("72755049-5ff7-435d-8348-4be97cfa6c7c");

fn check(hr: c.HRESULT) !void {
    if (hr < 0) return error.DirectWriteCallFailed;
}
fn release(object: anytype) void {
    const nullable: ?*c.IUnknown = @ptrCast(object);
    if (nullable) |unknown| {
        _ = unknown.lpVtbl.*.Release.?(unknown);
    }
}
pub fn reset() void {
    clearLayouts();
    for (&formats) |*entry| {
        release(entry.ellipsis);
        release(entry.format);
        entry.* = .{};
    }
    next_format = 0;
    release(brush);
    brush = null;
    release(backdrop);
    backdrop = null;
    if (backdrop_dc != null) _ = win.SelectObject(backdrop_dc, backdrop_old);
    if (backdrop_bitmap != null) _ = win.DeleteObject(backdrop_bitmap);
    if (backdrop_dc != null) _ = win.DeleteDC(backdrop_dc);
    backdrop_dc = null;
    backdrop_bitmap = null;
    backdrop_old = null;
    backdrop_bits = null;
    backdrop_width = 0;
    backdrop_height = 0;
    release(target);
    target = null;
    release(rendering);
    rendering = null;
    release(collection);
    collection = null;
    if (registered_loader) {
        _ = factory.?.lpVtbl.*.UnregisterFontCollectionLoader.?(factory.?, &loader);
        registered_loader = false;
    }
    for (&files) |*file| {
        release(file.*);
        file.* = null;
    }
    release(d2d);
    d2d = null;
    release(factory);
    factory = null;
    if (dll_draw != null) _ = win.FreeLibrary(dll_draw);
    if (dll_write != null) _ = win.FreeLibrary(dll_write);
    dll_draw = null;
    dll_write = null;
    initialized = false;
    directwrite = false;
    failed = false;
    last_failure = null;
    collection_backend = .none;
}
pub fn setBundledFontPaths(font_paths: []const [*:0]const u16) void {
    reset();
    path_count = 0;
    for (font_paths) |path| {
        if (path_count == paths.len) break;
        const text = std.mem.span(path);
        if (text.len >= paths[0].len) continue;
        @memcpy(paths[path_count][0..text.len], text);
        paths[path_count][text.len] = 0;
        path_count += 1;
    }
}
pub fn available() bool {
    if (failed) return false;
    ensure() catch |err| {
        last_failure = err;
        failed = true;
    };
    return directwrite;
}
fn fontSet5() !void {
    var f: ?*c.IDWriteFactory5 = null;
    try check(factory.?.lpVtbl.*.QueryInterface.?(factory.?, &iid_factory5, @ptrCast(&f)));
    defer release(f);
    var builder: ?*c.IDWriteFontSetBuilder1 = null;
    try check(f.?.lpVtbl.*.IDWriteFactory5_CreateFontSetBuilder.?(f.?, &builder));
    defer release(builder);
    for (files) |file| if (file != null) {
        try check(builder.?.lpVtbl.*.AddFontFile.?(builder.?, file));
    };
    var set: ?*c.IDWriteFontSet = null;
    try check(builder.?.lpVtbl.*.CreateFontSet.?(builder.?, &set));
    defer release(set);
    var result: ?*c.IDWriteFontCollection1 = null;
    try check(f.?.lpVtbl.*.CreateFontCollectionFromFontSet.?(f.?, set, &result));
    collection = @ptrCast(result);
}
fn fontSet3() !void {
    var f: ?*c.IDWriteFactory3 = null;
    try check(factory.?.lpVtbl.*.QueryInterface.?(factory.?, &iid_factory3, @ptrCast(&f)));
    defer release(f);
    var builder: ?*c.IDWriteFontSetBuilder = null;
    try check(f.?.lpVtbl.*.CreateFontSetBuilder.?(f.?, &builder));
    defer release(builder);
    for (files) |file| if (file != null) {
        var reference: ?*c.IDWriteFontFaceReference = null;
        try check(f.?.lpVtbl.*.CreateFontFaceReference_.?(f.?, file, 0, c.DWRITE_FONT_SIMULATIONS_NONE, &reference));
        defer release(reference);
        try check(builder.?.lpVtbl.*.AddFontFaceReference.?(builder.?, reference));
    };
    var set: ?*c.IDWriteFontSet = null;
    try check(builder.?.lpVtbl.*.CreateFontSet.?(builder.?, &set));
    defer release(set);
    var result: ?*c.IDWriteFontCollection1 = null;
    try check(f.?.lpVtbl.*.CreateFontCollectionFromFontSet.?(f.?, set, &result));
    collection = @ptrCast(result);
}
fn loaderCollection() !void {
    try check(factory.?.lpVtbl.*.RegisterFontCollectionLoader.?(factory.?, &loader));
    registered_loader = true;
    collection_key +%= 1;
    try check(factory.?.lpVtbl.*.CreateCustomFontCollection.?(factory.?, &loader, &collection_key, @sizeOf(u64), &collection));
    collection_backend = .loader;
}
fn makeCollection() !void {
    var count: usize = 0;
    for (paths[0..path_count], 0..) |*path, i| {
        if (win.GetFileAttributesW(path) == win.INVALID_FILE_ATTRIBUTES) continue;
        try check(factory.?.lpVtbl.*.CreateFontFileReference.?(factory.?, path, null, &files[i]));
        count += 1;
    }
    if (count == 0) return error.NoBundledFonts;
    fontSet5() catch {
        fontSet3() catch {
            try loaderCollection();
            return;
        };
    };
    collection_backend = .font_set;
}
fn ensure() !void {
    if (failed) return error.PreviousFailure;
    if (initialized) return;
    errdefer {
        const saved_failure = last_failure;
        reset();
        last_failure = saved_failure;
        failed = true;
    }
    dll_write = win.LoadLibraryW(wide("dwrite.dll")) orelse return error.DirectWriteUnavailable;
    dll_draw = win.LoadLibraryW(wide("d2d1.dll")) orelse return error.Direct2DUnavailable;
    const create_write: *const fn (c.DWRITE_FACTORY_TYPE, *const c.GUID, *?*c.IUnknown) callconv(.winapi) c.HRESULT = @ptrCast(win.GetProcAddress(dll_write, "DWriteCreateFactory") orelse return error.DirectWriteUnavailable);
    const create_draw: *const fn (c.D2D1_FACTORY_TYPE, *const c.GUID, ?*const c.D2D1_FACTORY_OPTIONS, *?*c.ID2D1Factory) callconv(.winapi) c.HRESULT = @ptrCast(win.GetProcAddress(dll_draw, "D2D1CreateFactory") orelse return error.Direct2DUnavailable);
    try check(create_write(c.DWRITE_FACTORY_TYPE_SHARED, &iid_factory, @ptrCast(&factory)));
    try check(create_draw(c.D2D1_FACTORY_TYPE_SINGLE_THREADED, &iid_d2d, null, &d2d));
    try makeCollection();
    var family_index: u32 = 0;
    var family_exists: c.BOOL = 0;
    try check(collection.?.lpVtbl.*.FindFamilyName.?(collection.?, wide("IBM Plex Sans"), &family_index, &family_exists));
    if (family_exists == 0) return error.BundledFamilyMissing;
    const properties = c.D2D1_RENDER_TARGET_PROPERTIES{
        .type = c.D2D1_RENDER_TARGET_TYPE_DEFAULT,
        .pixelFormat = .{ .format = c.DXGI_FORMAT_B8G8R8A8_UNORM, .alphaMode = c.D2D1_ALPHA_MODE_IGNORE },
        .dpiX = 96,
        .dpiY = 96,
        .usage = c.D2D1_RENDER_TARGET_USAGE_NONE,
        .minLevel = c.D2D1_FEATURE_LEVEL_DEFAULT,
    };
    try check(d2d.?.lpVtbl.*.CreateDCRenderTarget.?(d2d.?, &properties, &target));
    var defaults: ?*c.IDWriteRenderingParams = null;
    try check(factory.?.lpVtbl.*.CreateRenderingParams.?(factory.?, &defaults));
    defer release(defaults);
    const params = defaults.?;
    const p = params.lpVtbl.*;
    try check(factory.?.lpVtbl.*.CreateCustomRenderingParams.?(factory.?, p.GetGamma.?(params), p.GetEnhancedContrast.?(params), p.GetClearTypeLevel.?(params), p.GetPixelGeometry.?(params), c.DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC, &rendering));
    const rt: *c.ID2D1RenderTarget = @ptrCast(target.?);
    rt.lpVtbl.*.SetTextAntialiasMode.?(rt, c.D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);
    rt.lpVtbl.*.SetTextRenderingParams.?(rt, rendering);
    try check(rt.lpVtbl.*.CreateSolidColorBrush.?(rt, &@as(c.D2D1_COLOR_F, @bitCast([4]f32{ 0, 0, 0, 1 })), null, &brush));
    initialized = true;
    directwrite = true;
}
fn keyForDC(dc: win.HDC) !FormatKey {
    const font = win.GetCurrentObject(dc, win.OBJ_FONT) orelse return error.NoSelectedFont;
    var logfont: win.LOGFONTW = undefined;
    if (win.GetObjectW(font, @sizeOf(win.LOGFONTW), &logfont) == 0) return error.NoSelectedFont;
    var key = FormatKey{
        .height = @max(1, -logfont.lfHeight),
        .weight = if (logfont.lfWeight == 0) 400 else logfont.lfWeight,
        .italic = logfont.lfItalic != 0,
        .underline = logfont.lfUnderline != 0,
    };
    if (logfont.lfHeight > 0) {
        var metrics: win.TEXTMETRICW = undefined;
        if (win.GetTextMetricsW(dc, &metrics) == 0) return error.NoSelectedFont;
        key.height = @max(1, metrics.tmHeight - metrics.tmInternalLeading);
    }
    const family = std.mem.sliceTo(&logfont.lfFaceName, 0);
    const family_len = @min(family.len, key.family.len - 1);
    @memcpy(key.family[0..family_len], family[0..family_len]);
    return key;
}
fn getFormat(key: FormatKey) !*FormatEntry {
    for (&formats) |*entry| if (entry.format != null and entry.key.eql(key)) return entry;
    const plex = std.mem.eql(u16, std.mem.sliceTo(&key.family, 0), wide("IBM Plex Sans"));
    var format: ?*c.IDWriteTextFormat = null;
    try check(factory.?.lpVtbl.*.CreateTextFormat.?(factory.?, &key.family, if (plex) collection else null, @intCast(key.weight), if (key.italic) c.DWRITE_FONT_STYLE_ITALIC else c.DWRITE_FONT_STYLE_NORMAL, c.DWRITE_FONT_STRETCH_NORMAL, @floatFromInt(key.height), wide("en-us"), &format));
    const slot = &formats[next_format];
    release(slot.ellipsis);
    release(slot.format);
    slot.* = .{ .key = key, .format = format };
    next_format = (next_format + 1) % formats.len;
    return slot;
}
fn layoutFor(text: []const u16, key: FormatKey, rect: win.RECT, flags: u32) !Layout {
    var stamp = timestamp();
    const entry = try getFormat(key);
    mark(.format, &stamp);
    const format = entry.format.?;
    const opts = options(flags);
    const width = @max(1, rect.right - rect.left);
    const height = if (flags & Flags.calcrect == 0 and rect.bottom > rect.top) rect.bottom - rect.top else 10000000;
    const layout_flags = flags & (Flags.center | Flags.right | Flags.wordbreak | Flags.singleline | Flags.word_ellipsis | Flags.end_ellipsis);
    const hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(text));
    const cacheable = text.len <= layouts[0].text.len and !(builtin.is_test and reference_render);
    layout_clock += 1;
    if (cacheable) for (&layouts) |*cached| {
        if (cached.layout == null or cached.hash != hash or cached.len != text.len or cached.width != width or cached.flags != layout_flags or !cached.key.eql(key)) continue;
        const fits = opts.trimming == 0 and cached.metrics.height <= @as(f32, @floatFromInt(@min(cached.height, height)));
        if (cached.height != height and !fits) continue;
        if (!std.mem.eql(u16, cached.text[0..cached.len], text)) continue;
        cached.used = layout_clock;
        _ = cached.layout.?.lpVtbl.*.AddRef.?(cached.layout.?);
        if (builtin.is_test and profile.enabled) profile.hits += 1;
        mark(.layout, &stamp);
        return .{ .object = cached.layout.?, .metrics = cached.metrics, .overhang = cached.overhang };
    };
    if (builtin.is_test and profile.enabled) profile.misses += 1;
    var layout: ?*c.IDWriteTextLayout = null;
    try check(factory.?.lpVtbl.*.CreateTextLayout.?(factory.?, text.ptr, @intCast(text.len), format, @floatFromInt(width), @floatFromInt(height), &layout));
    errdefer release(layout);
    const l = layout.?;
    const v = l.lpVtbl.*;
    try check(v.SetWordWrapping.?(l, if (opts.wrap) c.DWRITE_WORD_WRAPPING_WRAP else c.DWRITE_WORD_WRAPPING_NO_WRAP));
    try check(v.SetTextAlignment.?(l, opts.alignment));
    if (opts.trimming != 0) {
        if (entry.ellipsis == null) try check(factory.?.lpVtbl.*.CreateEllipsisTrimmingSign.?(factory.?, format, &entry.ellipsis));
        const trimming = c.DWRITE_TRIMMING{ .granularity = opts.trimming, .delimiter = 0, .delimiterCount = 0 };
        try check(v.SetTrimming.?(l, &trimming, entry.ellipsis));
    }
    if (key.underline) try check(v.SetUnderline.?(l, 1, .{ .startPosition = 0, .length = @intCast(text.len) }));
    mark(.layout, &stamp);
    var result = Layout{ .object = l, .metrics = undefined, .overhang = undefined };
    try check(v.GetMetrics.?(l, &result.metrics));
    try check(v.GetOverhangMetrics.?(l, &result.overhang));
    mark(.metrics, &stamp);
    if (cacheable) {
        var slot = &layouts[0];
        for (&layouts) |*candidate| {
            if (candidate.layout == null) {
                slot = candidate;
                break;
            }
            if (candidate.used < slot.used) slot = candidate;
        }
        release(slot.layout);
        slot.* = .{ .key = key, .width = width, .height = height, .flags = layout_flags, .hash = hash, .len = text.len, .used = layout_clock, .layout = l, .metrics = result.metrics, .overhang = result.overhang };
        @memcpy(slot.text[0..text.len], text);
        _ = v.AddRef.?(l);
    }
    return result;
}
fn captureBackdrop(dc: win.HDC, binding: win.RECT) !void {
    const width = binding.right - binding.left;
    const height = binding.bottom - binding.top;
    const rt: *c.ID2D1RenderTarget = @ptrCast(target.?);
    if (backdrop_dc == null) backdrop_dc = win.CreateCompatibleDC(dc) orelse return error.BackdropDCFailed;
    if (width > backdrop_width or height > backdrop_height) {
        release(backdrop);
        backdrop = null;
        if (backdrop_bitmap != null) {
            _ = win.SelectObject(backdrop_dc, backdrop_old);
            _ = win.DeleteObject(backdrop_bitmap);
            backdrop_bitmap = null;
        }
        backdrop_width = @max(width, backdrop_width);
        backdrop_height = @max(height, backdrop_height);
        var info = std.mem.zeroes(win.BITMAPINFO);
        info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
        info.bmiHeader.biWidth = backdrop_width;
        info.bmiHeader.biHeight = -backdrop_height;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        backdrop_bitmap = win.CreateDIBSection(backdrop_dc, &info, win.DIB_RGB_COLORS, &backdrop_bits, null, 0) orelse return error.BackdropBitmapFailed;
        backdrop_old = win.SelectObject(backdrop_dc, backdrop_bitmap);
        const properties = c.D2D1_BITMAP_PROPERTIES{ .pixelFormat = .{ .format = c.DXGI_FORMAT_B8G8R8A8_UNORM, .alphaMode = c.D2D1_ALPHA_MODE_IGNORE }, .dpiX = 96, .dpiY = 96 };
        try check(rt.lpVtbl.*.CreateBitmap.?(rt, .{ .width = @intCast(backdrop_width), .height = @intCast(backdrop_height) }, null, 0, &properties, &backdrop));
    }
    if (win.BitBlt(backdrop_dc, 0, 0, width, height, dc, binding.left, binding.top, win.SRCCOPY) == 0) return error.BackdropCopyFailed;
    _ = win.GdiFlush();
    const copy = c.D2D1_RECT_U{ .left = 0, .top = 0, .right = @intCast(width), .bottom = @intCast(height) };
    try check(backdrop.?.lpVtbl.*.CopyFromMemory.?(backdrop.?, &copy, backdrop_bits, @intCast(backdrop_width * 4)));
}
fn render(dc: win.HDC, text_ptr: [*c]const u16, len: i32, rect: *win.RECT, flags: u32) !i32 {
    try ensure();
    const count: usize = if (len < 0) std.mem.len(@as([*:0]const u16, @ptrCast(text_ptr))) else @intCast(len);
    if (count == 0) {
        if (flags & Flags.calcrect != 0) return updateRect(rect, 0, 0);
        return 0;
    }
    var stamp = timestamp();
    if (builtin.is_test and profile.enabled) profile.calls += 1;
    const key = try keyForDC(dc);
    mark(.font, &stamp);
    var text: []const u16 = text_ptr[0..count];
    var local: [1024]u16 = undefined;
    var allocated: ?[]u16 = null;
    defer if (allocated) |buffer| std.heap.page_allocator.free(buffer);
    const prefix = flags & Flags.noprefix == 0 and std.mem.indexOfScalar(u16, text, '&') != null;
    const newlines = flags & Flags.singleline != 0 and (std.mem.indexOfScalar(u16, text, '\r') != null or std.mem.indexOfScalar(u16, text, '\n') != null);
    if (prefix or newlines) {
        const buffer = if (count <= local.len) local[0..count] else blk: {
            allocated = try std.heap.page_allocator.alloc(u16, count);
            break :blk allocated.?;
        };
        if (prefix) text = stripPrefix(text, buffer) else {
            @memcpy(buffer, text);
            text = buffer;
        }
        if (newlines) for (buffer[0..text.len]) |*unit| {
            if (unit.* == '\r' or unit.* == '\n') unit.* = ' ';
        };
    }
    mark(.string, &stamp);
    const shaped = try layoutFor(text, key, rect.*, flags);
    const layout = shaped.object;
    stamp = timestamp();
    defer release(layout);
    const metrics = shaped.metrics;
    const height: i32 = @intFromFloat(@ceil(metrics.height));
    mark(.metrics, &stamp);
    if (flags & Flags.calcrect != 0) return updateRect(rect, metrics.widthIncludingTrailingWhitespace, metrics.height);
    const opts = options(flags);
    const offset: i32 = switch (opts.vertical) {
        .top => 0,
        .center => @divTrunc(rect.bottom - rect.top - height, 2),
        .bottom => rect.bottom - rect.top - height,
    };
    var clip: win.RECT = undefined;
    const clip_kind = win.GetClipBox(dc, &clip);
    if (clip_kind == win.ERROR) return error.ClipFailed;
    if (clip_kind == win.NULLREGION) return height;
    const overhang = shaped.overhang;
    var bounds = win.RECT{
        .left = rect.left + @as(i32, @intFromFloat(@floor(@min(metrics.left, -overhang.left)))),
        .top = rect.top + offset + @as(i32, @intFromFloat(@floor(@min(metrics.top, -overhang.top)))),
        .right = rect.left + @as(i32, @intFromFloat(@ceil(@max(metrics.left + metrics.widthIncludingTrailingWhitespace, layout.lpVtbl.*.GetMaxWidth.?(layout) + overhang.right)))),
        .bottom = rect.top + offset + @as(i32, @intFromFloat(@ceil(if ((builtin.is_test and reference_render) or overhang.bottom > 0) @max(metrics.top + metrics.height, layout.lpVtbl.*.GetMaxHeight.?(layout) + overhang.bottom) else metrics.top + metrics.height))),
    };
    if (opts.clip) {
        bounds.left = @max(bounds.left, rect.left);
        bounds.top = @max(bounds.top, rect.top);
        bounds.right = @min(bounds.right, rect.right);
        bounds.bottom = @min(bounds.bottom, rect.bottom);
    }
    bounds.left = @max(bounds.left, clip.left);
    bounds.top = @max(bounds.top, clip.top);
    bounds.right = @min(bounds.right, clip.right);
    bounds.bottom = @min(bounds.bottom, clip.bottom);
    if (bounds.right <= bounds.left or bounds.bottom <= bounds.top) return height;
    var viewport: win.POINT = undefined;
    var window: win.POINT = undefined;
    if (win.GetViewportOrgEx(dc, &viewport) == 0 or win.GetWindowOrgEx(dc, &window) == 0) return error.OriginFailed;
    const dx = viewport.x - window.x;
    const dy = viewport.y - window.y;
    var binding = bounds;
    binding.left += dx;
    binding.right += dx;
    binding.top += dy;
    binding.bottom += dy;
    const saved = win.SaveDC(dc);
    if (saved == 0) return error.SaveDCFailed;
    defer _ = win.RestoreDC(dc, saved);
    _ = win.SetViewportOrgEx(dc, 0, 0, null);
    _ = win.SetWindowOrgEx(dc, 0, 0, null);
    _ = win.GdiFlush();
    const rt: *c.ID2D1RenderTarget = @ptrCast(target.?);
    mark(.bounds, &stamp);
    try check(target.?.lpVtbl.*.BindDC.?(target.?, @ptrCast(dc), @ptrCast(&binding)));
    mark(.bind, &stamp);
    try captureBackdrop(dc, binding);
    mark(.backdrop, &stamp);
    const color = win.GetTextColor(dc);
    brush.?.lpVtbl.*.SetColor.?(brush.?, &@as(c.D2D1_COLOR_F, @bitCast([4]f32{ @as(f32, @floatFromInt(color & 255)) / 255, @as(f32, @floatFromInt((color >> 8) & 255)) / 255, @as(f32, @floatFromInt((color >> 16) & 255)) / 255, 1 })));
    rt.lpVtbl.*.BeginDraw.?(rt);
    mark(.begin, &stamp);
    const surface = c.D2D1_RECT_F{ .left = 0, .top = 0, .right = @floatFromInt(bounds.right - bounds.left), .bottom = @floatFromInt(bounds.bottom - bounds.top) };
    rt.lpVtbl.*.DrawBitmap.?(rt, backdrop, &surface, 1, c.D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR, &surface);
    rt.lpVtbl.*.DrawTextLayout.?(rt, .{ .x = @floatFromInt(rect.left - bounds.left), .y = @floatFromInt(rect.top + offset - bounds.top) }, layout, @ptrCast(brush.?), c.D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
    mark(.draw, &stamp);
    try check(rt.lpVtbl.*.EndDraw.?(rt, null, null));
    mark(.end, &stamp);
    return height;
}
pub fn drawText(dc: win.HDC, text: [*c]const u16, len: i32, rect: *win.RECT, flags: u32) i32 {
    if (!failed) {
        return render(dc, text, len, rect, flags) catch |err| {
            last_failure = err;
            failed = true;
            directwrite = false;
            return win.DrawTextW(dc, text, len, rect, flags);
        };
    }
    return win.DrawTextW(dc, text, len, rect, flags);
}

pub fn drawRun(dc: win.HDC, x: i32, y: i32, text: [*c]const u16, len: i32) i32 {
    var rect = win.RECT{ .left = x, .top = y, .right = x, .bottom = y };
    return drawText(dc, text, len, &rect, win.DT_SINGLELINE | win.DT_NOPREFIX | win.DT_NOCLIP);
}

fn sameGuid(a: [*c]const c.GUID, b: *const c.GUID) bool {
    return a != null and std.mem.eql(u8, std.mem.asBytes(@as(*const c.GUID, @ptrCast(a))), std.mem.asBytes(b));
}
fn loaderQuery(this: [*c]c.IDWriteFontCollectionLoader, iid: [*c]const c.GUID, out: [*c]?*anyopaque) callconv(.winapi) c.HRESULT {
    out.* = null;
    if (!sameGuid(iid, &iid_unknown) and !sameGuid(iid, &iid_loader)) return c.E_NOINTERFACE;
    out.* = this;
    _ = loaderAddRef(this);
    return c.S_OK;
}
fn loaderAddRef(_: [*c]c.IDWriteFontCollectionLoader) callconv(.winapi) c.ULONG {
    return loader_refs.fetchAdd(1, .monotonic) + 1;
}
fn loaderRelease(_: [*c]c.IDWriteFontCollectionLoader) callconv(.winapi) c.ULONG {
    return loader_refs.fetchSub(1, .acq_rel) - 1;
}
const Enumerator = struct {
    interface: c.IDWriteFontFileEnumerator = .{ .lpVtbl = &enumerator_vtable },
    refs: std.atomic.Value(u32) = .init(1),
    index: usize = 0,
    snapshot: [4]?*c.IDWriteFontFile,
};
fn enumeratorFrom(this: [*c]c.IDWriteFontFileEnumerator) *Enumerator {
    return @fieldParentPtr("interface", @as(*c.IDWriteFontFileEnumerator, @ptrCast(this)));
}
fn enumQuery(this: [*c]c.IDWriteFontFileEnumerator, iid: [*c]const c.GUID, out: [*c]?*anyopaque) callconv(.winapi) c.HRESULT {
    out.* = null;
    if (!sameGuid(iid, &iid_unknown) and !sameGuid(iid, &iid_enumerator)) return c.E_NOINTERFACE;
    out.* = this;
    _ = enumAddRef(this);
    return c.S_OK;
}
fn enumAddRef(this: [*c]c.IDWriteFontFileEnumerator) callconv(.winapi) c.ULONG {
    const e = enumeratorFrom(this);
    return e.refs.fetchAdd(1, .monotonic) + 1;
}
fn enumRelease(this: [*c]c.IDWriteFontFileEnumerator) callconv(.winapi) c.ULONG {
    const e = enumeratorFrom(this);
    const refs = e.refs.fetchSub(1, .acq_rel) - 1;
    if (refs == 0) {
        for (e.snapshot) |file| release(file);
        std.heap.page_allocator.destroy(e);
    }
    return refs;
}
fn enumMove(this: [*c]c.IDWriteFontFileEnumerator, current: [*c]c.BOOL) callconv(.winapi) c.HRESULT {
    const e = enumeratorFrom(this);
    while (e.index < e.snapshot.len) {
        e.index += 1;
        if (e.snapshot[e.index - 1] != null) {
            current.* = 1;
            return c.S_OK;
        }
    }
    e.index = e.snapshot.len + 1;
    current.* = 0;
    return c.S_OK;
}
fn enumCurrent(this: [*c]c.IDWriteFontFileEnumerator, out: [*c][*c]c.IDWriteFontFile) callconv(.winapi) c.HRESULT {
    const e = enumeratorFrom(this);
    out.* = null;
    if (e.index == 0 or e.index > e.snapshot.len) return c.E_FAIL;
    const file = e.snapshot[e.index - 1] orelse return c.E_FAIL;
    _ = file.lpVtbl.*.AddRef.?(file);
    out.* = file;
    return c.S_OK;
}
fn createEnumerator(_: [*c]c.IDWriteFontCollectionLoader, _: [*c]c.IDWriteFactory, _: ?*const anyopaque, _: u32, out: [*c][*c]c.IDWriteFontFileEnumerator) callconv(.winapi) c.HRESULT {
    out.* = null;
    const e = std.heap.page_allocator.create(Enumerator) catch return c.E_OUTOFMEMORY;
    e.* = .{ .snapshot = files };
    for (e.snapshot) |file| if (file) |f| {
        _ = f.lpVtbl.*.AddRef.?(f);
    };
    out.* = &e.interface;
    return c.S_OK;
}
var loader_refs: std.atomic.Value(u32) = .init(1);
var loader_vtable = c.IDWriteFontCollectionLoaderVtbl{ .QueryInterface = loaderQuery, .AddRef = loaderAddRef, .Release = loaderRelease, .CreateEnumeratorFromKey = createEnumerator };
var loader = c.IDWriteFontCollectionLoader{ .lpVtbl = &loader_vtable };
var enumerator_vtable = c.IDWriteFontFileEnumeratorVtbl{ .QueryInterface = enumQuery, .AddRef = enumAddRef, .Release = enumRelease, .MoveNext = enumMove, .GetCurrentFontFile = enumCurrent };

test "WAZI-161 DT flags map wrapping alignment trimming and clipping" {
    const o = options(Flags.wordbreak | Flags.singleline | Flags.center | Flags.vcenter | Flags.word_ellipsis | Flags.noclip);
    try std.testing.expect(!o.wrap and !o.clip);
    try std.testing.expectEqual(@as(u32, 2), o.alignment);
    try std.testing.expectEqual(@as(u32, 2), o.trimming);
    try std.testing.expect(o.vertical == .center);
    try std.testing.expect(options(Flags.wordbreak).wrap);
    try std.testing.expect(options(Flags.vcenter).vertical == .top);
    try std.testing.expect(options(Flags.bottom).vertical == .bottom);
    try std.testing.expectEqual(@as(u32, 1), options(Flags.right | Flags.end_ellipsis).alignment);
    try std.testing.expectEqual(@as(u32, 1), options(Flags.end_ellipsis).trimming);
}
test "WAZI-161 GDI ampersand prefixes strip without corrupting UTF16" {
    var buffer: [128]u16 = undefined;
    const input = wide("&File && Edit &x &&&y &😀&");
    try std.testing.expectEqualSlices(u16, wide("File & Edit x &y 😀"), stripPrefix(input, &buffer));
    try std.testing.expectEqual(@as(usize, 0), stripPrefix(&.{}, &buffer).len);
    try std.testing.expectEqual(@as(usize, 0), stripPrefix(wide("&"), &buffer).len);
}
test "WAZI-161 CALCRECT rounds outward and preserves rectangle origin" {
    var rect = struct { left: i32 = 7, top: i32 = -3, right: i32 = 100, bottom: i32 = 99 }{};
    try std.testing.expectEqual(@as(i32, 22), updateRect(&rect, 31.2, 21.01));
    try std.testing.expectEqual(@as(i32, 39), rect.right);
    try std.testing.expectEqual(@as(i32, 19), rect.bottom);
    try std.testing.expectEqual(@as(i32, 7), rect.left);
    try std.testing.expectEqual(@as(i32, -3), rect.top);
    _ = updateRect(&rect, 0, 0);
    try std.testing.expectEqual(rect.left, rect.right);
    try std.testing.expectEqual(rect.top, rect.bottom);
}
test "WAZI-161 format cache keys include family height weight italic underline" {
    const base = FormatKey{};
    try std.testing.expect(base.eql(.{}));
    inline for (.{ "height", "weight", "italic", "underline" }) |field| {
        var different = base;
        if (@TypeOf(@field(different, field)) == bool) @field(different, field) = true else @field(different, field) += 1;
        try std.testing.expect(!base.eql(different));
    }
    var different = base;
    different.family[0] = 'X';
    try std.testing.expect(!base.eql(different));
}

test "bundled DirectWrite raster provenance wrapping origins clipping and timing" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const size = 512;
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
    const font = win.CreateFontW(-17, 0, 0, 0, @import("font_config.zig").body_weight, 0, 0, 0, win.DEFAULT_CHARSET, win.OUT_DEFAULT_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_NATURAL_QUALITY, win.DEFAULT_PITCH, wide("IBM Plex Sans")) orelse return error.CreateFontFailed;
    defer _ = win.DeleteObject(font);
    const previous_font = win.SelectObject(dc, font);
    defer _ = win.SelectObject(dc, previous_font);
    _ = win.SetTextColor(dc, 0);
    _ = win.SetBkMode(dc, win.TRANSPARENT);
    var font_path: [1024:0]u16 = undefined;
    const path_len = win.GetFullPathNameW(wide("assets\\IBMPlexSans-Medium.ttf"), font_path.len, &font_path, null);
    const font_files = @import("font_config.zig").files;
    var bundled_paths: [font_files.len][1024:0]u16 = undefined;
    var font_pointers: [font_files.len][*:0]const u16 = undefined;
    inline for (font_files, 0..) |file, i| {
        _ = win.GetFullPathNameW(wide("assets\\" ++ file), bundled_paths[i].len, &bundled_paths[i], null);
        font_pointers[i] = &bundled_paths[i];
    }
    setBundledFontPaths(&font_pointers);
    const first_path_unit = bundled_paths[0][0];
    bundled_paths[0][0] = '?';
    const paths_owned = paths[0][0] == first_path_unit;
    bundled_paths[0][0] = first_path_unit;
    defer reset();
    _ = available();
    const sample = wide("Smooth readable text IBM Plex Sans at seventeen pixels today");
    var drawn = win.RECT{ .left = 8, .top = 8, .right = 188, .bottom = 300 };
    var frequency: win.LARGE_INTEGER = undefined;
    _ = win.QueryPerformanceFrequency(&frequency);
    @memset(pixels, 0xffffffff);
    _ = drawText(dc, sample, @intCast(sample.len), &drawn, win.DT_WORDBREAK | win.DT_NOPREFIX);
    for ([_]bool{ true, false }) |reference| {
        reference_render = reference;
        defer reference_render = false;
        profile = .{ .enabled = true };
        const start = timestamp();
        for (0..200) |_| _ = drawText(dc, sample, @intCast(sample.len), &drawn, win.DT_WORDBREAK | win.DT_NOPREFIX);
        const end = timestamp();
        printProfile(if (reference) "repeated_before" else "repeated_after", end - start, frequency.QuadPart);
        profile.enabled = false;
    }
    try std.testing.expect(path_len > 0 and path_len < font_path.len);
    try std.testing.expect(paths_owned);
    try std.testing.expect(directwrite);
    std.debug.print("text: directwrite = {}, collection = {s}\n", .{ directwrite, @tagName(collection_backend) });
    {
        const key = try keyForDC(dc);
        const format = (try getFormat(key)).format.?;
        var actual_collection: ?*c.IDWriteFontCollection = null;
        try check(format.lpVtbl.*.GetFontCollection.?(format, &actual_collection));
        defer release(actual_collection);
        try std.testing.expect(actual_collection == collection);
        var family_index: u32 = 0;
        var exists: c.BOOL = 0;
        try check(actual_collection.?.lpVtbl.*.FindFamilyName.?(actual_collection.?, wide("IBM Plex Sans"), &family_index, &exists));
        try std.testing.expect(exists != 0);
        var family: ?*c.IDWriteFontFamily = null;
        try check(actual_collection.?.lpVtbl.*.GetFontFamily.?(actual_collection.?, family_index, &family));
        defer release(family);
        var resolved_font: ?*c.IDWriteFont = null;
        try check(family.?.lpVtbl.*.GetFirstMatchingFont.?(family.?, c.DWRITE_FONT_WEIGHT_MEDIUM, c.DWRITE_FONT_STRETCH_NORMAL, c.DWRITE_FONT_STYLE_NORMAL, &resolved_font));
        defer release(resolved_font);
        var face: ?*c.IDWriteFontFace = null;
        try check(resolved_font.?.lpVtbl.*.CreateFontFace.?(resolved_font.?, &face));
        defer release(face);
        var file_count: u32 = 1;
        var file: ?*c.IDWriteFontFile = null;
        try check(face.?.lpVtbl.*.GetFiles.?(face.?, &file_count, &file));
        defer release(file);
        var reference_key: ?*const anyopaque = null;
        var reference_size: u32 = 0;
        try check(file.?.lpVtbl.*.GetReferenceKey.?(file.?, &reference_key, &reference_size));
        var file_loader: ?*c.IDWriteFontFileLoader = null;
        try check(file.?.lpVtbl.*.GetLoader.?(file.?, &file_loader));
        defer release(file_loader);
        const iid_local_loader = guid("b2d9f3ec-c9fe-4a11-a2ec-d86208f7c0a2");
        var local_loader: ?*c.IDWriteLocalFontFileLoader = null;
        try check(file_loader.?.lpVtbl.*.QueryInterface.?(file_loader.?, &iid_local_loader, @ptrCast(&local_loader)));
        defer release(local_loader);
        var resolved_path: [1024:0]u16 = undefined;
        try check(local_loader.?.lpVtbl.*.GetFilePathFromKey.?(local_loader.?, reference_key, reference_size, &resolved_path, resolved_path.len));
        try std.testing.expect(windowsPathsEqual(std.mem.sliceTo(&font_path, 0), std.mem.sliceTo(&resolved_path, 0)));
        std.debug.print("bundled font reference key matches requested file\n", .{});
    }
    @memset(pixels, 0xffffffff);
    try std.testing.expectEqual(@as(usize, 60), sample.len);
    var measured = win.RECT{ .left = 8, .top = 8, .right = 188, .bottom = 0 };
    const measured_height = drawText(dc, sample, @intCast(sample.len), &measured, win.DT_WORDBREAK | win.DT_CALCRECT | win.DT_NOPREFIX);
    const drawn_height = drawText(dc, sample, @intCast(sample.len), &drawn, win.DT_WORDBREAK | win.DT_NOPREFIX);
    if (!directwrite) std.debug.print("DirectWrite failure: {any}\n", .{last_failure});
    try std.testing.expect(directwrite);
    try std.testing.expectEqual(measured_height, drawn_height);
    try std.testing.expectEqual(measured.bottom - measured.top, drawn_height);
    _ = win.GdiFlush();
    var shades = [_]bool{false} ** 256;
    var ink: usize = 0;
    for (pixels) |pixel| {
        if (pixel & 0xffffff == 0xffffff) continue;
        ink += 1;
        const grey = ((pixel & 255) + ((pixel >> 8) & 255) + ((pixel >> 16) & 255)) / 3;
        if (grey > 0 and grey < 255) shades[grey] = true;
    }
    const levels = std.mem.count(bool, &shades, &.{true});
    std.debug.print("raster: ink={d}, intermediate grey levels={d}, wrapped height={d}\n", .{ ink, levels, drawn_height });
    try std.testing.expect(ink > 0);
    try std.testing.expect(levels >= 8);
    {
        const saved = win.SaveDC(dc);
        defer _ = win.RestoreDC(dc, saved);
        _ = win.SetViewportOrgEx(dc, 31, 23, null);
        _ = win.SetWindowOrgEx(dc, 7, 5, null);
        _ = win.IntersectClipRect(dc, 12, 10, 72, 38);
        @memset(pixels, 0xffffffff);
        var translated = win.RECT{ .left = 8, .top = 8, .right = 180, .bottom = 60 };
        _ = drawText(dc, sample, -1, &translated, win.DT_SINGLELINE | win.DT_NOPREFIX | win.DT_NOCLIP);
        try std.testing.expect(directwrite);
        ink = 0;
        for (pixels, 0..) |pixel, i| {
            if (pixel & 0xffffff == 0xffffff) continue;
            const x = i % size;
            const y = i / size;
            try std.testing.expect(x >= 36 and x < 96 and y >= 28 and y < 56);
            ink += 1;
        }
        try std.testing.expect(ink > 0);
        std.debug.print("viewport/window origins and intersected DC clip verified\n", .{});
    }
    {
        const cases = [_]u32{
            win.DT_SINGLELINE | win.DT_NOPREFIX,
            win.DT_SINGLELINE | win.DT_CENTER | win.DT_VCENTER | win.DT_NOPREFIX,
            win.DT_SINGLELINE | win.DT_RIGHT | win.DT_BOTTOM | win.DT_NOPREFIX,
            win.DT_SINGLELINE | win.DT_END_ELLIPSIS | win.DT_CENTER | win.DT_NOPREFIX,
            win.DT_WORDBREAK | win.DT_WORD_ELLIPSIS | win.DT_NOPREFIX,
            win.DT_WORDBREAK | win.DT_NOPREFIX,
            win.DT_SINGLELINE | win.DT_NOCLIP,
        };
        const texts = [_][:0]const u16{ sample, wide("&Italic && underline Äg jfy\r\nsecond line"), wide("Short label") };
        const expected = try std.testing.allocator.alloc(u32, pixels.len);
        defer std.testing.allocator.free(expected);
        for ([_]i32{ 13, 17, 26 }, 0..) |font_size, style| {
            const variant = win.CreateFontW(-font_size, 0, 0, 0, if (style == 1) win.FW_SEMIBOLD else @import("font_config.zig").body_weight, @intFromBool(style == 2), @intFromBool(style == 2), 0, win.DEFAULT_CHARSET, win.OUT_DEFAULT_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_NATURAL_QUALITY, win.DEFAULT_PITCH, wide("IBM Plex Sans")) orelse return error.CreateFontFailed;
            defer _ = win.DeleteObject(variant);
            const previous = win.SelectObject(dc, variant);
            defer _ = win.SelectObject(dc, previous);
            for (cases) |flags| for (texts) |text| {
                clearLayouts();
                var expected_height: i32 = 0;
                for ([_]bool{ true, false, false }) |reference| {
                    reference_render = reference;
                    defer reference_render = false;
                    for (pixels, 0..) |*pixel, i| pixel.* = 0xff000000 | @as(u32, @intCast((i * 331) & 0xffffff));
                    var rect = win.RECT{ .left = 11, .top = 9, .right = 193, .bottom = 149 };
                    const actual_height = drawText(dc, text, -1, &rect, flags);
                    try std.testing.expect(directwrite);
                    _ = win.GdiFlush();
                    if (reference) {
                        @memcpy(expected, pixels);
                        expected_height = actual_height;
                    } else {
                        try std.testing.expectEqual(expected_height, actual_height);
                        if (!std.mem.eql(u32, expected, pixels)) std.debug.print("pixel mismatch style={d} flags={x} text_units={d} reference={}\n", .{ style, flags, text.len, reference });
                        try std.testing.expectEqualSlices(u32, expected, pixels);
                    }
                }
            };
        }
        std.debug.print("pixel-equivalent cached and tight-bound rendering: 63 style/flag/text cases, cold and warm\n", .{});
    }
    {
        clearLayouts();
        const key = try keyForDC(dc);
        const flags = win.DT_WORDBREAK | win.DT_NOPREFIX;
        const measure_rect = win.RECT{ .left = 8, .top = 8, .right = 188, .bottom = 0 };
        const first = try layoutFor(sample, key, measure_rect, flags | win.DT_CALCRECT);
        defer release(first.object);
        const second = try layoutFor(sample, key, drawn, flags);
        defer release(second.object);
        try std.testing.expect(first.object == second.object);
        const narrow = try layoutFor(sample, key, .{ .left = 8, .top = 8, .right = 88, .bottom = 300 }, flags);
        defer release(narrow.object);
        try std.testing.expect(narrow.object != first.object);
        const short = try layoutFor(sample, key, .{ .left = 8, .top = 8, .right = 188, .bottom = 20 }, flags);
        defer release(short.object);
        try std.testing.expect(short.object != first.object);
        const trimmed = try layoutFor(sample, key, drawn, flags | win.DT_WORD_ELLIPSIS);
        defer release(trimmed.object);
        try std.testing.expect(trimmed.object != first.object);
        var changed_key = key;
        changed_key.weight = win.FW_SEMIBOLD;
        const changed = try layoutFor(sample, changed_key, drawn, flags);
        defer release(changed.object);
        try std.testing.expect(changed.object != first.object);
        clearLayouts();
        var input = [_]u16{ 'a', 'b', 'c' };
        const original = try layoutFor(&input, key, drawn, flags);
        defer release(original.object);
        input[0] = 'z';
        const modified = try layoutFor(&input, key, drawn, flags);
        defer release(modified.object);
        try std.testing.expect(original.object != modified.object);
        const copied = try layoutFor(wide("abc"), key, drawn, flags);
        defer release(copied.object);
        try std.testing.expect(original.object == copied.object);
        layouts[0].hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(wide("xyz")));
        const collision = try layoutFor(wide("xyz"), key, drawn, flags);
        defer release(collision.object);
        try std.testing.expect(original.object != collision.object);
        clearLayouts();
        for (0..layouts.len) |i| {
            const value = [_]u16{ @intCast('A' + i), 'x' };
            const item = try layoutFor(&value, key, drawn, flags);
            release(item.object);
        }
        const oldest = layouts[0].layout.?;
        const victim = layouts[1].layout.?;
        _ = victim.lpVtbl.*.AddRef.?(victim);
        defer release(victim);
        const recent = try layoutFor(&[_]u16{ 'A', 'x' }, key, drawn, flags);
        defer release(recent.object);
        try std.testing.expect(recent.object == oldest);
        const extra = try layoutFor(wide("one more"), key, drawn, flags);
        defer release(extra.object);
        try std.testing.expect(layouts[0].layout.? == oldest);
        const evicted = try layoutFor(&[_]u16{ 'B', 'x' }, key, drawn, flags);
        defer release(evicted.object);
        try std.testing.expect(evicted.object != victim);
        var long_text: [1025]u16 = @splat('a');
        const long_first = try layoutFor(&long_text, key, drawn, flags);
        defer release(long_first.object);
        const long_second = try layoutFor(&long_text, key, drawn, flags);
        defer release(long_second.object);
        try std.testing.expect(long_first.object != long_second.object);
        clearLayouts();
        const retained = try layoutFor(sample, key, drawn, flags);
        defer release(retained.object);
        for (0..formats.len + 1) |i| {
            var varied = key;
            varied.height = @intCast(i + 10);
            _ = try getFormat(varied);
        }
        const after_eviction = try layoutFor(sample, key, drawn, flags);
        defer release(after_eviction.object);
        try std.testing.expect(retained.object == after_eviction.object);
        clearLayouts();
        for (layouts) |entry| try std.testing.expect(entry.layout == null);
        std.debug.print("layout cache: CALCRECT reuse, width/height/flags/font keys, owned text, hash collisions, long text, format/LRU eviction and reset verified\n", .{});
    }
    for (0..2) |backend| {
        clearLayouts();
        for (&formats) |*entry| {
            release(entry.ellipsis);
            release(entry.format);
            entry.* = .{};
        }
        release(collection);
        collection = null;
        if (backend == 0) try fontSet3() else try loaderCollection();
        @memset(pixels, 0xffffffff);
        try std.testing.expectEqual(drawn_height, drawText(dc, sample, -1, &drawn, win.DT_WORDBREAK | win.DT_NOPREFIX));
        try std.testing.expect(directwrite);
        try std.testing.expect(pixels[0] == 0xffffffff);
        var fallback_ink: usize = 0;
        for (pixels) |pixel| if (pixel & 0xffffff != 0xffffff) {
            fallback_ink += 1;
        };
        try std.testing.expect(fallback_ink > 0);
    }
    std.debug.print("Factory3 and legacy custom loader both render bundled text\n", .{});
    setBundledFontPaths(&.{wide("missing-font.ttf")});
    try std.testing.expect(!available());
    try std.testing.expect(last_failure != null and last_failure.? == error.NoBundledFonts);
    @memset(pixels, 0xffffffff);
    _ = drawText(dc, sample, -1, &drawn, win.DT_WORDBREAK | win.DT_NOPREFIX);
    try std.testing.expect(!directwrite);
    try std.testing.expect(last_failure != null and last_failure.? == error.NoBundledFonts);
    var fallback_ink: usize = 0;
    for (pixels) |pixel| if (pixel & 0xffffff != 0xffffff) {
        fallback_ink += 1;
    };
    try std.testing.expect(fallback_ink > 0);
    @memcpy(paths[0][0..path_len], font_path[0..path_len]);
    paths[0][path_len] = 0;
    try std.testing.expect(!available());
    try std.testing.expect(last_failure != null and last_failure.? == error.NoBundledFonts);
    reset();
    try std.testing.expect(available());
    try std.testing.expectEqual(@as(u32, 1), loader_refs.load(.acquire));
    std.debug.print("GDI failure fallback is sticky until reset, then DirectWrite recovers\n", .{});
}

test "Windows font provenance ignores case and separator spelling only" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.expect(windowsPathsEqual(wide("C:\\Fonts\\Plex.ttf"), wide("c:/FONTS/plex.TTF")));
    try std.testing.expect(windowsPathsEqual(wide("C:\\Ä\\Plex.ttf"), wide("c:/ä/plex.TTF")));
    try std.testing.expect(!windowsPathsEqual(wide("C:\\Fonts\\Plex.ttf"), wide("C:/Fonts/Other.ttf")));
    try std.testing.expect(!windowsPathsEqual(wide("C:\\Fonts\\Plex.ttf"), wide("D:/Fonts/Plex.ttf")));
}

test "DirectWrite fifty distinct strings frame benchmark" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const dc = win.CreateCompatibleDC(null) orelse return error.CreateDCFailed;
    defer _ = win.DeleteDC(dc);
    var info = std.mem.zeroes(win.BITMAPINFO);
    info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    info.bmiHeader.biWidth = 1200;
    info.bmiHeader.biHeight = -800;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    var bits: ?*anyopaque = null;
    const bitmap = win.CreateDIBSection(dc, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse return error.CreateBitmapFailed;
    defer _ = win.DeleteObject(bitmap);
    const old = win.SelectObject(dc, bitmap);
    defer _ = win.SelectObject(dc, old);
    const font = win.CreateFontW(-17, 0, 0, 0, @import("font_config.zig").body_weight, 0, 0, 0, win.DEFAULT_CHARSET, win.OUT_DEFAULT_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_NATURAL_QUALITY, win.DEFAULT_PITCH, wide("IBM Plex Sans")) orelse return error.CreateFontFailed;
    defer _ = win.DeleteObject(font);
    const previous = win.SelectObject(dc, font);
    defer _ = win.SelectObject(dc, previous);
    _ = win.SetTextColor(dc, 0);
    _ = win.SetBkMode(dc, win.TRANSPARENT);
    var font_path: [1024:0]u16 = undefined;
    _ = win.GetFullPathNameW(wide("assets\\IBMPlexSans-Medium.ttf"), font_path.len, &font_path, null);
    setBundledFontPaths(&.{&font_path});
    defer reset();
    _ = available();
    var strings: [50][200]u16 = undefined;
    var lengths: [50]usize = undefined;
    const paragraph = wide("Readable wrapped paragraphs exercise realistic message layouts with varied words, punctuation, and spacing. Each message uses the same bundled font and wraps naturally without changing its text or scale. ");
    for (&strings, &lengths, 0..) |*text, *len, i| {
        len.* = if (i % 2 == 0) 12 else 200;
        for (text[0..len.*], 0..) |*unit, j| unit.* = paragraph[j % paragraph.len];
        text[0] = 'A' + @as(u16, @intCast(i / 26));
        text[1] = 'a' + @as(u16, @intCast(i % 26));
    }
    var frequency: win.LARGE_INTEGER = undefined;
    _ = win.QueryPerformanceFrequency(&frequency);
    const frames = 10;
    for ([_]bool{ true, false }) |reference| {
        reference_render = reference;
        defer reference_render = false;
        clearLayouts();
        profile = .{ .enabled = true };
        const start = timestamp();
        for (0..frames) |_| {
            @memset(@as([*]u32, @ptrCast(@alignCast(bits.?)))[0 .. 1200 * 800], 0xffffffff);
            for (&strings, lengths, 0..) |*text, len, i| {
                const x: i32 = @intCast((i / 10) * 240);
                const y: i32 = @intCast((i % 10) * 80);
                var rect = win.RECT{ .left = x, .top = y, .right = x + 232, .bottom = y + 78 };
                _ = drawText(dc, text, @intCast(len), &rect, win.DT_WORDBREAK | win.DT_NOPREFIX);
            }
        }
        const end = timestamp();
        printProfile(if (reference) "frame_before" else "frame_after", end - start, frequency.QuadPart);
        profile.enabled = false;
        const ms = @as(f64, @floatFromInt(end - start)) * 1000 / @as(f64, @floatFromInt(frequency.QuadPart)) / frames;
        std.debug.print("text frame {s}: 1200x800, 50 distinct strings (25 labels, 25 200-unit paragraphs), {d} frames, {d:.2} ms/frame\n", .{ if (reference) "before" else "after", frames, ms });
        try std.testing.expect(directwrite);
    }
}

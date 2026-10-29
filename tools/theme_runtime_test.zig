const std = @import("std");
const theme = @import("theme.zig");
const menu_theme = @import("menu_theme.zig");

const App = struct {
    brush_bg: ?usize = null,
    brush_panel: ?usize = null,
    brush_sidebar: ?usize = null,
    brush_raised: ?usize = null,
    brush_muted: ?usize = null,
    status: []const u8 = "",
};

const win = struct {
    const DWORD = u32;
    const HKEY = ?usize;
    const HMODULE = ?usize;
    const HWND = usize;
    const LPARAM = isize;
    const BOOL = i32;
    const COLORREF = u32;
    const ERROR_SUCCESS = 0;
    const TRUE = 1;
    const FALSE = 0;
    const RRF_RT_REG_DWORD = 16;
    const REG_DWORD = 4;
    const KEY_SET_VALUE = 2;
    const RDW_INVALIDATE = 1;
    const RDW_ERASE = 4;
    const RDW_FRAME = 1024;
    const RDW_ALLCHILDREN = 128;
    const RDW_UPDATENOW = 256;
    var stored: ?u32 = null;
    var live: [128]?u32 = @splat(null);
    var allocations: usize = 0;
    var fail_at: ?usize = null;
    var redraws: usize = 0;
    var saves: usize = 0;
    const top_level_windows = [_]HWND{ 11, 23, 37, 41 };

    var menu_library_available = true;
    var mode_export_available = true;
    var flush_export_available = true;
    var menu_loads: usize = 0;
    var mode_calls: usize = 0;
    var menu_flushes: usize = 0;
    var menu_mode: menu_theme.PreferredAppMode = .default;

    fn LoadLibraryW(path: [*:0]const u16) HMODULE {
        std.debug.assert(std.mem.eql(u16, std.mem.span(path), std.mem.span(lit("uxtheme.dll"))));
        menu_loads += 1;
        return if (menu_library_available) 1 else null;
    }

    fn GetProcAddress(module: usize, ordinal: [*c]const u8) ?*const anyopaque {
        std.debug.assert(module == 1);
        return switch (@intFromPtr(ordinal)) {
            135 => if (mode_export_available) @ptrCast(&SetPreferredAppMode) else null,
            136 => if (flush_export_available) @ptrCast(&FlushMenuThemes) else null,
            else => unreachable,
        };
    }

    fn SetPreferredAppMode(mode: menu_theme.PreferredAppMode) callconv(.winapi) menu_theme.PreferredAppMode {
        const previous = menu_mode;
        menu_mode = mode;
        mode_calls += 1;
        return previous;
    }

    fn FlushMenuThemes() callconv(.winapi) void {
        menu_flushes += 1;
    }

    fn RegGetValueW(key: HKEY, path: [*:0]const u16, name: [*:0]const u16, flags: u32, _: ?*anyopaque, out: *u32, size: *u32) i32 {
        std.debug.assert(key == 0x80000001 and flags == RRF_RT_REG_DWORD);
        std.debug.assert(std.mem.eql(u16, std.mem.span(path), std.mem.span(lit("Software\\Messages"))));
        std.debug.assert(std.mem.eql(u16, std.mem.span(name), std.mem.span(lit("Theme"))));
        std.debug.assert(size.* == @sizeOf(u32));
        out.* = stored orelse return 2;
        return ERROR_SUCCESS;
    }

    fn RegCreateKeyExW(key: HKEY, path: [*:0]const u16, _: u32, _: ?*anyopaque, _: u32, access: u32, _: ?*anyopaque, out: *HKEY, disposition: *u32) i32 {
        std.debug.assert(key == 0x80000001 and access == KEY_SET_VALUE);
        std.debug.assert(std.mem.eql(u16, std.mem.span(path), std.mem.span(lit("Software\\Messages"))));
        out.* = 1;
        disposition.* = 0;
        return ERROR_SUCCESS;
    }

    fn RegCloseKey(_: HKEY) i32 {
        return ERROR_SUCCESS;
    }

    fn RegSetValueExW(_: HKEY, name: [*:0]const u16, _: u32, kind: u32, data: *const u32, size: u32) i32 {
        std.debug.assert(kind == REG_DWORD and size == @sizeOf(u32));
        std.debug.assert(std.mem.eql(u16, std.mem.span(name), std.mem.span(lit("Theme"))));
        stored = data.*;
        saves += 1;
        return ERROR_SUCCESS;
    }

    fn CreateSolidBrush(color: u32) ?usize {
        allocations += 1;
        if (fail_at == allocations) return null;
        live[allocations] = color;
        return allocations;
    }

    fn DeleteObject(handle: usize) i32 {
        std.debug.assert(live[handle] != null);
        live[handle] = null;
        return TRUE;
    }

    fn RedrawWindow(hwnd: HWND, _: ?*anyopaque, _: ?*anyopaque, flags: u32) i32 {
        std.debug.assert(hwnd == top_level_windows[redraws]);
        std.debug.assert(flags == RDW_INVALIDATE | RDW_ERASE | RDW_FRAME | RDW_ALLCHILDREN | RDW_UPDATENOW);
        redraws += 1;
        return TRUE;
    }

    fn GetCurrentThreadId() u32 {
        return 7;
    }

    fn EnumThreadWindows(thread: u32, callback: *const fn (HWND, LPARAM) callconv(.winapi) BOOL, param: LPARAM) i32 {
        std.debug.assert(thread == GetCurrentThreadId());
        redraws = 0;
        for (top_level_windows) |hwnd| std.debug.assert(callback(hwnd, param) == TRUE);
        return TRUE;
    }
};

fn lit(comptime value: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(value);
}

fn winHandle(comptime T: type, value: usize) T {
    return value;
}

fn setStatus(a: *App, value: []const u8) void {
    a.status = value;
}

fn updateTooltipTheme(_: *App) void {}

fn reset() void {
    theme.set(.amoled);
    win.stored = null;
    win.live = @splat(null);
    win.allocations = 0;
    win.fail_at = null;
    win.redraws = 0;
    win.saves = 0;
    menu_theme_module = null;
    win.menu_library_available = true;
    win.mode_export_available = true;
    win.flush_export_available = true;
    win.menu_loads = 0;
    win.mode_calls = 0;
    win.menu_flushes = 0;
    win.menu_mode = .default;
}

fn expectBrushes(a: *const App, palette: theme.Palette) !void {
    try std.testing.expectEqual(palette.surface, win.live[a.brush_bg.?].?);
    try std.testing.expectEqual(palette.surface_container_low, win.live[a.brush_panel.?].?);
    try std.testing.expectEqual(palette.sidebar_surface, win.live[a.brush_sidebar.?].?);
    try std.testing.expectEqual(palette.surface_container, win.live[a.brush_raised.?].?);
    try std.testing.expectEqual(palette.outline, win.live[a.brush_muted.?].?);
    var count: usize = 0;
    for (win.live) |brush| {
        if (brush != null) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), count);
}

test "startup loads valid DWORD themes and defaults missing or unknown values" {
    reset();
    defer theme.set(.amoled);
    for ([_]?u32{ null, 0, 1, 2, std.math.maxInt(u32) }) |stored| {
        win.stored = stored;
        applyTheme(loadTheme());
        const expected: theme.Choice = .amoled;
        try std.testing.expectEqual(expected, theme.choice);
        try std.testing.expectEqual(menu_theme.preferredAppMode(expected), win.menu_mode);
        try std.testing.expectEqual(theme.amoled.surface_container, fieldColor());
    }
}

test "live theme changes replace all brushes, save and redraw every top-level window with children" {
    reset();
    defer theme.set(.amoled);
    var app = App{};
    try std.testing.expect(recreateThemeBrushes(&app));
    try expectBrushes(&app, theme.amoled);
    for ([_]theme.Choice{ .amoled, .amoled, .amoled }) |choice| {
        const old = [_]usize{ app.brush_bg.?, app.brush_panel.?, app.brush_sidebar.?, app.brush_raised.?, app.brush_muted.? };
        try std.testing.expect(changeTheme(&app, choice));
        try std.testing.expectEqual(choice, theme.choice);
        try std.testing.expectEqual(menu_theme.preferredAppMode(choice), win.menu_mode);
        try std.testing.expectEqual(@intFromEnum(choice), win.stored.?);
        for (old) |brush| try std.testing.expectEqual(@as(?u32, null), win.live[brush]);
        try expectBrushes(&app, theme.current.*);
        try std.testing.expectEqual(win.top_level_windows.len, win.redraws);
        try std.testing.expectEqualStrings("Theme: Graphite", app.status);
    }
    try std.testing.expectEqual(@as(usize, 3), win.saves);
    try std.testing.expectEqual(@as(usize, 1), win.menu_loads);
    try std.testing.expectEqual(@as(usize, 3), win.mode_calls);
    try std.testing.expectEqual(@as(usize, 3), win.menu_flushes);
}

test "brush allocation failure preserves the previous palette, resources and saved choice" {
    for (1..6) |failure| {
        reset();
        defer theme.set(.amoled);
        var app = App{};
        try std.testing.expect(recreateThemeBrushes(&app));
        const old = app.brush_bg;
        win.fail_at = win.allocations + failure;
        try std.testing.expect(!changeTheme(&app, .amoled));
        try std.testing.expectEqual(theme.Choice.amoled, theme.choice);
        try std.testing.expectEqual(menu_theme.PreferredAppMode.force_dark, win.menu_mode);
        try std.testing.expectEqual(@as(usize, 2), win.mode_calls);
        try std.testing.expectEqual(@as(usize, 2), win.menu_flushes);
        try std.testing.expectEqual(old, app.brush_bg);
        try expectBrushes(&app, theme.amoled);
        try std.testing.expectEqual(@as(usize, 0), win.saves);
        try std.testing.expectEqual(@as(usize, 0), win.redraws);
        try std.testing.expectEqualStrings("Could not change theme", app.status);
    }
}

test "IGSH-505 missing native menu DLL or ordinal exports are harmless" {
    for ([_]bool{ false, true }) |library| {
        for ([_]bool{ false, true }) |mode| {
            for ([_]bool{ false, true }) |flush| {
                reset();
                defer theme.set(.amoled);
                win.menu_library_available = library;
                win.mode_export_available = mode;
                win.flush_export_available = flush;
                applyTheme(.amoled);
                try std.testing.expectEqual(theme.Choice.amoled, theme.choice);
                try std.testing.expectEqual(@as(usize, 1), win.menu_loads);
                try std.testing.expectEqual(@as(usize, if (library and mode) 1 else 0), win.mode_calls);
                try std.testing.expectEqual(@as(usize, if (library and flush) 1 else 0), win.menu_flushes);
                try std.testing.expectEqual(if (library and mode) menu_theme.PreferredAppMode.force_dark else .default, win.menu_mode);
            }
        }
    }
}

const std = @import("std");
const theme = @import("theme.zig");

const App = struct {
    brush_bg: ?usize = null,
    brush_panel: ?usize = null,
    brush_raised: ?usize = null,
    brush_muted: ?usize = null,
    status: []const u8 = "",
    slack_setup_window: ?usize = null,
    tg_login_window: ?usize = null,
};

const win = struct {
    const DWORD = u32;
    const HKEY = ?usize;
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
    var dialog_dark: [2]?BOOL = @splat(null);

    fn DwmSetWindowAttribute(hwnd: HWND, attribute: DWORD, value: *BOOL, size: usize) i32 {
        std.debug.assert(attribute == 20 and size == @sizeOf(BOOL));
        dialog_dark[hwnd - 1] = value.*;
        return 0;
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
        std.debug.assert(hwnd == redraws + 1);
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
        for (1..5) |hwnd| std.debug.assert(callback(hwnd, param) == TRUE);
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
    theme.set(.green);
    win.stored = null;
    win.live = @splat(null);
    win.allocations = 0;
    win.fail_at = null;
    win.redraws = 0;
    win.saves = 0;
    win.dialog_dark = @splat(null);
}

fn expectBrushes(a: *const App, palette: theme.Palette) !void {
    try std.testing.expectEqual(palette.surface, win.live[a.brush_bg.?].?);
    try std.testing.expectEqual(palette.surface_container_low, win.live[a.brush_panel.?].?);
    try std.testing.expectEqual(palette.surface_container_high, win.live[a.brush_raised.?].?);
    try std.testing.expectEqual(palette.outline, win.live[a.brush_muted.?].?);
    var count: usize = 0;
    for (win.live) |brush| {
        if (brush != null) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), count);
}

test "startup loads valid DWORD themes and defaults missing or unknown values" {
    reset();
    defer theme.set(.amoled);
    for ([_]?u32{ null, 0, 1, 2, std.math.maxInt(u32) }) |stored| {
        win.stored = stored;
        theme.set(loadTheme());
        const expected: theme.Choice = if (stored == 0) .green else .amoled;
        try std.testing.expectEqual(expected, theme.choice);
        try std.testing.expectEqual(if (expected == .amoled) theme.amoled.surface else theme.green.surface_container_high, fieldColor());
    }
}

test "live theme changes replace all brushes, save and redraw every top-level window with children" {
    reset();
    defer theme.set(.amoled);
    var app = App{};
    try std.testing.expect(recreateThemeBrushes(&app));
    try expectBrushes(&app, theme.green);
    app.slack_setup_window = 1;
    app.tg_login_window = 2;
    for ([_]theme.Choice{ .amoled, .green, .amoled }) |choice| {
        const old = app.brush_bg.?;
        try std.testing.expect(changeTheme(&app, choice));
        try std.testing.expectEqual(choice, theme.choice);
        try std.testing.expectEqual(@intFromEnum(choice), win.stored.?);
        try std.testing.expectEqual(@as(?u32, null), win.live[old]);
        try expectBrushes(&app, theme.current.*);
        try std.testing.expectEqual(@as(usize, 4), win.redraws);
        for (win.dialog_dark) |dark| try std.testing.expectEqual(@as(?win.BOOL, if (choice == .amoled) win.TRUE else 0), dark);
        try std.testing.expectEqualStrings(if (choice == .amoled) "Theme: AMOLED black" else "Theme: Green", app.status);
    }
    try std.testing.expectEqual(@as(usize, 3), win.saves);
}

test "brush allocation failure preserves the previous palette, resources and saved choice" {
    for (1..5) |failure| {
        reset();
        defer theme.set(.amoled);
        var app = App{};
        try std.testing.expect(recreateThemeBrushes(&app));
        const old = app.brush_bg;
        win.fail_at = win.allocations + failure;
        try std.testing.expect(!changeTheme(&app, .amoled));
        try std.testing.expectEqual(theme.Choice.green, theme.choice);
        try std.testing.expectEqual(old, app.brush_bg);
        try expectBrushes(&app, theme.green);
        try std.testing.expectEqual(@as(usize, 0), win.saves);
        try std.testing.expectEqual(@as(usize, 0), win.redraws);
        try std.testing.expectEqualStrings("Could not change theme", app.status);
    }
}

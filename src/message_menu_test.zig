const std = @import("std");
const theme = @import("theme");
const lit = std.unicode.utf8ToUtf16LeStringLiteral;
const reaction_row = 3010;
const reaction_remove = 3007;
const command_reply = 2020;
const command_copy_text = 2021;
const command_copy_link = 2022;
const quick_reactions = [_]u16{3000};
const App = struct {
    hwnd: ?usize = 1,
    brush_panel: ?usize = 10,
    brush_raised: ?usize = 11,
    brush_muted: ?usize = 12,
    font: ?*anyopaque = @ptrFromInt(16),
};
const MenuItem = struct { flags: u32, command: usize, label: ?[*:0]const u16 };
var rows: [8]MenuItem = undefined;
var row_count: usize = 0;
var menu_info: ?win.MENUINFO = null;
var destroyed = false;
var fills: [2]usize = undefined;
var fill_count: usize = 0;
var text_color: u32 = 0;
var drawn_text: ?[*:0]const u16 = null;
const win = struct {
    const UINT = u32;
    const HMENU = usize;
    const MF_STRING = 0;
    const MF_SEPARATOR = 0x800;
    const MF_OWNERDRAW = 0x100;
    const MIM_BACKGROUND = 2;
    const MIM_APPLYTOSUBMENUS = 0x80000000;
    const TPM_RETURNCMD = 0x100;
    const TPM_NONOTIFY = 0x80;
    const ODS_SELECTED = 1;
    const ODS_DISABLED = 4;
    const TRANSPARENT = 1;
    const DT_LEFT = 0;
    const DT_SINGLELINE = 0x20;
    const DT_VCENTER = 4;
    const DT_NOPREFIX = 0x800;
    const RECT = struct { left: i32 = 0, top: i32 = 0, right: i32 = 320, bottom: i32 = 24 };
    const POINT = struct { x: i32 = 0, y: i32 = 0 };
    const SIZE = struct { cx: i32, cy: i32 };
    const MENUINFO = struct { cbSize: u32, fMask: u32, hbrBack: ?usize };
    const MEASUREITEMSTRUCT = struct { itemData: usize, itemWidth: u32 = 0, itemHeight: u32 = 0 };
    const DRAWITEMSTRUCT = struct { itemData: usize, itemState: u32 = 0, hDC: usize = 1, rcItem: RECT = .{} };
    fn CreatePopupMenu() ?usize {
        return 1;
    }
    fn DestroyMenu(_: usize) i32 {
        destroyed = true;
        return 1;
    }
    fn AppendMenuW(_: usize, flags: u32, command: usize, label: ?[*:0]const u16) i32 {
        rows[row_count] = .{ .flags = flags, .command = command, .label = label };
        row_count += 1;
        return 1;
    }
    fn SetMenuInfo(_: usize, info: *const MENUINFO) i32 {
        menu_info = info.*;
        return 1;
    }
    fn TrackPopupMenu(_: usize, _: u32, _: i32, _: i32, _: i32, _: usize, _: ?*const RECT) u32 {
        return 0;
    }
    fn GetMenuItemRect(_: usize, _: usize, _: u32, _: *RECT) i32 {
        return 0;
    }
    fn GetCursorPos(_: *POINT) i32 {
        return 0;
    }
    fn GetDC(_: ?usize) ?usize {
        return 1;
    }
    fn ReleaseDC(_: ?usize, _: usize) i32 {
        return 1;
    }
    fn SaveDC(_: usize) i32 {
        return 1;
    }
    fn RestoreDC(_: usize, _: i32) i32 {
        return 1;
    }
    fn SelectObject(_: usize, _: *anyopaque) usize {
        return 1;
    }
    fn GetTextExtentPoint32W(_: usize, _: [*:0]const u16, length: i32, size: *SIZE) i32 {
        size.* = .{ .cx = length * 8, .cy = 16 };
        return 1;
    }
    fn FillRect(_: usize, _: *const RECT, brush: usize) i32 {
        fills[fill_count] = brush;
        fill_count += 1;
        return 1;
    }
    fn SetBkMode(_: usize, _: i32) i32 {
        return 1;
    }
    fn SetTextColor(_: usize, color: u32) u32 {
        text_color = color;
        return 0;
    }
};
const text_draw = struct {
    fn drawText(_: usize, label: [*:0]const u16, _: i32, _: *win.RECT, _: u32) i32 {
        drawn_text = label;
        return 1;
    }
};
fn px(_: *const App, value: i32) i32 {
    return value;
}
fn reactionCellWidth(_: *const App) i32 {
    return 36;
}
fn startReply(_: *App) void {}
fn openReactionPicker(_: *App) void {}
fn reactToSelected(_: *App, _: u16) void {}
fn reset(choice: theme.Choice) void {
    theme.set(choice);
    row_count = 0;
    menu_info = null;
    destroyed = false;
    fill_count = 0;
    drawn_text = null;
}

test "IGSH-505 message menu sets AMOLED background and owner draws every row" {
    reset(.amoled);
    var app: App = .{};
    openReactionMenu(&app, 100, 100);
    try std.testing.expect(destroyed);
    const info = menu_info orelse return error.MissingAmoledMenuBackground;
    try std.testing.expectEqual(@as(u32, @sizeOf(win.MENUINFO)), info.cbSize);
    try std.testing.expectEqual(@as(u32, win.MIM_BACKGROUND | win.MIM_APPLYTOSUBMENUS), info.fMask);
    try std.testing.expectEqual(app.brush_panel, info.hbrBack);
    try std.testing.expectEqual(@as(usize, 8), row_count);
    for (rows) |row| try std.testing.expectEqual(@as(u32, win.MF_OWNERDRAW), row.flags);
    try std.testing.expectEqual(@as(usize, reaction_row), rows[2].command);
    for ([_]usize{ 0, 4, 6, 7 }, [_]usize{ command_reply, reaction_remove, command_copy_text, command_copy_link }) |index, command| {
        try std.testing.expectEqual(command, rows[index].command);
        const label = rows[index].label orelse return error.MissingMenuLabel;
        var measured: win.MEASUREITEMSTRUCT = .{ .itemData = @intFromPtr(label) };
        measureMessageMenuItem(&app, &measured);
        try std.testing.expect(measured.itemWidth >= std.mem.len(label) * 8 + 32);
        try std.testing.expect(measured.itemHeight >= 24);
        for ([_]u32{ 0, win.ODS_SELECTED, win.ODS_DISABLED }) |state| {
            fill_count = 0;
            drawn_text = null;
            var item: win.DRAWITEMSTRUCT = .{ .itemData = @intFromPtr(label), .itemState = state };
            drawMessageMenuItem(&app, &item);
            try std.testing.expectEqual(@as(usize, 1), fill_count);
            try std.testing.expectEqual(if (state == win.ODS_SELECTED) app.brush_raised.? else app.brush_panel.?, fills[0]);
            try std.testing.expectEqual(if (state == win.ODS_DISABLED) theme.amoled.on_surface_variant else theme.amoled.on_surface, text_color);
            try std.testing.expectEqualStrings(std.mem.sliceAsBytes(std.mem.span(label)), std.mem.sliceAsBytes(std.mem.span(drawn_text.?)));
        }
    }
}

test "IGSH-505 message menu separators are painted on AMOLED not system light" {
    reset(.amoled);
    var app: App = .{};
    var measured: win.MEASUREITEMSTRUCT = .{ .itemData = 0 };
    measureMessageMenuItem(&app, &measured);
    try std.testing.expectEqual(@as(u32, 8), measured.itemHeight);
    var item: win.DRAWITEMSTRUCT = .{ .itemData = 0 };
    drawMessageMenuItem(&app, &item);
    try std.testing.expectEqual(@as(usize, 2), fill_count);
    try std.testing.expectEqual(app.brush_panel.?, fills[0]);
    try std.testing.expectEqual(app.brush_muted.?, fills[1]);
    try std.testing.expect(drawn_text == null);
}

test "IGSH-505 Green message menu keeps native text and separators after AMOLED" {
    var app: App = .{};
    for ([_]theme.Choice{ .amoled, .green, .amoled, .green }) |choice| {
        reset(choice);
        openReactionMenu(&app, 100, 100);
        if (choice != .green) continue;
        try std.testing.expect(menu_info == null);
        try std.testing.expectEqual(@as(usize, 8), row_count);
        for (rows, 0..) |row, index| {
            const expected: u32 = if (index == 2) win.MF_OWNERDRAW else if (row.label == null) win.MF_SEPARATOR else win.MF_STRING;
            try std.testing.expectEqual(expected, row.flags);
        }
    }
}

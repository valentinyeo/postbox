const std = @import("std");
const win = @import("win32.zig").c;

fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

var shell32: win.HMODULE = null;
var comdlg32: win.HMODULE = null;

pub var shellExecuteW: ?*const @TypeOf(win.ShellExecuteW) = null;
pub var shCreateItemFromParsingName: ?*const @TypeOf(win.SHCreateItemFromParsingName) = null;
pub var dragQueryFileW: ?*const @TypeOf(win.DragQueryFileW) = null;

pub fn ensureShell32() bool {
    if (shell32 != null) return true;
    const module = win.LoadLibraryW(lit("shell32.dll")) orelse return false;
    const execute_raw = win.GetProcAddress(module, "ShellExecuteW") orelse return false;
    const create_item_raw = win.GetProcAddress(module, "SHCreateItemFromParsingName") orelse return false;
    const drag_query_raw = win.GetProcAddress(module, "DragQueryFileW") orelse return false;
    shellExecuteW = @ptrCast(@alignCast(execute_raw));
    shCreateItemFromParsingName = @ptrCast(@alignCast(create_item_raw));
    dragQueryFileW = @ptrCast(@alignCast(drag_query_raw));
    shell32 = module;
    return true;
}

pub var getOpenFileNameW: ?*const fn (*anyopaque) callconv(.winapi) win.BOOL = null;

pub fn ensureComdlg32() bool {
    if (comdlg32 != null) return true;
    const module = win.LoadLibraryW(lit("comdlg32.dll")) orelse return false;
    const raw = win.GetProcAddress(module, "GetOpenFileNameW") orelse return false;
    getOpenFileNameW = @ptrCast(@alignCast(raw));
    comdlg32 = module;
    return true;
}

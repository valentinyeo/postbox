const std = @import("std");
const win = @import("win32.zig").c;

fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

var mfplat: win.HMODULE = null;
var mfreadwrite: win.HMODULE = null;
var mfplay: win.HMODULE = null;

var startup_fn: ?*const @TypeOf(win.MFStartup) = null;
var shutdown_fn: ?*const @TypeOf(win.MFShutdown) = null;

pub var createAttributes: ?*const @TypeOf(win.MFCreateAttributes) = null;
pub var createMediaType: ?*const @TypeOf(win.MFCreateMediaType) = null;
pub var createSourceReaderFromURL: ?*const @TypeOf(win.MFCreateSourceReaderFromURL) = null;
pub var createMediaPlayer: ?*const @TypeOf(win.MFPCreateMediaPlayer) = null;

var started = false;

pub fn ensureStarted() bool {
    if (started) return true;
    mfplat = win.LoadLibraryW(lit("mfplat.dll")) orelse return false;
    mfreadwrite = win.LoadLibraryW(lit("mfreadwrite.dll")) orelse return false;
    mfplay = win.LoadLibraryW(lit("mfplay.dll")) orelse return false;

    startup_fn = @ptrCast(@alignCast(win.GetProcAddress(mfplat, "MFStartup") orelse return false));
    shutdown_fn = @ptrCast(@alignCast(win.GetProcAddress(mfplat, "MFShutdown") orelse return false));
    createAttributes = @ptrCast(@alignCast(win.GetProcAddress(mfplat, "MFCreateAttributes") orelse return false));
    createMediaType = @ptrCast(@alignCast(win.GetProcAddress(mfplat, "MFCreateMediaType") orelse return false));
    createSourceReaderFromURL = @ptrCast(@alignCast(win.GetProcAddress(mfreadwrite, "MFCreateSourceReaderFromURL") orelse return false));
    createMediaPlayer = @ptrCast(@alignCast(win.GetProcAddress(mfplay, "MFPCreateMediaPlayer") orelse return false));

    if (startup_fn.?(win.MF_VERSION, win.MFSTARTUP_FULL) < 0) return false;
    started = true;
    return true;
}

pub fn isStarted() bool {
    return started;
}

pub fn unloadIfStarted() void {
    if (!started) return;
    if (shutdown_fn) |shutdown| _ = shutdown();
    startup_fn = null;
    shutdown_fn = null;
    createAttributes = null;
    createMediaType = null;
    createSourceReaderFromURL = null;
    createMediaPlayer = null;
    started = false;
    if (mfplay) |m| _ = win.FreeLibrary(m);
    if (mfreadwrite) |m| _ = win.FreeLibrary(m);
    if (mfplat) |m| _ = win.FreeLibrary(m);
    mfplay = null;
    mfreadwrite = null;
    mfplat = null;
    _ = win.CoFreeUnusedLibraries();
}

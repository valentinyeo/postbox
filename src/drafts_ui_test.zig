const std = @import("std");
const drafts = @import("drafts.zig");
const chat_key = @import("chat_key.zig");
const edit_contract = @import("edit_contract.zig");
const allocator = std.testing.allocator;

const Text = struct {
    value: []const u8,
    len: usize = 1,
    pub fn slice(self: *const Text) []const u8 {
        return self.value;
    }
};
const Chat = struct {
    provider: @import("transport.zig").Provider = .slack,
    account: Text,
    jid: Text = .{ .value = "same-chat" },
};
const dictation = struct {
    const State = enum { idle, failed, recording, transcribing, ready };
};
const Session = struct {
    origin: drafts.Identity,
    ready: bool = true,
    fn state(self: *const Session) dictation.State {
        return if (self.ready) .ready else .idle;
    }
    fn takeTranscript(self: *Session, buffer: []u8) ?[]const u8 {
        if (!self.ready) return null;
        self.ready = false;
        const text = "spoken transcript";
        @memcpy(buffer[0..text.len], text);
        return buffer[0..text.len];
    }
};
const App = struct {
    allocator: std.mem.Allocator = allocator,
    draft_store: drafts.Store = .{},
    draft_loading: bool = false,
    compose: ?usize = 1,
    dictate: ?usize = 2,
    chats_hwnd: ?usize = 3,
    hwnd: ?usize = 4,
    chats: [2]Chat = .{ .{ .account = .{ .value = "workspace-a" } }, .{ .account = .{ .value = "workspace-b" } } },
    chat_count: usize = 2,
    selected_chat: usize = 0,
    compose_client_width: i32 = 600,
    compose_client_height: i32 = 400,
    dictation_session: ?*Session = null,
    last_dictation_state: dictation.State = .idle,
    text: [drafts.max_text + 1]u16 = @splat(0),
    disk: []u8 = &.{},
    clipboard: [:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("pasted transcript"),
    switch_during_paste: bool = false,
    undo_clears: usize = 0,
    enabled: bool = true,
    invalidated_row: ?win.RECT = null,
    full_list_invalidations: usize = 0,
    selection_start: usize = 0,
    selection_end: usize = 0,

    fn deinit(self: *App) void {
        self.draft_store.deinit(self.allocator);
        self.allocator.free(self.disk);
        current = null;
    }
};
var current: ?*App = null;

const win = struct {
    const FALSE = 0;
    const TRUE = 1;
    const CF_UNICODETEXT = 13;
    const EM_EMPTYUNDOBUFFER = 1;
    const EM_SETSEL = 2;
    const EM_SCROLLCARET = 3;
    const EM_REPLACESEL = 4;
    const EM_GETSEL = 5;
    const LB_GETITEMRECT = 6;
    const LB_ERR = -1;
    const RECT = struct { left: i32, top: i32, right: i32, bottom: i32 };

    fn GetWindowTextLengthW(_: usize) i32 {
        return @intCast(std.mem.indexOfScalar(u16, &current.?.text, 0).?);
    }
    fn GetWindowTextW(_: usize, destination: [*]u16, capacity: i32) i32 {
        const length = @min(@as(usize, @intCast(GetWindowTextLengthW(1))), @as(usize, @intCast(capacity - 1)));
        @memcpy(destination[0..length], current.?.text[0..length]);
        destination[length] = 0;
        return @intCast(length);
    }
    fn SetWindowTextW(hwnd: usize, value: [*]const u16) i32 {
        if (hwnd != 1) return TRUE;
        const text = std.mem.span(@as([*:0]const u16, @ptrCast(value)));
        @memcpy(current.?.text[0..text.len], text);
        current.?.text[text.len] = 0;
        current.?.selection_start = text.len;
        current.?.selection_end = text.len;
        saveComposerDraft(current.?);
        return TRUE;
    }
    fn SetFocus(_: usize) usize {
        return 1;
    }
    fn SendMessageW(_: usize, message: u32, wparam: usize, lparam: isize) isize {
        if (message == LB_GETITEMRECT) {
            if (wparam >= current.?.chat_count) return LB_ERR;
            const rect: *RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const top: i32 = @as(i32, @intCast(wparam)) * 64;
            rect.* = .{ .left = 0, .top = top, .right = 380, .bottom = top + 64 };
        }
        if (message == EM_GETSEL) {
            @as(*u32, @ptrFromInt(wparam)).* = @intCast(current.?.selection_start);
            @as(*u32, @ptrFromInt(@as(usize, @bitCast(lparam)))).* = @intCast(current.?.selection_end);
        }
        if (message == EM_SETSEL) {
            current.?.selection_start = wparam;
            current.?.selection_end = @intCast(lparam);
        }
        if (message == EM_EMPTYUNDOBUFFER) current.?.undo_clears += 1;
        if (message == EM_REPLACESEL) {
            const value: [*:0]const u16 = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const text = std.mem.span(value);
            const length: usize = @intCast(GetWindowTextLengthW(1));
            const first = @min(current.?.selection_start, length);
            const last = @min(current.?.selection_end, length);
            const tail = current.?.text[last .. length + 1];
            const destination = current.?.text[first + text.len ..][0..tail.len];
            if (first + text.len >= last) {
                std.mem.copyBackwards(u16, destination, tail);
            } else {
                std.mem.copyForwards(u16, destination, tail);
            }
            @memcpy(current.?.text[first..][0..text.len], text);
            current.?.selection_start = first + text.len;
            current.?.selection_end = first + text.len;
            saveComposerDraft(current.?);
        }
        return 0;
    }
    fn EnableWindow(_: usize, enabled: i32) i32 {
        current.?.enabled = enabled != FALSE;
        return TRUE;
    }
    fn InvalidateRect(hwnd: usize, rect: ?*const RECT, erase: i32) i32 {
        if (hwnd == 3) {
            if (rect) |row| {
                std.debug.assert(erase == FALSE);
                current.?.invalidated_row = row.*;
            } else current.?.full_list_invalidations += 1;
        }
        return TRUE;
    }
    fn OpenClipboard(_: ?usize) i32 {
        return TRUE;
    }
    fn CloseClipboard() i32 {
        return TRUE;
    }
    fn GetClipboardData(_: u32) ?usize {
        if (current.?.switch_during_paste) {
            current.?.switch_during_paste = false;
            current.?.selected_chat = 1;
            switchComposerDraft(current.?);
        }
        return 1;
    }
    fn GlobalSize(_: usize) usize {
        return (current.?.clipboard.len + 1) * @sizeOf(u16);
    }
    fn GlobalLock(_: usize) ?*anyopaque {
        return @ptrCast(@constCast(current.?.clipboard.ptr));
    }
    fn GlobalUnlock(_: usize) i32 {
        return TRUE;
    }
};

fn layout(_: *App, _: i32, _: i32) void {}
fn clearReply(_: *App) void {}
fn shortcodeHide(_: *App) void {}
fn focusCompose(_: *App) void {}
fn updateAttachButton(_: *App) void {}
fn updateDictateButton(a: *App, state: dictation.State) void {
    a.last_dictation_state = state;
}
fn setStatus(_: *App, _: []const u8) void {}
fn messagesDirPath(a: *App, name: []const u8) ?[]u8 {
    return a.allocator.dupe(u8, name) catch null;
}
fn writeCacheFileAtomic(a: *App, _: []const u8, bytes: []const u8) bool {
    const copy = a.allocator.dupe(u8, bytes) catch return false;
    a.allocator.free(a.disk);
    a.disk = copy;
    return true;
}
fn readFileWin(a: std.mem.Allocator, _: []const u8, _: usize) ?[]u8 {
    return a.dupe(u8, current.?.disk) catch null;
}
fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
fn expectComposer(a: *App, expected: []const u8) !void {
    const text = composerText(a).?;
    defer a.allocator.free(text);
    try std.testing.expectEqualStrings(expected, text);
}

test "IGSH-497 UI restore and persist never leaks between workspaces and clears undo" {
    var app = App{};
    current = &app;
    defer app.deinit();
    switchComposerDraft(&app);
    _ = win.SetWindowTextW(1, lit("workspace A draft"));
    app.selected_chat = 1;
    switchComposerDraft(&app);
    try expectComposer(&app, "");
    _ = win.SetWindowTextW(1, lit("workspace B draft"));
    app.selected_chat = 0;
    switchComposerDraft(&app);
    try expectComposer(&app, "workspace A draft");
    try std.testing.expectEqual(@as(usize, 3), app.undo_clears);
    _ = win.SetWindowTextW(1, lit(""));
    app.draft_store.deinit(allocator);
    loadDrafts(&app);
    switchComposerDraft(&app);
    try expectComposer(&app, "");
    app.selected_chat = 1;
    switchComposerDraft(&app);
    try expectComposer(&app, "workspace B draft");
    app.chat_count = 0;
    switchComposerDraft(&app);
    try expectComposer(&app, "");
    try std.testing.expect(!app.enabled);
}

test "IGSH-497 UI dictation and delayed transcript paste restore only their originating workspace" {
    var app = App{};
    current = &app;
    defer app.deinit();
    switchComposerDraft(&app);
    _ = win.SetWindowTextW(1, lit("A "));
    var session = Session{ .origin = app.draft_store.open.? };
    app.dictation_session = &session;
    app.switch_during_paste = true;
    pasteComposerText(&app);
    try expectComposer(&app, "");
    _ = win.SetWindowTextW(1, lit("B"));
    updateDictation(&app);
    try expectComposer(&app, "B");
    app.selected_chat = 0;
    switchComposerDraft(&app);
    try expectComposer(&app, "A pasted transcript spoken transcript");
    app.dictation_session = null;
}

test "IGSH-466 UI dictation replaces the selection at the caret and remains undoable" {
    var app = App{};
    current = &app;
    defer app.deinit();
    switchComposerDraft(&app);
    _ = win.SetWindowTextW(1, lit("one old two"));
    app.selection_start = 4;
    app.selection_end = 7;
    const undo_clears = app.undo_clears;
    var session = Session{ .origin = app.draft_store.open.? };
    app.dictation_session = &session;
    updateDictation(&app);
    try expectComposer(&app, "one spoken transcript two");
    try std.testing.expectEqual(undo_clears, app.undo_clears);
    try std.testing.expectEqual(@as(usize, 21), app.selection_start);
    try std.testing.expectEqualStrings("one spoken transcript two", app.draft_store.get(session.origin.key()));
}

test "IGSH-510 draft edits invalidate only their visible chat row" {
    var app = App{};
    current = &app;
    defer app.deinit();
    switchComposerDraft(&app);
    app.invalidated_row = null;
    app.full_list_invalidations = 0;
    _ = win.SetWindowTextW(1, lit("draft"));
    try std.testing.expectEqualDeep(win.RECT{ .left = 0, .top = 0, .right = 380, .bottom = 64 }, app.invalidated_row.?);
    try std.testing.expectEqual(@as(usize, 0), app.full_list_invalidations);
    app.selected_chat = 1;
    switchComposerDraft(&app);
    app.invalidated_row = null;
    _ = win.SetWindowTextW(1, lit("second draft"));
    try std.testing.expectEqualDeep(win.RECT{ .left = 0, .top = 64, .right = 380, .bottom = 128 }, app.invalidated_row.?);
}

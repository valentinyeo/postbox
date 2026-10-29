const std = @import("std");
const theme = @import("theme.zig");
const compose_layout = @import("compose_layout.zig");
const source = @embedFile("main-source.zig");
const smooth_geometry = struct {
    const icon_stroke_width = 2;
};
const id_dictate = 1056;
const id_send = 1040;
const id_emoji = 1080;
const State = enum { idle, recording, transcribing, ready, failed };
const App = struct {
    dpi: i32 = 96,
    font_scale: i32 = 82,
    last_dictation_state: State = .idle,
    btn_hover: [10]bool = @splat(false),
    brush_raised: ?usize = 1,
    font_bold: ?usize = 2,
    font_icon: ?usize = 4,
    font_emoji: ?usize = 3,
    dictate: ?usize = 0,
    voice_btn: ?usize = 1,
    emoji_btn: ?usize = 2,
    send: ?usize = 3,
    attach_btn: ?usize = 4,
    voice_active: bool = false,
    compose_geometry: compose_layout.Layout = .{},
    compose_pill: win.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
};
const win = struct {
    const HWND = usize;
    const HDC = usize;
    const HFONT = usize;
    const COLORREF = u32;
    const ODS_SELECTED = 1;
    const ODS_DISABLED = 4;
    const ODS_FOCUS = 16;
    const TRUE = 1;
    const FALSE = 0;
    var bounds: [5]RECT = undefined;
    fn MoveWindow(hwnd: usize, x: i32, y: i32, width: i32, height: i32, _: i32) i32 {
        bounds[hwnd] = .{ .left = x, .top = y, .right = x + width, .bottom = y + height };
        return TRUE;
    }
    const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
    const DRAWITEMSTRUCT = struct {
        CtlID: u32 = id_dictate,
        itemState: u32 = 0,
        hDC: HDC = 1,
        rcItem: RECT = .{ .left = 0, .top = 0, .right = 44, .bottom = 44 },
    };
    fn FillRect(_: HDC, _: *const RECT, _: usize) i32 {
        return 1;
    }
};
const Paint = struct {
    label: []const u16 = &.{},
    face: u32 = 0,
    foreground: u32 = 0,
    frame: ?u32 = null,
    capsules: usize = 0,
    arcs: usize = 0,
    lines: usize = 0,
    icon_color: u32 = 0,
};
var painted = Paint{};
const smooth = struct {
    const Context = struct {
        fn init(_: win.HDC) Context {
            return .{};
        }
        fn deinit(_: *Context) void {}
    };
    fn fillRoundRect(_: *const Context, _: win.RECT, _: i32, _: i32, color: u32) void {
        painted.capsules += 1;
        painted.icon_color = color;
    }
    fn fillEllipse(_: *const Context, _: win.RECT, color: u32) void {
        painted.icon_color = color;
    }
    fn strokeArc(_: *const Context, _: win.RECT, _: f32, _: f32, color: u32, _: i32) void {
        painted.arcs += 1;
        painted.icon_color = color;
    }
    fn strokePolyline(_: *const Context, _: []const [2]f32, color: u32, _: f32) void {
        painted.lines += 1;
        painted.icon_color = color;
    }
};
fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
fn px(a: *App, value: i32) i32 {
    return @divTrunc(value * a.dpi + 48, 96);
}
fn buttonLabel(item: *win.DRAWITEMSTRUCT, _: []u16) []const u16 {
    return std.mem.span(if (item.CtlID == id_dictate) lit("Dictate") else lit("Send"));
}
fn paintRoundedButton(_: *App, _: *const smooth.Context, _: win.HDC, _: win.RECT, face: u32, foreground: u32, _: win.HFONT, frame: ?u32, text: []const u16) void {
    painted.label = text;
    painted.face = face;
    painted.foreground = foreground;
    painted.frame = frame;
}
fn section(start: []const u8, end: []const u8) []const u8 {
    const begin = std.mem.indexOf(u8, source, start).?;
    const finish = begin + std.mem.indexOf(u8, source[begin..], end).?;
    return source[begin..finish];
}

test "IGSH-534 Dictate draws no text label and uses the shared Fluent dictation glyph in every state" {
    defer theme.set(.amoled);
    for ([_]theme.Choice{.amoled}) |choice| {
        theme.set(choice);
        for ([_]State{ .idle, .recording, .transcribing, .ready, .failed }) |state| {
            for ([_]i32{ 96, 144, 192 }) |dpi| {
                var app = App{ .last_dictation_state = state, .dpi = dpi };
                var item = win.DRAWITEMSTRUCT{};
                painted = .{};
                drawComposerButton(&app, &item);
                try std.testing.expectEqual(@as(usize, 1), painted.label.len);
                try std.testing.expectEqual(@as(u16, 0xE720), painted.label[0]);
                try std.testing.expectEqual(@as(usize, 0), painted.arcs);
                try std.testing.expectEqual(@as(usize, 0), painted.lines);
            }
        }
    }
}

test "IGSH-534 composer icons have equal gaps and give freed width to the typing box" {
    for ([_]i32{ 96, 144, 192 }) |dpi| {
        var app = App{ .dpi = dpi };
        layoutComposer(&app, px(&app, 1200), px(&app, 900));
        const dictate = win.bounds[0];
        const mic = win.bounds[1];
        const emoji = win.bounds[2];
        const send = win.bounds[3];
        try std.testing.expectEqual(mic.right - mic.left, dictate.right - dictate.left);
        try std.testing.expectEqual(mic.bottom - mic.top, dictate.bottom - dictate.top);
        try std.testing.expectEqual(dictate.right - dictate.left, dictate.bottom - dictate.top);
        try std.testing.expectEqual(emoji.right - emoji.left, dictate.right - dictate.left);
        const gap = px(&app, 4);
        try std.testing.expectEqual(gap, dictate.left - mic.right);
        try std.testing.expectEqual(gap, emoji.left - dictate.right);
        try std.testing.expectEqual(gap, send.left - emoji.right);
        try std.testing.expect(app.compose_geometry.text.right < mic.left);
        try std.testing.expectEqual(px(&app, 36), send.right - send.left);
        for (win.bounds) |rect| {
            try std.testing.expect(rect.left >= app.compose_pill.left and rect.right <= app.compose_pill.right);
            try std.testing.expectEqual(app.compose_pill.bottom - px(&app, 40), rect.top);
            try std.testing.expectEqual(px(&app, 36), rect.bottom - rect.top);
        }
        app.voice_active = true;
        layoutComposer(&app, px(&app, 1200), px(&app, 900));
        const recording = win.bounds[1];
        try std.testing.expectEqual(px(&app, 200), recording.right - recording.left);
        try std.testing.expectEqual(gap, win.bounds[0].left - recording.right);
        try std.testing.expect(app.compose_geometry.text.right < recording.left);
        try std.testing.expectEqualDeep(emoji, win.bounds[2]);
        try std.testing.expectEqualDeep(dictate, win.bounds[0]);
        try std.testing.expectEqualDeep(send, win.bounds[3]);
    }
}

test "IGSH-534 Dictate keeps its accessible name and shortcut tooltip throughout dictation" {
    try std.testing.expect(std.mem.indexOf(u8, source, "a.dictate = win.CreateWindowExW(0, lit(\"BUTTON\"), lit(\"Dictate\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "addTooltip(a, tt, a.dictate, lit(\"Dictate  Ctrl+D\"))") != null);
    const dictation_source = section("fn toggleDictation(", "fn selectChat(");
    try std.testing.expect(std.mem.indexOf(u8, dictation_source, "SetWindowTextW(a.dictate") == null);
    try std.testing.expect(std.mem.indexOf(u8, dictation_source, "updateDictateButton(a, state)") != null);
    const button_source = section("fn updateDictateButton(", "fn loadRegistryString(");
    try std.testing.expect(std.mem.indexOf(u8, button_source, "a.last_dictation_state = state;") != null);
    try std.testing.expect(std.mem.indexOf(u8, button_source, "InvalidateRect(button, null, win.TRUE)") != null);
    try std.testing.expect(std.mem.indexOf(u8, button_source, "SetWindowTextW") == null);
    try std.testing.expect(std.mem.indexOf(u8, button_source, "TTM_UPDATETIPTEXTW") == null);
}

test "IGSH-534 Dictate retains theme hover pressed focus and recording colours and keeps the shared Send glyph" {
    defer theme.set(.amoled);
    for ([_]theme.Choice{.amoled}) |choice| {
        theme.set(choice);
        for ([_]bool{ false, true }) |hover| {
            for ([_]u32{ 0, win.ODS_SELECTED, win.ODS_FOCUS, win.ODS_SELECTED | win.ODS_FOCUS }) |flags| {
                for ([_]State{ .idle, .recording, .transcribing }) |state| {
                    var app = App{ .last_dictation_state = state };
                    app.btn_hover[0] = hover;
                    var item = win.DRAWITEMSTRUCT{ .itemState = flags };
                    painted = .{};
                    drawComposerButton(&app, &item);
                    const active = flags & win.ODS_SELECTED != 0 or state == .recording or state == .transcribing;
                    const face = if (choice == .amoled) (if (active) theme.amoled_button_pressed else if (hover) theme.amoled_button_hover else theme.current.surface_container_high) else if (active) theme.current.primary_container else if (hover) theme.current.surface_container_highest else theme.current.surface_container_high;
                    try std.testing.expectEqual(face, painted.face);
                    try std.testing.expectEqual(if (choice == .amoled) theme.amoled_button_text else if (active) theme.current.on_primary_container else theme.current.on_surface, painted.foreground);
                    const frame: ?u32 = if (flags & win.ODS_FOCUS != 0) theme.current.primary else if (choice == .amoled and hover) theme.current.outline_variant else null;
                    try std.testing.expectEqual(frame, painted.frame);
                }
            }
        }
        var app = App{};
        var send = win.DRAWITEMSTRUCT{ .CtlID = id_send };
        painted = .{};
        drawComposerButton(&app, &send);
        try std.testing.expectEqual(@as(usize, 1), painted.label.len);
        try std.testing.expectEqual(@as(usize, 0), painted.capsules + painted.arcs);
        try std.testing.expectEqual(@as(u16, 0xE724), painted.label[0]);
        try std.testing.expectEqual(if (choice == .amoled) theme.amoled_send else theme.current.primary, painted.face);
    }
}

fn threadPanelWidth(_: *const App, _: i32, _: i32) i32 {
    return 0;
}

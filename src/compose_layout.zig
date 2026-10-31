pub const edit_min_height: i32 = 44;
pub const default_max_height: i32 = 240;
pub const canvas_min_height: i32 = 160;
pub const strip_padding: i32 = 22;

pub const Composer = struct {
    edit_height: i32,
    strip_height: i32,
};

pub const preview_band: i32 = 54;

pub fn compute(dragged: i32, content_height: i32, client_height: i32, preview: bool) Composer {
    return computeScaled(dragged, content_height, client_height, preview, 96);
}

pub fn computeScaled(dragged: i32, content_height: i32, client_height: i32, preview: bool, dpi: i32) Composer {
    const band: i32 = if (preview) scale(preview_band, dpi) else 0;
    const min_height = scale(edit_min_height, dpi);
    const cap: i32 = @max(scale(default_max_height, dpi), dragged);
    var edit: i32 = @max(@max(min_height, dragged), content_height);
    edit = @min(edit, cap);
    const room_for_edit: i32 = client_height - scale(canvas_min_height, dpi) - scale(strip_padding, dpi) - band;
    if (room_for_edit > 0 and edit > room_for_edit) edit = room_for_edit;
    if (edit < min_height) edit = @min(min_height, @max(0, room_for_edit));
    return .{ .edit_height = edit, .strip_height = edit + scale(strip_padding, dpi) + band };
}

pub const Rect = extern struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
};

pub fn composerBorderRect(box: Rect) Rect {
    return .{ .left = box.left, .top = box.top, .right = box.right + 1, .bottom = box.bottom + 1 };
}

pub const Layout = struct {
    box: Rect = .{},
    attach: Rect = .{},
    text: Rect = .{},
    voice: Rect = .{},
    dictate: Rect = .{},
    emoji: Rect = .{},
    send: Rect = .{},
};

pub const column_margin: i32 = 14;

pub fn messageColumn(pane_width: i32, dpi: i32) Rect {
    const inset = @max(0, @divTrunc(pane_width - scale(@import("theme.zig").chat_column_width, dpi), 2));
    const margin = @min(scale(column_margin, dpi), @divTrunc(@max(0, pane_width), 2));
    const left = inset + margin;
    return .{ .left = left, .top = 0, .right = @max(left, pane_width - inset - margin), .bottom = 0 };
}

pub fn arrange(pane: Rect, edit_height: i32, dpi: i32, recording: bool, dictating: bool) Layout {
    const bottom = @max(pane.top, pane.bottom - scale(11, dpi));
    const column = messageColumn(pane.right - pane.left, dpi);
    const box = Rect{ .left = pane.left + column.left, .top = @max(pane.top, bottom - edit_height), .right = pane.left + column.right, .bottom = bottom };
    const width = @max(0, box.right - box.left);
    const height = @max(0, box.bottom - box.top);
    const padding = @min(scale(16, dpi), @divTrunc(width, 12));
    const gap = @min(scale(4, dpi), @divTrunc(width, 32));
    const vertical = @min(scale(6, dpi), @divTrunc(height, 2));
    const icon = @max(0, @min(scale(@import("design_tokens.zig").button_size, dpi), @min(height - @min(scale(12, dpi), height), @divTrunc(width - 2 * padding - 6 * gap, 7))));
    const icon_bottom = box.bottom - vertical;
    const icon_top = icon_bottom - icon;
    const send = Rect{ .left = box.right - padding - icon, .top = icon_top, .right = box.right - padding, .bottom = icon_bottom };
    const emoji = Rect{ .left = send.left - gap - icon, .top = icon_top, .right = send.left - gap, .bottom = icon_bottom };
    const text_min = @min(scale(32, dpi), 2 * icon);
    const dictate_width = if (dictating) @max(icon, @min(scale(@import("design_tokens.zig").mic_width, dpi), width - 2 * padding - 4 * icon - 6 * gap - text_min - scale(8, dpi))) else icon;
    const dictate = Rect{ .left = emoji.left - gap - dictate_width, .top = icon_top, .right = emoji.left - gap, .bottom = icon_bottom };
    const attach = Rect{ .left = box.left + padding, .top = icon_top, .right = box.left + padding + icon, .bottom = icon_bottom };
    const text_left = attach.right + gap;
    const voice_width = if (recording) @max(icon, @min(scale(200, dpi), dictate.left - text_left - 3 * gap - text_min - scale(8, dpi))) else icon;
    const voice = Rect{ .left = dictate.left - gap - voice_width, .top = icon_top, .right = dictate.left - gap, .bottom = icon_bottom };
    const text = Rect{ .left = text_left, .top = box.top + @min(1, height), .right = @max(text_left, voice.left - gap - @min(scale(8, dpi), icon)), .bottom = @max(box.top + @min(1, height), box.bottom - 1) };
    return .{ .box = box, .attach = attach, .text = text, .voice = voice, .dictate = dictate, .emoji = emoji, .send = send };
}

pub fn recordingTimerVisible(rect: Rect, dpi: i32) bool {
    return rect.right - rect.left >= scale(120, dpi);
}

fn scale(v: i32, dpi: i32) i32 {
    return @divTrunc(v * dpi + 48, 96);
}

test "grows with content up to the default cap" {
    const c = compute(0, 600, 900, false);
    try @import("std").testing.expectEqual(@as(i32, 240), c.edit_height);
    const mid = compute(0, 80, 900, false);
    try @import("std").testing.expectEqual(@as(i32, 80), mid.edit_height);
    const one = compute(0, 30, 900, false);
    try @import("std").testing.expectEqual(@as(i32, 44), one.edit_height);
}

test "dragged height raises floor and cap" {
    const c = compute(320, 30, 900, false);
    try @import("std").testing.expectEqual(@as(i32, 320), c.edit_height);
    const over = compute(320, 400, 900, false);
    try @import("std").testing.expectEqual(@as(i32, 320), over.edit_height);
}

test "clamps to keep the message pane usable" {
    const c = compute(400, 400, 300, false);
    try @import("std").testing.expectEqual(@as(i32, 118), c.edit_height);
    try @import("std").testing.expectEqual(@as(i32, 140), c.strip_height);
}

test "preview band adds height" {
    const plain = compute(0, 30, 900, false);
    const with = compute(0, 30, 900, true);
    try @import("std").testing.expectEqual(plain.strip_height + preview_band, with.strip_height);
}

test "one box contains disjoint text and bottom anchored icons at narrow and wide widths" {
    const testing = @import("std").testing;
    for ([_]i32{ 96, 120, 144, 192 }) |dpi| {
        for ([_]i32{ 280, 900 }) |width| {
            const pane = Rect{ .left = scale(300, dpi), .top = 0, .right = scale(300 + width, dpi), .bottom = scale(900, dpi) };
            for ([_]bool{ false, true }) |recording| {
                const baseline = arrange(pane, scale(44, dpi), dpi, recording, false);
                for ([_]i32{ 1, 2, 8 }) |lines| {
                    const size = computeScaled(0, scale(lines * 20 + 16, dpi), pane.bottom, false, dpi);
                    const slots = arrange(pane, size.edit_height, dpi, recording, false);
                    if (recording) {
                        try testing.expectEqual(width == 900, recordingTimerVisible(slots.voice, dpi));
                        try testing.expect(!recordingTimerVisible(.{ .right = scale(120, dpi) - 1 }, dpi));
                        try testing.expect(recordingTimerVisible(.{ .right = scale(120, dpi) }, dpi));
                    }
                    const icons = [_]Rect{ slots.attach, slots.voice, slots.dictate, slots.emoji, slots.send };
                    const baseline_icons = [_]Rect{ baseline.attach, baseline.voice, baseline.dictate, baseline.emoji, baseline.send };
                    const all = [_]Rect{ slots.attach, slots.text, slots.voice, slots.dictate, slots.emoji, slots.send };
                    for (all, 0..) |rect, i| {
                        try testing.expect(rect.left >= slots.box.left and rect.right <= slots.box.right);
                        try testing.expect(rect.top >= slots.box.top and rect.bottom <= slots.box.bottom);
                        try testing.expect(rect.right > rect.left and rect.bottom > rect.top);
                        const radius = @as(f64, @floatFromInt(@min(scale(56, dpi), slots.box.bottom - slots.box.top))) / 2;
                        for ([_]i32{ rect.left, rect.right }) |x| {
                            for ([_]i32{ rect.top, rect.bottom }) |y| {
                                const xf: f64 = @floatFromInt(x);
                                const yf: f64 = @floatFromInt(y);
                                const cx = @import("std").math.clamp(xf, @as(f64, @floatFromInt(slots.box.left)) + radius, @as(f64, @floatFromInt(slots.box.right)) - radius);
                                const cy = @import("std").math.clamp(yf, @as(f64, @floatFromInt(slots.box.top)) + radius, @as(f64, @floatFromInt(slots.box.bottom)) - radius);
                                const dx = xf - cx;
                                const dy = yf - cy;
                                try testing.expect(dx * dx + dy * dy <= radius * radius);
                            }
                        }
                        for (all[i + 1 ..]) |other| {
                            try testing.expect(rect.right <= other.left or other.right <= rect.left or rect.bottom <= other.top or other.bottom <= rect.top);
                        }
                    }
                    for (icons, baseline_icons) |rect, initial| {
                        try testing.expectEqualDeep(initial, rect);
                        try testing.expectEqual(slots.box.bottom - scale(6, dpi), rect.bottom);
                        try testing.expect(rect.bottom - rect.top <= scale(@import("design_tokens.zig").button_size, dpi));
                        if (!recording or rect.left != slots.voice.left) try testing.expectEqual(rect.bottom - rect.top, rect.right - rect.left);
                        if (width == 900) try testing.expectEqual(scale(@import("design_tokens.zig").button_size, dpi), rect.bottom - rect.top);
                    }
                    try testing.expectEqual(slots.box.left + scale(16, dpi), slots.attach.left);
                    try testing.expectEqual(slots.box.right - scale(16, dpi), slots.send.right);
                    try testing.expectEqual(size.edit_height, slots.box.bottom - slots.box.top);
                    try testing.expectEqual(slots.box.top + 1, slots.text.top);
                    try testing.expectEqual(slots.box.bottom - 1, slots.text.bottom);
                }
            }
        }
    }
}

test "composer border centreline has equal inset on all four sides at 100 125 150 percent" {
    const testing = @import("std").testing;
    for ([_]i32{ 96, 120, 144 }) |dpi| {
        for ([_]i32{ 44, 81, 240 }) |height| {
            const box = Rect{ .left = scale(404, dpi), .top = scale(600, dpi), .right = scale(900, dpi), .bottom = scale(600 + height, dpi) };
            const border = composerBorderRect(box);
            const centreline = Rect{ .left = border.left, .top = border.top, .right = border.right - 1, .bottom = border.bottom - 1 };
            const insets = [_]i32{ centreline.left - box.left, centreline.top - box.top, box.right - centreline.right, box.bottom - centreline.bottom };
            for (insets) |inset| try testing.expectEqual(@as(i32, 0), inset);
            const text = arrange(.{ .left = box.left - scale(14, dpi), .right = box.right + scale(14, dpi), .bottom = box.bottom + scale(11, dpi) }, box.bottom - box.top, dpi, false, false).text;
            try testing.expectEqual(box.top + 1, text.top);
            try testing.expectEqual(box.bottom - 1, text.bottom);
            try testing.expectEqual(text.top - centreline.top, centreline.bottom - text.bottom);
        }
    }
}

test "active dictation keeps the shared pill inside the composer at narrow widths and every DPI" {
    const testing = @import("std").testing;
    for ([_]i32{ 96, 120, 144, 192 }) |dpi| {
        for ([_]i32{ 280, 900 }) |width| {
            const pane = Rect{ .left = 0, .right = scale(width, dpi), .bottom = scale(900, dpi) };
            const slots = arrange(pane, scale(44, dpi), dpi, false, true);
            const pill = slots.dictate;
            try testing.expect(pill.left >= slots.box.left and pill.right <= slots.box.right);
            try testing.expect(pill.top >= slots.box.top and pill.bottom <= slots.box.bottom);
            try testing.expect(slots.text.right <= slots.voice.left and slots.voice.right < pill.left);
            try testing.expect(slots.emoji.left > pill.right);
            if (width == 900) try testing.expectEqual(scale(@import("design_tokens.zig").mic_width, dpi), pill.right - pill.left);
        }
    }
}

test "message column and composer box share both edges at every width and dpi" {
    const testing = @import("std").testing;
    for ([_]i32{ 320, 723, 1024, 1600, 2560 }) |pane_width| {
        for ([_]i32{ 96, 120, 144, 192 }) |dpi| {
            const pane = Rect{ .left = 301, .top = 0, .right = 301 + pane_width, .bottom = 900 };
            const column = messageColumn(pane_width, dpi);
            const layout = arrange(pane, scale(edit_min_height, dpi), dpi, false, false);
            try testing.expectEqual(pane.left + column.left, layout.box.left);
            try testing.expectEqual(pane.left + column.right, layout.box.right);
            try testing.expect(column.right > column.left);
        }
    }
}

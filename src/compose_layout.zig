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

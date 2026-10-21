const theme = @import("theme.zig");
const smooth = @import("smooth_shapes.zig");
const std = @import("std");
const win = @import("win32.zig").c;
const text_draw = @import("text_draw.zig");
const status = @import("status_view.zig");

pub const State = struct {
    mode: enum { closed, list, viewer } = .closed,
    navigation: status.Navigation = .{},
    scroll: i32 = 0,
    selected: usize = 0,
    hits: [status.max_rows]win.RECT = undefined,
    hit_count: usize = 0,
    bitmap: ?win.HBITMAP = null,
    width: i32 = 0,
    height: i32 = 0,
    displayed: bool = false,
    failed: bool = false,
};

fn wide(a: anytype, text: []const u8) ?[:0]u16 {
    return std.unicode.utf8ToUtf16LeAllocZ(a.allocator, text) catch null;
}

fn textAt(a: anytype, hdc: win.HDC, text: []const u8, rect: win.RECT, flags: win.UINT) void {
    const text_wide = wide(a, text) orelse return;
    defer a.allocator.free(text_wide);
    var box = rect;
    _ = text_draw.drawText(hdc, text_wide.ptr, @intCast(text_wide.len), &box, flags);
}

fn timeLabel(buffer: []u8, timestamp: i64, now: i64) []const u8 {
    const minutes = @divTrunc(@max(0, now - timestamp), 60);
    if (minutes == 0) return "Just now";
    if (minutes < 60) return std.fmt.bufPrint(buffer, "{d} min ago", .{minutes}) catch "";
    return std.fmt.bufPrint(buffer, "{d} h ago", .{@divTrunc(minutes, 60)}) catch "";
}

pub fn clearMedia(a: anytype) void {
    if (a.status_ui.bitmap) |bitmap| _ = win.DeleteObject(bitmap);
    a.status_ui.bitmap = null;
    a.status_ui.width = 0;
    a.status_ui.height = 0;
    a.status_ui.displayed = false;
}

pub fn drawPinned(a: anytype, item: *win.DRAWITEMSTRUCT, comptime actions: anytype) void {
    _ = win.FillRect(item.hDC, &item.rcItem, a.brush_panel.?);
    _ = win.SetBkMode(item.hDC, win.TRANSPARENT);
    _ = win.SelectObject(item.hDC, a.font_bold.?);
    _ = win.SetTextColor(item.hDC, theme.current.on_surface);
    var box = item.rcItem;
    box.left += actions.px(a, 16);
    box.top += actions.px(a, 7);
    box.bottom = box.top + actions.px(a, 25);
    textAt(a, item.hDC, "Status", box, win.DT_SINGLELINE | win.DT_END_ELLIPSIS);
    box.top = box.bottom;
    box.bottom = item.rcItem.bottom;
    _ = win.SelectObject(item.hDC, a.font_small.?);
    _ = win.SetTextColor(item.hDC, theme.current.primary);
    var buffer: [100]u8 = undefined;
    const groups = status.group(actions.rows(a), &a.status_viewed);
    const label = std.fmt.bufPrint(&buffer, "{d} contacts with unseen updates", .{groups.recent}) catch "";
    textAt(a, item.hDC, label, box, win.DT_SINGLELINE | win.DT_END_ELLIPSIS);
    if ((item.itemState & win.ODS_FOCUS) != 0) _ = win.DrawFocusRect(item.hDC, &item.rcItem);
}

pub fn paint(a: anytype, hwnd: win.HWND, comptime actions: anytype) void {
    var ps = win.PAINTSTRUCT{};
    const hdc = win.BeginPaint(hwnd, &ps);
    defer _ = win.EndPaint(hwnd, &ps);
    var client: win.RECT = undefined;
    _ = win.GetClientRect(hwnd, &client);
    _ = win.FillRect(hdc, &client, a.brush_bg.?);
    _ = win.SetBkMode(hdc, win.TRANSPARENT);
    _ = win.SetTextColor(hdc, theme.current.on_surface);
    _ = win.SelectObject(hdc, a.font_bold.?);
    const margin = actions.px(a, 24);
    var box = win.RECT{ .left = margin, .top = margin, .right = client.right - margin, .bottom = actions.px(a, 58) };
    const rows = actions.rows(a);
    if (a.status_ui.mode == .viewer) {
        const index = a.status_ui.navigation.current() orelse return;
        if (index >= rows.len) return;
        const row = rows[index];
        textAt(a, hdc, row.name(), box, win.DT_SINGLELINE | win.DT_END_ELLIPSIS);
        box.top = box.bottom;
        box.bottom += actions.px(a, 28);
        _ = win.SelectObject(hdc, a.font_small.?);
        var buffer: [48]u8 = undefined;
        textAt(a, hdc, timeLabel(&buffer, row.ts, actions.now()), box, win.DT_SINGLELINE);
        var content = win.RECT{ .left = margin, .top = actions.px(a, 100), .right = client.right - margin, .bottom = client.bottom - actions.px(a, 64) };
        if (row.media_type.len == 0) {
            const brush = win.CreateSolidBrush(status.backgroundColor(row.background_color));
            if (brush) |b| {
                _ = win.FillRect(hdc, &content, b);
                _ = win.DeleteObject(b);
            }
            _ = win.SelectObject(hdc, a.font.?);
            var measured = content;
            const value = wide(a, row.text) orelse return;
            defer a.allocator.free(value);
            _ = text_draw.drawText(hdc, value.ptr, @intCast(value.len), &measured, win.DT_CENTER | win.DT_WORDBREAK | win.DT_CALCRECT);
            content.top += @max(0, @divTrunc(content.bottom - content.top - (measured.bottom - measured.top), 2));
            _ = text_draw.drawText(hdc, value.ptr, @intCast(value.len), &content, win.DT_CENTER | win.DT_WORDBREAK);
            actions.viewed(a);
        } else if (a.status_ui.bitmap) |bitmap| {
            const width = @max(1, content.right - content.left);
            const height = @max(1, content.bottom - content.top);
            const scale = @min(@as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(a.status_ui.width)), @as(f64, @floatFromInt(height)) / @as(f64, @floatFromInt(a.status_ui.height)));
            const w: i32 = @max(1, @as(i32, @intFromFloat(@as(f64, @floatFromInt(a.status_ui.width)) * scale)));
            const h: i32 = @max(1, @as(i32, @intFromFloat(@as(f64, @floatFromInt(a.status_ui.height)) * scale)));
            const dc = win.CreateCompatibleDC(hdc);
            if (dc != null) {
                const old = win.SelectObject(dc, bitmap);
                _ = win.SetStretchBltMode(hdc, win.HALFTONE);
                _ = win.StretchBlt(hdc, content.left + @divTrunc(width - w, 2), content.top + @divTrunc(height - h, 2), w, h, dc, 0, 0, a.status_ui.width, a.status_ui.height, win.SRCCOPY);
                _ = win.SelectObject(dc, old);
                _ = win.DeleteDC(dc);
                actions.viewed(a);
            }
        } else {
            _ = win.SelectObject(hdc, a.font.?);
            const label = if (a.status_ui.failed) "This update is unavailable" else if (row.local_path.len == 0) "Downloading update..." else "Video playing in-app";
            textAt(a, hdc, label, content, win.DT_CENTER | win.DT_SINGLELINE | win.DT_VCENTER);
        }
        box = .{ .left = margin, .top = client.bottom - actions.px(a, 48), .right = client.right - margin, .bottom = client.bottom - actions.px(a, 12) };
        _ = win.SelectObject(hdc, a.font_small.?);
        box.right = @divTrunc(client.right, 3);
        textAt(a, hdc, "← Previous", box, win.DT_CENTER | win.DT_SINGLELINE | win.DT_END_ELLIPSIS);
        box.left = box.right;
        box.right = @divTrunc(client.right * 2, 3);
        textAt(a, hdc, "Reply (R)", box, win.DT_CENTER | win.DT_SINGLELINE | win.DT_END_ELLIPSIS);
        box.top += actions.px(a, 20);
        textAt(a, hdc, "Esc: updates", box, win.DT_CENTER | win.DT_SINGLELINE | win.DT_END_ELLIPSIS);
        box.top -= actions.px(a, 20);
        box.left = box.right;
        box.right = client.right - margin;
        textAt(a, hdc, "Next →", box, win.DT_CENTER | win.DT_SINGLELINE | win.DT_END_ELLIPSIS);
        return;
    }
    textAt(a, hdc, "Status", box, win.DT_SINGLELINE);
    const groups = status.group(rows, &a.status_viewed);
    a.status_ui.hit_count = groups.count;
    const saved = win.SaveDC(hdc);
    defer _ = win.RestoreDC(hdc, saved);
    _ = win.IntersectClipRect(hdc, 0, actions.px(a, 72), client.right, client.bottom);
    var shapes = smooth.Context.init(hdc);
    defer shapes.deinit();
    const heading = actions.px(a, 40);
    const row_height = actions.px(a, 76);
    const total = actions.px(a, 88) + 2 * heading + @as(i32, @intCast(groups.count)) * row_height;
    a.status_ui.scroll = std.math.clamp(a.status_ui.scroll, 0, @max(0, total - client.bottom));
    var y = actions.px(a, 88) - a.status_ui.scroll;
    for (0..2) |section| {
        _ = win.SelectObject(hdc, a.font_bold.?);
        _ = win.SetTextColor(hdc, theme.current.on_surface);
        box = .{ .left = margin, .top = y, .right = client.right - margin, .bottom = y + heading };
        textAt(a, hdc, if (section == 0) "Recent updates" else "Viewed updates", box, win.DT_SINGLELINE | win.DT_VCENTER);
        y += heading;
        const start = if (section == 0) 0 else groups.recent;
        const end = if (section == 0) groups.recent else groups.count;
        for (groups.contacts[start..end], start..) |contact, i| {
            const row = rows[contact.newest];
            const hit = win.RECT{ .left = margin, .top = y, .right = client.right - margin, .bottom = y + row_height };
            a.status_ui.hits[i] = hit;
            if (y + row_height >= 0 and y < client.bottom) {
                if (i == a.status_ui.selected) {
                    if (theme.choice == .amoled) {
                        smooth.fillRoundRect(&shapes, hit, 16, 16, theme.current.surface_container_highest);
                        smooth.strokeRoundRect(&shapes, hit, 16, 16, theme.current.outline_variant, 1);
                    } else _ = win.FillRect(hdc, &hit, a.brush_panel.?);
                }
                const left = margin + actions.px(a, 8);
                const top = y + actions.px(a, 12);
                smooth.strokeEllipse(&shapes, .{ .left = left - 4, .top = top - 4, .right = left + 46, .bottom = top + 46 }, if (contact.unseen) theme.current.primary else theme.current.outline, actions.px(a, 3));
                const entry = actions.avatar(a, row.sender_jid);
                if (entry != null and entry.?.bitmap != null) {
                    actions.drawAvatar(hdc, entry.?.bitmap.?, left, top, 42);
                } else {
                    const name = wide(a, row.name());
                    if (name) |value| {
                        defer a.allocator.free(value);
                        if (value.len > 0) {
                            var initial_box = win.RECT{ .left = left, .top = top, .right = left + 42, .bottom = top + 42 };
                            _ = win.SelectObject(hdc, a.font_bold.?);
                            _ = win.SetTextColor(hdc, theme.current.on_surface);
                            _ = text_draw.drawText(hdc, value.ptr, if (value[0] >= 0xd800 and value[0] <= 0xdbff and value.len > 1) 2 else 1, &initial_box, win.DT_CENTER | win.DT_SINGLELINE | win.DT_VCENTER);
                        }
                    }
                }
                box = .{ .left = left + actions.px(a, 64), .top = y + actions.px(a, 10), .right = client.right - margin, .bottom = y + actions.px(a, 36) };
                _ = win.SelectObject(hdc, a.font.?);
                _ = win.SetTextColor(hdc, theme.current.on_surface);
                textAt(a, hdc, row.name(), box, win.DT_SINGLELINE | win.DT_END_ELLIPSIS);
                box.top = box.bottom;
                box.bottom = y + row_height;
                _ = win.SelectObject(hdc, a.font_small.?);
                _ = win.SetTextColor(hdc, theme.current.on_surface_variant);
                var buffer: [48]u8 = undefined;
                textAt(a, hdc, timeLabel(&buffer, row.ts, actions.now()), box, win.DT_SINGLELINE);
            }
            y += row_height;
        }
    }
    if (groups.count == 0) {
        box = .{ .left = margin, .top = y + margin, .right = client.right - margin, .bottom = client.bottom };
        textAt(a, hdc, if (a.status_ui.failed) "Status is unavailable. Try again later." else if (a.status_list == null) "Loading updates..." else "No updates in the last 24 hours", box, win.DT_CENTER | win.DT_WORDBREAK);
    }
}

pub fn click(a: anytype, hwnd: win.HWND, x: i32, y: i32, comptime actions: anytype) void {
    if (a.status_ui.mode == .viewer) {
        var client: win.RECT = undefined;
        _ = win.GetClientRect(hwnd, &client);
        if (y >= client.bottom - actions.px(a, 60) and x >= @divTrunc(client.right, 3) and x < @divTrunc(client.right * 2, 3)) {
            actions.reply(a);
        } else if (x < @divTrunc(client.right, 3)) {
            actions.step(a, -1);
        } else if (x >= @divTrunc(client.right * 2, 3)) {
            actions.step(a, 1);
        }
    } else {
        for (a.status_ui.hits[0..a.status_ui.hit_count], 0..) |hit, index| {
            if (x >= hit.left and x < hit.right and y >= hit.top and y < hit.bottom) {
                actions.openContact(a, index);
                break;
            }
        }
    }
}

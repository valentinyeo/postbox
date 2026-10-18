from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def section(source, start, end):
    first = source.index(start)
    return source[first:source.index(end, first + len(start))]


def require(source, *needles):
    for needle in needles:
        if needle not in source:
            raise AssertionError(f"missing Status integration: {needle}")


def reject(source, *needles):
    for needle in needles:
        if needle in source:
            raise AssertionError(f"unexpected Status side effect: {needle}")


def verify(files):
    main = files["src/main.zig"]
    model = files["src/status_view.zig"]
    ui = files["src/status_ui.zig"]
    control = files["src/control.zig"]
    require(main, 'const status_view = @import("status_view.zig");', 'const status_ui = @import("status_ui.zig");')
    palette = section(main, "fn buildPaletteItems(", "fn ")
    require(palette, 'appendPalette(a, "Status", "", command_status);')
    layout = section(main, "fn layout(", "fn loadAvatarBitmap(")
    require(layout, "activeChatView(a) == .whatsapp", "status_row_height", "search_height + status_row_height", "a.status_row", "win.SW_HIDE")
    require(main, 'controlId(id_status_row)', 'status_ui.drawPinned(a, item, status_actions);', 'id == id_status_row and notification == win.BN_CLICKED', 'command_status => openStatuses(a, true)')
    require(ui, 'contacts with unseen updates', 'status.group(actions.rows(a), &a.status_viewed)')
    require(ui, '"Recent updates"', '"Viewed updates"', 'win.Ellipse', 'contact.unseen', 'actions.avatar(a, row.sender_jid)', 'timeLabel(&buffer, row.ts')
    require(main, '.avatar = avatarForChat', '.drawAvatar = drawAvatarBitmap')
    require(model, 'if (row.from_me) continue;', 'if (a.unseen != b.unseen) return a.unseen;', 'return ra.ts > rb.ts;')
    require(main, 'status_ui.paint(a, hwnd, status_actions)', 'status_ui.click(a, hwnd, x, y, status_actions)', 'win.VK_LEFT =>', 'stepStatus(a, -1)', 'win.VK_RIGHT =>', 'stepStatus(a, 1)', 'statusBack(a)', 'image_viewer.decodeImageViewerBitmap(a, &message', 'playVideoInline(a, &message)')
    require(ui, 'status.backgroundColor(row.background_color)', 'row.text', 'win.DT_CENTER', 'client.right * 2, 3', 'client.right, 3', 'actions.step(a, -1)', 'actions.step(a, 1)')
    contact = section(main, "fn openStatusContact(", "fn markStatusViewed(")
    require(contact, 'status_view.Navigation.init', 'showStatusMedia(a)', 'drainMediaDownloads(a)')
    auto = section(main, "fn autoDownloadStatus(", "fn replyToStatus(")
    require(auto, 'for (rows) |row|', 'rows[current].sender_jid', 'return startMediaDownload(a, status_view.broadcast, row.msg_id)', 'media_drain.mayContinueBurst', 'mediaAttempted', 'failure.retry_after_ms')
    require(main, 'if (a.status_ui.mode == .viewer) return autoDownloadStatus(a);')
    download = section(main, "fn startMediaDownload(", "fn downloadMedia(")
    require(download, 'stopSync(a, "media")', '"--lock-wait", "10s"', '"media", "download", "--chat", slot.jid.slice(), "--id", slot.id.slice()')
    require(main, 'status_finished) refreshStatuses(a, true)', 'wacliPendingGet(a, .statuses) > 0')
    mark = section(main, "fn markStatusViewed(", "fn showStatusMedia(")
    require(mark, 'status_viewed.mark', 'rows[index].msg_id, rows[index].ts', 'persistStatusViewed(a)')
    reject(mark, 'wacliEnqueue', 'markChatRead', 'pending_reads', 'sendMessage')
    persist = section(main, "fn persistStatusViewed(", "fn refreshStatuses(")
    require(persist, '"status-viewed.txt"', 'status_viewed.encode', 'writeCacheFileAtomic')
    require(main[main.index('pub fn main(init: std.process.Init) !void {'):], 'app.status_viewed.load(init.gpa, data, nowUnixSeconds())', 'defer app.status_viewed.deinit(init.gpa)')
    require(model, 'now - 48 * 3600', 'pub fn load(', 'pub fn encode(')
    reply = section(main, "fn replyToStatus(", "const status_actions")
    require(reply, 'jid.set(row.sender_jid)', 'row.quote()', 'switchChatView(a, .whatsapp)', 'a.status_reply_chat', 'a.show_archived = false', 'controlSelectIndex(a, selected.?)', 'win.SetWindowTextW(compose, quoted.ptr())', 'focusCompose(a)')
    require(main, "'R' =>", 'replyToStatus(a)')
    require(ui, 'Reply (R)', 'actions.reply(a)')
    require(control, '@"open-status"', '.cmd = .statuses', 'Command.statuses', 'Command.@"open-status"')
    require(main, '.statuses => try status_view.writeStatuses(w, statusRows(a), &a.status_viewed)', '.@"open-status" =>', 'openStatuses(a, false)')
    require(files['src/wazigctl.zig'], '@import("control.zig")', 'control.parseArgs', 'control.writeRequest', 'control_pipe.writeAll')
    require(files['src/control_pipe.zig'], 'callUi(', 'win.PostMessageW')
    require(model, 'pub fn writeStatuses(', '\\"msg_id\\"', '\\"sender_jid\\"', '\\"sender_name\\"', '\\"ts\\"', '\\"from_me\\"', '\\"viewed\\"', '\\"media_type\\"', '\\"local_path\\"')
    refresh = section(main, 'fn refreshStatuses(', 'fn applyStatuses(')
    require(refresh, 'a.wacli_thread == null', 'wacliPendingGet(a, .statuses)', 'if (!a.status_refresh_requested and !status_view.mayRefresh(a.status_last_refresh_ms, now)) return;', 'stopSync(a, "status")', 'wacliJobArgs(&job, &.{ a.wacli_path, "--json", "--read-only", "status", "list", "--limit", "200" })', 'a.status_last_refresh_ms = now', 'wacliEnqueue(a, job, false)')
    reject(refresh, 'child_process.run', 'child_process.spawn')
    require(section(main, 'fn openStatuses(', 'fn closeStatuses('), 'refreshStatuses(a, true)')
    require(main, 'refreshContactsIndex(a);\n            refreshStatuses(a, false);', 'updateVoiceButton(a);\n                refreshStatuses(a, false);')
    require(model, 'pub const refresh_ms = 5 * 60 * 1000;', 'now -| time >= refresh_ms')
    require(files['build.zig'], '"src/status_view.zig"')


paths = ['src/main.zig', 'src/status_view.zig', 'src/status_ui.zig', 'src/control.zig', 'src/control_pipe.zig', 'src/wazigctl.zig', 'build.zig']
files = {path: (ROOT / path).read_text() for path in paths}
verify(files)
mutations = [
    ('src/main.zig', 'appendPalette(a, "Status", "", command_status);'),
    ('src/status_ui.zig', '"Recent updates"'),
    ('src/main.zig', 'return startMediaDownload(a, status_view.broadcast, row.msg_id)'),
    ('src/main.zig', 'rows[index].msg_id, rows[index].ts'),
    ('src/main.zig', 'win.SetWindowTextW(compose, quoted.ptr())'),
    ('src/main.zig', '.statuses => try status_view.writeStatuses(w, statusRows(a), &a.status_viewed)'),
    ('src/main.zig', 'if (!a.status_refresh_requested and !status_view.mayRefresh(a.status_last_refresh_ms, now)) return;'),
]
for path, token in mutations:
    changed = dict(files)
    changed[path] = changed[path].replace(token, '', 1)
    try:
        verify(changed)
    except (AssertionError, ValueError):
        continue
    raise AssertionError(f"integration check missed removal: {token}")
positive = dict(files)
positive['src/main.zig'] = positive['src/main.zig'].replace('fn markStatusViewed(a: *App) void {', 'fn markStatusViewed(a: *App) void {\n    wacliEnqueue(a, job, false);', 1)
try:
    verify(positive)
except AssertionError:
    pass
else:
    raise AssertionError('viewed-state side-effect guard missed a network write')
print('Status integration passed: seven requirement paths, removal controls and receipt guard')

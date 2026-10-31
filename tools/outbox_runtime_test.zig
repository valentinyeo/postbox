const std = @import("std");
const staged_images = @import("staged_images.zig");
var verification_fixture = false;
fn verificationEnqueue(_: *App, _: WacliJob) bool {
    return false;
}
const drafts = struct {
    const max_text = 64 * 1024;
};
const outbox = @import("outbox.zig");
const chat_key = @import("chat_key.zig");
const transport = @import("transport.zig");
const voice_sent = @import("voice_sent.zig");
const Utf8Text = outbox.Str;
const max_pending_sends = 32;
const max_messages = 3;
const max_send_retries = 4;
const file_send_placeholder = "Sending file...";
const max_slack_outbox = 16;
const max_wacli_args = 4;
const wacli_arg_cap = 4095;
const wacli_queue_size = 4;
const WacliJobKind = enum(u8) { chats, groups, messages, reaction, slack_workspace, slack_users, slack_history, slack_replies, slack_send, slack_attach, slack_download, slack_auth, cache_tag, slack_mark };
const WacliLane = enum { wacli, slack, hub_media, hub_send };
const WacliJob = struct {
    kind: WacliJobKind = .chats,
    gen: u64 = 0,
    jid: Utf8Text(191) = .{},
    msg_id: Utf8Text(191) = .{},
    extra: Utf8Text(63) = .{},
    started_ms: u64 = 0,
    arg_count: usize = 0,
    args: [max_wacli_args]Utf8Text(wacli_arg_cap) = @splat(.{}),
};
const WacliResult = struct {
    kind: WacliJobKind = .slack_send,
    jid: Utf8Text(191) = .{},
    msg_id: Utf8Text(191) = .{},
    extra: Utf8Text(63) = .{},
    ok: bool = false,
    data: []u8 = &.{},
};
const PendingSend = struct {
    jid: Utf8Text(191) = .{},
    text: Utf8Text(4095) = .{},
    file: Utf8Text(519) = .{},
    reply_to: Utf8Text(191) = .{},
    reply_sender: Utf8Text(191) = .{},
    id: [outbox.id_len]u8 = @splat('0'),
    seq: u64 = 0,
    queued_unix: i64 = 0,
    retries: u8 = 0,
    ambiguous: bool = false,
    completed: bool = false,
    not_before_ms: u64 = 0,
};
const SlackOutbox = struct {
    entry: outbox.Entry = .{},
    inflight: bool = false,
    completed: bool = false,
    not_before_ms: u64 = 0,
};
fn WideText(comptime capacity: usize) type {
    return struct {
        buf: [capacity + 1]u16 = @splat(0),
        len: usize = 0,
        fn set(self: *@This(), _: std.mem.Allocator, text: []const u8) void {
            self.len = std.unicode.utf8ToUtf16Le(self.buf[0..capacity], text) catch 0;
            self.buf[self.len] = 0;
        }
        fn slice(self: *const @This()) []const u16 {
            return self.buf[0..self.len];
        }
    };
}
const Message = struct {
    thread_ts: Utf8Text(191) = .{},
    quoted_msg_id: Utf8Text(191) = .{},
    quote: WideText(4095) = .{},
    quote_sender: WideText(159) = .{},
    quote_sender_jid: Utf8Text(191) = .{},
    sender_jid: Utf8Text(191) = .{},
    filename: WideText(259) = .{},
    media_type: Utf8Text(31) = .{},
    local_path: WideText(519) = .{},
    from_me: bool = true,
    send_state: enum { none, pending, failed } = .pending,
    text: WideText(4095) = .{},
    sender: WideText(159) = .{},
    timestamp: Utf8Text(63) = .{},
    id: Utf8Text(191) = .{},
    time: WideText(15) = .{},
};
const NoLock = struct {
    fn lockUncancelable(_: *@This(), _: std.Io) void {}
    fn unlock(_: *@This(), _: std.Io) void {}
    fn broadcast(_: *@This(), _: std.Io) void {}
    fn markAccount(_: *@This(), _: []const u8, _: []const u8, _: []const u8) bool {
        return true;
    }
};
const TelegramClient = struct {
    fn sendTextReply(_: *@This(), _: i64, _: []const u8, _: i64) bool {
        return false;
    }
    fn sendFile(_: *@This(), _: i64, _: []const u8, _: []const u8, _: i64) bool {
        return false;
    }
};
const FailedSend = struct {
    unified: bool = false,
    id: [outbox.id_len]u8 = @splat('0'),
    provider: transport.Provider = .whatsapp,
    account: Utf8Text(32) = .{},
    jid: Utf8Text(191) = .{},
    text: Utf8Text(4095) = .{},
    file: Utf8Text(519) = .{},
    reply_to: Utf8Text(191) = .{},
    reply_sender: Utf8Text(191) = .{},
    queued_unix: i64 = 0,
    ptt: bool = false,
    voice_seconds: u32 = 0,
    ambiguous: bool = false,
};
fn recordVerificationDispatch(_: *App, _: *const WacliJob) void {}

fn captureVerificationCheckpointBefore(_: *App, _: []const u8) void {}

const App = struct {
    dictation_operation: ?struct { origin: chat_key.Stored } = null,
    draft_store: struct {
        fn isOpen(_: *const @This(), _: chat_key.Key) bool {
            return false;
        }
    } = .{},
    allocator: std.mem.Allocator = std.testing.allocator,
    io: std.Io = std.testing.io,
    cache_tag: Utf8Text(32) = .{},
    outbox_path: []const u8 = "outbox.jsonl",
    outbox_load_failed: bool = false,
    unified_write_fault: enum { none, open, write, flush, close, replace } = .none,
    unified_fault_active: bool = false,
    unified_fault_hits: u64 = 0,
    failed_sends: [outbox.max_entries]FailedSend = @splat(.{}),
    failed_send_count: usize = 0,
    pending_sends: [max_pending_sends]PendingSend = @splat(.{}),
    pending_send_count: usize = 0,
    activity_key: chat_key.Stored = .{},
    activity_seconds: i64 = 0,
    chat_refilters: usize = 0,
    slack_outbox: [max_slack_outbox]SlackOutbox = @splat(.{}),
    slack_outbox_count: usize = 0,
    slack_outbox_dirty: bool = false,
    send_seq: u64 = 0,
    send_started_ms: u64 = 0,
    failed_count: usize = 0,
    sent_voice: [voice_sent.max_entries]voice_sent.Entry = @splat(.{}),
    sent_voice_count: usize = 0,
    slack_tokens: ?bool = true,
    slack_account_available: bool = true,
    slack_bridge: ?bool = null,
    wacli_mutex: NoLock = .{},
    wacli_cond: NoLock = .{},
    wacli_thread: ?bool = true,
    wacli_slack_thread: ?bool = true,
    hub_media_thread: ?bool = null,
    hub_send_thread: ?bool = true,
    hub_account: Utf8Text(32) = .{},
    unified_hub: bool = false,
    unified_inflight: ?struct { id: [outbox.id_len]u8, attempt: u64 } = null,
    verification_retry_evidence: bool = false,
    wacli_queue: [wacli_queue_size]WacliJob = @splat(.{}),
    wacli_queue_len: usize = 0,
    wacli_refresh_again: bool = false,
    wacli_pending: [@typeInfo(WacliJobKind).@"enum".fields.len]u32 = @splat(0),
    compose: ?usize = 1,
    thread_compose: ?usize = null,
    thread_parent: Utf8Text(191) = .{},
    thread_origin: chat_key.Stored = .{},
    canvas: ?usize = null,
    hwnd: ?usize = null,
    chat_count: usize = 1,
    selected_chat: usize = 0,
    chats: [1]struct { account: Utf8Text(32) = .{}, jid: Utf8Text(191) = .{}, provider: transport.Provider = .whatsapp } = @splat(.{}),
    reply_to: Utf8Text(191) = .{},
    reply_sender: Utf8Text(191) = .{},
    staged_images: staged_images.List(struct { provider: transport.Provider = .whatsapp, account: Utf8Text(32) = .{}, path: Utf8Text(519) = .{}, jid: Utf8Text(191) = .{} }) = .{},
    slack_attach: WideText(519) = .{},
    slack_attach_jid: Utf8Text(191) = .{},
    slack_attach_account: Utf8Text(32) = .{},
    telegram: ?*TelegramClient = null,
    user_viewed: bool = false,
    scroll_y: i32 = 0,
    compose_client_width: i32 = 0,
    compose_client_height: i32 = 0,
    messages: [3]Message = @splat(.{}),
    message_count: usize = 0,
    displayed_provider: transport.Provider = .whatsapp,
    displayed_account: Utf8Text(32) = .{},
    displayed_jid: Utf8Text(191) = .{},
    slack_log_mutex: NoLock = .{},
    slack_log: NoLock = .{},
    send_child: ?usize = null,
    read_child: ?usize = null,
    archive_child: ?usize = null,
    sync_child: ?usize = null,
};
const media_age = struct {
    fn unixSeconds(_: []const u8) ?i64 {
        return 42;
    }
};
const slack = struct {
    const max_text = 4095;
    fn parseSentTs(_: std.mem.Allocator, _: []const u8) ?[]u8 {
        return null;
    }
};
const win = struct {
    const SYSTEMTIME = struct { wHour: u16 = 0, wMinute: u16 = 0 };
    fn GetLocalTime(_: *SYSTEMTIME) void {}
    const DWORD = u32;
    const LARGE_INTEGER = struct { QuadPart: i64 };
    const INVALID_HANDLE_VALUE: ?usize = 99;
    const GENERIC_WRITE = 1;
    const GENERIC_READ = 2;
    const CREATE_ALWAYS = 3;
    const OPEN_EXISTING = 4;
    const FILE_ATTRIBUTE_NORMAL = 0;
    const FILE_SHARE_READ = 0;
    const MOVEFILE_REPLACE_EXISTING = 1;
    const MOVEFILE_WRITE_THROUGH = 2;
    const ERROR_FILE_NOT_FOUND = 2;
    const TRUE = 1;
    const FALSE = 0;
    fn CreateFileW(_: [*:0]const u16, access: u32, _: u32, _: ?usize, _: u32, _: u32, _: ?usize) ?usize {
        if (io_fault == .open) return INVALID_HANDLE_VALUE;
        if (access == GENERIC_READ) {
            read_position = 0;
            return if (exists) 2 else INVALID_HANDLE_VALUE;
        }
        temp_len = 0;
        return 1;
    }
    fn GetLastError() u32 {
        return if (exists) 5 else ERROR_FILE_NOT_FOUND;
    }
    fn GetFileSizeEx(_: ?usize, size: *LARGE_INTEGER) u32 {
        size.QuadPart = @intCast(disk_len);
        return 1;
    }
    fn WriteFile(_: ?usize, bytes: [*]const u8, len: u32, written: *u32, _: ?usize) u32 {
        if (io_fault == .write) {
            written.* = 0;
            return 0;
        }
        const count = @min(len, 17);
        @memcpy(temp[temp_len..][0..count], bytes[0..count]);
        temp_len += count;
        written.* = count;
        return 1;
    }
    fn ReadFile(_: ?usize, bytes: [*]u8, len: u32, got: *u32, _: ?usize) u32 {
        if (io_fault == .read and read_position > 0) {
            got.* = 0;
            return 0;
        }
        const count = @min(@min(len, 17), disk_len - read_position);
        @memcpy(bytes[0..count], disk[read_position..][0..count]);
        read_position += count;
        got.* = @intCast(count);
        return 1;
    }
    fn FlushFileBuffers(_: ?usize) u32 {
        flushes += 1;
        return if (io_fault == .flush) 0 else 1;
    }
    fn CloseHandle(_: ?usize) u32 {
        closes += 1;
        return 1;
    }
    fn DeleteFileW(_: [*:0]const u16) u32 {
        return 1;
    }
    fn MoveFileExW(_: [*:0]const u16, _: [*:0]const u16, flags: u32) u32 {
        if (io_fault == .rename) return 0;
        try_write_through = flags & MOVEFILE_WRITE_THROUGH != 0;
        @memcpy(disk[0..temp_len], temp[0..temp_len]);
        disk_len = temp_len;
        exists = true;
        return 1;
    }
    fn GetTickCount64() u64 {
        return 1000;
    }
    fn GetWindowTextW(_: usize, dest: []u16, capacity: usize) i32 {
        const len = @min(compose_len, capacity - 1);
        @memcpy(dest[0..len], compose_text[0..len]);
        return @intCast(len);
    }
    fn SetFocus(_: usize) ?usize {
        return null;
    }
    fn SetWindowTextW(_: usize, _: [*:0]const u16) u32 {
        compose_len = 0;
        return 1;
    }
    fn InvalidateRect(_: usize, _: ?usize, _: u32) u32 {
        return 1;
    }
};
var io_fault: enum { none, open, write, flush, rename, read } = .none;
var disk: [outbox.max_entries * outbox.max_line_len]u8 = undefined;
var temp: [outbox.max_entries * outbox.max_line_len]u8 = undefined;
var disk_len: usize = 0;
var temp_len: usize = 0;
var exists = false;
var read_position: usize = 0;
var flushes: usize = 0;
var closes: usize = 0;
var try_write_through = false;
var deleted: usize = 0;
var spawned: usize = 0;
var pumped: usize = 0;
var refreshed: usize = 0;
var compose_text: [4096]u16 = @splat(0);
var compose_len: usize = 0;
fn reset() void {
    io_fault = .none;
    disk_len = 0;
    temp_len = 0;
    exists = false;
    flushes = 0;
    closes = 0;
    deleted = 0;
    spawned = 0;
    pumped = 0;
    try_write_through = false;
    compose_len = 0;
    refreshed = 0;
}
fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
fn setStatus(_: *App, _: []const u8) void {}
fn rememberFailedSend(a: *App, _: *const PendingSend) void {
    a.failed_count += 1;
}
fn restoreFailedSendText(_: *App, _: *const PendingSend) void {}
fn cancelSlackMark(_: *App) void {}
fn logSlackFailure(_: *App, _: WacliJobKind, _: []const u8, _: u32) void {}
fn unarchiveSentChat(_: *App, _: []const u8) void {}
fn persistFileOutbox(_: *App) void {}
fn selectedChatIsSlack(a: *App) bool {
    return a.chats[0].provider == .slack;
}
fn selectedChatIsTelegram(a: *App) bool {
    return a.chats[0].provider == .telegram;
}
fn slackAccountConfigured(a: *App, _: []const u8) bool {
    return a.slack_account_available;
}
fn slackAccountIsBridge(a: *App, _: []const u8) bool {
    return a.slack_bridge != null;
}
fn slackConfigured(a: *App) bool {
    return a.slack_tokens != null or a.slack_bridge != null;
}
fn tgSelectedChatIsGroup(_: *App) bool {
    return false;
}
fn tgSelectedChatId(_: *App) ?i64 {
    return 1;
}
fn invalidateCanvasIconTooltips(_: *App) void {}
fn clearReply(a: *App) void {
    a.reply_to = .{};
    a.reply_sender = .{};
}
fn saveComposerDraft(_: *App) void {}
fn focusCompose(_: *App) void {}
fn layout(_: *App, _: i32, _: i32) void {}
fn releaseStagedImage(a: *App) void {
    a.staged_images.clear();
}
fn discardStagedImage(a: *App) void {
    releaseStagedImage(a);
}
fn removeStagedImage(a: *App, index: usize, _: bool) void {
    _ = a.staged_images.remove(index);
}
fn forgetFailedSend(_: *App, _: chat_key.Key, _: []const u8) void {}
fn noteChatActivity(a: *App, key: chat_key.Key, seconds: i64) void {
    a.activity_key.set(key);
    a.activity_seconds = seconds;
}
fn refilterChats(a: *App) void {
    a.chat_refilters += 1;
}
fn nowUnixSeconds() i64 {
    return 42;
}
fn mintSendId(_: *App, id: *[outbox.id_len]u8) void {
    std.testing.io.random(id);
    id.* = outbox.hexId(id[0..16].*);
}
fn appendSlackPending(_: *App, _: []const u8, _: []const u8, _: []const u8) void {}
fn wacliPumpSync(_: *App) void {
    pumped += 1;
}
fn deleteFileUtf8(_: []const u8) void {
    deleted += 1;
}
fn oldestPendingSend(a: *App) ?usize {
    for (a.messages[0..a.message_count], 0..) |*message, index| if (message.send_state == .pending) {
        return index;
    };
    return null;
}
fn removeMessageAt(_: *App, _: usize) void {}
fn formatSlackTime(_: *WideText(15), _: std.mem.Allocator, _: []const u8) void {}
fn unifiedHub(a: *const App) bool {
    return a.unified_hub;
}

fn finishDictation(_: *App) void {}

fn sendUnifiedMessage(_: *App, _: bool) bool {
    @panic("unified admission belongs to the unified harness");
}
fn beginUnifiedSend(_: *App, _: u64) void {
    @panic("unified dispatch belongs to the unified harness");
}
fn finishUnifiedSend(_: *App, _: *const WacliResult) void {
    @panic("unified outcomes belong to the unified harness");
}

fn hubConfigured(_: *const App) bool {
    return false;
}

fn hubJobReady(_: *const App, _: WacliJob) bool {
    return true;
}

fn mediaBusy(_: *App) bool {
    return false;
}
fn avatarBusy(_: *App) bool {
    return false;
}
fn appendLaunchLog(_: *App, _: []const u8) void {}
fn drainMediaDownloads(_: *App) void {}
fn startSync(_: *App) void {}
fn refreshChats(_: *App) void {}
fn refreshMessages(_: *App) void {
    refreshed += 1;
}
fn refreshGroups(_: *App) void {}
fn refreshSlackWorkspace(_: *App) void {}
fn enqueueCacheTagProbe(_: *App) void {}
fn fixture() App {
    var app = App{};
    app.cache_tag.set("aaaaaaaaaaaaaaaa");
    app.chats[0].account = app.cache_tag;
    app.displayed_account = app.cache_tag;
    return app;
}
fn sampleEntry(number: u8) outbox.Entry {
    var value = outbox.Entry{};
    value.id = outbox.hexId(@splat(number));
    value.jid.set("synthetic-chat");
    value.text.set("synthetic text");
    value.client_msg_id.set(if (number == 1) "client-one" else "client-two");
    return value;
}
fn setCompose(text: []const u8) void {
    compose_len = std.unicode.utf8ToUtf16Le(&compose_text, text) catch unreachable;
}

test "failed atomic journal stages do not acknowledge persistence" {
    for ([_]@TypeOf(io_fault){ .open, .write, .flush, .rename }) |failure| {
        reset();
        var app = fixture();
        app.slack_outbox_count = 1;
        app.slack_outbox[0].entry = sampleEntry(1);
        try std.testing.expect(persistOutbox(&app));
        const old_len = disk_len;
        const old_hash = std.hash.Wyhash.hash(0, disk[0..disk_len]);
        app.slack_outbox[0].entry.text.set("replacement");
        io_fault = failure;
        try std.testing.expect(!persistOutbox(&app));
        try std.testing.expectEqual(old_len, disk_len);
        try std.testing.expectEqual(old_hash, std.hash.Wyhash.hash(0, disk[0..disk_len]));
    }
    reset();
    var app = fixture();
    try std.testing.expect(persistOutbox(&app));
    try std.testing.expect(flushes > 0 and try_write_through);
}

test "failed journal admission preserves composer reply and staged image" {
    reset();
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    app.reply_to.set("synthetic-reply");
    setCompose("draft");
    io_fault = .rename;
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 0), app.pending_send_count);
    try std.testing.expect(compose_len > 0 and app.reply_to.len > 0);
    app.staged_images.count = 1;
    app.staged_images.items[0].path.set("synthetic.png");
    app.staged_images.items[0].jid = app.chats[0].jid;
    app.staged_images.items[0].provider = app.chats[0].provider;
    app.staged_images.items[0].account = app.chats[0].account;
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 0), app.pending_send_count);
    try std.testing.expect(app.staged_images.items[0].path.len > 0 and app.reply_to.len > 0);
    app.chats[0].provider = .slack;
    app.chats[0].account.set("");
    app.staged_images.items[0].provider = .slack;
    app.staged_images.items[0].account.set("");
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 0), app.slack_outbox_count);
    try std.testing.expect(app.staged_images.items[0].path.len > 0 and compose_len > 0);
}

test "completed file stays alive until journal retirement succeeds" {
    reset();
    var app = fixture();
    app.pending_send_count = 1;
    app.pending_sends[0].file.set("synthetic.png");
    try std.testing.expect(persistOutbox(&app));
    io_fault = .rename;
    removeFirstPendingSend(&app, true);
    try std.testing.expectEqual(@as(usize, 1), app.pending_send_count);
    try std.testing.expect(app.pending_sends[0].completed);
    try std.testing.expectEqual(@as(usize, 0), deleted);
    startNextSend(&app);
    try std.testing.expectEqual(@as(usize, 0), spawned);
    io_fault = .none;
    startNextSend(&app);
    try std.testing.expectEqual(@as(usize, 0), app.pending_send_count);
    try std.testing.expectEqual(@as(usize, 0), deleted);
    try std.testing.expectEqual(@as(usize, 1), app.sent_voice_count);
    try std.testing.expectEqual(@as(usize, 0), disk_len);
}

test "restored WhatsApp sends have unique bubble sequences" {
    reset();
    var app = fixture();
    app.slack_outbox_count = 2;
    app.slack_outbox[0].entry = sampleEntry(1);
    app.slack_outbox[1].entry = sampleEntry(2);
    try std.testing.expect(persistOutbox(&app));
    var restored = fixture();
    loadOutbox(&restored);
    try std.testing.expect(!restored.outbox_load_failed);
    try std.testing.expectEqual(@as(usize, 2), restored.pending_send_count);
    try std.testing.expect(restored.pending_sends[0].seq > 0);
    try std.testing.expect(restored.pending_sends[1].seq > restored.pending_sends[0].seq);
    startNextSend(&restored);
    try std.testing.expectEqual(@as(usize, 2), restored.pending_send_count);
    try std.testing.expectEqual(@as(usize, 1), spawned);
}

test "restored WhatsApp send already delivered in the chat is not resent" {
    reset();
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    app.pending_send_count = 1;
    app.pending_sends[0].id = sampleEntry(1).id;
    app.pending_sends[0].jid = app.chats[0].jid;
    app.pending_sends[0].text.set("synthetic text");
    app.pending_sends[0].queued_unix = 42;
    try std.testing.expect(persistOutbox(&app));
    var restored = fixture();
    restored.chats = app.chats;
    loadOutbox(&restored);
    try std.testing.expect(!restored.outbox_load_failed);
    try std.testing.expectEqual(@as(usize, 1), restored.pending_send_count);
    try std.testing.expect(restored.pending_sends[0].from_disk);
    try std.testing.expectEqual(@as(u8, 0), restored.pending_sends[0].retries);
    try std.testing.expect(!restored.pending_sends[0].ambiguous);
    restored.message_count = 1;
    restored.messages[0].send_state = .none;
    restored.messages[0].text.set(restored.allocator, "synthetic text");
    restored.messages[0].timestamp.set("1970-01-01T00:00:42Z");
    restored.displayed_jid = restored.chats[0].jid;
    startNextSend(&restored);
    try std.testing.expectEqual(@as(usize, 0), spawned);
    try std.testing.expectEqual(@as(usize, 0), restored.pending_send_count);
    try std.testing.expectEqual(@as(usize, 0), disk_len);
}

test "fresh WhatsApp send is not suppressed by matching delivered text" {
    reset();
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    app.displayed_jid = app.chats[0].jid;
    app.message_count = 1;
    app.messages[0].send_state = .none;
    app.messages[0].text.set(app.allocator, "synthetic text");
    app.messages[0].timestamp.set("1970-01-01T00:00:42Z");
    setCompose("synthetic text");
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 1), app.pending_send_count);
    try std.testing.expect(!app.pending_sends[0].from_disk);
    try std.testing.expectEqual(@as(i64, 42), app.activity_seconds);
    try std.testing.expect(chat_key.Key.eql(chat_key.of(&app.chats[0]), app.activity_key.key()));
    try std.testing.expectEqual(@as(usize, 1), app.chat_refilters);
    try std.testing.expectEqual(@as(usize, 1), spawned);
}

test "partial journal read fails closed and cannot overwrite disk" {
    reset();
    var app = fixture();
    app.slack_outbox_count = 1;
    app.slack_outbox[0].entry = sampleEntry(1);
    try std.testing.expect(persistOutbox(&app));
    const saved_len = disk_len;
    io_fault = .read;
    var restored = fixture();
    loadOutbox(&restored);
    try std.testing.expect(restored.outbox_load_failed);
    io_fault = .none;
    try std.testing.expect(!persistOutbox(&restored));
    try std.testing.expectEqual(saved_len, disk_len);
    startNextSend(&restored);
    try std.testing.expectEqual(@as(usize, 0), spawned);
}

test "disconnected Slack outbox waits without losing entries" {
    reset();
    var app = fixture();
    app.slack_tokens = null;
    app.slack_outbox_count = 1;
    app.slack_outbox[0].entry = sampleEntry(1);
    retrySlackOutbox(&app);
    try std.testing.expectEqual(@as(usize, 0), app.wacli_queue_len);
    try std.testing.expect(!app.slack_outbox[0].inflight);
    app.slack_tokens = true;
    retrySlackOutbox(&app);
    try std.testing.expectEqual(@as(usize, 1), app.wacli_queue_len);
    try std.testing.expectEqualStrings(app.slack_outbox[0].entry.idSlice(), app.wacli_queue[0].msg_id.slice());
}

test "refused write cannot be overtaken and full queue preserves writes" {
    reset();
    var app = fixture();
    app.slack_outbox_count = 2;
    app.slack_outbox[0].entry = sampleEntry(1);
    app.slack_outbox[1].entry = sampleEntry(2);
    app.wacli_queue_len = app.wacli_queue.len;
    for (&app.wacli_queue) |*job| job.kind = .slack_send;
    app.wacli_pending[@intFromEnum(WacliJobKind.slack_send)] = @intCast(app.wacli_queue_len);
    enqueueSlackOutbox(&app, &app.slack_outbox[0]);
    try std.testing.expectEqual(app.wacli_queue.len, app.wacli_queue_len);
    try std.testing.expect(!app.slack_outbox[0].inflight);
    try std.testing.expect(!wacliEnqueue(&app, .{ .kind = .chats }, false));
    _ = wacliTakeJob(&app, .slack);
    enqueueSlackOutbox(&app, &app.slack_outbox[1]);
    try std.testing.expect(!app.slack_outbox[1].inflight);
    app.slack_outbox[0].not_before_ms = 0;
    retrySlackOutbox(&app);
    try std.testing.expect(app.slack_outbox[0].inflight and !app.slack_outbox[1].inflight);
}

test "Slack results retire exact ids even after echo and out-of-order admission" {
    reset();
    var app = fixture();
    app.slack_outbox_count = 2;
    app.slack_outbox[0].entry = sampleEntry(1);
    app.slack_outbox[1].entry = sampleEntry(2);
    const second_id = app.slack_outbox[1].entry.id;
    retireSlackOutbox(&app, &second_id);
    try std.testing.expectEqual(@as(usize, 1), app.slack_outbox_count);
    try std.testing.expectEqualStrings("client-one", app.slack_outbox[0].entry.client_msg_id.slice());
    retireSlackOutbox(&app, &second_id);
    try std.testing.expectEqual(@as(usize, 1), app.slack_outbox_count);
    io_fault = .rename;
    const first_id = app.slack_outbox[0].entry.id;
    retireSlackOutbox(&app, &first_id);
    retrySlackOutbox(&app);
    try std.testing.expect(app.slack_outbox[0].completed);
    try std.testing.expectEqual(@as(usize, 0), app.wacli_queue_len);
    io_fault = .none;
    retrySlackOutbox(&app);
    try std.testing.expectEqual(@as(usize, 0), app.slack_outbox_count);
}

test "failed Slack result never fails a later bubble consumed by a prior echo" {
    reset();
    var app = fixture();
    app.slack_outbox_count = 2;
    app.slack_outbox[0].entry = sampleEntry(1);
    app.slack_outbox[1].entry = sampleEntry(2);
    app.displayed_jid.set("synthetic-chat");
    app.message_count = 1;
    app.messages[0].timestamp.set("client-two");
    app.messages[0].text.set(app.allocator, "later draft");
    var result = WacliResult{ .account = app.displayed_account };
    result.jid.set("synthetic-chat");
    result.extra.set("HttpFailed");
    result.msg_id.set(app.slack_outbox[0].entry.idSlice());
    resolveSlackSend(&app, &result);
    try std.testing.expectEqual(@TypeOf(app.messages[0].send_state).pending, app.messages[0].send_state);
    result.msg_id.set(app.slack_outbox[1].entry.idSlice());
    resolveSlackSend(&app, &result);
    try std.testing.expectEqual(@TypeOf(app.messages[0].send_state).failed, app.messages[0].send_state);
}

test "staged files reach wacli only for WhatsApp" {
    try std.testing.expect(stagedFileGoesToWacli(.whatsapp));
    try std.testing.expect(!stagedFileGoesToWacli(.slack));
    try std.testing.expect(!stagedFileGoesToWacli(.telegram));
}

test "Slack pasted image reaches Slack journal and preserves borrowed path" {
    reset();
    var app = fixture();
    app.chats[0].provider = .slack;
    app.chats[0].account.set("");
    app.staged_images.items[0].provider = .slack;
    app.staged_images.items[0].account.set("");
    app.chats[0].jid.set("synthetic-chat");
    app.staged_images.items[0].jid = app.chats[0].jid;
    app.staged_images.items[0].provider = app.chats[0].provider;
    app.staged_images.items[0].account = app.chats[0].account;
    app.staged_images.count = 1;
    app.staged_images.items[0].path.set("synthetic.png");
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 0), app.pending_send_count);
    try std.testing.expectEqual(@as(usize, 1), app.slack_outbox_count);
    try std.testing.expectEqualStrings("synthetic.png", app.slack_outbox[0].entry.file.slice());
    try std.testing.expectEqualStrings("synthetic.png", app.wacli_queue[0].args[2].slice());
    try std.testing.expectEqual(outbox.Provider.slack, app.slack_outbox[0].entry.provider);
}

test "multibyte composer text is refused rather than journaled as invalid UTF8" {
    reset();
    var app = fixture();
    app.chats[0].provider = .slack;
    app.chats[0].account.set("");
    app.staged_images.items[0].provider = .slack;
    app.staged_images.items[0].account.set("");
    compose_len = 3000;
    @memset(compose_text[0..compose_len], 0x00fc);
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 0), app.slack_outbox_count);
    try std.testing.expectEqual(@as(usize, 3000), compose_len);
}

test "Slack text is not truncated to the old 512-byte job capacity" {
    reset();
    var app = fixture();
    app.chats[0].provider = .slack;
    app.chats[0].account.set("");
    app.staged_images.items[0].provider = .slack;
    app.staged_images.items[0].account.set("");
    app.chats[0].jid.set("synthetic-chat");
    const text = [_]u8{'a'} ** 1024;
    setCompose(&text);
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 1), app.slack_outbox_count);
    try std.testing.expectEqualStrings(&text, app.wacli_queue[0].args[1].slice());
    try std.testing.expectEqualStrings(app.slack_outbox[0].entry.text.slice(), app.wacli_queue[0].args[1].slice());
}

test "chat read refused by writes retries after the queue drains" {
    reset();
    var app = fixture();
    app.wacli_queue_len = app.wacli_queue.len;
    for (&app.wacli_queue) |*job| job.kind = .slack_send;
    try std.testing.expect(!wacliEnqueue(&app, .{ .kind = .messages }, true));
    try std.testing.expect(app.wacli_refresh_again);
    retryWacliRefreshes(&app);
    try std.testing.expectEqual(@as(usize, 0), refreshed);
    while (wacliTakeJob(&app, .slack) != null) {}
    retryWacliRefreshes(&app);
    try std.testing.expectEqual(@as(usize, 1), refreshed);
    try std.testing.expect(!app.wacli_refresh_again);
}

test "restored pending bubble is not hidden by a matching old text" {
    reset();
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    app.message_count = 1;
    app.messages[0].send_state = .none;
    app.messages[0].text.set(app.allocator, "synthetic text");
    var pending = PendingSend{ .account = app.chats[0].account };
    pending.from_disk = true;
    pending.jid = app.chats[0].jid;
    pending.text.set("synthetic text");
    pending.queued_unix = 42;
    appendWhatsAppPending(&app, &pending, true);
    try std.testing.expectEqual(@as(usize, 2), app.message_count);
    try std.testing.expectEqual(@TypeOf(app.messages[1].send_state).pending, app.messages[1].send_state);
}

test "restored voice notes retain their transport flag duration and local player" {
    reset();
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    app.pending_send_count = 1;
    const pending = &app.pending_sends[0];
    pending.id = sampleEntry(1).id;
    pending.jid = app.chats[0].jid;
    pending.file.set("synthetic.ogg");
    pending.ptt = true;
    pending.voice_seconds = 42;
    pending.reply_to.set("synthetic-reply");
    try std.testing.expect(persistOutbox(&app));
    var restored = fixture();
    restored.chats = app.chats;
    loadOutbox(&restored);
    try std.testing.expectEqual(@as(usize, 1), restored.pending_send_count);
    const head = &restored.pending_sends[0];
    try std.testing.expect(head.ptt);
    try std.testing.expectEqual(@as(u32, 42), head.voice_seconds);
    try std.testing.expectEqualStrings("synthetic-reply", head.reply_to.slice());
    appendWhatsAppPending(&restored, head, true);
    try std.testing.expectEqualStrings("audio", restored.messages[0].media_type.slice());
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("synthetic.ogg"), restored.messages[0].local_path.slice());
}

test "failed file retirement keeps its source without unarchiving or caching delivery" {
    reset();
    var app = fixture();
    app.pending_send_count = 1;
    app.pending_sends[0].file.set("synthetic.png");
    try std.testing.expect(persistOutbox(&app));
    removeFirstPendingSend(&app, false);
    try std.testing.expectEqual(@as(usize, 0), app.pending_send_count);
    try std.testing.expectEqual(@as(usize, 0), app.sent_voice_count);
    try std.testing.expectEqual(@as(usize, 0), deleted);
    try std.testing.expectEqual(@as(usize, 0), disk_len);
}

test "queued reactions are retained when the shared queue is full" {
    reset();
    var app = fixture();
    for (0..app.wacli_queue.len) |_| {
        try std.testing.expect(wacliEnqueue(&app, .{ .kind = .reaction }, true));
    }
    try std.testing.expect(!wacliEnqueue(&app, .{ .kind = .slack_send }, true));
    try std.testing.expectEqual(app.wacli_queue.len, app.wacli_queue_len);
    for (app.wacli_queue) |job| try std.testing.expectEqual(WacliJobKind.reaction, job.kind);
}

test "legacy outbox migration retains every send with immediate or delayed account discovery" {
    const legacy = "{\"id\":\"01010101010101010101010101010101\",\"provider\":\"whatsapp\",\"jid\":\"synthetic-chat\",\"text\":\"synthetic text\",\"file\":\"synthetic.ogg\",\"reply_to\":\"quoted-id\",\"reply_sender\":\"sender\",\"client_msg_id\":\"\",\"attempts\":0,\"upload_file_id\":\"\",\"state\":\"queued\",\"queued_unix\":42,\"ptt\":true,\"voice_seconds\":7}\n";
    for ([_]bool{ false, true }) |delayed| {
        reset();
        var writer = std.Io.Writer.fixed(&disk);
        try writer.writeAll(legacy);
        var other = outbox.Entry{};
        other.id = sampleEntry(2).id;
        other.jid.set("synthetic-chat");
        other.text.set("synthetic text");
        other.account.set("bbbbbbbbbbbbbbbb");
        try outbox.writeLine(&writer, &other);
        var slack_entry = sampleEntry(3);
        slack_entry.provider = .slack;
        try outbox.writeLine(&writer, &slack_entry);
        disk_len = writer.end;
        exists = true;
        const old_hash = std.hash.Wyhash.hash(0, disk[0..disk_len]);
        var app = fixture();
        if (delayed) app.cache_tag.set("");
        loadOutbox(&app);
        try std.testing.expect(!app.outbox_load_failed);
        try std.testing.expectEqual(@as(usize, 2), app.pending_send_count);
        try std.testing.expectEqual(@as(usize, 1), app.slack_outbox_count);
        try std.testing.expectEqualStrings("bbbbbbbbbbbbbbbb", app.pending_sends[1].account.slice());
        if (delayed) {
            try std.testing.expectEqualStrings("", app.pending_sends[0].account.slice());
            try std.testing.expectEqual(old_hash, std.hash.Wyhash.hash(0, disk[0..disk_len]));
            startNextSend(&app);
            try std.testing.expectEqual(@as(usize, 0), spawned);
            app.cache_tag.set("aaaaaaaaaaaaaaaa");
            io_fault = .rename;
            bindOutboxAccount(&app);
            try std.testing.expect(app.slack_outbox_dirty);
            try std.testing.expectEqual(old_hash, std.hash.Wyhash.hash(0, disk[0..disk_len]));
            startNextSend(&app);
            try std.testing.expectEqual(@as(usize, 0), spawned);
            io_fault = .none;
            bindOutboxAccount(&app);
        }
        try std.testing.expect(!app.slack_outbox_dirty);
        var expected = outbox.Entry{};
        try std.testing.expect(outbox.parseLine(std.testing.allocator, legacy, &expected));
        expected.account.set("aaaaaaaaaaaaaaaa");
        var scanner = outbox.Scanner.init(std.testing.allocator, disk[0..disk_len]);
        try std.testing.expectEqualDeep(expected, scanner.next().?.*);
        try std.testing.expectEqualDeep(other, scanner.next().?.*);
        try std.testing.expectEqualDeep(slack_entry, scanner.next().?.*);
        try std.testing.expect(scanner.next() == null);
        const writes = flushes;
        bindOutboxAccount(&app);
        try std.testing.expectEqual(writes, flushes);
        var restarted = fixture();
        loadOutbox(&restarted);
        try std.testing.expectEqual(@as(usize, 2), restarted.pending_send_count);
        try std.testing.expectEqual(@as(usize, 1), restarted.slack_outbox_count);
        try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaa", restarted.pending_sends[0].account.slice());
        try std.testing.expectEqualStrings("bbbbbbbbbbbbbbbb", restarted.pending_sends[1].account.slice());
        try std.testing.expectEqualStrings("synthetic.ogg", restarted.pending_sends[0].file.slice());
        try std.testing.expectEqualStrings("quoted-id", restarted.pending_sends[0].reply_to.slice());
        try std.testing.expect(restarted.pending_sends[0].ptt);
        try std.testing.expectEqual(@as(u32, 7), restarted.pending_sends[0].voice_seconds);
    }
}

test "queued send for another account waits and cannot dedup against the shared contact" {
    reset();
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    app.pending_send_count = 1;
    const pending = &app.pending_sends[0];
    pending.id = sampleEntry(1).id;
    pending.account.set("bbbbbbbbbbbbbbbb");
    pending.jid = app.chats[0].jid;
    pending.text.set("synthetic text");
    pending.from_disk = true;
    pending.queued_unix = 42;
    app.displayed_jid = app.chats[0].jid;
    app.message_count = 1;
    app.messages[0].send_state = .none;
    app.messages[0].text.set(app.allocator, "synthetic text");
    try std.testing.expect(persistOutbox(&app));
    try std.testing.expect(!sentMessageExists(&app, chat_key.of(pending), pending.text.slice(), 42));
    startNextSend(&app);
    try std.testing.expectEqual(@as(usize, 0), spawned);
    try std.testing.expectEqual(@as(usize, 1), app.pending_send_count);
    app.cache_tag.set("bbbbbbbbbbbbbbbb");
    startNextSend(&app);
    try std.testing.expectEqual(@as(usize, 1), spawned);
    try std.testing.expectEqual(@as(usize, 1), app.pending_send_count);
    appendWhatsAppPending(&app, pending, true);
    try std.testing.expectEqual(@as(usize, 1), app.message_count);
    app.chats[0].account = app.cache_tag;
    appendWhatsAppPending(&app, pending, true);
    try std.testing.expectEqual(@as(usize, 2), app.message_count);
}

test "removing one Slack workspace pauses only its durable sends" {
    reset();
    var app = fixture();
    app.slack_outbox_count = 1;
    app.slack_outbox[0].entry = sampleEntry(1);
    app.slack_outbox[0].entry.account.set("T0000000001");
    app.slack_account_available = false;
    retrySlackOutbox(&app);
    try std.testing.expectEqual(@as(usize, 0), app.wacli_queue_len);
    try std.testing.expect(!app.slack_outbox[0].inflight);
    app.slack_account_available = true;
    retrySlackOutbox(&app);
    try std.testing.expectEqual(@as(usize, 1), app.wacli_queue_len);
    try std.testing.expectEqualStrings("T0000000001", app.wacli_queue[0].account.slice());
}

test "Slack jobs never fall back to UI-thread networking when the worker is unavailable" {
    var app = fixture();
    app.wacli_slack_thread = null;
    try std.testing.expect(!wacliEnqueue(&app, .{ .kind = .slack_auth, .provider = .slack }, false));
    try std.testing.expectEqual(@as(usize, 0), app.wacli_queue_len);
}

test "staged batch journal failure retains all images and caption" {
    reset();
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    for ([_][]const u8{ "first.png", "second.png" }) |path| {
        var image = app.staged_images.items[0];
        image.jid = app.chats[0].jid;
        image.account = app.chats[0].account;
        image.path.set(path);
        try std.testing.expect(app.staged_images.add(image));
    }
    setCompose("caption");
    io_fault = .rename;
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 0), app.pending_send_count);
    try std.testing.expectEqual(@as(usize, 2), app.staged_images.count);
    try std.testing.expectEqual(@as(usize, 7), compose_len);
    try std.testing.expectEqual(@as(usize, 0), spawned);
    try std.testing.expectEqualStrings("second.png", app.staged_images.items[1].path.slice());
}

test "staged batch queue saturation never admits a partial message" {
    reset();
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    for ([_][]const u8{ "first.png", "second.png" }) |path| {
        var image = app.staged_images.items[0];
        image.jid = app.chats[0].jid;
        image.account = app.chats[0].account;
        image.path.set(path);
        try std.testing.expect(app.staged_images.add(image));
    }
    app.pending_send_count = max_pending_sends - 1;
    setCompose("caption");
    sendMessage(&app);
    try std.testing.expectEqual(max_pending_sends - 1, app.pending_send_count);
    try std.testing.expectEqual(@as(usize, 2), app.staged_images.count);
    try std.testing.expectEqual(@as(usize, 7), compose_len);
    try std.testing.expectEqual(@as(usize, 0), spawned);
}

test "staged direct Slack sends each image through its own journal entry" {
    reset();
    var app = fixture();
    app.chats[0].provider = .slack;
    app.chats[0].account.set("");
    app.chats[0].jid.set("synthetic-chat");
    for ([_][]const u8{ "first.png", "second.png" }) |path| {
        var image = app.staged_images.items[0];
        image.provider = .slack;
        image.account = app.chats[0].account;
        image.jid = app.chats[0].jid;
        image.path.set(path);
        try std.testing.expect(app.staged_images.add(image));
    }
    setCompose("caption");
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 0), app.pending_send_count);
    try std.testing.expectEqual(@as(usize, 2), app.slack_outbox_count);
    try std.testing.expectEqual(@as(usize, 0), app.staged_images.count);
    try std.testing.expectEqualStrings("first.png", app.slack_outbox[0].entry.file.slice());
    try std.testing.expectEqualStrings("second.png", app.slack_outbox[1].entry.file.slice());
    try std.testing.expectEqualStrings("caption", app.slack_outbox[0].entry.text.slice());
    try std.testing.expectEqualStrings("", app.slack_outbox[1].entry.text.slice());
    try std.testing.expect(!std.mem.eql(u8, &app.slack_outbox[0].entry.id, &app.slack_outbox[1].entry.id));
    var restored = fixture();
    loadOutbox(&restored);
    try std.testing.expectEqual(@as(usize, 2), restored.slack_outbox_count);
    for (app.slack_outbox[0..2], restored.slack_outbox[0..2]) |before, after| {
        try std.testing.expectEqualSlices(u8, &before.entry.id, &after.entry.id);
        try std.testing.expectEqualStrings(before.entry.file.slice(), after.entry.file.slice());
        try std.testing.expectEqualStrings(before.entry.text.slice(), after.entry.text.slice());
    }
}

test "verification fixture refuses provider queues and sends without losing a draft" {
    reset();
    verification_fixture = true;
    defer verification_fixture = false;
    var app = fixture();
    setCompose("Verification draft");
    sendMessage(&app);
    try std.testing.expectEqual(@as(usize, 0), app.pending_send_count);
    try std.testing.expectEqual(@as(usize, 0), app.slack_outbox_count);
    try std.testing.expect(compose_len > 0);
    try std.testing.expect(!wacliEnqueue(&app, .{ .kind = .messages }, true));
    try std.testing.expectEqual(@as(usize, 0), app.wacli_queue_len);
}

test "reply previews keep first-line text and label media originals" {
    var app = fixture();
    var original = Message{};
    original.text.set(app.allocator, "First line\nHidden second line");
    var snippet = replySnippet(&app, &original);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("First line"), snippet.slice());
    original.text = .{};
    original.media_type.set("image");
    snippet = replySnippet(&app, &original);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("Photo"), snippet.slice());
    original.media_type.set("audio");
    snippet = replySnippet(&app, &original);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("Voice message"), snippet.slice());
    original.media_type.set("document");
    original.filename.set(app.allocator, "report.pdf");
    snippet = replySnippet(&app, &original);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("File: report.pdf"), snippet.slice());
}

test "pending replies retain original id sender and snippet without overwriting server quotes" {
    var app = fixture();
    app.chats[0].jid.set("synthetic-chat");
    app.message_count = 1;
    app.messages[0].id.set("original");
    app.messages[0].sender.set(app.allocator, "Synthetic Sender");
    app.messages[0].sender_jid.set("synthetic-sender");
    app.messages[0].text.set(app.allocator, "First line\nSecond line");
    var pending = PendingSend{ .account = app.chats[0].account };
    pending.jid = app.chats[0].jid;
    pending.reply_to.set("original");
    pending.text.set("Answer");
    appendWhatsAppPending(&app, &pending, false);
    const reply = &app.messages[1];
    try std.testing.expectEqualStrings("original", reply.quoted_msg_id.slice());
    try std.testing.expectEqualStrings("synthetic-sender", reply.quote_sender_jid.slice());
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("First line"), reply.quote.slice());
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("Synthetic Sender"), reply.quote_sender.slice());
    reply.quote.set(app.allocator, "Server-provided excerpt");
    setReplyQuote(&app, reply, "original");
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("Server-provided excerpt"), reply.quote.slice());
}

test "IGSH-1213 queued group text is visibly sending before any confirmation" {
    reset();
    var a = fixture();
    a.chats[0].jid.set("personal:fixture-group@g.us");
    var pending = PendingSend{ .account = a.cache_tag, .seq = 1 };
    pending.jid = a.chats[0].jid;
    pending.text.set("Synthetic group message");
    appendWhatsAppPending(&a, &pending, false);
    try std.testing.expectEqual(@as(usize, 1), a.message_count);
    try std.testing.expectEqual(.pending, a.messages[0].send_state);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("Synthetic group message (sending)"), a.messages[0].text.slice());
}

test "intermediate unified outbox refuses send jobs" {
    var app = App{};
    app.unified_hub = true;
    const before = app.wacli_queue_len;
    try std.testing.expect(!wacliEnqueue(&app, .{ .kind = .hub_send }, true));
    try std.testing.expectEqual(before, app.wacli_queue_len);
}

test "unified sends use independent lane and retain immutable job identity" {
    reset();
    var app = fixture();
    app.unified_hub = true;
    const id = [_]u8{'a'} ** outbox.id_len;
    app.unified_inflight = .{ .id = id, .attempt = 7 };
    var read = WacliJob{ .kind = .messages };
    read.jid.set("chat-before");
    try std.testing.expect(wacliEnqueue(&app, read, false));
    var send = WacliJob{ .kind = .hub_send, .provider = .slack, .gen = 7 };
    send.account.set("workspace-a");
    send.jid.set("chat-before");
    send.msg_id.set(&id);
    send.unified_filename.set("picture.png");
    send.unified_file_sha256 = @splat(42);
    send.unified_file_bytes = 123;
    try std.testing.expect(wacliEnqueue(&app, send, true));
    const reader = wacliTakeJob(&app, .wacli).?;
    try std.testing.expectEqual(WacliJobKind.messages, reader.kind);
    const outgoing = wacliTakeJob(&app, .hub_send).?;
    try std.testing.expectEqual(WacliJobKind.hub_send, outgoing.kind);
    try std.testing.expectEqual(transport.Provider.slack, outgoing.provider);
    try std.testing.expectEqualStrings("workspace-a", outgoing.account.slice());
    try std.testing.expectEqualStrings("chat-before", outgoing.jid.slice());
    try std.testing.expectEqualStrings(&id, outgoing.msg_id.slice());
    try std.testing.expectEqual(@as(u64, 7), outgoing.gen);
    try std.testing.expectEqualStrings("picture.png", outgoing.unified_filename.slice());
    try std.testing.expectEqual(@as(u64, 123), outgoing.unified_file_bytes);
    try std.testing.expectEqualSlices(u8, &([_]u8{42} ** 32), &outgoing.unified_file_sha256);
    try std.testing.expect(wacliTakeJob(&app, .hub_send) == null);
}

test "missing unified sender rejects without synchronous pumping" {
    reset();
    var app = fixture();
    app.unified_hub = true;
    app.hub_send_thread = null;
    app.wacli_thread = null;
    const id = [_]u8{'b'} ** outbox.id_len;
    app.unified_inflight = .{ .id = id, .attempt = 1 };
    var job = WacliJob{ .kind = .hub_send, .gen = 1 };
    job.msg_id.set(&id);
    try std.testing.expect(!wacliEnqueue(&app, job, true));
    try std.testing.expectEqual(@as(usize, 0), app.wacli_queue_len);
    try std.testing.expectEqual(@as(u32, 0), app.wacli_pending[@intFromEnum(WacliJobKind.hub_send)]);
    try std.testing.expectEqual(@as(usize, 0), pumped);
}

test "legacy hub sends remain on reader lane" {
    reset();
    var app = fixture();
    try std.testing.expect(wacliEnqueue(&app, .{ .kind = .hub_send }, true));
    try std.testing.expect(wacliTakeJob(&app, .hub_send) == null);
    try std.testing.expectEqual(WacliJobKind.hub_send, wacliTakeJob(&app, .wacli).?.kind);
}

test "unified sender rejects a different checkpoint owner" {
    reset();
    var app = fixture();
    app.unified_hub = true;
    const id = [_]u8{'c'} ** outbox.id_len;
    app.unified_inflight = .{ .id = id, .attempt = 3 };
    var job = WacliJob{ .kind = .hub_send, .gen = 2 };
    job.msg_id.set(&id);
    try std.testing.expect(!wacliEnqueue(&app, job, true));
    job.gen = 3;
    job.msg_id.set("dddddddddddddddddddddddddddddddd");
    try std.testing.expect(!wacliEnqueue(&app, job, true));
    try std.testing.expectEqual(@as(usize, 0), app.wacli_queue_len);
    try std.testing.expectEqual(@as(u32, 0), app.wacli_pending[@intFromEnum(WacliJobKind.hub_send)]);
    try std.testing.expectEqual(@as(usize, 0), pumped);
}

test "unified sender does not pump missing reader on the UI thread" {
    reset();
    var app = fixture();
    app.unified_hub = true;
    app.wacli_thread = null;
    const id = [_]u8{'e'} ** outbox.id_len;
    app.unified_inflight = .{ .id = id, .attempt = 1 };
    var job = WacliJob{ .kind = .hub_send, .gen = 1 };
    job.msg_id.set(&id);
    try std.testing.expect(wacliEnqueue(&app, job, true));
    try std.testing.expectEqual(@as(usize, 0), pumped);
    try std.testing.expectEqual(WacliJobKind.hub_send, wacliTakeJob(&app, .hub_send).?.kind);
}

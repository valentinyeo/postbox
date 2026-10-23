const std = @import("std");
const chat_key = @import("chat_key");
const transport = struct {
    const Provider = @FieldType(chat_key.Key, "provider");
};
const outbox = @import("outbox");
const slack_send = @import("slack_send");
const slack = @import("slack");
const max_slack_outbox = 16;
const max_failed_sends = 8;
const max_wacli_args = 16;
const wacli_arg_cap = 4095;
const Utf8Text = outbox.Str;

var now: u64 = 100;
const win = struct {
    fn GetTickCount64() u64 {
        return now;
    }
    const TRUE = 1;
    const FALSE = 0;
    fn InvalidateRect(_: u8, _: ?*anyopaque, _: u8) u8 {
        return 1;
    }
};

const BubbleText = struct {
    value: Utf8Text(4095) = .{},
    fn set(self: *BubbleText, _: std.mem.Allocator, text: []const u8) void {
        self.value.set(text);
    }
};
const Bubble = struct {
    timestamp: Utf8Text(63) = .{},
    send_state: enum { pending, failed } = .failed,
    text: BubbleText = .{},
};

const App = struct {
    slack_outbox: [max_slack_outbox]SlackOutbox = @splat(.{}),
    slack_outbox_count: usize = 0,
    slack_outbox_dirty: bool = false,
    outbox_load_failed: bool = false,
    fail_writes: bool = false,
    queue_full: bool = false,
    disconnected_account: Utf8Text(32) = .{},
    jobs: usize = 0,
    last_job: WacliJob = .{},
    journal: [128 * 1024]u8 = undefined,
    journal_len: usize = 0,
    status: Utf8Text(127) = .{},
    failed_bubbles: usize = 0,
    sent_bubbles: usize = 0,
    activity_seconds: i64 = 0,
    refreshed_chats: usize = 0,
    allocator: std.mem.Allocator = std.testing.allocator,
    selected_chat: usize = 0,
    chats: [1]struct { provider: enum { slack } = .slack, account: Utf8Text(32) = .{}, jid: Utf8Text(191) = .{} } = .{.{}},
    messages: [1]Bubble = .{.{}},
    canvas: ?u8 = null,
};

fn selectedChatIsSlack(_: *App) bool {
    return true;
}

fn slackAccountConfigured(a: *App, account: []const u8) bool {
    return a.disconnected_account.len == 0 or !std.mem.eql(u8, a.disconnected_account.slice(), account);
}

fn slackConfigured(_: *App) bool {
    return true;
}

fn setStatus(a: *App, status: []const u8) void {
    a.status.set(status);
}

fn resolveSlackSend(a: *App, result: *WacliResult) void {
    if (result.ok) a.sent_bubbles += 1 else a.failed_bubbles += 1;
}

fn noteSlackActivity(a: *App, _: []const u8, _: []const u8, seconds: i64) void {
    a.activity_seconds = seconds;
}

fn refreshVisibleChats(a: *App) void {
    a.refreshed_chats += 1;
}

fn persistOutbox(a: *App) bool {
    if (a.fail_writes) return false;
    var writer = std.Io.Writer.fixed(&a.journal);
    for (a.slack_outbox[0..a.slack_outbox_count]) |*slot| {
        if (!slot.completed) outbox.writeLine(&writer, &slot.entry) catch return false;
    }
    a.journal_len = writer.end;
    a.slack_outbox_dirty = false;
    return true;
}

fn wacliEnqueue(a: *App, job: WacliJob, urgent: bool) bool {
    std.debug.assert(urgent);
    if (a.queue_full) return false;
    if (job.kind == .slack_share) {
        var scanner = outbox.Scanner.init(std.testing.allocator, a.journal[0..a.journal_len]);
        var saved = false;
        while (scanner.next()) |entry| {
            if (std.mem.eql(u8, entry.idSlice(), job.msg_id.slice())) {
                std.debug.assert(entry.state == .uploaded);
                std.debug.assert(std.mem.eql(u8, entry.upload_file_id.slice(), job.args[2].slice()));
                saved = true;
            }
        }
        std.debug.assert(saved);
    }
    a.jobs += 1;
    a.last_job = job;
    return true;
}

fn addEntry(a: *App, image: bool) *SlackOutbox {
    const slot = &a.slack_outbox[a.slack_outbox_count];
    slot.* = .{};
    slot.entry.id = outbox.hexId(@splat(@intCast(a.slack_outbox_count + 1)));
    slot.entry.provider = .slack;
    slot.entry.jid.set("C01234567");
    slot.entry.text.set("test message");
    slot.entry.client_msg_id.set("00000000-0000-4000-8000-000000000000");
    slot.entry.queued_unix = @intCast(a.slack_outbox_count + 1);
    if (image) slot.entry.file.set("C:\\cache\\image.png");
    a.slack_outbox_count += 1;
    return slot;
}

fn resultFor(slot: *SlackOutbox, kind: WacliJobKind) WacliResult {
    var result = WacliResult{ .kind = kind, .jid = .{} };
    result.jid.set(slot.entry.jid.slice());
    result.msg_id.set(slot.entry.idSlice());
    result.extra.set("HttpFailed");
    result.http_status = 503;
    return result;
}

fn restart(a: *App) App {
    var loaded = App{};
    var scanner = outbox.Scanner.init(std.testing.allocator, a.journal[0..a.journal_len]);
    while (scanner.next()) |entry| {
        loaded.slack_outbox[loaded.slack_outbox_count].entry = entry.*;
        loaded.slack_outbox_count += 1;
    }
    std.debug.assert(persistOutbox(&loaded));
    return loaded;
}

test "Slack retries keep the journal and bubble pending until exhaustion" {
    var a = App{};
    now = 100;
    const slot = addEntry(&a, false);
    try std.testing.expect(persistOutbox(&a));
    enqueueSlackOutbox(&a, slot);
    for ([_]u64{ 3000, 10000, 30000 }) |delay| {
        var result = resultFor(slot, .slack_send);
        handleSlackSendResult(&a, &result);
        try std.testing.expectEqual(outbox.SendState.queued, slot.entry.state);
        try std.testing.expectEqual(@as(usize, 0), a.failed_bubbles);
        const before = a.jobs;
        now += delay - 1;
        retrySlackOutbox(&a);
        try std.testing.expectEqual(before, a.jobs);
        now += 1;
        retrySlackOutbox(&a);
        try std.testing.expectEqual(before + 1, a.jobs);
    }
    var result = resultFor(slot, .slack_send);
    handleSlackSendResult(&a, &result);
    try std.testing.expectEqual(@as(u8, 4), slot.entry.attempts);
    try std.testing.expectEqual(outbox.SendState.failed, slot.entry.state);
    try std.testing.expectEqual(@as(usize, 1), a.failed_bubbles);
    var loaded = restart(&a);
    retrySlackOutbox(&loaded);
    try std.testing.expectEqual(@as(usize, 0), loaded.jobs);
    try std.testing.expectEqual(outbox.SendState.failed, loaded.slack_outbox[0].entry.state);
}

test "Slack queued retries resume after restart and permanent failures do not block" {
    var a = App{};
    const first = addEntry(&a, false);
    var result = resultFor(first, .slack_send);
    handleSlackSendResult(&a, &result);
    var loaded = restart(&a);
    retrySlackOutbox(&loaded);
    try std.testing.expectEqual(@as(usize, 1), loaded.jobs);
    try std.testing.expectEqual(@as(u8, 1), loaded.slack_outbox[0].entry.attempts);
    result.slack_error.set("invalid_auth");
    handleSlackSendResult(&a, &result);
    try std.testing.expectEqual(outbox.SendState.failed, first.entry.state);
    const second = addEntry(&a, false);
    enqueueSlackOutbox(&a, second);
    try std.testing.expect(second.inflight);
}

test "Slack upload checkpoint must be saved before sharing including after restart" {
    var a = App{};
    const slot = addEntry(&a, true);
    try std.testing.expect(persistOutbox(&a));
    enqueueSlackOutbox(&a, slot);
    try std.testing.expectEqual(WacliJobKind.slack_attach, a.last_job.kind);
    var result = resultFor(slot, .slack_attach);
    result.ok = true;
    result.data = @constCast("F01234567");
    a.fail_writes = true;
    handleSlackSendResult(&a, &result);
    try std.testing.expectEqual(@as(usize, 1), a.jobs);
    retrySlackOutbox(&a);
    try std.testing.expectEqual(@as(usize, 1), a.jobs);
    a.fail_writes = false;
    retrySlackOutbox(&a);
    try std.testing.expectEqual(WacliJobKind.slack_share, a.last_job.kind);
    try std.testing.expectEqual(@as(u8, 0), slot.entry.attempts);
    var loaded = restart(&a);
    retrySlackOutbox(&loaded);
    try std.testing.expectEqual(WacliJobKind.slack_share, loaded.last_job.kind);
    try std.testing.expectEqualStrings("F01234567", loaded.last_job.args[2].slice());
    var shared = resultFor(&loaded.slack_outbox[0], .slack_share);
    shared.ok = true;
    shared.data = @constCast("{\"ok\":true,\"already_shared\":true}");
    handleSlackSendResult(&loaded, &shared);
    try std.testing.expectEqual(@as(usize, 0), loaded.slack_outbox_count);
    try std.testing.expectEqual(@as(usize, 0), loaded.journal_len);
    try std.testing.expect(std.mem.startsWith(u8, loaded.status.slice(), "Image sent"));
}

test "Slack missing upload restarts phase A and failed images survive restart" {
    var a = App{};
    const slot = addEntry(&a, true);
    slot.entry.upload_file_id.set("F01234567");
    slot.entry.state = .uploaded;
    try std.testing.expect(persistOutbox(&a));
    var result = resultFor(slot, .slack_share);
    result.extra.set("FileMissing");
    handleSlackSendResult(&a, &result);
    try std.testing.expectEqual(WacliJobKind.slack_attach, a.last_job.kind);
    try std.testing.expectEqualStrings("", slot.entry.upload_file_id.slice());
    result = resultFor(slot, .slack_attach);
    result.extra.set("ReadFailed");
    result.http_status = 0;
    handleSlackSendResult(&a, &result);
    try std.testing.expectEqualStrings("Slack image send failed", a.status.slice());
    var loaded = restart(&a);
    retrySlackOutbox(&loaded);
    try std.testing.expectEqual(@as(usize, 0), loaded.jobs);
    try std.testing.expectEqual(outbox.SendState.failed, loaded.slack_outbox[0].entry.state);
    try std.testing.expectEqual(@as(usize, 0), a.failed_bubbles);
}

test "Slack retains only eight failures and evicts oldest failed before refusing capacity" {
    var a = App{};
    for (0..9) |_| {
        const slot = addEntry(&a, false);
        var result = resultFor(slot, .slack_send);
        result.slack_error.set("invalid_auth");
        handleSlackSendResult(&a, &result);
    }
    try std.testing.expectEqual(@as(usize, 8), a.slack_outbox_count);
    try std.testing.expectEqual(@as(i64, 2), a.slack_outbox[0].entry.queued_unix);
    while (a.slack_outbox_count < max_slack_outbox) _ = addEntry(&a, false);
    try std.testing.expect(evictOldestFailedSlackOutbox(&a));
    try std.testing.expectEqual(@as(usize, 15), a.slack_outbox_count);
}

const JobContext = struct { host: []const u8 = "slack.com", user_token: []const u8 = "" };
const Response = struct {
    status: u32,
    body: []u8,
    fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};
var info_body: []const u8 = "";
var complete_calls: usize = 0;

fn callWithRetry(allocator: std.mem.Allocator, _: []const u8, _: []const u8, path: []const u8, body: ?[]const u8) !Response {
    if (std.mem.startsWith(u8, path, "/api/files.info?file=")) {
        try std.testing.expectEqualStrings("/api/files.info?file=F01234567", path);
        try std.testing.expect(body == null);
        return .{ .status = 200, .body = try allocator.dupe(u8, info_body) };
    }
    try std.testing.expectEqualStrings("/api/files.completeUploadExternal", path);
    try std.testing.expect(std.mem.indexOf(u8, body.?, "F01234567") != null);
    complete_calls += 1;
    return .{ .status = 200, .body = try allocator.dupe(u8, "{\"ok\":true}") };
}

fn httpOk(allocator: std.mem.Allocator, body: []const u8) bool {
    return slack.responseIsOk(allocator, body);
}

fn bodyOnly(_: std.mem.Allocator, response: Response) []u8 {
    return response.body;
}

test "Slack share worker never shares an already shared file again" {
    info_body = "{\"ok\":true,\"file\":{\"id\":\"F01234567\",\"shares\":{\"private\":{\"C01234567\":[{\"ts\":\"1700000000.000100\"}]}}}}";
    complete_calls = 0;
    const body = try shareImage(std.testing.allocator, .{}, "C01234567", "", "F01234567", "caption");
    defer std.testing.allocator.free(body);
    try std.testing.expectEqual(@as(usize, 0), complete_calls);
    try std.testing.expectEqualStrings("{\"ok\":true,\"already_shared\":true}", body);
}

test "Slack share worker shares unshared files but never missing or unknown files" {
    info_body = "{\"ok\":true,\"file\":{\"id\":\"F01234567\",\"channels\":[],\"shares\":{}}}";
    complete_calls = 0;
    const body = try shareImage(std.testing.allocator, .{}, "C01234567", "", "F01234567", "caption");
    defer std.testing.allocator.free(body);
    try std.testing.expectEqual(@as(usize, 1), complete_calls);
    info_body = "{\"ok\":false,\"error\":\"file_deleted\"}";
    try std.testing.expectError(error.FileMissing, shareImage(std.testing.allocator, .{}, "C01234567", "", "F01234567", "caption"));
    info_body = "{\"ok\":false,\"error\":\"file_not_found\"}";
    try std.testing.expectError(error.FileMissing, shareImage(std.testing.allocator, .{}, "C01234567", "", "F01234567", "caption"));
    info_body = "invalid json";
    try std.testing.expectError(error.HttpFailed, shareImage(std.testing.allocator, .{}, "C01234567", "", "F01234567", "caption"));
    try std.testing.expectEqual(@as(usize, 1), complete_calls);
}

test "Slack manual resend reuses and resets the failed journal entry" {
    var a = App{};
    const slot = addEntry(&a, false);
    slot.entry.state = .failed;
    slot.entry.attempts = 4;
    a.chats[0].jid.set(slot.entry.jid.slice());
    a.messages[0].timestamp.set(slot.entry.client_msg_id.slice());
    try std.testing.expect(persistOutbox(&a));
    try std.testing.expect(resendSlackBubble(&a));
    try std.testing.expectEqual(@as(usize, 1), a.slack_outbox_count);
    try std.testing.expectEqual(@as(u8, 0), slot.entry.attempts);
    try std.testing.expectEqual(outbox.SendState.queued, slot.entry.state);
    try std.testing.expectEqual(.pending, a.messages[0].send_state);
    try std.testing.expectEqualStrings(slot.entry.client_msg_id.slice(), a.last_job.args[3].slice());
    var loaded = restart(&a);
    retrySlackOutbox(&loaded);
    try std.testing.expectEqual(@as(usize, 1), loaded.jobs);
}

test "Slack share retries preserve the uploaded id and eventually persist failure" {
    var a = App{};
    const slot = addEntry(&a, true);
    slot.entry.state = .uploaded;
    slot.entry.upload_file_id.set("F01234567");
    for (0..4) |_| {
        var result = resultFor(slot, .slack_share);
        handleSlackSendResult(&a, &result);
        try std.testing.expectEqualStrings("F01234567", slot.entry.upload_file_id.slice());
    }
    try std.testing.expectEqual(outbox.SendState.failed, slot.entry.state);
    var loaded = restart(&a);
    retrySlackOutbox(&loaded);
    try std.testing.expectEqual(@as(usize, 0), loaded.jobs);
    try std.testing.expectEqualStrings("F01234567", loaded.slack_outbox[0].entry.upload_file_id.slice());
}

test "Slack successful share is not requeued when retirement persistence fails" {
    var a = App{};
    const slot = addEntry(&a, true);
    slot.entry.state = .uploaded;
    slot.entry.upload_file_id.set("F01234567");
    try std.testing.expect(persistOutbox(&a));
    var result = resultFor(slot, .slack_share);
    result.ok = true;
    a.fail_writes = true;
    handleSlackSendResult(&a, &result);
    retrySlackOutbox(&a);
    try std.testing.expectEqual(@as(usize, 0), a.jobs);
    try std.testing.expect(slot.completed);
    var loaded = restart(&a);
    retrySlackOutbox(&loaded);
    try std.testing.expectEqual(WacliJobKind.slack_share, loaded.last_job.kind);
    a.fail_writes = false;
    retrySlackOutbox(&a);
    try std.testing.expectEqual(@as(usize, 0), a.slack_outbox_count);
}

test "outbox keeps colliding channel ids isolated and one disconnected workspace cannot block another" {
    var a = App{};
    const first = addEntry(&a, false);
    first.entry.account.set("T0000000001");
    const second = addEntry(&a, false);
    second.entry.account.set("T0000000002");
    a.disconnected_account.set("T0000000001");
    retrySlackOutbox(&a);
    try std.testing.expect(!first.inflight);
    try std.testing.expect(second.inflight);
    try std.testing.expectEqual(@as(usize, 1), a.jobs);
    try std.testing.expectEqualStrings("T0000000002", a.last_job.account.slice());
    try std.testing.expectEqualStrings(first.entry.jid.slice(), a.last_job.jid.slice());
    var result = resultFor(first, .slack_send);
    result.extra.set("WorkspaceDisconnected");
    handleSlackSendResult(&a, &result);
    try std.testing.expectEqual(@as(u8, 0), first.entry.attempts);
    try std.testing.expectEqual(outbox.SendState.queued, first.entry.state);
}

test "successful Slack send records last message time and refreshes chat ordering without an echo" {
    var a = App{};
    const slot = addEntry(&a, false);
    var result = resultFor(slot, .slack_send);
    result.ok = true;
    result.data = @constCast("{\"ok\":true,\"ts\":\"1740000500.000100\"}");
    handleSlackSendResult(&a, &result);
    try std.testing.expectEqual(@as(i64, 1740000500), a.activity_seconds);
    try std.testing.expectEqual(@as(usize, 1), a.refreshed_chats);
    try std.testing.expectEqual(@as(usize, 0), a.slack_outbox_count);
}

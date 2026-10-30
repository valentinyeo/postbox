const std = @import("std");
const outbox = @import("outbox.zig");

const App = struct {
    provider: enum { slack, whatsapp, telegram, signal } = .slack,
    threads_enabled: bool = true,
};
const Message = struct {
    id: outbox.Str(191) = .{},
    thread_ts: outbox.Str(191) = .{},
    from_me: bool = false,
    send_state: enum { none, pending, failed } = .none,
};
fn slackThreadsEnabled(a: *App) bool {
    return a.provider == .slack and a.threads_enabled;
}

test "local pending and failed replies stay in the channel" {
    var app = App{};
    var message = Message{ .from_me = true, .send_state = .pending };
    message.id.set("local-pending-id");
    message.thread_ts.set("parent-id");
    try std.testing.expect(channelMessageVisible(&app, &message));
    message.id.set("");
    message.send_state = .failed;
    try std.testing.expect(channelMessageVisible(&app, &message));
    app.threads_enabled = false;
    try std.testing.expect(channelMessageVisible(&app, &message));
}

test "canonical Slack replies remain filtered only with threads enabled" {
    var app = App{};
    var message = Message{ .from_me = true };
    message.id.set("server-reply-id");
    message.thread_ts.set("parent-id");
    try std.testing.expect(!channelMessageVisible(&app, &message));
    message.from_me = false;
    try std.testing.expect(!channelMessageVisible(&app, &message));
    app.threads_enabled = false;
    try std.testing.expect(channelMessageVisible(&app, &message));
}

test "channel roots and non-Slack providers remain visible" {
    var app = App{};
    var message = Message{};
    message.id.set("parent-id");
    message.thread_ts.set("parent-id");
    try std.testing.expect(channelMessageVisible(&app, &message));
    message.thread_ts.set("");
    try std.testing.expect(channelMessageVisible(&app, &message));
    message.thread_ts.set("other-parent");
    inline for (.{ .whatsapp, .telegram, .signal }) |provider| {
        app.provider = provider;
        try std.testing.expect(channelMessageVisible(&app, &message));
        message.from_me = true;
        message.send_state = .failed;
        try std.testing.expect(channelMessageVisible(&app, &message));
        message.from_me = false;
        message.send_state = .none;
    }
}

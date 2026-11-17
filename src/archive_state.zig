const std = @import("std");

pub const Pending = enum { archive_pending, unarchive_pending };
pub const Completion = enum { confirm_archived_and_drop, drop, drop_managed_locally, retry };

pub fn isUnarchive(pending: Pending) bool {
    return pending == .unarchive_pending;
}

test "pending unarchive intent" {
    try std.testing.expect(!isUnarchive(.archive_pending));
    try std.testing.expect(isUnarchive(.unarchive_pending));
}

pub fn completion(pending: Pending, ok: bool, managed_locally: bool) Completion {
    if (ok) return if (pending == .archive_pending) .confirm_archived_and_drop else .drop;
    return if (managed_locally) .drop_managed_locally else .retry;
}

test "archive completion covers pending intent and result" {
    try std.testing.expectEqual(Completion.confirm_archived_and_drop, completion(.archive_pending, true, false));
    try std.testing.expectEqual(Completion.confirm_archived_and_drop, completion(.archive_pending, true, true));
    try std.testing.expectEqual(Completion.drop, completion(.unarchive_pending, true, false));
    try std.testing.expectEqual(Completion.drop, completion(.unarchive_pending, true, true));
    try std.testing.expectEqual(Completion.retry, completion(.archive_pending, false, false));
    try std.testing.expectEqual(Completion.drop_managed_locally, completion(.archive_pending, false, true));
    try std.testing.expectEqual(Completion.retry, completion(.unarchive_pending, false, false));
    try std.testing.expectEqual(Completion.drop_managed_locally, completion(.unarchive_pending, false, true));
}

pub const Intent = enum { archive, unarchive };
pub const Base = enum { inbox, archived };

pub fn fromUnarchive(unarchive: bool) Pending {
    return if (unarchive) .unarchive_pending else .archive_pending;
}

pub fn sameIntent(existing: Pending, wanted: Pending) bool {
    return existing == wanted;
}

test "unarchive flag maps to pending intent" {
    try std.testing.expectEqual(Pending.archive_pending, fromUnarchive(false));
    try std.testing.expectEqual(Pending.unarchive_pending, fromUnarchive(true));
}

test "pending intents match only in the same direction" {
    try std.testing.expect(sameIntent(.archive_pending, .archive_pending));
    try std.testing.expect(sameIntent(.unarchive_pending, .unarchive_pending));
    try std.testing.expect(!sameIntent(.archive_pending, .unarchive_pending));
    try std.testing.expect(!sameIntent(.unarchive_pending, .archive_pending));
}

pub fn visibleArchived(base_archived: bool, pending: ?Pending) bool {
    return switch (pending orelse return base_archived) {
        .archive_pending => true,
        .unarchive_pending => false,
    };
}

test "pending archive intent determines visible archived state" {
    try std.testing.expect(!visibleArchived(false, null));
    try std.testing.expect(visibleArchived(true, null));
    try std.testing.expect(visibleArchived(false, .archive_pending));
    try std.testing.expect(visibleArchived(true, .archive_pending));
    try std.testing.expect(!visibleArchived(true, .unarchive_pending));
    try std.testing.expect(!visibleArchived(false, .unarchive_pending));
}

pub const Operation = union(enum) {
    none: ?Intent,
    archiving: ?Intent,
    unarchiving: ?Intent,
};

pub const State = struct {
    base: Base = .inbox,
    operation: Operation = .{ .none = null },
};

pub const Event = enum {
    user_archive,
    user_unarchive,
    wacli_ok,
    wacli_failed,
    sync_says_archived,
    sync_says_inbox,
    queue_full,
    start_queued,
};

pub fn step(state: State, event: Event) State {
    var next = state;
    switch (event) {
        .sync_says_archived => next.base = .archived,
        .sync_says_inbox => next.base = .inbox,
        .user_archive, .user_unarchive => {
            const intent: Intent = if (event == .user_archive) .archive else .unarchive;
            next.operation = switch (state.operation) {
                .none => |queued| if (queued != null) .{ .none = intent } else if (intent == .archive) .{ .archiving = null } else .{ .unarchiving = null },
                .archiving => .{ .archiving = if (intent == .archive) null else intent },
                .unarchiving => .{ .unarchiving = if (intent == .unarchive) null else intent },
            };
        },
        .wacli_ok, .wacli_failed => {
            switch (state.operation) {
                .none => {},
                .archiving => |queued| {
                    next.base = if (event == .wacli_ok) .archived else .inbox;
                    next.operation = if (queued) |intent| switch (intent) {
                        .archive => .{ .archiving = null },
                        .unarchive => .{ .unarchiving = null },
                    } else .{ .none = null };
                },
                .unarchiving => |queued| {
                    if (event == .wacli_ok) next.base = .inbox;
                    next.operation = if (queued) |intent| switch (intent) {
                        .archive => .{ .archiving = null },
                        .unarchive => .{ .unarchiving = null },
                    } else .{ .none = null };
                },
            }
        },
        .queue_full => switch (state.operation) {
            .unarchiving => |queued| if (queued == null) {
                next.operation = .{ .none = .unarchive };
            },
            else => {},
        },
        .start_queued => switch (state.operation) {
            .none => |queued| if (queued) |intent| {
                next.operation = switch (intent) {
                    .archive => .{ .archiving = null },
                    .unarchive => .{ .unarchiving = null },
                };
            },
            else => {},
        },
    }
    return next;
}

test "archive and unarchive complete and failed archive returns to inbox" {
    var state = State{};
    state = step(state, .user_archive);
    try std.testing.expectEqualDeep(Operation{ .archiving = null }, state.operation);
    state = step(state, .wacli_ok);
    try std.testing.expectEqual(Base.archived, state.base);
    try std.testing.expectEqualDeep(Operation{ .none = null }, state.operation);
    state = step(state, .user_unarchive);
    state = step(state, .wacli_ok);
    try std.testing.expectEqual(Base.inbox, state.base);
    state = step(step(state, .user_archive), .wacli_failed);
    try std.testing.expectEqual(Base.inbox, state.base);
    try std.testing.expectEqualDeep(Operation{ .none = null }, state.operation);
}

test "opposing intent waits for the active operation" {
    var state = step(State{}, .user_archive);
    state = step(state, .user_unarchive);
    try std.testing.expectEqualDeep(Operation{ .archiving = .unarchive }, state.operation);
    state = step(state, .user_unarchive);
    try std.testing.expectEqualDeep(Operation{ .archiving = .unarchive }, state.operation);
    state = step(state, .user_archive);
    try std.testing.expectEqualDeep(Operation{ .archiving = null }, state.operation);
    state = step(state, .user_unarchive);
    state = step(state, .wacli_ok);
    try std.testing.expectEqual(Base.archived, state.base);
    try std.testing.expectEqualDeep(Operation{ .unarchiving = null }, state.operation);
    state = step(state, .user_archive);
    state = step(state, .wacli_failed);
    try std.testing.expectEqualDeep(Operation{ .archiving = null }, state.operation);
}

test "sync changes the base without discarding operations" {
    var state = step(step(State{}, .user_archive), .user_unarchive);
    state = step(state, .sync_says_archived);
    try std.testing.expectEqual(Base.archived, state.base);
    try std.testing.expectEqualDeep(Operation{ .archiving = .unarchive }, state.operation);
    state = step(state, .sync_says_inbox);
    try std.testing.expectEqual(Base.inbox, state.base);
    try std.testing.expectEqualDeep(Operation{ .archiving = .unarchive }, state.operation);
}

test "a full queue retains an unarchive request until it can start" {
    var state = State{ .base = .archived };
    state = step(step(state, .user_unarchive), .queue_full);
    try std.testing.expectEqualDeep(Operation{ .none = .unarchive }, state.operation);
    state = step(state, .sync_says_archived);
    try std.testing.expectEqualDeep(Operation{ .none = .unarchive }, state.operation);
    state = step(state, .start_queued);
    try std.testing.expectEqualDeep(Operation{ .unarchiving = null }, state.operation);
    state = step(state, .wacli_ok);
    try std.testing.expectEqual(Base.inbox, state.base);
}

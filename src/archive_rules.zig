//! Archived-chat rules, pure so they are unit testable on the host: when an
//! archived WhatsApp chat comes back to the inbox, the "Keep archived" set,
//! the per-chat baseline it is compared against, and the Ctrl+A selection.
//! The app persists State as a small text file in %LOCALAPPDATA%\Messages.

const std = @import("std");

pub const max_entries = 300;
pub const max_jid = 191;
pub const max_ts = 47;

pub fn pendingHidesChat(show_archived: bool, should_unarchive: bool) bool {
    return show_archived == should_unarchive;
}

pub fn progressStatus(out: []u8, should_unarchive: bool, total: usize, remaining: usize) ?[]const u8 {
    if (total <= 1 or remaining == 0 or remaining > total) return null;
    return std.fmt.bufPrint(out, "{s} {d} of {d}", .{
        if (should_unarchive) @as([]const u8, "Unarchiving") else "Archiving",
        total - remaining + 1,
        total,
    }) catch null;
}

pub const Action = enum {
    archive,
    keep,
    unarchive,

    pub fn status(self: Action) []const u8 {
        return switch (self) {
            .archive => "Archived. Comes back on a new message",
            .keep => "Kept archived. Won't come back",
            .unarchive => "Chat unarchived",
        };
    }
};

/// What the app knows about one archived chat: whether it must stay archived
/// and the last-message stamp seen when it was archived (or first seen
/// archived). A newer incoming message than the baseline brings it back.
pub const Entry = struct {
    jid: [max_jid]u8 = undefined,
    jid_len: u8 = 0,
    ts: [max_ts]u8 = undefined,
    ts_len: u8 = 0,
    keep: bool = false,

    pub fn jidSlice(self: *const Entry) []const u8 {
        return self.jid[0..self.jid_len];
    }
    pub fn tsSlice(self: *const Entry) []const u8 {
        return self.ts[0..self.ts_len];
    }
};

pub const State = struct {
    entries: [max_entries]Entry = undefined,
    count: usize = 0,

    pub fn find(self: *const State, jid: []const u8) ?usize {
        for (self.entries[0..self.count], 0..) |*entry, index| {
            if (std.mem.eql(u8, entry.jidSlice(), jid)) return index;
        }
        return null;
    }

    pub fn isKept(self: *const State, jid: []const u8) bool {
        const index = self.find(jid) orelse return false;
        return self.entries[index].keep;
    }

    /// Baseline stamp, or null when the chat has none yet.
    pub fn baseline(self: *const State, jid: []const u8) ?[]const u8 {
        const index = self.find(jid) orelse return null;
        const ts = self.entries[index].tsSlice();
        return if (ts.len == 0) null else ts;
    }

    /// Entry for jid, created when missing. A full table drops the oldest
    /// entry that is not kept; a table of only kept chats refuses (null).
    fn slot(self: *State, jid: []const u8) ?*Entry {
        if (jid.len == 0 or jid.len > max_jid) return null;
        if (self.find(jid)) |index| return &self.entries[index];
        if (self.count >= max_entries) {
            var victim: ?usize = null;
            for (self.entries[0..self.count], 0..) |*entry, index| {
                if (!entry.keep) {
                    victim = index;
                    break;
                }
            }
            const drop = victim orelse return null;
            self.removeAt(drop);
        }
        const entry = &self.entries[self.count];
        entry.* = .{};
        @memcpy(entry.jid[0..jid.len], jid);
        entry.jid_len = @intCast(jid.len);
        self.count += 1;
        return entry;
    }

    pub fn setBaseline(self: *State, jid: []const u8, ts: []const u8) void {
        const entry = self.slot(jid) orelse return;
        const n = @min(ts.len, max_ts);
        @memcpy(entry.ts[0..n], ts[0..n]);
        entry.ts_len = @intCast(n);
    }

    /// Reserve kept state before queuing the write: a full kept table must
    /// not silently turn "Keep archived" into regular archiving.
    pub fn archive(self: *State, jid: []const u8, ts: []const u8, keep: bool) bool {
        const entry = self.slot(jid) orelse return false;
        entry.keep = keep;
        if (ts.len > 0) self.setBaseline(jid, ts);
        return true;
    }

    pub fn setKeep(self: *State, jid: []const u8, keep: bool) void {
        if (!keep) {
            const index = self.find(jid) orelse return;
            self.entries[index].keep = false;
            return;
        }
        const entry = self.slot(jid) orelse return;
        entry.keep = true;
    }

    fn removeAt(self: *State, index: usize) void {
        var i = index + 1;
        while (i < self.count) : (i += 1) self.entries[i - 1] = self.entries[i];
        self.count -= 1;
    }

    /// Forget a chat entirely (it was unarchived).
    pub fn remove(self: *State, jid: []const u8) void {
        if (self.find(jid)) |index| self.removeAt(index);
    }

    /// Text form: one chat per line, "jid<TAB>keep<TAB>baseline".
    pub fn format(self: *const State, out: []u8) []const u8 {
        var len: usize = 0;
        for (self.entries[0..self.count]) |*entry| {
            const line = std.fmt.bufPrint(out[len..], "{s}\t{d}\t{s}\n", .{ entry.jidSlice(), @intFromBool(entry.keep), entry.tsSlice() }) catch break;
            len += line.len;
        }
        return out[0..len];
    }

    pub fn parse(self: *State, text: []const u8) void {
        self.count = 0;
        var lines = std.mem.tokenizeAny(u8, text, "\r\n");
        while (lines.next()) |line| {
            var fields = std.mem.splitScalar(u8, line, '\t');
            const jid = fields.next() orelse continue;
            const keep = fields.next() orelse continue;
            const ts = fields.next() orelse "";
            const entry = self.slot(jid) orelse continue;
            entry.keep = std.mem.eql(u8, keep, "1");
            const n = @min(ts.len, max_ts);
            @memcpy(entry.ts[0..n], ts[0..n]);
            entry.ts_len = @intCast(n);
        }
    }
};

/// A list row for an archived chat moved past its baseline: worth one probe
/// of its newest message. Kept chats never resurface, so they are never
/// probed. wacli stamps are fixed-width ISO strings, so byte order is time
/// order (same convention as chat_reconcile).
pub fn needsProbe(kept: bool, last_ts: []const u8, baseline_ts: []const u8) bool {
    if (kept or last_ts.len == 0 or baseline_ts.len == 0) return false;
    return std.mem.order(u8, last_ts, baseline_ts) == .gt;
}

/// The decision itself: bring an archived chat back to the inbox when its
/// newest message is from someone else, arrived after the baseline, and the
/// chat is not kept archived.
pub fn shouldResurface(newest_from_me: bool, kept: bool, newest_ts: []const u8, baseline_ts: []const u8) bool {
    if (newest_from_me or kept) return false;
    if (newest_ts.len == 0 or baseline_ts.len == 0) return false;
    return std.mem.order(u8, newest_ts, baseline_ts) == .gt;
}

/// Ctrl+A in the chat list: a snapshot of the jids on screen, so a row that
/// appears afterwards is never archived by a later Ctrl+E.
pub fn Selection(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        jids: [capacity][max_jid]u8 = undefined,
        lens: [capacity]u8 = [_]u8{0} ** capacity,
        count: usize = 0,

        pub fn clear(self: *Self) void {
            self.count = 0;
        }

        pub fn add(self: *Self, jid: []const u8) void {
            if (jid.len == 0 or jid.len > max_jid or self.count >= capacity) return;
            @memcpy(self.jids[self.count][0..jid.len], jid);
            self.lens[self.count] = @intCast(jid.len);
            self.count += 1;
        }

        pub fn at(self: *const Self, index: usize) []const u8 {
            return self.jids[index][0..self.lens[index]];
        }

        pub fn contains(self: *const Self, jid: []const u8) bool {
            var index: usize = 0;
            while (index < self.count) : (index += 1) {
                if (std.mem.eql(u8, self.at(index), jid)) return true;
            }
            return false;
        }
    };
}

/// After rows were removed, does the open pane still show the selected row?
/// True when the pane must be re-read at once: the open chat left the list
/// (or the list is empty).
pub fn paneNeedsSwitch(open_jid: []const u8, selected_jid: ?[]const u8) bool {
    const now = selected_jid orelse return true;
    return !std.mem.eql(u8, open_jid, now);
}

test "a newer incoming message resurfaces an archived chat" {
    try std.testing.expect(shouldResurface(false, false, "2026-10-10T10:30:00Z", "2026-10-10T10:24:33Z"));
}

test "my own newest message, a kept chat or an old stamp never resurface" {
    try std.testing.expect(!shouldResurface(true, false, "2026-10-10T10:30:00Z", "2026-10-10T10:24:33Z"));
    try std.testing.expect(!shouldResurface(false, true, "2026-10-10T10:30:00Z", "2026-10-10T10:24:33Z"));
    try std.testing.expect(!shouldResurface(false, false, "2026-10-10T10:24:33Z", "2026-10-10T10:24:33Z"));
    try std.testing.expect(!shouldResurface(false, false, "2026-10-10T09:00:00Z", "2026-10-10T10:24:33Z"));
    try std.testing.expect(!shouldResurface(false, false, "", "2026-10-10T10:24:33Z"));
    try std.testing.expect(!shouldResurface(false, false, "2026-10-10T10:30:00Z", ""));
}

test "only moved, unkept chats with a baseline are probed" {
    try std.testing.expect(needsProbe(false, "2026-10-10T10:30:00Z", "2026-10-10T10:24:33Z"));
    try std.testing.expect(!needsProbe(true, "2026-10-10T10:30:00Z", "2026-10-10T10:24:33Z"));
    try std.testing.expect(!needsProbe(false, "2026-10-10T10:24:33Z", "2026-10-10T10:24:33Z"));
    try std.testing.expect(!needsProbe(false, "2026-10-10T10:30:00Z", ""));
}

test "state keeps, forgets and round-trips through text" {
    var state = State{};
    state.setBaseline("a@g.us", "2026-10-10T10:00:00Z");
    state.setKeep("b@s.whatsapp.net", true);
    state.setBaseline("b@s.whatsapp.net", "2026-10-10T11:00:00Z");
    try std.testing.expect(state.isKept("b@s.whatsapp.net"));
    try std.testing.expect(!state.isKept("a@g.us"));
    try std.testing.expectEqualStrings("2026-10-10T10:00:00Z", state.baseline("a@g.us").?);

    var buffer: [512]u8 = undefined;
    const text = state.format(&buffer);
    var loaded = State{};
    loaded.parse(text);
    try std.testing.expectEqual(@as(usize, 2), loaded.count);
    try std.testing.expect(loaded.isKept("b@s.whatsapp.net"));
    try std.testing.expectEqualStrings("2026-10-10T11:00:00Z", loaded.baseline("b@s.whatsapp.net").?);

    loaded.setKeep("b@s.whatsapp.net", false);
    try std.testing.expect(!loaded.isKept("b@s.whatsapp.net"));
    loaded.remove("a@g.us");
    try std.testing.expect(loaded.baseline("a@g.us") == null);
}

test "a full table drops unkept entries first" {
    var state = State{};
    state.setKeep("keep@g.us", true);
    var i: usize = 0;
    var name: [16]u8 = undefined;
    while (i < max_entries + 5) : (i += 1) {
        const jid = std.fmt.bufPrint(&name, "{d}@g.us", .{i}) catch unreachable;
        state.setBaseline(jid, "2026-10-10T10:00:00Z");
    }
    try std.testing.expectEqual(@as(usize, max_entries), state.count);
    try std.testing.expect(state.isKept("keep@g.us"));
}

test "select-all snapshot holds exactly the rows shown" {
    var selection = Selection(4){};
    selection.add("a@g.us");
    selection.add("b@s.whatsapp.net");
    try std.testing.expect(selection.contains("a@g.us"));
    try std.testing.expect(!selection.contains("c@g.us"));
    try std.testing.expectEqual(@as(usize, 2), selection.count);
    selection.clear();
    try std.testing.expect(!selection.contains("a@g.us"));
}

test "the pane switches when the open chat left the list" {
    try std.testing.expect(paneNeedsSwitch("a@g.us", "b@g.us"));
    try std.testing.expect(paneNeedsSwitch("a@g.us", null));
    try std.testing.expect(!paneNeedsSwitch("a@g.us", "a@g.us"));
}

test "archive modes survive restart and allow resurfacing undoes keep" {
    const jid = "kept@g.us";
    const baseline_ts = "2026-10-10T10:00:00Z";
    const incoming_ts = "2026-10-10T11:00:00Z";
    var state = State{};
    try std.testing.expect(state.archive(jid, baseline_ts, true));
    var buffer: [512]u8 = undefined;
    var loaded = State{};
    loaded.parse(state.format(&buffer));
    try std.testing.expect(!needsProbe(loaded.isKept(jid), incoming_ts, loaded.baseline(jid).?));
    try std.testing.expect(!shouldResurface(false, loaded.isKept(jid), incoming_ts, loaded.baseline(jid).?));
    loaded.setKeep(jid, false);
    state.parse(loaded.format(&buffer));
    try std.testing.expect(shouldResurface(false, state.isKept(jid), incoming_ts, state.baseline(jid).?));
    try std.testing.expect(!shouldResurface(true, state.isKept(jid), incoming_ts, state.baseline(jid).?));
    try std.testing.expect(state.archive(jid, incoming_ts, false));
    try std.testing.expect(!shouldResurface(false, state.isKept(jid), incoming_ts, state.baseline(jid).?));
    try std.testing.expect(shouldResurface(false, state.isKept(jid), "2026-10-10T12:00:00Z", state.baseline(jid).?));
}

test "a full kept table refuses a new archive without changing existing state" {
    var state = State{};
    var name: [16]u8 = undefined;
    for (0..max_entries) |i| {
        const jid = try std.fmt.bufPrint(&name, "{d}@g.us", .{i});
        try std.testing.expect(state.archive(jid, "baseline", true));
    }
    try std.testing.expect(!state.archive("overflow@g.us", "baseline", true));
    try std.testing.expectEqual(@as(usize, max_entries), state.count);
    try std.testing.expect(state.isKept("0@g.us"));
    try std.testing.expect(state.archive("0@g.us", "new-baseline", true));
    try std.testing.expectEqualStrings("new-baseline", state.baseline("0@g.us").?);
}

test "plain archive explicitly replaces keep and own messages never resurface" {
    var state = State{};
    const jid = "a@g.us";
    try std.testing.expect(state.archive(jid, "2026-10-10T10:00:00Z", true));
    try std.testing.expect(state.archive(jid, "2026-10-10T11:00:00Z", false));
    try std.testing.expect(!state.isKept(jid));
    for ([_]bool{ false, true }) |kept| {
        try std.testing.expect(!shouldResurface(true, kept, "2026-10-10T12:00:00Z", state.baseline(jid).?));
    }
}

test "pending operations hide chats only in the view they are leaving" {
    try std.testing.expect(pendingHidesChat(false, false));
    try std.testing.expect(!pendingHidesChat(true, false));
    try std.testing.expect(pendingHidesChat(true, true));
    try std.testing.expect(!pendingHidesChat(false, true));
}

test "batch progress includes the current operation through the last item" {
    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Archiving 1 of 250", progressStatus(&out, false, 250, 250).?);
    try std.testing.expectEqualStrings("Archiving 12 of 250", progressStatus(&out, false, 250, 239).?);
    try std.testing.expectEqualStrings("Archiving 250 of 250", progressStatus(&out, false, 250, 1).?);
    try std.testing.expectEqualStrings("Unarchiving 2 of 3", progressStatus(&out, true, 3, 2).?);
    try std.testing.expect(progressStatus(&out, false, 250, 0) == null);
    try std.testing.expect(progressStatus(&out, false, 1, 1) == null);
    try std.testing.expect(progressStatus(&out, false, 0, 0) == null);
    try std.testing.expect(progressStatus(&out, false, 2, 3) == null);
    try std.testing.expect(progressStatus(out[0..1], false, 250, 239) == null);
}

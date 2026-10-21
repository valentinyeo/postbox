const std = @import("std");
const keys = @import("environment_keys");
const dictation_policy = @import("dictation_policy");
const Language = dictation_policy.Language;
const Text = struct {
    value: []const u8 = "",
    len: usize = 0,
    fn slice(self: @This()) []const u8 {
        return self.value;
    }
};
const Message = struct {
    transcript_state: enum { none, loading, ready, failed } = .none,
};
const App = struct {
    transcribe_attempts: [512]u64 = [_]u64{0} ** 512,
    transcribe_attempt_count: usize = 0,
    transcribe_active_id: Text = .{},
    messages: [4]Message = .{ .{}, .{}, .{}, .{} },
    message_count: usize = 4,
};
const environment_keys = struct {
    const shouldRetry = keys.shouldRetry;
    fn readUser(allocator: std.mem.Allocator, comptime _: []const u8) ?[]u8 {
        reads += 1;
        return allocator.dupe(u8, fixture_saved) catch unreachable;
    }
};
var calls: usize = 0;
var reads: usize = 0;
var fixture_saved: []const u8 = "replacement-value";
var reject_replacement = false;
fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
fn transcribeAt(allocator: std.mem.Allocator, key: []const u8, _: [*:0]const u16, _: []const u8, _: []const u8) ![]u8 {
    calls += 1;
    if (std.mem.eql(u8, key, "inherited-value") or reject_replacement) return error.Unauthorized;
    return allocator.dupe(u8, "transcript");
}
fn reset() void {
    calls = 0;
    reads = 0;
    fixture_saved = "replacement-value";
    reject_replacement = false;
}

test "ISSUE-517 failed voice notes retry once per chat open without redoing cached or active notes" {
    var a = App{};
    a.messages[0].transcript_state = .failed;
    a.messages[1].transcript_state = .ready;
    a.messages[2].transcript_state = .loading;
    a.transcribe_active_id = .{ .value = "active-note", .len = "active-note".len };
    try std.testing.expect(!transcribeWasAttempted(&a, "failed-note"));
    try std.testing.expect(transcribeWasAttempted(&a, "failed-note"));
    beginTranscriptionOpen(&a);
    try std.testing.expectEqual(.none, a.messages[0].transcript_state);
    try std.testing.expectEqual(.ready, a.messages[1].transcript_state);
    try std.testing.expectEqual(.loading, a.messages[2].transcript_state);
    try std.testing.expect(transcribeWasAttempted(&a, "active-note"));
    try std.testing.expect(!transcribeWasAttempted(&a, "failed-note"));
    a.messages[0].transcript_state = .failed;
    try std.testing.expect(transcribeWasAttempted(&a, "failed-note"));
    beginTranscriptionOpen(&a);
    try std.testing.expect(!transcribeWasAttempted(&a, "failed-note"));
    a.transcribe_attempt_count = a.transcribe_attempts.len;
    try std.testing.expect(transcribeWasAttempted(&a, "another-note"));
    try std.testing.expect(transcribeWasAttempted(&a, "failed-note"));
}

test "ISSUE-517 transcription transport refreshes Unauthorized once and uses the replacement" {
    reset();
    var transport = Transport{ .allocator = std.testing.allocator, .api_key = "inherited-value" };
    defer if (transport.refreshed_key) |key| std.testing.allocator.free(key);
    const result = try dictation_policy.transcribeFile(&transport, .automatic, "audio/ogg", "audio");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("transcript", result);
    try std.testing.expectEqual(@as(usize, 2), calls);
    try std.testing.expectEqual(@as(usize, 1), reads);
    try std.testing.expectEqualStrings("replacement-value", transport.api_key);
}

test "ISSUE-517 rejected replacement and unchanged keys do not loop" {
    reset();
    reject_replacement = true;
    var transport = Transport{ .allocator = std.testing.allocator, .api_key = "inherited-value" };
    defer if (transport.refreshed_key) |key| std.testing.allocator.free(key);
    try std.testing.expectError(error.Unauthorized, transport.send(.automatic, "audio/ogg", "audio"));
    try std.testing.expectEqual(@as(usize, 2), calls);
    try std.testing.expectEqual(@as(usize, 1), reads);
    try std.testing.expectError(error.Unauthorized, transport.sendMultilingual("audio/ogg", "audio"));
    try std.testing.expectEqual(@as(usize, 3), calls);
    try std.testing.expectEqual(@as(usize, 1), reads);
    reset();
    fixture_saved = "inherited-value";
    var unchanged = Transport{ .allocator = std.testing.allocator, .api_key = "inherited-value" };
    try std.testing.expectError(error.Unauthorized, unchanged.send(.automatic, "audio/ogg", "audio"));
    try std.testing.expectEqual(@as(usize, 1), calls);
    try std.testing.expectEqual(@as(usize, 1), reads);
}

const std = @import("std");
const policy = @import("dictation_policy.zig");

pub const capacity = 8192;
const timestamp_tolerance = 0.000001;
pub const Anchor = struct { start: u32, end: u32 };

pub fn path(comptime language: policy.Language) []const u8 {
    const base = "/v1/listen?model=nova-3&smart_format=true&interim_results=true&encoding=linear16&sample_rate=16000&channels=1";
    return base ++ switch (language) {
        .automatic => "&language=multi&language_hint=en&language_hint=de&tag=wazig",
        .english => "&language=en&tag=wazig",
        .german => "&language=de&tag=wazig",
    };
}

pub const Transcript = struct {
    committed: [capacity]u8 = undefined,
    committed_len: usize = 0,
    interim: [capacity]u8 = undefined,
    interim_len: usize = 0,
    interim_start: f64 = 0,
    final_end: f64 = 0,
    final_start: ?f64 = null,

    pub fn apply(self: *Transcript, text: []const u8, final: bool, start: f64, duration: f64) !void {
        if (!std.math.isFinite(start) or !std.math.isFinite(duration) or !std.math.isFinite(start + duration) or start < 0 or duration < 0) return error.BadResponse;
        if (!std.unicode.utf8ValidateSlice(text) or std.mem.indexOfScalar(u8, text, 0) != null) return error.BadResponse;
        if (start < self.final_end - timestamp_tolerance or (self.final_start != null and start <= self.final_start.?)) return;
        if (final) {
            const separator: usize = @intFromBool(self.committed_len > 0 and text.len > 0);
            const clears_interim = start + duration > self.interim_start + timestamp_tolerance or std.math.approxEqAbs(f64, start, self.interim_start, timestamp_tolerance);
            const remaining = if (clears_interim) 0 else self.interim_len;
            const committed_len = self.committed_len + separator + text.len;
            if (committed_len + remaining + @intFromBool(remaining > 0 and committed_len > 0) > capacity) return error.TranscriptTooLong;
            if (separator > 0) self.committed[self.committed_len] = ' ';
            self.committed_len += separator;
            @memcpy(self.committed[self.committed_len..][0..text.len], text);
            self.committed_len += text.len;
            self.final_start = start;
            self.final_end = start + duration;
            if (clears_interim) self.interim_len = 0;
        } else {
            if (self.interim_len > 0 and start < self.interim_start) return;
            if (self.committed_len + text.len + @intFromBool(self.committed_len > 0 and text.len > 0) > capacity) return error.TranscriptTooLong;
            @memcpy(self.interim[0..text.len], text);
            self.interim_len = text.len;
            self.interim_start = start;
        }
    }

    pub fn copy(self: *const Transcript, out: []u8) ![]const u8 {
        const separator: usize = @intFromBool(self.committed_len > 0 and self.interim_len > 0);
        const length = self.committed_len + separator + self.interim_len;
        if (length > out.len) return error.TranscriptTooLong;
        @memcpy(out[0..self.committed_len], self.committed[0..self.committed_len]);
        if (separator > 0) out[self.committed_len] = ' ';
        @memcpy(out[self.committed_len + separator ..][0..self.interim_len], self.interim[0..self.interim_len]);
        return out[0..length];
    }

    pub fn receive(self: *Transcript, allocator: std.mem.Allocator, json: []const u8, language: policy.Language) !bool {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
        defer parsed.deinit();
        const root = try object(parsed.value);
        const kind = try string(root.get("type") orelse return error.BadResponse);
        if (std.mem.eql(u8, kind, "Error")) return error.TranscriptionFailed;
        if (!std.mem.eql(u8, kind, "Results")) return false;
        const channel = try object(root.get("channel") orelse return error.BadResponse);
        const alternatives = channel.get("alternatives") orelse return error.BadResponse;
        if (alternatives != .array or alternatives.array.items.len == 0) return error.BadResponse;
        const alternative = try object(alternatives.array.items[0]);
        const text = try string(alternative.get("transcript") orelse return error.BadResponse);
        if (language == .automatic and text.len > 0 and !allowedLanguages(alternative)) return error.UnsupportedLanguage;
        const final = root.get("is_final") orelse return error.BadResponse;
        if (final != .bool) return error.BadResponse;
        try self.apply(text, final.bool, try number(root.get("start") orelse return error.BadResponse), try number(root.get("duration") orelse return error.BadResponse));
        return true;
    }
};

fn object(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |v| v,
        else => error.BadResponse,
    };
}

fn string(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |v| v,
        else => error.BadResponse,
    };
}

fn number(value: std.json.Value) !f64 {
    return switch (value) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        else => error.BadResponse,
    };
}

fn allowedLanguage(value: std.json.Value) bool {
    const tag = string(value) catch return false;
    return std.mem.eql(u8, tag, "en") or std.mem.eql(u8, tag, "de") or std.mem.startsWith(u8, tag, "en-") or std.mem.startsWith(u8, tag, "de-");
}

fn allowedLanguages(alternative: std.json.ObjectMap) bool {
    if (alternative.get("words")) |words| {
        if (words != .array) return false;
        if (words.array.items.len > 0) {
            for (words.array.items) |word| {
                const fields = object(word) catch return false;
                if (!allowedLanguage(fields.get("language") orelse return false)) return false;
            }
            return true;
        }
    }
    const languages = alternative.get("languages") orelse return false;
    if (languages != .array or languages.array.items.len == 0) return false;
    for (languages.array.items) |language| if (!allowedLanguage(language)) return false;
    return true;
}

test "interim revisions replace in place and final replay never duplicates words" {
    var state = Transcript{};
    var out: [capacity]u8 = undefined;
    try state.apply("hel", false, 0, 1);
    try std.testing.expectEqualStrings("hel", try state.copy(&out));
    try state.apply("hello world", false, 0, 2);
    try std.testing.expectEqualStrings("hello world", try state.copy(&out));
    try state.apply("Hello world.", true, 0, 2);
    try state.apply("Hello world.", true, 0, 2);
    try state.apply("hello", false, 0, 1);
    try std.testing.expectEqualStrings("Hello world.", try state.copy(&out));
    try state.apply("next", false, 2, 1);
    try state.apply("Next sentence.", true, 2, 2);
    try std.testing.expectEqualStrings("Hello world. Next sentence.", try state.copy(&out));
}

test "late final preserves newer interim and stale interim cannot replace it" {
    var state = Transcript{};
    var out: [capacity]u8 = undefined;
    try state.apply("second", false, 2, 1);
    try state.apply("stale", false, 0, 1);
    try state.apply("First.", true, 0, 2);
    try std.testing.expectEqualStrings("First. second", try state.copy(&out));
    try state.apply("Second.", true, 2, 1);
    try state.apply("", true, 3, 0);
    try std.testing.expectEqualStrings("First. Second.", try state.copy(&out));
}

test "genuine repeated speech is retained and a revised interim can shrink" {
    var state = Transcript{};
    var out: [capacity]u8 = undefined;
    try state.apply("Yes.", true, 0, 1);
    try state.apply("Yes.", true, 1, 1);
    try state.apply("a long guess", false, 2, 1);
    try state.apply("short", false, 2, 1);
    try std.testing.expectEqualStrings("Yes. Yes. short", try state.copy(&out));
    try state.apply("", false, 2, 1);
    try std.testing.expectEqualStrings("Yes. Yes.", try state.copy(&out));
}

test "bad timestamps text and capacity errors leave the transcript intact" {
    var state = Transcript{};
    var out: [capacity]u8 = undefined;
    try state.apply("Grüße", false, 0, 1);
    try std.testing.expectError(error.BadResponse, state.apply("bad", true, std.math.nan(f64), 1));
    try std.testing.expectError(error.BadResponse, state.apply("\xff", false, 0, 1));
    const too_long = [_]u8{'x'} ** (capacity + 1);
    try std.testing.expectError(error.TranscriptTooLong, state.apply(&too_long, true, 0, 1));
    try std.testing.expectEqualStrings("Grüße", try state.copy(&out));
}

test "live automatic results accept English and German but reject other or missing language metadata" {
    var state = Transcript{};
    const prefix = "{\"type\":\"Results\",\"start\":0,\"duration\":1,\"is_final\":false,\"channel\":{\"alternatives\":[{\"transcript\":\"Hallo\",";
    try std.testing.expect(try state.receive(std.testing.allocator, prefix ++ "\"languages\":[\"de-DE\",\"en\"]}]}}", .automatic));
    try std.testing.expectError(error.UnsupportedLanguage, state.receive(std.testing.allocator, prefix ++ "\"languages\":[\"fr\"]}]}}", .automatic));
    try std.testing.expectError(error.UnsupportedLanguage, state.receive(std.testing.allocator, prefix ++ "\"languages\":[\"en\"],\"words\":[{\"language\":\"fr\"}]}]}}", .automatic));
    try std.testing.expectError(error.UnsupportedLanguage, state.receive(std.testing.allocator, prefix ++ "\"words\":[{}]}]}}", .automatic));
    try std.testing.expect(try state.receive(std.testing.allocator, prefix ++ "\"words\":[]}]}}", .german));
    try std.testing.expect(!(try state.receive(std.testing.allocator, "{\"type\":\"Metadata\"}", .automatic)));
    try std.testing.expectError(error.TranscriptionFailed, state.receive(std.testing.allocator, "{\"type\":\"Error\"}", .automatic));
}

test "live paths select fixed languages or en de hints with interim PCM results" {
    inline for (std.enums.values(policy.Language)) |language| {
        try std.testing.expect(std.mem.indexOf(u8, path(language), "interim_results=true&encoding=linear16&sample_rate=16000&channels=1") != null);
    }
    try std.testing.expect(std.mem.endsWith(u8, path(.automatic), "&language=multi&language_hint=en&language_hint=de&tag=wazig"));
    try std.testing.expect(std.mem.endsWith(u8, path(.english), "&language=en&tag=wazig"));
    try std.testing.expect(std.mem.endsWith(u8, path(.german), "&language=de&tag=wazig"));
}

test "fractional segment boundaries keep the next interim and final words" {
    var state = Transcript{};
    var out: [capacity]u8 = undefined;
    try state.apply("second", false, 0.3, 0.1);
    try state.apply("First.", true, 0.1, 0.2);
    try std.testing.expectEqualStrings("First. second", try state.copy(&out));
    try state.apply("Second.", true, 0.3, 0.1);
    try std.testing.expectEqualStrings("First. Second.", try state.copy(&out));
}

const std = @import("std");

pub const Language = enum(u8) { automatic, english, german };

pub fn path(comptime language: Language) []const u8 {
    return switch (language) {
        .automatic => "/v1/listen?model=nova-3&smart_format=true&detect_language=en&detect_language=de&tag=wazig",
        .english => "/v1/listen?model=nova-3&smart_format=true&language=en&tag=wazig",
        .german => "/v1/listen?model=nova-3&smart_format=true&language=de&tag=wazig",
    };
}

pub const Recognition = struct {
    text: []u8,
    language: ?Language,
    confidence: f64,
};

pub fn transcribeSupported(transport: anytype, language: Language, content_type: []const u8, body: []const u8) ![]u8 {
    const result = try transport.recognize(language, content_type, body);
    if (language != .automatic or result.language != null) return result.text;
    transport.allocator.free(result.text);
    const english = transport.recognize(.english, content_type, body) catch |err| if (err == error.NoSpeech) null else return err;
    defer if (english) |value| transport.allocator.free(value.text);
    const german = transport.recognize(.german, content_type, body) catch |err| if (err == error.NoSpeech) null else return err;
    defer if (german) |value| transport.allocator.free(value.text);
    const chosen = if (english) |en|
        if (german) |de| (if (de.confidence > en.confidence) de else en) else en
    else
        german orelse return error.NoSpeech;
    return transport.allocator.dupe(u8, chosen.text);
}

pub fn parseResponse(allocator: std.mem.Allocator, response: []const u8) !Recognition {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();
    const root = switch (parsed.value) {
        .object => |value| value,
        else => return error.BadResponse,
    };
    const results = switch (root.get("results") orelse return error.BadResponse) {
        .object => |value| value,
        else => return error.BadResponse,
    };
    const channels = switch (results.get("channels") orelse return error.BadResponse) {
        .array => |value| value,
        else => return error.BadResponse,
    };
    if (channels.items.len == 0) return error.NoSpeech;
    const channel = switch (channels.items[0]) {
        .object => |value| value,
        else => return error.BadResponse,
    };
    const alternatives = switch (channel.get("alternatives") orelse return error.BadResponse) {
        .array => |value| value,
        else => return error.BadResponse,
    };
    if (alternatives.items.len == 0) return error.NoSpeech;
    const alternative = switch (alternatives.items[0]) {
        .object => |value| value,
        else => return error.BadResponse,
    };
    const transcript = switch (alternative.get("transcript") orelse return error.BadResponse) {
        .string => |value| value,
        else => return error.BadResponse,
    };
    if (transcript.len == 0) return error.NoSpeech;
    const detected = channel.get("detected_language");
    const code = if (detected != null and detected.? == .string) detected.?.string else "";
    const primary = code[0 .. std.mem.indexOfScalar(u8, code, '-') orelse code.len];
    const language: ?Language = if (std.mem.eql(u8, primary, "en")) .english else if (std.mem.eql(u8, primary, "de")) .german else null;
    const score = alternative.get("confidence");
    const confidence: f64 = if (score) |value| switch (value) {
        .float => |number| number,
        .integer => |number| @floatFromInt(number),
        else => 0,
    } else 0;
    return .{ .text = try allocator.dupe(u8, transcript), .language = language, .confidence = confidence };
}

pub fn hasSpeech(wav: []const u8) bool {
    if (wav.len < 12 or !std.mem.eql(u8, wav[0..4], "RIFF") or !std.mem.eql(u8, wav[8..12], "WAVE")) return true;
    const riff_size = std.mem.readInt(u32, wav[4..8], .little);
    if (riff_size < 4 or riff_size > wav.len - 8) return true;
    const end: usize = @as(usize, riff_size) + 8;
    var format: ?[]const u8 = null;
    var data: ?[]const u8 = null;
    var offset: usize = 12;
    while (offset < end) {
        if (end - offset < 8) return true;
        const id = wav[offset..][0..4];
        const size: usize = std.mem.readInt(u32, wav[offset + 4 ..][0..4], .little);
        offset += 8;
        if (size > end - offset) return true;
        const chunk = wav[offset .. offset + size];
        if (std.mem.eql(u8, id, "fmt ")) {
            if (format != null) return true;
            format = chunk;
        } else if (std.mem.eql(u8, id, "data")) {
            if (data != null) return true;
            data = chunk;
        }
        offset += size;
        if (size % 2 != 0) {
            if (offset == end) return true;
            offset += 1;
        }
    }
    const fmt = format orelse return true;
    const samples = data orelse return true;
    if (fmt.len < 16 or fmt.len == 17) return true;
    if (fmt.len >= 18 and std.mem.readInt(u16, fmt[16..18], .little) > fmt.len - 18) return true;
    var tag = std.mem.readInt(u16, fmt[0..2], .little);
    const channels: usize = std.mem.readInt(u16, fmt[2..4], .little);
    const sample_rate = std.mem.readInt(u32, fmt[4..8], .little);
    const block_align: usize = std.mem.readInt(u16, fmt[12..14], .little);
    const bits = std.mem.readInt(u16, fmt[14..16], .little);
    if (tag == 0xfffe) {
        if (fmt.len < 40 or std.mem.readInt(u16, fmt[16..18], .little) < 22) return true;
        if (!std.mem.eql(u8, fmt[26..40], &.{ 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xaa, 0, 0x38, 0x9b, 0x71 })) return true;
        tag = std.mem.readInt(u16, fmt[24..26], .little);
        if (std.mem.readInt(u16, fmt[18..20], .little) != bits) return true;
    }
    if (!((tag == 1 and bits == 16) or (tag == 3 and bits == 32))) return true;
    const sample_bytes: usize = bits / 8;
    if (channels == 0 or sample_rate < 50 or block_align != channels * sample_bytes) return true;
    if (samples.len % block_align != 0) return true;
    const frames_per_window: usize = sample_rate / 50;
    offset = 0;
    while (offset < samples.len) {
        const frames = @min(frames_per_window, (samples.len - offset) / block_align);
        const count = frames * channels;
        var energy: f64 = 0;
        for (0..count) |_| {
            const sample: f64 = if (tag == 1)
                @as(f64, @floatFromInt(std.mem.readInt(i16, samples[offset..][0..2], .little))) / 32768.0
            else
                @as(f32, @bitCast(std.mem.readInt(u32, samples[offset..][0..4], .little)));
            if (!std.math.isFinite(sample)) return true;
            energy += sample * sample;
            offset += sample_bytes;
        }
        if (@sqrt(energy / @as(f64, @floatFromInt(count))) >= 0.002) return true;
    }
    return false;
}

pub fn transcribe(transport: anytype, language: Language, content_type: []const u8, body: []const u8) ![]u8 {
    if (std.mem.eql(u8, content_type, "audio/wav") and !hasSpeech(body)) return error.NoSpeech;
    return transport.send(language, content_type, body);
}

pub const multilingual_path = "/v1/listen?model=nova-3&smart_format=true&language=multi&tag=wazig";

pub fn transcribeFile(transport: anytype, language: Language, content_type: []const u8, body: []const u8) ![]u8 {
    return transcribe(transport, language, content_type, body) catch |err| {
        if (err == error.NoSpeech and language == .automatic and std.mem.eql(u8, content_type, "audio/ogg")) {
            return transport.sendMultilingual(content_type, body);
        }
        return err;
    };
}

pub fn failureText(failure: anyerror) []const u8 {
    return switch (failure) {
        error.NoSpeech => "No speech recognized",
        error.LocalFileUnavailable => "Voice file could not be read",
        error.BadAudio => "Voice audio was rejected",
        error.Unauthorized => "Transcription key rejected",
        error.PaymentRequired => "Transcription credits exhausted",
        error.RateLimited => "Transcription limit reached",
        error.NetworkFailed => "Transcription connection failed",
        error.TranscriptionUnavailable => "Transcription service unavailable",
        else => "Transcription failed",
    };
}

const FakeRecognitionTransport = struct {
    allocator: std.mem.Allocator = std.testing.allocator,
    responses: []const []const u8,
    calls: usize = 0,
    languages: [3]?Language = .{ null, null, null },
    failure_at: ?usize = null,

    pub fn recognize(self: *@This(), language: Language, content_type: []const u8, body: []const u8) !Recognition {
        try std.testing.expectEqualStrings("audio/wav", content_type);
        try std.testing.expectEqualStrings("synthetic recording", body);
        if (self.calls >= self.languages.len) return error.UnexpectedRequest;
        self.languages[self.calls] = language;
        self.calls += 1;
        if (self.failure_at == self.calls) return error.NetworkFailed;
        if (self.calls > self.responses.len) return error.UnexpectedRequest;
        return parseResponse(self.allocator, self.responses[self.calls - 1]);
    }

    pub fn send(self: *@This(), language: Language, content_type: []const u8, body: []const u8) ![]u8 {
        return transcribeSupported(self, language, content_type, body);
    }
};

fn recognitionResponse(comptime language: []const u8, comptime text: []const u8, comptime confidence: []const u8) []const u8 {
    return "{\"results\":{\"channels\":[{\"detected_language\":" ++ language ++ ",\"alternatives\":[{\"transcript\":\"" ++ text ++ "\",\"confidence\":" ++ confidence ++ "}]}]}}";
}

test "automatic dictation accepts only English and German detection without retry" {
    inline for (.{ "\"en\"", "\"de\"", "\"en-GB\"", "\"de-CH\"" }) |language| {
        var transport: FakeRecognitionTransport = .{ .responses = &.{recognitionResponse(language, "recognized speech", "0.9")} };
        const text = try transcribe(&transport, .automatic, "audio/wav", "synthetic recording");
        defer transport.allocator.free(text);
        try std.testing.expectEqualStrings("recognized speech", text);
        try std.testing.expectEqual(@as(usize, 1), transport.calls);
        try std.testing.expectEqual(Language.automatic, transport.languages[0].?);
    }
}

test "unsupported or missing automatic language chooses the better English or German recognition" {
    inline for (.{
        recognitionResponse("\"tr\"", "unsupported transcript", "0.99"),
        recognitionResponse("\"fr\"", "unsupported transcript", "0.99"),
        recognitionResponse("null", "unsupported transcript", "0.99"),
        "{\"results\":{\"channels\":[{\"alternatives\":[{\"transcript\":\"unsupported transcript\"}]}]}}",
    }) |response| {
        inline for (.{ false, true }) |prefer_german| {
            var transport: FakeRecognitionTransport = .{ .responses = &.{
                response,
                recognitionResponse("null", "English result", if (prefer_german) "0.4" else "0.9"),
                recognitionResponse("null", "German result", if (prefer_german) "0.9" else "0.4"),
            } };
            const text = try transcribe(&transport, .automatic, "audio/wav", "synthetic recording");
            defer transport.allocator.free(text);
            try std.testing.expectEqualStrings(if (prefer_german) "German result" else "English result", text);
            try std.testing.expectEqualSlices(?Language, &.{ .automatic, .english, .german }, &transport.languages);
            try std.testing.expectEqual(@as(usize, 3), transport.calls);
        }
    }
}

test "fixed dictation languages preserve their response without detection or retry" {
    for ([_]Language{ .english, .german }) |language| {
        var transport: FakeRecognitionTransport = .{ .responses = &.{recognitionResponse("null", "fixed result", "1")} };
        const text = try transcribe(&transport, language, "audio/wav", "synthetic recording");
        defer transport.allocator.free(text);
        try std.testing.expectEqualStrings("fixed result", text);
        try std.testing.expectEqual(@as(usize, 1), transport.calls);
        try std.testing.expectEqual(language, transport.languages[0].?);
    }
}

test "automatic fallback handles empty candidates and ties without leaking unsupported text" {
    inline for (.{ false, true }) |empty_english| {
        var transport: FakeRecognitionTransport = .{ .responses = &.{
            recognitionResponse("\"tr\"", "unsupported transcript", "1"),
            recognitionResponse("null", if (empty_english) "" else "English result", "0.5"),
            recognitionResponse("null", if (empty_english) "German result" else "", "0.5"),
        } };
        const text = try transcribe(&transport, .automatic, "audio/wav", "synthetic recording");
        defer transport.allocator.free(text);
        try std.testing.expectEqualStrings(if (empty_english) "German result" else "English result", text);
    }
    var tie: FakeRecognitionTransport = .{ .responses = &.{
        recognitionResponse("\"tr\"", "unsupported transcript", "1"),
        recognitionResponse("null", "English result", "0.5"),
        recognitionResponse("null", "German result", "0.5"),
    } };
    const text = try transcribe(&tie, .automatic, "audio/wav", "synthetic recording");
    defer tie.allocator.free(text);
    try std.testing.expectEqualStrings("English result", text);
    var empty: FakeRecognitionTransport = .{ .responses = &.{
        recognitionResponse("\"tr\"", "unsupported transcript", "1"),
        recognitionResponse("null", "", "0"),
        recognitionResponse("null", "", "0"),
    } };
    try std.testing.expectError(error.NoSpeech, transcribe(&empty, .automatic, "audio/wav", "synthetic recording"));
}

test "automatic fallback propagates network errors and malformed responses" {
    for (1..4) |attempt| {
        var transport: FakeRecognitionTransport = .{
            .responses = &.{
                recognitionResponse("\"tr\"", "unsupported transcript", "1"),
                recognitionResponse("null", "English result", "0.5"),
                recognitionResponse("null", "German result", "0.5"),
            },
            .failure_at = attempt,
        };
        try std.testing.expectError(error.NetworkFailed, transcribe(&transport, .automatic, "audio/wav", "synthetic recording"));
        try std.testing.expectEqual(attempt, transport.calls);
    }
    var malformed: FakeRecognitionTransport = .{ .responses = &.{"{}"} };
    try std.testing.expectError(error.BadResponse, transcribe(&malformed, .automatic, "audio/wav", "synthetic recording"));
    try std.testing.expectEqual(@as(usize, 1), malformed.calls);
}

const FakeTransport = struct {
    calls: usize = 0,
    multilingual_calls: usize = 0,
    multilingual_failure: ?error{ NoSpeech, NetworkFailed } = null,
    failure: ?error{ NoSpeech, NetworkFailed } = null,
    language: ?Language = null,
    content_type: []const u8 = "",
    body: []const u8 = "",
    response: [4]u8 = .{ 't', 'e', 's', 't' },

    pub fn send(self: *FakeTransport, language: Language, content_type: []const u8, body: []const u8) ![]u8 {
        self.calls += 1;
        self.language = language;
        self.content_type = content_type;
        self.body = body;
        if (self.failure) |err| return err;
        return &self.response;
    }

    pub fn sendMultilingual(self: *FakeTransport, content_type: []const u8, body: []const u8) ![]u8 {
        self.multilingual_calls += 1;
        self.content_type = content_type;
        self.body = body;
        if (self.multilingual_failure) |err| return err;
        return &self.response;
    }
};

fn testWav(tag: u16, channels: u16, format_size: usize, amplitude: f64) ![]u8 {
    const sample_bytes: usize = if (tag == 1) 2 else 4;
    const size = 4800 * @as(usize, channels) * sample_bytes;
    const wav = try std.testing.allocator.alloc(u8, 28 + format_size + size);
    @memset(wav, 0);
    @memcpy(wav[0..4], "RIFF");
    std.mem.writeInt(u32, wav[4..8], @intCast(wav.len - 8), .little);
    @memcpy(wav[8..16], "WAVEfmt ");
    std.mem.writeInt(u32, wav[16..20], @intCast(format_size), .little);
    std.mem.writeInt(u16, wav[20..22], if (format_size >= 40) 0xfffe else tag, .little);
    std.mem.writeInt(u16, wav[22..24], channels, .little);
    std.mem.writeInt(u32, wav[24..28], 48000, .little);
    std.mem.writeInt(u32, wav[28..32], @intCast(48000 * @as(usize, channels) * sample_bytes), .little);
    std.mem.writeInt(u16, wav[32..34], @intCast(channels * sample_bytes), .little);
    std.mem.writeInt(u16, wav[34..36], @intCast(sample_bytes * 8), .little);
    if (format_size >= 18) std.mem.writeInt(u16, wav[36..38], @intCast(format_size - 18), .little);
    if (format_size >= 40) {
        std.mem.writeInt(u16, wav[38..40], @intCast(sample_bytes * 8), .little);
        std.mem.writeInt(u16, wav[44..46], tag, .little);
        @memcpy(wav[46..60], &[_]u8{ 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xaa, 0, 0x38, 0x9b, 0x71 });
    }
    const data_offset = 20 + format_size;
    @memcpy(wav[data_offset..][0..4], "data");
    std.mem.writeInt(u32, wav[data_offset + 4 ..][0..4], @intCast(size), .little);
    for (0..4800) |frame| {
        const sample = amplitude * @sin(2 * std.math.pi * 440 * @as(f64, @floatFromInt(frame)) / 48000);
        for (0..channels) |channel| {
            const offset = data_offset + 8 + (frame * channels + channel) * sample_bytes;
            if (tag == 1) {
                std.mem.writeInt(i16, wav[offset..][0..2], @intFromFloat(sample * 32767), .little);
            } else {
                std.mem.writeInt(u32, wav[offset..][0..4], @bitCast(@as(f32, @floatCast(sample))), .little);
            }
        }
    }
    return wav;
}

test "silent PCM16 WAV makes zero requests in every language" {
    const wav = try testWav(1, 1, 16, 0);
    defer std.testing.allocator.free(wav);
    for (std.enums.values(Language)) |language| {
        var transport: FakeTransport = .{};
        try std.testing.expectError(error.NoSpeech, transcribe(&transport, language, "audio/wav", wav));
        try std.testing.expectEqual(@as(usize, 0), transport.calls);
    }
}

test "zero-padded extensible float32 microphone WAV makes zero requests" {
    const wav = try testWav(3, 2, 40, 0);
    defer std.testing.allocator.free(wav);
    @memset(wav[68..], 0);
    var transport: FakeTransport = .{};
    try std.testing.expectError(error.NoSpeech, transcribe(&transport, .automatic, "audio/wav", wav));
    try std.testing.expectEqual(@as(usize, 0), transport.calls);
}

test "automatic NoSpeech answer makes exactly one request without retry" {
    const wav = try testWav(1, 1, 16, 0.1);
    defer std.testing.allocator.free(wav);
    var transport: FakeTransport = .{ .failure = error.NoSpeech };
    try std.testing.expectError(error.NoSpeech, transcribe(&transport, .automatic, "audio/wav", wav));
    try std.testing.expectEqual(@as(usize, 1), transport.calls);
    try std.testing.expectEqual(Language.automatic, transport.language.?);
}

test "speech-like PCM16 and float32 WAVs make one request" {
    for ([_]u16{ 1, 3 }) |tag| {
        for ([_]usize{ 16, 18, 40 }) |format_size| {
            const wav = try testWav(tag, 3, format_size, 0.1);
            defer std.testing.allocator.free(wav);
            var transport: FakeTransport = .{};
            try std.testing.expectEqualStrings("test", try transcribe(&transport, .german, "audio/wav", wav));
            try std.testing.expectEqual(@as(usize, 1), transport.calls);
            try std.testing.expectEqual(Language.german, transport.language.?);
            try std.testing.expectEqualStrings("audio/wav", transport.content_type);
            try std.testing.expectEqualSlices(u8, wav, transport.body);
        }
    }
}

test "noise near minus 70 dBFS makes zero requests" {
    for ([_]u16{ 1, 3 }) |tag| {
        const wav = try testWav(tag, 2, 16, 0.000447);
        defer std.testing.allocator.free(wav);
        var transport: FakeTransport = .{};
        try std.testing.expectError(error.NoSpeech, transcribe(&transport, .english, "audio/wav", wav));
        try std.testing.expectEqual(@as(usize, 0), transport.calls);
    }
}

test "unknown WAV format is sent once fail open" {
    const wav = try testWav(1, 1, 16, 0);
    defer std.testing.allocator.free(wav);
    std.mem.writeInt(u16, wav[20..22], 7, .little);
    var transport: FakeTransport = .{};
    _ = try transcribe(&transport, .automatic, "audio/wav", wav);
    try std.testing.expectEqual(@as(usize, 1), transport.calls);
}

test "Ogg bypasses WAV energy checks and is sent once" {
    const wav = try testWav(1, 1, 16, 0);
    defer std.testing.allocator.free(wav);
    var transport: FakeTransport = .{};
    _ = try transcribe(&transport, .english, "audio/ogg", wav);
    try std.testing.expectEqual(@as(usize, 1), transport.calls);
    try std.testing.expectEqualStrings("audio/ogg", transport.content_type);
}

test "all request paths preserve language and model settings and end with wazig tag" {
    inline for (std.enums.values(Language)) |language| {
        try std.testing.expect(std.mem.startsWith(u8, path(language), "/v1/listen?model=nova-3&smart_format=true&"));
        try std.testing.expect(std.mem.endsWith(u8, path(language), "&tag=wazig"));
        try std.testing.expect(std.mem.indexOf(u8, path(language), "language=multi") == null);
    }
    try std.testing.expectEqualStrings("/v1/listen?model=nova-3&smart_format=true&detect_language=en&detect_language=de&tag=wazig", path(.automatic));
    try std.testing.expectEqualStrings("/v1/listen?model=nova-3&smart_format=true&language=en&tag=wazig", path(.english));
    try std.testing.expectEqualStrings("/v1/listen?model=nova-3&smart_format=true&language=de&tag=wazig", path(.german));
}

test "RIFF walker handles odd padded chunks and data before extended fmt" {
    const original = try testWav(1, 2, 40, 0);
    defer std.testing.allocator.free(original);
    const wav = try std.testing.allocator.alloc(u8, original.len + 10);
    defer std.testing.allocator.free(wav);
    @memcpy(wav[0..12], original[0..12]);
    std.mem.writeInt(u32, wav[4..8], @intCast(wav.len - 8), .little);
    @memcpy(wav[12..16], "JUNK");
    std.mem.writeInt(u32, wav[16..20], 1, .little);
    @memset(wav[20..22], 0xff);
    const data_len = original.len - 60;
    @memcpy(wav[22 .. 22 + data_len], original[60..]);
    @memcpy(wav[22 + data_len ..], original[12..60]);
    try std.testing.expect(!hasSpeech(wav));
    std.mem.writeInt(i16, wav[30..32], 32767, .little);
    try std.testing.expect(hasSpeech(wav));
}

test "empty data is quiet and final partial window uses all channels" {
    const wav = try testWav(3, 2, 18, 0);
    defer std.testing.allocator.free(wav);
    std.mem.writeInt(u32, wav[4..8], 38, .little);
    std.mem.writeInt(u32, wav[42..46], 0, .little);
    try std.testing.expect(!hasSpeech(wav[0..46]));
    std.mem.writeInt(u32, wav[4..8], 46, .little);
    std.mem.writeInt(u32, wav[42..46], 8, .little);
    std.mem.writeInt(u32, wav[50..54], @bitCast(@as(f32, 0.004)), .little);
    try std.testing.expect(hasSpeech(wav[0..54]));
    for ([_]f32{ 0.00199, 0.002 }) |level| {
        std.mem.writeInt(u32, wav[46..50], @bitCast(level), .little);
        std.mem.writeInt(u32, wav[50..54], @bitCast(level), .little);
        try std.testing.expectEqual(level >= 0.002, hasSpeech(wav[0..54]));
    }
    std.mem.writeInt(u32, wav[4..8], @intCast(wav.len - 8), .little);
    std.mem.writeInt(u32, wav[42..46], @intCast(wav.len - 46), .little);
    @memset(wav[46..], 0);
    for (0..960) |frame| {
        std.mem.writeInt(u32, wav[46 + frame * 8 ..][0..4], @bitCast(@as(f32, 0.004)), .little);
    }
    try std.testing.expect(hasSpeech(wav));
}

test "malformed and unsupported WAVs fail open without dropping recordings" {
    const wav = try testWav(3, 2, 40, 0);
    defer std.testing.allocator.free(wav);
    for (0..wav.len) |length| try std.testing.expect(hasSpeech(wav[0..length]));
    for ([_]usize{ 0, 8, 12, 16, 20, 22, 32, 34, 36, 38, 44, 46, 60, 64 }) |offset| {
        const saved = wav[offset];
        wav[offset] = 0xff;
        try std.testing.expect(hasSpeech(wav));
        wav[offset] = saved;
    }
    std.mem.writeInt(u32, wav[68..72], @bitCast(std.math.nan(f32)), .little);
    try std.testing.expect(hasSpeech(wav));
}

test "transport errors other than NoSpeech also propagate without retry" {
    var transport: FakeTransport = .{ .failure = error.NetworkFailed };
    try std.testing.expectError(error.NetworkFailed, transcribe(&transport, .automatic, "audio/ogg", "OggS"));
    try std.testing.expectEqual(@as(usize, 1), transport.calls);
}

test "ISSUE-517 stored own Ogg falls back after empty automatic recognition" {
    var transport: FakeTransport = .{ .failure = error.NoSpeech };
    try std.testing.expectEqualStrings("test", try transcribeFile(&transport, .automatic, "audio/ogg", "OggS"));
    try std.testing.expectEqual(@as(usize, 1), transport.calls);
    try std.testing.expectEqual(@as(usize, 1), transport.multilingual_calls);
    try std.testing.expectEqualStrings("audio/ogg", transport.content_type);
    try std.testing.expectEqualStrings("OggS", transport.body);
    try std.testing.expectEqualStrings("/v1/listen?model=nova-3&smart_format=true&language=multi&tag=wazig", multilingual_path);
}

test "ISSUE-517 stored voice fallback never retries success network errors or fixed languages" {
    var success: FakeTransport = .{};
    _ = try transcribeFile(&success, .automatic, "audio/ogg", "OggS");
    try std.testing.expectEqual(@as(usize, 0), success.multilingual_calls);
    var network: FakeTransport = .{ .failure = error.NetworkFailed };
    try std.testing.expectError(error.NetworkFailed, transcribeFile(&network, .automatic, "audio/ogg", "OggS"));
    try std.testing.expectEqual(@as(usize, 0), network.multilingual_calls);
    for ([_]Language{ .english, .german }) |language| {
        var selected: FakeTransport = .{ .failure = error.NoSpeech };
        try std.testing.expectError(error.NoSpeech, transcribeFile(&selected, language, "audio/ogg", "OggS"));
        try std.testing.expectEqual(@as(usize, 0), selected.multilingual_calls);
    }
    var microphone: FakeTransport = .{ .failure = error.NoSpeech };
    try std.testing.expectError(error.NoSpeech, transcribeFile(&microphone, .automatic, "audio/wav", "RIFF"));
    try std.testing.expectEqual(@as(usize, 0), microphone.multilingual_calls);
    var empty: FakeTransport = .{ .failure = error.NoSpeech, .multilingual_failure = error.NoSpeech };
    try std.testing.expectError(error.NoSpeech, transcribeFile(&empty, .automatic, "audio/ogg", "OggS"));
    try std.testing.expectEqual(@as(usize, 1), empty.multilingual_calls);
    try std.testing.expectEqualStrings("No speech recognized", failureText(error.NoSpeech));
    try std.testing.expectEqualStrings("Voice file could not be read", failureText(error.LocalFileUnavailable));
    try std.testing.expectEqualStrings("Transcription key rejected", failureText(error.Unauthorized));
    try std.testing.expectEqualStrings("Transcription limit reached", failureText(error.RateLimited));
    try std.testing.expectEqualStrings("Transcription connection failed", failureText(error.NetworkFailed));
    try std.testing.expectEqualStrings("Transcription failed", failureText(error.ApiFailed));
}

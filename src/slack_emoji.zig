const std = @import("std");
const data = @embedFile("slack_emoji.tsv");

pub const Resolver = struct {
    context: *anyopaque,
    resolve: *const fn (*anyopaque, []const u8) ?[]const u8,
};

pub fn standard(name: []const u8) ?[]const u8 {
    var lo: usize = 0;
    var hi: usize = data.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const start = if (std.mem.lastIndexOfScalar(u8, data[lo..mid], '\n')) |end| lo + end + 1 else lo;
        const end = start + (std.mem.indexOfScalar(u8, data[start..], '\n') orelse return null);
        const tab = start + (std.mem.indexOfScalar(u8, data[start..end], '\t') orelse return null);
        switch (std.mem.order(u8, name, data[start..tab])) {
            .eq => return data[tab + 1 .. end],
            .lt => hi = start,
            .gt => lo = end + 1,
        }
    }
    return null;
}

pub fn customName(emoji: std.json.ObjectMap, original: []const u8) ?[]const u8 {
    var name = original;
    for (0..32) |_| {
        if (standard(name) != null) return name;
        const value = emoji.get(name) orelse return null;
        if (value != .string) return null;
        if (std.mem.startsWith(u8, value.string, "alias:")) {
            name = value.string[6..];
        } else return if (std.mem.startsWith(u8, value.string, "https://") or std.mem.startsWith(u8, value.string, "http://")) name else null;
    }
    return null;
}

pub const Token = struct { start: usize, end: usize, name: []const u8 };

pub fn next(text: []const u8, from: usize) ?Token {
    var start = from;
    while (start < text.len) : (start += 1) {
        if (std.mem.startsWith(u8, text[start..], "https://") or std.mem.startsWith(u8, text[start..], "http://")) {
            while (start < text.len and !std.ascii.isWhitespace(text[start]) and text[start] != '|' and text[start] != '>') start += 1;
            if (start == text.len) return null;
            continue;
        }
        if (text[start] != ':') continue;
        var end = start + 1;
        while (end < text.len and end - start <= 192) : (end += 1) {
            const c = text[end];
            if (c == ':') {
                if (end > start + 1) return .{ .start = start, .end = end + 1, .name = text[start + 1 .. end] };
                break;
            }
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '+') break;
        }
    }
    return null;
}

pub fn replace(buffer: []u8, text: []const u8, custom: ?Resolver) []const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    var cursor: usize = 0;
    while (next(text, cursor)) |token| {
        writer.writeAll(text[cursor..token.start]) catch break;
        var end = token.end;
        var name_buffer: [256]u8 = undefined;
        var name = token.name;
        var emoji = standard(name);
        while (end < text.len) {
            const tone = next(text, end) orelse break;
            if (tone.start != end or !std.mem.startsWith(u8, tone.name, "skin-tone-")) break;
            const combined = std.fmt.bufPrint(&name_buffer, "{s}::{s}", .{ text[token.start + 1 .. end - 1], tone.name }) catch break;
            const toned = standard(combined) orelse break;
            name = combined;
            emoji = toned;
            end = tone.end;
        }
        if (emoji == null) if (custom) |resolver| {
            emoji = resolver.resolve(resolver.context, name);
        };
        writer.writeAll(emoji orelse text[token.start..end]) catch break;
        cursor = end;
    }
    writer.writeAll(text[cursor..]) catch {};
    return buffer[0..writer.end];
}

test "IGSH-670 standard aliases skin tones adjacent pairs and unknown" {
    var buffer: [512]u8 = undefined;
    try std.testing.expectEqualStrings("💔⏲️🧢🤞😢🍵", replace(&buffer, ":broken_heart::timer_clock::billed_cap::crossed_fingers::cry::tea:", null));
    try std.testing.expectEqualStrings("👍🏻 👍🏿", replace(&buffer, ":thumbsup::skin-tone-2: :+1::skin-tone-6:", null));
    try std.testing.expectEqualStrings("❤️", replace(&buffer, ":heart:", null));
    try std.testing.expectEqualStrings("<https://example.invalid/:tea:|💔> https://example.invalid/:tea:", replace(&buffer, "<https://example.invalid/:tea:|:broken_heart:> https://example.invalid/:tea:", null));
    try std.testing.expectEqualStrings(":unknown_fixture: :thumbsup_extra:", replace(&buffer, ":unknown_fixture: :thumbsup_extra:", null));
}

test "IGSH-670 custom resolver preserves unknown" {
    const Custom = struct {
        fn resolve(_: *anyopaque, name: []const u8) ?[]const u8 {
            return if (std.mem.eql(u8, name, "fixture_custom")) "\u{e000}" else null;
        }
    };
    var context: u8 = 0;
    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings("\u{e000} :unknown_fixture:", replace(&buffer, ":fixture_custom: :unknown_fixture:", .{ .context = &context, .resolve = Custom.resolve }));
}

test "IGSH-670 custom aliases standard targets unknown names and cycles" {
    const raw =
        \\{"fixture":"https://example.invalid/image.png","fixture_alias":"alias:fixture","fixture_standard":"alias:tea","cycle_a":"alias:cycle_b","cycle_b":"alias:cycle_a"}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
    defer parsed.deinit();
    const emoji = parsed.value.object;
    try std.testing.expectEqualStrings("fixture", customName(emoji, "fixture_alias").?);
    try std.testing.expectEqualStrings("tea", customName(emoji, "fixture_standard").?);
    try std.testing.expect(customName(emoji, "unknown_fixture") == null);
    try std.testing.expect(customName(emoji, "cycle_a") == null);
}

test "IGSH-670 every generated standard name resolves exactly" {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const tab = std.mem.indexOfScalar(u8, line, '\t').?;
        try std.testing.expectEqualStrings(line[tab + 1 ..], standard(line[0..tab]).?);
        try std.testing.expect(std.unicode.utf8ValidateSlice(line[tab + 1 ..]));
    }
}

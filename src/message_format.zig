const std = @import("std");

pub const Style = packed struct(u8) {
    bold: bool = false,
    italic: bool = false,
    strike: bool = false,
    mono: bool = false,
    quote: bool = false,
    block: bool = false,
    footer: bool = false,
    reserved: bool = false,
};

pub const Parsed = struct {
    text: [4095]u16 = undefined,
    styles: [4095]Style = undefined,
    source: [4095]u16 = undefined,
    len: usize = 0,

    fn append(self: *Parsed, unit: u16, style: Style, source: usize) void {
        if (self.len == self.text.len) return;
        self.text[self.len] = unit;
        self.styles[self.len] = style;
        self.source[self.len] = @intCast(source);
        self.len += 1;
    }
};

fn space(unit: u16) bool {
    return unit == ' ' or unit == '\n' or unit == '\r' or unit == '\t';
}

fn word(unit: u16) bool {
    return (unit >= 'a' and unit <= 'z') or (unit >= 'A' and unit <= 'Z') or (unit >= '0' and unit <= '9');
}

pub fn parse(input: []const u16, slack: bool) Parsed {
    var result = Parsed{};
    var style = Style{};
    var ends: [3]?usize = @splat(null);
    var index: usize = 0;
    var line_start = true;
    while (index < input.len) {
        if (line_start) {
            style.quote = false;
            if (!style.block and input[index] == '>' and (index + 1 == input.len or space(input[index + 1]))) {
                style.quote = true;
                index += 1;
                if (index < input.len and input[index] == ' ') index += 1;
                if (index == input.len) break;
            }
            if (slack and std.mem.startsWith(u16, input[index..], &.{ '`', '`', '`' })) {
                const rest = input[index + 3 ..];
                const end = std.mem.indexOfScalar(u16, rest, '\n') orelse rest.len;
                if (style.block or std.mem.indexOf(u16, rest[0..end], &.{ '`', '`', '`' }) == null) {
                    style.block = !style.block;
                    style.mono = style.block;
                    index += 3 + end;
                    if (index < input.len) index += 1;
                    continue;
                }
            }
            line_start = false;
        }
        const unit = input[index];
        if (unit == '\r') {
            index += 1;
            continue;
        }
        if (unit == '\n') {
            result.append(unit, style, index);
            line_start = true;
            style.bold = false;
            style.italic = false;
            style.strike = false;
            ends = @splat(null);
            index += 1;
            continue;
        }
        if (!style.block and unit == '`') {
            const count: usize = if (std.mem.startsWith(u16, input[index..], &.{ '`', '`', '`' })) 3 else 1;
            if (std.mem.indexOf(u16, input[index + count ..], input[index .. index + count])) |offset| {
                const end = index + count + offset;
                var code_style = style;
                code_style.mono = true;
                while (index + count < end) {
                    result.append(input[index + count], code_style, index + count);
                    index += 1;
                }
                index = end + count;
                continue;
            }
        }
        if (!style.block) {
            const slot: ?usize = switch (unit) {
                '*' => 0,
                '_' => 1,
                '~' => 2,
                else => null,
            };
            if (slot) |s| {
                if (ends[s] != null and ends[s].? == index) {
                    switch (s) {
                        0 => style.bold = false,
                        1 => style.italic = false,
                        2 => style.strike = false,
                        else => unreachable,
                    }
                    ends[s] = null;
                    index += 1;
                    continue;
                }
                if (ends[s] == null and index + 1 < input.len and !space(input[index + 1]) and (index == 0 or !word(input[index - 1]))) {
                    var close = index + 1;
                    while (close < input.len and input[close] != '\n') : (close += 1) {
                        if (input[close] != unit or space(input[close - 1])) continue;
                        if (close + 1 < input.len and word(input[close + 1])) continue;
                        ends[s] = close;
                        switch (s) {
                            0 => style.bold = true,
                            1 => style.italic = true,
                            2 => style.strike = true,
                            else => unreachable,
                        }
                        break;
                    }
                    if (ends[s] != null) {
                        index += 1;
                        continue;
                    }
                }
            }
        }
        result.append(unit, style, index);
        index += 1;
    }
    var start: usize = 0;
    while (start < result.len) {
        const end = std.mem.indexOfScalarPos(u16, result.text[0..result.len], start, '\n') orelse result.len;
        if (std.mem.startsWith(u16, result.text[start..end], std.unicode.utf8ToUtf16LeStringLiteral("Sent using "))) {
            for (result.styles[start..end]) |*entry| entry.footer = true;
        }
        start = end + 1;
    }
    return result;
}

test "IGSH-1120 source marks become style runs without changing source offsets" {
    const input = std.unicode.utf8ToUtf16LeStringLiteral("*bold* _italic_ ~gone~ `*code*`\n> *Traffic* 2,124\n>\n> next\nSent using Claude");
    const parsed = parse(input, true);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("bold italic gone *code*\nTraffic 2,124\n\nnext\nSent using Claude"), parsed.text[0..parsed.len]);
    try std.testing.expect(parsed.styles[0].bold);
    try std.testing.expect(parsed.styles[5].italic);
    try std.testing.expect(parsed.styles[12].strike);
    try std.testing.expect(parsed.styles[17].mono);
    try std.testing.expect(parsed.styles[24].quote);
    try std.testing.expect(parsed.styles[parsed.len - 1].footer);
    for (parsed.text[0..parsed.len], parsed.source[0..parsed.len]) |unit, source| try std.testing.expectEqual(input[source], unit);
}

test "IGSH-1120 literal marks, nested styles, fenced and WhatsApp monospace survive" {
    const literal = std.unicode.utf8ToUtf16LeStringLiteral("file_name unmatched * and 2 * 3\n\n- list\n1. next");
    const plain = parse(literal, false);
    try std.testing.expectEqualSlices(u16, literal, plain.text[0..plain.len]);
    const nested = parse(std.unicode.utf8ToUtf16LeStringLiteral("*bold _both_*"), true);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("bold both"), nested.text[0..nested.len]);
    try std.testing.expect(nested.styles[6].bold and nested.styles[6].italic);
    const block = parse(std.unicode.utf8ToUtf16LeStringLiteral("```zig\n*literal*\n```\nafter"), true);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("*literal*\nafter"), block.text[0..block.len]);
    try std.testing.expect(block.styles[0].block and block.styles[0].mono);
    try std.testing.expect(!block.styles[block.len - 1].mono);
    const mono = parse(std.unicode.utf8ToUtf16LeStringLiteral("before ```*literal*``` after"), false);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("before *literal* after"), mono.text[0..mono.len]);
    try std.testing.expect(mono.styles[7].mono and !mono.styles[7].bold);
}

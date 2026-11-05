const std = @import("std");

pub const max_title_bytes = 120;
pub const max_body_bytes = 400;
pub const max_xml_bytes = 4096;

const head = "<toast><visual><binding template=\"ToastGeneric\"><text>";
const middle = "</text><text>";
const tail = "</text></binding></visual></toast>";

pub fn clip(text: []const u8, max: usize) []const u8 {
    if (text.len <= max) return text;
    var end = max;
    while (end > 0 and (text[end] & 0xC0) == 0x80) end -= 1;
    return text[0..end];
}

fn put(out: []u8, used: *usize, text: []const u8) bool {
    if (used.* + text.len > out.len) return false;
    @memcpy(out[used.*..][0..text.len], text);
    used.* += text.len;
    return true;
}

fn putEscaped(out: []u8, used: *usize, text: []const u8) bool {
    for (text) |byte| {
        const ok = switch (byte) {
            '&' => put(out, used, "&amp;"),
            '<' => put(out, used, "&lt;"),
            '>' => put(out, used, "&gt;"),
            '"' => put(out, used, "&quot;"),
            '\'' => put(out, used, "&apos;"),
            '\t', '\n', '\r' => put(out, used, " "),
            0...8, 11, 12, 14...31, 127 => true,
            else => put(out, used, &.{byte}),
        };
        if (!ok) return false;
    }
    return true;
}

pub fn build(out: []u8, title: []const u8, body: []const u8) ?[]const u8 {
    var used: usize = 0;
    if (!put(out, &used, head)) return null;
    if (!putEscaped(out, &used, clip(title, max_title_bytes))) return null;
    if (!put(out, &used, middle)) return null;
    if (!putEscaped(out, &used, clip(body, max_body_bytes))) return null;
    if (!put(out, &used, tail)) return null;
    return out[0..used];
}

test "IGSH-1737 the alert text is escaped so Windows accepts the markup" {
    var buffer: [max_xml_bytes]u8 = undefined;
    const xml = build(&buffer, "Tom & Jerry <3", "say \"hi\" it's > ok").?;
    try std.testing.expectEqualStrings(
        "<toast><visual><binding template=\"ToastGeneric\"><text>Tom &amp; Jerry &lt;3</text><text>say &quot;hi&quot; it&apos;s &gt; ok</text></binding></visual></toast>",
        xml,
    );
}

test "IGSH-1737 control characters never reach the markup" {
    var buffer: [max_xml_bytes]u8 = undefined;
    const xml = build(&buffer, "a\x00b\x07c", "line one\nline two\ttab\x7f").?;
    try std.testing.expect(std.mem.indexOf(u8, xml, "<text>abc</text>") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "line one line two tab</text>") != null);
}

test "IGSH-1737 long text is cut on a character boundary" {
    var buffer: [max_xml_bytes]u8 = undefined;
    var long: [max_body_bytes + 8]u8 = undefined;
    @memset(&long, 'x');
    long[max_body_bytes - 1] = 0xC3;
    long[max_body_bytes] = 0xA9;
    const clipped = clip(&long, max_body_bytes);
    try std.testing.expectEqual(@as(usize, max_body_bytes - 1), clipped.len);
    const xml = build(&buffer, "t", &long).?;
    try std.testing.expect(std.unicode.utf8ValidateSlice(xml));
}

test "IGSH-1737 an output buffer that is too small fails instead of truncating" {
    var tiny: [20]u8 = undefined;
    try std.testing.expect(build(&tiny, "a", "b") == null);
}

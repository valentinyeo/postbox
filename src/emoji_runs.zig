pub const Run = struct { start: usize, len: usize, emoji: bool };
pub const max_runs = 128;

pub fn isEmojiCodepoint(cp: u21) bool {
    return (cp >= 0xE000 and cp <= 0xF8FF) or
        (cp >= 0x1F000 and cp <= 0x1FAFF) or
        (cp >= 0xE0020 and cp <= 0xE007F) or
        (cp >= 0x2600 and cp <= 0x27BF) or
        (cp >= 0x2B00 and cp <= 0x2BFF) or
        cp == 0xFE0F or cp == 0x200D or cp == 0x20E3 or
        cp == 0x00A9 or cp == 0x00AE or cp == 0x2122;
}

pub const TextUnit = struct { emoji: bool, len: usize };

pub fn emojiUnitAt(text: []const u16, index: usize) TextUnit {
    const unit = text[index];
    if (unit >= 0xD800 and unit <= 0xDBFF and index + 1 < text.len) {
        const low = text[index + 1];
        if (low >= 0xDC00 and low <= 0xDFFF) {
            const cp: u21 = 0x10000 + ((@as(u21, unit) - 0xD800) << 10) + (@as(u21, low) - 0xDC00);
            return .{ .emoji = isEmojiCodepoint(cp), .len = 2 };
        }
    }
    return .{ .emoji = isEmojiCodepoint(unit), .len = 1 };
}


pub fn splitRuns(text: []const u16, runs: []Run) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (index < text.len) {
        const emoji = emojiUnitAt(text, index).emoji;
        const start = index;
        while (index < text.len) {
            const unit = text[index];
            const current = emojiUnitAt(text, index);
            const glue = unit == 0x200D or unit == 0xFE0F or unit == 0x20E3;
            if (current.emoji != emoji and !glue) break;
            index += current.len;
        }
        if (count >= runs.len) break;
        runs[count] = .{ .start = start, .len = index - start, .emoji = emoji };
        count += 1;
    }
    return count;
}

pub fn containsEmoji(text: []const u16) bool {
    var index: usize = 0;
    while (index < text.len) {
        const current = emojiUnitAt(text, index);
        if (current.emoji) return true;
        index += current.len;
    }
    return false;
}

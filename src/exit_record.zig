const std = @import("std");

pub const Reason = enum { wm_close, update };

pub const Record = struct {
    at: i64 = 0,
    version: []const u8 = "",
    reason: Reason = .wm_close,
    uptime_seconds: u64 = 0,
    code: u32 = 0,
};

pub fn reasonName(reason: Reason) []const u8 {
    return @tagName(reason);
}

pub fn format(out: []u8, record: Record) ![]const u8 {
    return std.fmt.bufPrint(out, "at={d} version={s} reason={s} uptime={d} code={d}\n", .{
        record.at,
        record.version,
        reasonName(record.reason),
        record.uptime_seconds,
        record.code,
    });
}

pub fn parse(text: []const u8) ?Record {
    var record = Record{};
    var has_reason = false;
    var fields = std.mem.tokenizeScalar(u8, std.mem.trim(u8, text, " \t\r\n"), ' ');
    while (fields.next()) |field| {
        const separator = std.mem.indexOfScalar(u8, field, '=') orelse return null;
        const key = field[0..separator];
        const value = field[separator + 1 ..];
        if (std.mem.eql(u8, key, "at")) {
            record.at = std.fmt.parseInt(i64, value, 10) catch return null;
        } else if (std.mem.eql(u8, key, "version")) {
            record.version = value;
        } else if (std.mem.eql(u8, key, "reason")) {
            record.reason = std.meta.stringToEnum(Reason, value) orelse return null;
            has_reason = true;
        } else if (std.mem.eql(u8, key, "uptime")) {
            record.uptime_seconds = std.fmt.parseInt(u64, value, 10) catch return null;
        } else if (std.mem.eql(u8, key, "code")) {
            record.code = std.fmt.parseInt(u32, value, 10) catch return null;
        } else return null;
    }
    if (!has_reason or record.version.len == 0) return null;
    return record;
}

pub fn closeRequestLine(out: []u8, uptime_seconds: u64) ![]const u8 {
    return std.fmt.bufPrint(out, "shutdown: close requested uptime={d}", .{uptime_seconds});
}

pub fn exitLine(out: []u8, record: Record) ![]const u8 {
    return std.fmt.bufPrint(out, "shutdown: clean exit code={d} reason={s} uptime={d}", .{
        record.code,
        reasonName(record.reason),
        record.uptime_seconds,
    });
}

pub fn startupLine(out: []u8, record: Record) ![]const u8 {
    return std.fmt.bufPrint(out, "startup: previous exit reason={s} at={d} version={s} uptime={d} code={d}", .{
        reasonName(record.reason),
        record.at,
        record.version,
        record.uptime_seconds,
        record.code,
    });
}

pub const startup_missing_line: []const u8 = "startup: previous exit left no record";

test "an exit record round trips through its own format" {
    var buffer: [128]u8 = undefined;
    const written = try format(&buffer, .{ .at = 1764000000, .version = "0.9.536", .reason = .wm_close, .uptime_seconds = 613, .code = 0 });
    try std.testing.expectEqualStrings("at=1764000000 version=0.9.536 reason=wm_close uptime=613 code=0\n", written);
    const record = parse(written).?;
    try std.testing.expectEqual(@as(i64, 1764000000), record.at);
    try std.testing.expectEqualStrings("0.9.536", record.version);
    try std.testing.expectEqual(Reason.wm_close, record.reason);
    try std.testing.expectEqual(@as(u64, 613), record.uptime_seconds);
    try std.testing.expectEqual(@as(u32, 0), record.code);
}

test "an update relaunch parses back as its own reason" {
    var buffer: [128]u8 = undefined;
    const record = parse(try format(&buffer, .{ .at = 12, .version = "0.9.537", .reason = .update, .uptime_seconds = 4, .code = 0 })).?;
    try std.testing.expectEqual(Reason.update, record.reason);
    try std.testing.expectEqualStrings("update", reasonName(record.reason));
}

test "an exit record without a reason or version is unreadable" {
    try std.testing.expectEqual(@as(?Record, null), parse("at=1 version=0.9.1 uptime=4 code=0"));
    try std.testing.expectEqual(@as(?Record, null), parse("at=1 reason=wm_close uptime=4 code=0"));
    try std.testing.expectEqual(@as(?Record, null), parse("at=1 version=0.9.1 reason=crash uptime=4 code=0"));
    try std.testing.expectEqual(@as(?Record, null), parse("at=soon version=0.9.1 reason=wm_close"));
    try std.testing.expectEqual(@as(?Record, null), parse("nonsense"));
    try std.testing.expectEqual(@as(?Record, null), parse(""));
}

test "a close request names its uptime and a clean exit names its reason" {
    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings("shutdown: close requested uptime=42", try closeRequestLine(&buffer, 42));
    try std.testing.expectEqualStrings("shutdown: clean exit code=0 reason=wm_close uptime=42", try exitLine(&buffer, .{ .reason = .wm_close, .uptime_seconds = 42 }));
}

test "the next start reports the previous exit or says there is no record" {
    var buffer: [192]u8 = undefined;
    try std.testing.expectEqualStrings(
        "startup: previous exit reason=update at=1764000000 version=0.9.537 uptime=9 code=0",
        try startupLine(&buffer, .{ .at = 1764000000, .version = "0.9.537", .reason = .update, .uptime_seconds = 9 }),
    );
    try std.testing.expectEqualStrings("startup: previous exit left no record", startup_missing_line);
}

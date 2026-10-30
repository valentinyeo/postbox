const std = @import("std");
const outbox = @import("outbox.zig");

pub const max_backend_len = 2047;
pub const max_document_bytes = 8 * 1024 * 1024;
pub const Phase = enum { ready, uncertain, held };

pub const Record = struct {
    entry: outbox.Entry = .{},
    phase: Phase = .held,
    attempt_serial: u64 = 0,
    owned_file: outbox.Str(outbox.max_file_len) = .{},
    wire_filename: outbox.Str(outbox.max_file_len) = .{},
    file_sha256: [32]u8 = @splat(0),
    file_bytes: u64 = 0,
    attachment_ready: bool = false,
    failure_reason: outbox.Str(95) = .{},
    not_before_ms: u64 = 0,
};

pub const Snapshot = struct {
    version: u32 = 2,
    backend: outbox.Str(max_backend_len) = .{},
    count: usize = 0,
    records: [outbox.max_entries]Record = [_]Record{.{}} ** outbox.max_entries,
};

const WireRecord = struct {
    id: []const u8,
    provider: []const u8,
    account: []const u8,
    jid: []const u8,
    text: []const u8,
    file: []const u8,
    reply_to: []const u8,
    reply_sender: []const u8,
    client_msg_id: []const u8,
    attempts: u8,
    ambiguous: bool,
    upload_file_id: []const u8,
    queued_unix: i64,
    ptt: bool,
    voice_seconds: u32,
    phase: []const u8,
    attempt_serial: u64,
    owned_file: []const u8,
    wire_filename: []const u8,
    file_sha256: []const u8,
    file_bytes: u64,
    attachment_ready: bool,
    failure_reason: []const u8,
};

const WireSnapshot = struct {
    version: u32,
    backend: []const u8,
    records: []const WireRecord,
};

pub const DecodeError = error{ OutOfMemory, InvalidSnapshot, UnsupportedVersion, WrongBackend, CapacityExceeded };
pub const EncodeError = error{ OutOfMemory, InvalidSnapshot, CapacityExceeded };

fn validText(value: []const u8, max: usize) bool {
    return value.len <= max and std.mem.indexOfScalar(u8, value, 0) == null and std.unicode.utf8ValidateSlice(value);
}

fn validRecord(record: *const Record) bool {
    const e = &record.entry;
    if (!outbox.validId(e.idSlice()) or e.state != .queued or e.queued_unix < 0) return false;
    if (e.account.len == 0 or e.jid.len == 0 or (e.text.len == 0 and e.file.len == 0)) return false;
    if (!validText(e.account.slice(), outbox.max_account_len) or !validText(e.jid.slice(), outbox.max_jid_len) or
        !validText(e.text.slice(), outbox.max_text_len) or !validText(e.file.slice(), outbox.max_file_len) or
        !validText(e.reply_to.slice(), outbox.max_jid_len) or !validText(e.reply_sender.slice(), outbox.max_jid_len) or
        !validText(e.client_msg_id.slice(), outbox.max_client_msg_id_len) or !validText(e.upload_file_id.slice(), outbox.max_file_id_len) or
        !validText(record.owned_file.slice(), outbox.max_file_len) or !validText(record.wire_filename.slice(), outbox.max_file_len) or
        !validText(record.failure_reason.slice(), 95)) return false;
    if (record.wire_filename.len > 0 and (std.mem.indexOfAny(u8, record.wire_filename.slice(), "\\/:\r\n") != null or
        std.mem.eql(u8, record.wire_filename.slice(), ".") or std.mem.eql(u8, record.wire_filename.slice(), ".."))) return false;
    if (record.file_bytes > 64 * 1024 * 1024) return false;
    if (record.phase == .uncertain and record.attempt_serial == 0) return false;
    if (e.file.len == 0) {
        if (record.attachment_ready or record.owned_file.len != 0 or record.wire_filename.len != 0 or record.file_bytes != 0 or
            !std.mem.allEqual(u8, &record.file_sha256, 0) or e.ptt or e.voice_seconds != 0) return false;
    } else if (record.attachment_ready) {
        if (record.owned_file.len == 0 or record.wire_filename.len == 0 or record.file_bytes == 0) return false;
    } else {
        if (record.owned_file.len != 0 or record.file_bytes != 0 or !std.mem.allEqual(u8, &record.file_sha256, 0)) return false;
        if (record.phase != .held) return false;
    }
    return true;
}

fn validSnapshot(snapshot: *const Snapshot) EncodeError!void {
    if (snapshot.version != 2 or snapshot.backend.len == 0 or !validText(snapshot.backend.slice(), max_backend_len)) return error.InvalidSnapshot;
    if (snapshot.count > outbox.max_entries) return error.CapacityExceeded;
    for (snapshot.records[0..snapshot.count], 0..) |*record, i| {
        if (!validRecord(record)) return error.InvalidSnapshot;
        for (snapshot.records[0..i]) |*previous| {
            if (std.mem.eql(u8, previous.entry.idSlice(), record.entry.idSlice())) return error.InvalidSnapshot;
        }
    }
}

pub fn encode(allocator: std.mem.Allocator, snapshot: *const Snapshot) EncodeError![]u8 {
    try validSnapshot(snapshot);
    const rows = allocator.alloc(WireRecord, snapshot.count) catch return error.OutOfMemory;
    defer allocator.free(rows);
    const digests = allocator.alloc([64]u8, snapshot.count) catch return error.OutOfMemory;
    defer allocator.free(digests);
    for (snapshot.records[0..snapshot.count], 0..) |*r, i| {
        const e = &r.entry;
        digests[i] = std.fmt.bytesToHex(r.file_sha256, .lower);
        rows[i] = .{
            .id = e.idSlice(), .provider = @tagName(e.provider), .account = e.account.slice(), .jid = e.jid.slice(),
            .text = e.text.slice(), .file = e.file.slice(), .reply_to = e.reply_to.slice(), .reply_sender = e.reply_sender.slice(),
            .client_msg_id = e.client_msg_id.slice(), .attempts = e.attempts, .ambiguous = e.ambiguous,
            .upload_file_id = e.upload_file_id.slice(), .queued_unix = e.queued_unix, .ptt = e.ptt, .voice_seconds = e.voice_seconds,
            .phase = @tagName(r.phase), .attempt_serial = r.attempt_serial, .owned_file = r.owned_file.slice(),
            .wire_filename = r.wire_filename.slice(), .file_sha256 = &digests[i], .file_bytes = r.file_bytes,
            .attachment_ready = r.attachment_ready, .failure_reason = r.failure_reason.slice(),
        };
    }
    const encoded = std.json.Stringify.valueAlloc(allocator, WireSnapshot{ .version = 2, .backend = snapshot.backend.slice(), .records = rows }, .{}) catch return error.OutOfMemory;
    if (encoded.len > max_document_bytes) {
        allocator.free(encoded);
        return error.CapacityExceeded;
    }
    return encoded;
}

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, expected_backend: []const u8, candidate: *Snapshot) DecodeError!void {
    if (bytes.len > max_document_bytes) return error.CapacityExceeded;
    var parsed = std.json.parseFromSlice(WireSnapshot, allocator, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidSnapshot,
    };
    defer parsed.deinit();
    const doc = parsed.value;
    if (doc.version != 2) return error.UnsupportedVersion;
    if (!std.mem.eql(u8, doc.backend, expected_backend)) return error.WrongBackend;
    if (doc.records.len > outbox.max_entries) return error.CapacityExceeded;
    if (doc.backend.len == 0 or !validText(doc.backend, max_backend_len)) return error.InvalidSnapshot;
    const temp = allocator.create(Snapshot) catch return error.OutOfMemory;
    defer allocator.destroy(temp);
    temp.* = .{};
    temp.backend.set(doc.backend);
    for (doc.records, 0..) |wire, i| {
        if (!outbox.validId(wire.id) or !validText(wire.account, outbox.max_account_len) or !validText(wire.jid, outbox.max_jid_len) or
            !validText(wire.text, outbox.max_text_len) or !validText(wire.file, outbox.max_file_len) or
            !validText(wire.reply_to, outbox.max_jid_len) or !validText(wire.reply_sender, outbox.max_jid_len) or
            !validText(wire.client_msg_id, outbox.max_client_msg_id_len) or !validText(wire.upload_file_id, outbox.max_file_id_len) or
            !validText(wire.owned_file, outbox.max_file_len) or !validText(wire.wire_filename, outbox.max_file_len) or
            !validText(wire.failure_reason, 95) or wire.file_sha256.len != 64) return error.InvalidSnapshot;
        const r = &temp.records[i];
        r.* = .{};
        @memcpy(&r.entry.id, wire.id);
        r.entry.provider = std.meta.stringToEnum(outbox.Provider, wire.provider) orelse return error.InvalidSnapshot;
        r.entry.account.set(wire.account);
        r.entry.jid.set(wire.jid);
        r.entry.text.set(wire.text);
        r.entry.file.set(wire.file);
        r.entry.reply_to.set(wire.reply_to);
        r.entry.reply_sender.set(wire.reply_sender);
        r.entry.client_msg_id.set(wire.client_msg_id);
        r.entry.attempts = wire.attempts;
        r.entry.ambiguous = wire.ambiguous;
        r.entry.upload_file_id.set(wire.upload_file_id);
        r.entry.queued_unix = wire.queued_unix;
        r.entry.ptt = wire.ptt;
        r.entry.voice_seconds = wire.voice_seconds;
        r.phase = std.meta.stringToEnum(Phase, wire.phase) orelse return error.InvalidSnapshot;
        r.attempt_serial = wire.attempt_serial;
        r.owned_file.set(wire.owned_file);
        r.wire_filename.set(wire.wire_filename);
        _ = std.fmt.hexToBytes(&r.file_sha256, wire.file_sha256) catch return error.InvalidSnapshot;
        r.file_bytes = wire.file_bytes;
        r.attachment_ready = wire.attachment_ready;
        r.failure_reason.set(wire.failure_reason);
        if (!validRecord(r)) return error.InvalidSnapshot;
        for (temp.records[0..i]) |*previous| {
            if (std.mem.eql(u8, previous.entry.idSlice(), r.entry.idSlice())) return error.InvalidSnapshot;
        }
        temp.count += 1;
    }
    candidate.* = temp.*;
}

fn testSnapshot() !*Snapshot {
    const snapshot = try std.testing.allocator.create(Snapshot);
    snapshot.* = .{};
    snapshot.backend.set("https://example.invalid:443");
    const text = &snapshot.records[0];
    text.entry.id = [_]u8{'a'} ** outbox.id_len;
    text.entry.provider = .slack;
    text.entry.account.set("workspace-a");
    text.entry.jid.set("slack:workspace-a:channel");
    text.entry.text.set("caption");
    text.entry.reply_to.set("1700000000.000001");
    text.entry.reply_sender.set("sender");
    text.entry.client_msg_id.set("client");
    text.entry.upload_file_id.set("upload");
    text.entry.queued_unix = 123;
    text.entry.attempts = 2;
    text.entry.ambiguous = true;
    text.phase = .uncertain;
    text.attempt_serial = 4;
    text.failure_reason.set("unconfirmed");
    const voice = &snapshot.records[1];
    voice.* = text.*;
    voice.entry.id = [_]u8{'b'} ** outbox.id_len;
    voice.entry.file.set("C:\\original\\voice.ogg");
    voice.entry.ptt = true;
    voice.entry.voice_seconds = 9;
    voice.owned_file.set("C:\\private\\voice.ogg");
    voice.wire_filename.set("voice.ogg");
    voice.file_sha256 = [_]u8{0xab} ** 32;
    voice.file_bytes = 42;
    voice.attachment_ready = true;
    voice.phase = .held;
    snapshot.count = 2;
    return snapshot;
}

test "snapshot roundtrip retains full intent and normalizes runtime fields" {
    const original = try testSnapshot();
    defer std.testing.allocator.destroy(original);
    const candidate = try std.testing.allocator.create(Snapshot);
    defer std.testing.allocator.destroy(candidate);
    const bytes = try encode(std.testing.allocator, original);
    defer std.testing.allocator.free(bytes);
    try decode(std.testing.allocator, bytes, original.backend.slice(), candidate);
    try std.testing.expectEqual(@as(usize, 2), candidate.count);
    try std.testing.expectEqualDeep(original.records[0], candidate.records[0]);
    try std.testing.expectEqualDeep(original.records[1], candidate.records[1]);
    try std.testing.expectEqual(outbox.SendState.queued, candidate.records[1].entry.state);
}

test "snapshot rejects corrupt documents without publishing" {
    const original = try testSnapshot();
    defer std.testing.allocator.destroy(original);
    const candidate = try std.testing.allocator.create(Snapshot);
    defer std.testing.allocator.destroy(candidate);
    candidate.* = .{};
    candidate.count = 37;
    const bytes = try encode(std.testing.allocator, original);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectError(error.WrongBackend, decode(std.testing.allocator, bytes, "https://other.invalid:443", candidate));
    try std.testing.expectError(error.InvalidSnapshot, decode(std.testing.allocator, bytes[0 .. bytes.len - 1], original.backend.slice(), candidate));
    const trailing = try std.fmt.allocPrint(std.testing.allocator, "{s} trailing", .{bytes});
    defer std.testing.allocator.free(trailing);
    try std.testing.expectError(error.InvalidSnapshot, decode(std.testing.allocator, trailing, original.backend.slice(), candidate));
    const version = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, "\"version\":2", "\"version\":3");
    defer std.testing.allocator.free(version);
    try std.testing.expectError(error.UnsupportedVersion, decode(std.testing.allocator, version, original.backend.slice(), candidate));
    const duplicate_field = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, "\"version\":2", "\"version\":2,\"version\":2");
    defer std.testing.allocator.free(duplicate_field);
    try std.testing.expectError(error.InvalidSnapshot, decode(std.testing.allocator, duplicate_field, original.backend.slice(), candidate));
    const phase = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, "\"phase\":\"uncertain\"", "\"phase\":\"unknown\"");
    defer std.testing.allocator.free(phase);
    try std.testing.expectError(error.InvalidSnapshot, decode(std.testing.allocator, phase, original.backend.slice(), candidate));
    const no_attempt = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, "\"attempt_serial\":4", "\"attempt_serial\":0");
    defer std.testing.allocator.free(no_attempt);
    try std.testing.expectError(error.InvalidSnapshot, decode(std.testing.allocator, no_attempt, original.backend.slice(), candidate));
    const bad_filename = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, "\"wire_filename\":\"voice.ogg\"", "\"wire_filename\":\"../voice.ogg\"");
    defer std.testing.allocator.free(bad_filename);
    try std.testing.expectError(error.InvalidSnapshot, decode(std.testing.allocator, bad_filename, original.backend.slice(), candidate));
    const bad_size = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, "\"file_bytes\":42", "\"file_bytes\":67108865");
    defer std.testing.allocator.free(bad_size);
    try std.testing.expectError(error.InvalidSnapshot, decode(std.testing.allocator, bad_size, original.backend.slice(), candidate));
    const duplicate_id = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    defer std.testing.allocator.free(duplicate_id);
    try std.testing.expectError(error.InvalidSnapshot, decode(std.testing.allocator, duplicate_id, original.backend.slice(), candidate));
    try std.testing.expectEqual(@as(usize, 37), candidate.count);
}

test "snapshot enforces capacity and unique ids" {
    const snapshot = try testSnapshot();
    defer std.testing.allocator.destroy(snapshot);
    for (2..outbox.max_entries) |i| {
        snapshot.records[i] = snapshot.records[0];
        const id = std.fmt.bytesToHex([_]u8{@intCast(i)} ** 16, .lower);
        snapshot.records[i].entry.id = id;
    }
    snapshot.count = outbox.max_entries;
    const bytes = try encode(std.testing.allocator, snapshot);
    defer std.testing.allocator.free(bytes);
    const candidate = try std.testing.allocator.create(Snapshot);
    defer std.testing.allocator.destroy(candidate);
    try decode(std.testing.allocator, bytes, snapshot.backend.slice(), candidate);
    try std.testing.expectEqual(@as(usize, outbox.max_entries), candidate.count);
    const first_start = (std.mem.indexOf(u8, bytes, "\"records\":[") orelse return error.MissingRecords) + "\"records\":[".len;
    const first_end = (std.mem.indexOfPos(u8, bytes, first_start, "},") orelse return error.MissingRecord) + 1;
    const too_many = try std.fmt.allocPrint(std.testing.allocator, "{s},{s}]}}", .{ bytes[0 .. bytes.len - 2], bytes[first_start..first_end] });
    defer std.testing.allocator.free(too_many);
    try std.testing.expectError(error.CapacityExceeded, decode(std.testing.allocator, too_many, snapshot.backend.slice(), candidate));
    try std.testing.expectEqual(@as(usize, outbox.max_entries), candidate.count);
    snapshot.count += 1;
    try std.testing.expectError(error.CapacityExceeded, encode(std.testing.allocator, snapshot));
    snapshot.count = 2;
    snapshot.records[1].entry.id = snapshot.records[0].entry.id;
    try std.testing.expectError(error.InvalidSnapshot, encode(std.testing.allocator, snapshot));
}

fn decodeWithFailure(allocator: std.mem.Allocator, bytes: []const u8, candidate: *Snapshot) !void {
    candidate.count = 37;
    decode(allocator, bytes, "https://example.invalid:443", candidate) catch |err| {
        try std.testing.expectEqual(@as(usize, 37), candidate.count);
        return err;
    };
    try std.testing.expectEqual(@as(usize, 2), candidate.count);
}

test "allocation failure never publishes a partial snapshot" {
    const snapshot = try testSnapshot();
    defer std.testing.allocator.destroy(snapshot);
    const bytes = try encode(std.testing.allocator, snapshot);
    defer std.testing.allocator.free(bytes);
    const candidate = try std.testing.allocator.create(Snapshot);
    defer std.testing.allocator.destroy(candidate);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, decodeWithFailure, .{ bytes, candidate });
}

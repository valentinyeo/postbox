const std = @import("std");
const tj = @import("telegram_json.zig");

const c = struct {
    extern fn td_json_client_create() ?*anyopaque;
    extern fn td_json_client_send(client: *anyopaque, request: [*:0]const u8) void;
    extern fn td_json_client_receive(client: *anyopaque, timeout: f64) ?[*:0]const u8;
    extern fn td_json_client_execute(client: *anyopaque, request: [*:0]const u8) ?[*:0]const u8;
    extern fn td_json_client_destroy(client: *anyopaque) void;
};

pub const enabled = true;

pub const AuthState = tj.AuthState;
pub const MediaKind = tj.MediaKind;
pub const Event = tj.Event;
pub const Msg = tj.Msg;
pub const ChatInfo = tj.ChatInfo;

const max_queued_events = 512;
const max_history_per_chat = 200;

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: ?*anyopaque = null,
    thread: ?std.Thread = null,
    queue_mutex: std.Io.Mutex = .init,
    queue: std.ArrayList(Event) = .empty,
    dropped_events: u64 = 0,
    state_mutex: std.Io.Mutex = .init,
    chats: std.AutoHashMap(i64, ChatInfo),
    history: std.AutoHashMap(i64, std.ArrayList(Msg)),
    users: std.AutoHashMap(i64, []u8),
    auth: AuthState = .unknown,
    api_id: i32,
    api_hash: []u8,
    database_dir: []u8,
    files_dir: []u8,
    stopping: std.atomic.Value(bool) = .init(false),
    parameters_sent: bool = false,
    pending_phone: ?[]u8 = null,

    pub fn create(allocator: std.mem.Allocator, io: std.Io, api_id: i32, api_hash: []const u8, base_dir: []const u8) ?*Client {
        const self = allocator.create(Client) catch return null;
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .api_id = api_id,
            .api_hash = undefined,
            .database_dir = undefined,
            .files_dir = undefined,
            .chats = std.AutoHashMap(i64, ChatInfo).init(allocator),
            .history = std.AutoHashMap(i64, std.ArrayList(Msg)).init(allocator),
            .users = std.AutoHashMap(i64, []u8).init(allocator),
        };
        self.api_hash = allocator.dupe(u8, api_hash) catch return null;
        errdefer allocator.free(self.api_hash);
        self.database_dir = std.fmt.allocPrint(allocator, "{s}\\td", .{base_dir}) catch return null;
        errdefer allocator.free(self.database_dir);
        self.files_dir = std.fmt.allocPrint(allocator, "{s}\\files", .{base_dir}) catch return null;
        errdefer allocator.free(self.files_dir);
        ensureDirectory(self.allocator, self.database_dir);
        ensureDirectory(self.allocator, self.files_dir);
        self.client = c.td_json_client_create() orelse return null;
        self.thread = std.Thread.spawn(.{}, receiveLoop, .{self}) catch null;
        return self;
    }

    pub fn destroy(self: *Client) void {
        self.stopping.store(true, .release);
        self.sendClose();
        if (self.thread) |thread| thread.join();
        if (self.pending_phone) |phone| self.allocator.free(phone);
        for (self.queue.items) |*event| event.deinit(self.allocator);
        self.queue.deinit(self.allocator);
        var chat_iterator = self.chats.iterator();
        while (chat_iterator.next()) |entry| entry.value_ptr.deinit(self.allocator);
        self.chats.deinit();
        var user_iterator = self.users.iterator();
        while (user_iterator.next()) |entry| self.allocator.free(entry.value_ptr.*);
        self.users.deinit();
        var history_iterator = self.history.iterator();
        while (history_iterator.next()) |entry| {
            for (entry.value_ptr.items) |*msg| msg.deinit(self.allocator);
            entry.value_ptr.deinit(self.allocator);
        }
        self.history.deinit();
        self.allocator.free(self.api_hash);
        self.allocator.free(self.database_dir);
        self.allocator.free(self.files_dir);
        self.allocator.destroy(self);
    }

    pub fn poll(self: *Client) ?Event {
        self.queue_mutex.lockUncancelable(self.io);
        defer self.queue_mutex.unlock(self.io);
        if (self.queue.items.len == 0) return null;
        const event = self.queue.orderedRemove(0);
        return event;
    }

    pub fn authState(self: *Client) AuthState {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        return self.auth;
    }

    pub fn authPhone(self: *Client, phone: []const u8) void {
        self.state_mutex.lockUncancelable(self.io);
        const wait_for_it = self.auth == .unknown or self.auth == .wait_parameters;
        if (wait_for_it) {
            const copy = self.allocator.dupe(u8, phone) catch {
                self.state_mutex.unlock(self.io);
                return;
            };
            if (self.pending_phone) |old| self.allocator.free(old);
            self.pending_phone = copy;
        } else {
            self.sendPhoneNumber(phone);
        }
        self.state_mutex.unlock(self.io);
    }

    fn sendPhoneNumber(self: *Client, phone: []const u8) void {
        self.sendFields(.{ .type = "setAuthenticationPhoneNumber", .phone_number = phone, .allow_flash_call = false, .is_current_phone_number = true });
    }

    pub fn authCode(self: *Client, code: []const u8) void {
        self.sendFields(.{ .type = "checkAuthenticationCode", .code = code });
    }

    pub fn authPassword(self: *Client, password: []const u8) void {
        self.sendFields(.{ .type = "checkAuthenticationPassword", .password = password });
    }

    pub fn requestChats(self: *Client) void {
        self.sendFields(.{ .type = "getChats", .limit = 1000 });
        self.sendFields(.{ .type = "loadChats", .limit = 100, .extra = "load_chats" });
    }

    pub fn requestHistory(self: *Client, chat_id: i64) void {
        self.sendFields(.{ .type = "getChatHistory", .chat_id = chat_id, .limit = 100 });
    }

    pub fn sendText(self: *Client, chat_id: i64, text: []const u8) bool {
        return self.sendTextReply(chat_id, text, 0);
    }

    pub fn sendTextReply(self: *Client, chat_id: i64, text: []const u8, reply_to: i64) bool {
        var allocating = std.Io.Writer.Allocating.init(self.allocator);
        defer allocating.deinit();
        var json = std.json.Stringify{ .writer = &allocating.writer };
        json.beginObject() catch return false;
        json.objectField("@type") catch return false;
        json.write("sendMessage") catch return false;
        json.objectField("chat_id") catch return false;
        json.write(chat_id) catch return false;
        if (reply_to != 0) {
            json.objectField("reply_to") catch return false;
            json.write(.{ .@"@type" = "inputMessageReplyToMessage", .message_id = reply_to }) catch return false;
        }
        json.objectField("input_message_content") catch return false;
        json.beginObject() catch return false;
        json.objectField("@type") catch return false;
        json.write("inputMessageText") catch return false;
        json.objectField("text") catch return false;
        json.beginObject() catch return false;
        json.objectField("@type") catch return false;
        json.write("formattedText") catch return false;
        json.objectField("text") catch return false;
        json.write(text) catch return false;
        json.endObject() catch return false;
        json.endObject() catch return false;
        json.endObject() catch return false;
        self.sendAllocated(&allocating);
        return true;
    }

    pub fn sendFile(self: *Client, chat_id: i64, path: []const u8, caption: []const u8, reply_to: i64) bool {
        const extension = std.fs.path.extension(path);
        const photo = std.ascii.eqlIgnoreCase(extension, ".png") or std.ascii.eqlIgnoreCase(extension, ".jpg") or std.ascii.eqlIgnoreCase(extension, ".jpeg") or std.ascii.eqlIgnoreCase(extension, ".webp");
        var allocating = std.Io.Writer.Allocating.init(self.allocator);
        defer allocating.deinit();
        var json = std.json.Stringify{ .writer = &allocating.writer };
        json.beginObject() catch return false;
        json.objectField("@type") catch return false;
        json.write("sendMessage") catch return false;
        json.objectField("chat_id") catch return false;
        json.write(chat_id) catch return false;
        if (reply_to != 0) {
            json.objectField("reply_to") catch return false;
            json.write(.{ .@"@type" = "inputMessageReplyToMessage", .message_id = reply_to }) catch return false;
        }
        json.objectField("input_message_content") catch return false;
        json.beginObject() catch return false;
        json.objectField("@type") catch return false;
        json.write(if (photo) "inputMessagePhoto" else "inputMessageDocument") catch return false;
        json.objectField(if (photo) "photo" else "document") catch return false;
        json.write(.{ .@"@type" = "inputFileLocal", .path = path }) catch return false;
        json.objectField("caption") catch return false;
        json.write(.{ .@"@type" = "formattedText", .text = caption }) catch return false;
        json.endObject() catch return false;
        json.endObject() catch return false;
        self.sendAllocated(&allocating);
        return true;
    }

    pub fn markRead(self: *Client, chat_id: i64, message_id: i64) void {
        var allocating = std.Io.Writer.Allocating.init(self.allocator);
        defer allocating.deinit();
        var json = std.json.Stringify{ .writer = &allocating.writer };
        json.beginObject() catch return;
        json.objectField("@type") catch return;
        json.write("viewMessages") catch return;
        json.objectField("chat_id") catch return;
        json.write(chat_id) catch return;
        json.objectField("message_ids") catch return;
        json.beginArray() catch return;
        json.write(message_id) catch return;
        json.endArray() catch return;
        json.objectField("force_read") catch return;
        json.write(true) catch return;
        json.endObject() catch return;
        self.sendAllocated(&allocating);
    }

    pub fn download(self: *Client, file_id: i32) void {
        if (file_id == 0) return;
        self.sendFields(.{ .type = "downloadFile", .file_id = file_id, .priority = 32, .offset = 0, .limit = 0, .synchronous = false });
    }

    pub fn logOut(self: *Client) void {
        self.sendFields(.{ .type = "logOut" });
    }

    pub fn chatSnapshot(self: *Client, allocator: std.mem.Allocator) []ChatInfo {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        var list = std.ArrayList(ChatInfo).empty;
        errdefer {
            for (list.items) |*item| item.deinit(allocator);
            list.deinit(allocator);
        }
        var iterator = self.chats.iterator();
        while (iterator.next()) |entry| {
            const info = entry.value_ptr.*;
            list.append(allocator, info) catch return &.{};
            list.items[list.items.len - 1].title = allocator.dupe(u8, entry.value_ptr.title) catch return &.{};
        }
        return list.toOwnedSlice(allocator) catch return &.{};
    }

    pub fn freeChatSnapshot(self: *Client, allocator: std.mem.Allocator, snapshot: []ChatInfo) void {
        _ = self;
        for (snapshot) |*item| item.deinit(allocator);
        allocator.free(snapshot);
    }

    pub fn historySnapshot(self: *Client, allocator: std.mem.Allocator, chat_id: i64) []Msg {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        const stored = self.history.getPtr(chat_id) orelse return &.{};
        var list = std.ArrayList(Msg).empty;
        errdefer {
            for (list.items) |*item| item.deinit(allocator);
            list.deinit(allocator);
        }
        for (stored.items) |*msg| {
            const copy = self.dupeMessage(msg) orelse return &.{};
            list.append(allocator, copy) catch {
                var dropped = copy;
                dropped.deinit(allocator);
                return &.{};
            };
        }
        return list.toOwnedSlice(allocator) catch return &.{};
    }

    pub fn freeHistorySnapshot(self: *Client, allocator: std.mem.Allocator, snapshot: []Msg) void {
        _ = self;
        for (snapshot) |*item| item.deinit(allocator);
        allocator.free(snapshot);
    }

    fn sendFields(self: *Client, fields: anytype) void {
        var allocating = std.Io.Writer.Allocating.init(self.allocator);
        defer allocating.deinit();
        var json = std.json.Stringify{ .writer = &allocating.writer };
        json.beginObject() catch return;
        inline for (std.meta.fields(@TypeOf(fields))) |field| {
            json.objectField(comptime mapKey(field.name)) catch return;
            json.write(@field(fields, field.name)) catch return;
        }
        json.endObject() catch return;
        self.sendAllocated(&allocating);
    }

    fn sendAllocated(self: *Client, allocating: *std.Io.Writer.Allocating) void {
        const text = allocating.toOwnedSlice() catch return;
        defer self.allocator.free(text);
        const zero_terminated = self.allocator.dupeZ(u8, text) catch return;
        defer self.allocator.free(zero_terminated);
        const client = self.client orelse return;
        c.td_json_client_send(client, zero_terminated.ptr);
    }

    fn sendTdlibParameters(self: *Client) void {
        self.sendFields(.{
            .type = "setTdlibParameters",
            .database_directory = self.database_dir,
            .files_directory = self.files_dir,
            .database_encryption_key = "",
            .use_message_database = true,
            .use_secret_chats = false,
            .api_id = self.api_id,
            .api_hash = self.api_hash,
            .system_language_code = "en",
            .device_model = "Desktop",
            .application_version = "1.0",
        });
        self.parameters_sent = true;
    }

    fn sendClose(self: *Client) void {
        const client = self.client orelse return;
        const request = self.allocator.dupeZ(u8, "{\"@type\":\"close\"}") catch return;
        defer self.allocator.free(request);
        c.td_json_client_send(client, request.ptr);
    }

    fn receiveLoop(self: *Client) void {
        const client = self.client orelse return;
        while (!self.stopping.load(.acquire)) {
            const raw = c.td_json_client_receive(client, 0.5) orelse continue;
            const text = std.mem.span(raw);
            self.handleRaw(text);
        }
        c.td_json_client_destroy(client);
    }

    fn handleRaw(self: *Client, text: []const u8) void {
        if (std.json.parseFromSlice(std.json.Value, self.allocator, text, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value == .object) {
                const object = parsed.value.object;
                if (object.get("@extra")) |extra| {
                    if (extra == .string and std.mem.eql(u8, extra.string, "load_chats")) {
                        if (object.get("@type")) |kind| {
                            if (kind == .string and std.mem.eql(u8, kind.string, "ok")) self.sendFields(.{ .type = "loadChats", .limit = 100, .extra = "load_chats" });
                        }
                        return;
                    }
                }
            }
        } else |_| {}

        var events = tj.parseEventBatch(self.allocator, text) catch return;
        defer events.deinit(self.allocator);
        for (events.items) |*event| {
            switch (event.*) {
                .auth => |auth| {
                    self.state_mutex.lockUncancelable(self.io);
                    if (auth.state != .unknown) self.auth = auth.state;
                    var pending: ?[]u8 = null;
                    if (auth.state != .unknown and auth.state != .wait_parameters) {
                        pending = self.pending_phone;
                        self.pending_phone = null;
                    }
                    if (auth.state == .wait_phone) if (pending) |phone| self.sendPhoneNumber(phone);
                    self.state_mutex.unlock(self.io);
                    if (auth.state == .wait_parameters and !self.parameters_sent) self.sendTdlibParameters();
                    if (pending) |phone| self.allocator.free(phone);
                },
                .chat => |*info| {
                    self.applyChat(info);
                },
                .message => |*msg| {
                    self.resolveSender(msg);
                    self.storeMessage(msg);
                    if (msg.reply_to != 0) {
                        const reply_chat = if (msg.reply_chat_id != 0) msg.reply_chat_id else msg.chat_id;
                        self.state_mutex.lockUncancelable(self.io);
                        var found = false;
                        if (self.history.getPtr(reply_chat)) |list| {
                            for (list.items) |original| {
                                if (original.id == msg.reply_to) {
                                    found = true;
                                    break;
                                }
                            }
                        }
                        self.state_mutex.unlock(self.io);
                        if (!found) self.sendFields(.{ .type = "getMessage", .chat_id = reply_chat, .message_id = msg.reply_to });
                    }
                },
                .chat_last_date => |update| {
                    self.state_mutex.lockUncancelable(self.io);
                    if (self.chats.getPtr(update.chat_id)) |info| info.last_date = update.date;
                    self.state_mutex.unlock(self.io);
                },
                .deleted => |deleted| {
                    self.state_mutex.lockUncancelable(self.io);
                    if (self.history.getPtr(deleted.chat_id)) |list| {
                        for (list.items, 0..) |existing, index| {
                            if (existing.id == deleted.message_id) {
                                var removed = list.orderedRemove(index);
                                removed.deinit(self.allocator);
                                break;
                            }
                        }
                    }
                    self.state_mutex.unlock(self.io);
                },
                .user => |named| {
                    self.state_mutex.lockUncancelable(self.io);
                    const entry = self.users.getOrPut(named.user_id) catch {
                        self.state_mutex.unlock(self.io);
                        continue;
                    };
                    if (entry.found_existing) self.allocator.free(entry.value_ptr.*);
                    const user_name = self.allocator.dupe(u8, named.name) catch {
                        _ = self.users.remove(named.user_id);
                        self.state_mutex.unlock(self.io);
                        continue;
                    };
                    entry.value_ptr.* = user_name;
                    self.state_mutex.unlock(self.io);
                },
                .file => |update| {
                    if (update.local_path.len > 0) {
                        self.state_mutex.lockUncancelable(self.io);
                        var history_iterator = self.history.iterator();
                        while (history_iterator.next()) |entry| {
                            for (entry.value_ptr.items) |*msg| {
                                if (msg.file_id == update.file_id and msg.local_path.len == 0) {
                                    msg.local_path = self.allocator.dupe(u8, update.local_path) catch &.{};
                                }
                            }
                        }
                        self.state_mutex.unlock(self.io);
                    }
                },
                else => {},
            }
        }
        self.queue_mutex.lockUncancelable(self.io);
        defer self.queue_mutex.unlock(self.io);
        for (events.items) |event| {
            if (self.queue.items.len >= max_queued_events) {
                self.dropped_events += 1;
                var dropped = event;
                dropped.deinit(self.allocator);
                continue;
            }
            self.queue.append(self.allocator, event) catch {
                var dropped = event;
                dropped.deinit(self.allocator);
            };
        }
    }

    fn applyChat(self: *Client, info: *ChatInfo) void {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        const stored_title = self.allocator.dupe(u8, info.title) catch return;
        const entry = self.chats.getOrPut(info.id) catch {
            self.allocator.free(stored_title);
            return;
        };
        if (entry.found_existing) {
            const previous = entry.value_ptr.*;
            entry.value_ptr.* = info.*;
            entry.value_ptr.title = stored_title;
            if (info.title.len == 0) {
                entry.value_ptr.title = previous.title;
                entry.value_ptr.is_group = previous.is_group;
                entry.value_ptr.is_channel = previous.is_channel;
                self.allocator.free(stored_title);
            } else {
                self.allocator.free(previous.title);
            }
            if (info.last_date == 0) entry.value_ptr.last_date = previous.last_date;
        } else {
            entry.value_ptr.* = info.*;
            entry.value_ptr.title = stored_title;
        }
    }

    fn storeMessage(self: *Client, msg: *Msg) void {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        if (self.chats.getPtr(msg.chat_id)) |info| info.last_date = @max(info.last_date, msg.date);
        const pointer = self.history.getOrPut(msg.chat_id) catch return;
        if (!pointer.found_existing) pointer.value_ptr.* = .empty;
        const list = pointer.value_ptr;
        if (msg.old_message_id != 0 and msg.old_message_id != msg.id) {
            for (list.items, 0..) |existing, index| {
                if (existing.id == msg.old_message_id) {
                    var removed = list.orderedRemove(index);
                    removed.deinit(self.allocator);
                    break;
                }
            }
        }
        for (list.items) |*existing| {
            if (existing.id == msg.id) {
                if (msg.content_update) {
                    self.allocator.free(existing.text);
                    self.allocator.free(existing.local_path);
                    self.allocator.free(existing.mime);
                    existing.text = self.allocator.dupe(u8, msg.text) catch &.{};
                    existing.local_path = self.allocator.dupe(u8, msg.local_path) catch &.{};
                    existing.mime = self.allocator.dupe(u8, msg.mime) catch &.{};
                    existing.media_kind = msg.media_kind;
                    existing.file_id = msg.file_id;
                    existing.duration_ms = msg.duration_ms;
                    existing.animated_sticker = msg.animated_sticker;
                } else if (self.dupeMessage(msg)) |copy| {
                    existing.deinit(self.allocator);
                    existing.* = copy;
                }
                return;
            }
        }
        if (msg.content_update) return;
        if (self.dupeMessage(msg)) |copy| {
            list.append(self.allocator, copy) catch {
                var dropped = copy;
                dropped.deinit(self.allocator);
                return;
            };
        }
        std.mem.sort(Msg, list.items, {}, struct {
            fn less(_: void, left: Msg, right: Msg) bool {
                if (left.sending != right.sending) return left.sending;
                if (left.date != right.date) return left.date > right.date;
                return left.id > right.id;
            }
        }.less);
        while (list.items.len > max_history_per_chat) {
            var oldest = list.pop().?;
            oldest.deinit(self.allocator);
        }
    }

    fn resolveSender(self: *Client, msg: *Msg) void {
        if (msg.sender_user_id == 0) return;
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        if (self.users.get(msg.sender_user_id)) |name_text| {
            const copy = self.allocator.dupe(u8, name_text) catch return;
            if (msg.sender_name.len > 0) self.allocator.free(msg.sender_name);
            msg.sender_name = copy;
        }
    }

    fn dupeMessage(self: *Client, msg: *const Msg) ?Msg {
        var copy = msg.*;
        copy.sender_name = self.allocator.dupe(u8, msg.sender_name) catch return null;
        copy.text = self.allocator.dupe(u8, msg.text) catch {
            self.allocator.free(copy.sender_name);
            return null;
        };
        copy.timestamp = self.allocator.dupe(u8, msg.timestamp) catch {
            self.allocator.free(copy.sender_name);
            self.allocator.free(copy.text);
            return null;
        };
        copy.local_path = self.allocator.dupe(u8, msg.local_path) catch {
            self.allocator.free(copy.sender_name);
            self.allocator.free(copy.text);
            self.allocator.free(copy.timestamp);
            return null;
        };
        copy.mime = self.allocator.dupe(u8, msg.mime) catch {
            self.allocator.free(copy.sender_name);
            self.allocator.free(copy.text);
            self.allocator.free(copy.timestamp);
            self.allocator.free(copy.local_path);
            return null;
        };
        return copy;
    }
};

extern "kernel32" fn CreateDirectoryW(lp_path_name: [*:0]const u16, lp_security_attributes: ?*anyopaque) callconv(.c) c_int;

fn ensureDirectory(allocator: std.mem.Allocator, path: []const u8) void {
    const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return;
    defer allocator.free(wide);
    _ = CreateDirectoryW(wide.ptr, null);
}

fn mapKey(comptime name: []const u8) []const u8 {
    if (comptime std.mem.eql(u8, name, "type")) return "@type";
    if (comptime std.mem.eql(u8, name, "extra")) return "@extra";
    return name;
}

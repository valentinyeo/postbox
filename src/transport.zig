const std = @import("std");

pub const ChatSummary = struct {
    id: []const u8,
    name: []const u8,
    unread_count: i32,
    is_group: bool,
    timestamp: []const u8,
};

pub const Provider = enum { whatsapp, telegram, slack };

pub const Transport = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        refreshChats: *const fn (context: *anyopaque) void,
        refreshMessages: *const fn (context: *anyopaque, chat_id: []const u8) void,
        sendText: *const fn (context: *anyopaque, chat_id: []const u8, text: []const u8, client_id: []const u8) bool,
        markRead: *const fn (context: *anyopaque, chat_id: []const u8, message_id: []const u8) void,
        archive: *const fn (context: *anyopaque, chat_id: []const u8, archived: bool) bool,
        react: *const fn (context: *anyopaque, chat_id: []const u8, message_id: []const u8, emoji: []const u8, client_id: []const u8) bool,
        downloadMedia: *const fn (context: *anyopaque, chat_id: []const u8, message_id: []const u8) void,
    };

    pub fn refreshChats(self: Transport) void {
        self.vtable.refreshChats(self.context);
    }

    pub fn refreshMessages(self: Transport, chat_id: []const u8) void {
        self.vtable.refreshMessages(self.context, chat_id);
    }

    pub fn sendText(self: Transport, chat_id: []const u8, text: []const u8, client_id: []const u8) bool {
        return self.vtable.sendText(self.context, chat_id, text, client_id);
    }

    pub fn markRead(self: Transport, chat_id: []const u8, message_id: []const u8) void {
        self.vtable.markRead(self.context, chat_id, message_id);
    }

    pub fn archive(self: Transport, chat_id: []const u8, archived: bool) bool {
        return self.vtable.archive(self.context, chat_id, archived);
    }

    pub fn react(self: Transport, chat_id: []const u8, message_id: []const u8, emoji: []const u8, client_id: []const u8) bool {
        return self.vtable.react(self.context, chat_id, message_id, emoji, client_id);
    }

    pub fn downloadMedia(self: Transport, chat_id: []const u8, message_id: []const u8) void {
        self.vtable.downloadMedia(self.context, chat_id, message_id);
    }
};

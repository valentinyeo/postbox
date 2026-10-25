const std = @import("std");
const hub = @import("wa_hub.zig");
const slack_win = @import("winhttp.zig");

pub const Client = struct {
    endpoint: hub.Endpoint,
    key: []const u8,

    pub fn open(self: Client, allocator: std.mem.Allocator, request: hub.Request, cancel: ?*slack_win.HttpCancel) !slack_win.HttpStream {
        return slack_win.openHttp(allocator, self.endpoint.host, self.endpoint.port, self.endpoint.secure, self.key, request.method, request.path, request.content_type, request.body, request.last_event_id, cancel);
    }

    pub fn call(self: Client, allocator: std.mem.Allocator, request: hub.Request) !slack_win.Response {
        const stream = try self.open(allocator, request, null);
        defer stream.deinit();
        return stream.response(allocator, @intCast(slack_win.max_download_bytes));
    }
};

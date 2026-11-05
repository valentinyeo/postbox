const std = @import("std");

pub const balloon_show: usize = 0x402;
pub const balloon_hide: usize = 0x403;
pub const balloon_timeout: usize = 0x404;
pub const balloon_user_click: usize = 0x405;

pub const Balloons = struct {
    open: u8 = 0,

    pub fn event(self: *Balloons, code: usize) bool {
        switch (code) {
            balloon_show => {
                self.open +|= 1;
                return false;
            },
            balloon_hide, balloon_timeout, balloon_user_click => {
                self.open -|= 1;
                return self.open == 0;
            },
            else => return false,
        }
    }

    pub fn reset(self: *Balloons) void {
        self.open = 0;
    }
};

test "IGSH-1735 the tray icon goes when the last alert closes" {
    var b = Balloons{};
    try std.testing.expect(!b.event(balloon_show));
    try std.testing.expect(b.event(balloon_timeout));
    try std.testing.expect(!b.event(balloon_show));
    try std.testing.expect(b.event(balloon_user_click));
    try std.testing.expect(!b.event(balloon_show));
    try std.testing.expect(b.event(balloon_hide));
}

test "IGSH-1735 a replaced alert keeps the icon until the newest one closes" {
    var b = Balloons{};
    try std.testing.expect(!b.event(balloon_show));
    try std.testing.expect(!b.event(balloon_show));
    try std.testing.expect(!b.event(balloon_timeout));
    try std.testing.expect(b.event(balloon_timeout));
}

test "IGSH-1735 stray close events never underflow and other events do nothing" {
    var b = Balloons{};
    try std.testing.expect(b.event(balloon_timeout));
    try std.testing.expectEqual(@as(u8, 0), b.open);
    try std.testing.expect(!b.event(0x400));
    try std.testing.expect(!b.event(0x201));
    try std.testing.expectEqual(@as(u8, 0), b.open);
}

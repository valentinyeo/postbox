const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [64]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.print("{x:0>16}", .{std.hash.Wyhash.hash(0, "verify-alpha")});
    try out.interface.flush();
}

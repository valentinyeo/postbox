const std = @import("std");
const Provider = @import("transport.zig").Provider;

const order = [_]Provider{ .whatsapp, .slack, .telegram };

fn configured(provider: Provider, slack: bool, telegram: bool) bool {
    return switch (provider) {
        .whatsapp => true,
        .slack => slack,
        .telegram => telegram,
    };
}

pub fn forNumber(number: usize, slack: bool, telegram: bool) ?Provider {
    var seen: usize = 0;
    for (order) |provider| {
        if (!configured(provider, slack, telegram)) continue;
        seen += 1;
        if (seen == number) return provider;
    }
    return null;
}

pub fn numberFor(provider: Provider, slack: bool, telegram: bool) ?usize {
    var seen: usize = 0;
    for (order) |candidate| {
        if (!configured(candidate, slack, telegram)) continue;
        seen += 1;
        if (candidate == provider) return seen;
    }
    return null;
}

pub fn effective(wanted: Provider, slack: bool, telegram: bool) Provider {
    return if (configured(wanted, slack, telegram)) wanted else .whatsapp;
}

pub fn label(provider: Provider) []const u8 {
    return switch (provider) {
        .whatsapp => "WhatsApp",
        .slack => "Slack",
        .telegram => "Telegram",
    };
}

test "Alt+N numbers only configured messengers, in a fixed order" {
    try std.testing.expectEqual(@as(?Provider, .whatsapp), forNumber(1, false, false));
    try std.testing.expectEqual(@as(?Provider, null), forNumber(2, false, false));
    try std.testing.expectEqual(@as(?Provider, .slack), forNumber(2, true, false));
    try std.testing.expectEqual(@as(?Provider, .telegram), forNumber(2, false, true));
    try std.testing.expectEqual(@as(?Provider, .telegram), forNumber(3, true, true));
    try std.testing.expectEqual(@as(?usize, 3), numberFor(.telegram, true, true));
    try std.testing.expectEqual(@as(?usize, null), numberFor(.slack, false, true));
    try std.testing.expectEqual(@as(?Provider, null), forNumber(0, true, true));
}

test "a remembered view that is not set up falls back to WhatsApp" {
    try std.testing.expectEqual(Provider.whatsapp, effective(.slack, false, false));
    try std.testing.expectEqual(Provider.slack, effective(.slack, true, false));
    try std.testing.expectEqual(Provider.whatsapp, effective(.telegram, true, false));
}

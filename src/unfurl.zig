const std = @import("std");

pub const Provider = enum { none, youtube, instagram, facebook, page, image };

pub const FetchKind = enum { page, image };

pub const max_id_len = 40;
pub const max_canonical_len = 384;

pub const Info = struct {
    provider: Provider = .none,
    id: [max_id_len]u8 = undefined,
    id_len: usize = 0,
    canonical: [max_canonical_len]u8 = undefined,
    canonical_len: usize = 0,

    pub fn idSlice(self: *const Info) []const u8 {
        return self.id[0..self.id_len];
    }

    pub fn canonicalSlice(self: *const Info) []const u8 {
        return self.canonical[0..self.canonical_len];
    }
};

const youtube_hosts = [_][]const u8{
    "youtube.com", "www.youtube.com",      "m.youtube.com", "music.youtube.com",
    "youtu.be",    "youtube-nocookie.com",
};
const instagram_hosts = [_][]const u8{
    "instagram.com", "www.instagram.com", "m.instagram.com", "instagr.am", "www.instagr.am",
};
const facebook_hosts = [_][]const u8{
    "facebook.com", "www.facebook.com", "m.facebook.com", "web.facebook.com", "fb.watch",
};

fn hostIs(host: []const u8, list: []const []const u8) bool {
    for (list) |allowed| if (std.ascii.eqlIgnoreCase(host, allowed)) return true;
    return false;
}

fn providerForHost(host: []const u8) Provider {
    if (hostIs(host, &youtube_hosts)) return .youtube;
    if (hostIs(host, &instagram_hosts)) return .instagram;
    if (hostIs(host, &facebook_hosts)) return .facebook;
    return .none;
}

fn isLinkId(unit: u8, provider: Provider) bool {
    return switch (provider) {
        .youtube => std.ascii.isAlphanumeric(unit) or unit == '_' or unit == '-',
        else => std.ascii.isAlphanumeric(unit) or unit == '_' or unit == '-',
    };
}

fn store(info: *Info, provider: Provider, id: []const u8, canonical: []const u8) bool {
    if (id.len == 0 or id.len > max_id_len) return false;
    if (canonical.len == 0 or canonical.len > max_canonical_len) return false;
    info.provider = provider;
    @memcpy(info.id[0..id.len], id);
    info.id_len = id.len;
    @memcpy(info.canonical[0..canonical.len], canonical);
    info.canonical_len = canonical.len;
    return true;
}

fn trimTrailingPunctuation(url: []const u8) []const u8 {
    return std.mem.trimEnd(u8, url, ".,;:!?)]}>\"'");
}

fn splitHostPath(rest: []const u8) ?struct { host: []const u8, path: []const u8 } {
    const host_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
    var host = rest[0..host_end];
    if (std.mem.indexOfScalar(u8, host, '@') != null) return null;
    const path_and_more = if (host_end < rest.len) rest[host_end..] else "";
    if (std.mem.indexOfScalar(u8, host, ':')) |at| host = host[0..at];
    host = std.mem.trimEnd(u8, host, ".");
    if (host.len == 0) return null;
    for (host) |unit| {
        if (!std.ascii.isAlphanumeric(unit) and unit != '.' and unit != '-') return null;
    }
    return .{ .host = host, .path = path_and_more };
}

fn pathOf(path_and_more: []const u8) []const u8 {
    var path = path_and_more;
    if (path.len > 0 and path[0] == '/') {} else if (path.len > 0 and path[0] == '?') {
        return "/";
    } else if (path.len > 0 and path[0] == '#') {
        return "/";
    }
    const cut = std.mem.indexOfAny(u8, path, "?#") orelse path.len;
    return path[0..cut];
}

fn queryOf(path_and_more: []const u8) []const u8 {
    const question = std.mem.indexOfScalar(u8, path_and_more, '?') orelse return "";
    const cut = std.mem.indexOfScalar(u8, path_and_more[question..], '#') orelse path_and_more.len - question;
    return path_and_more[question + 1 ..][0 .. cut - 1];
}

fn queryValue(query: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..equals], key)) return pair[equals + 1 ..];
    }
    return null;
}

fn idUntilStop(segment: []const u8, provider: Provider) []const u8 {
    var len: usize = 0;
    while (len < segment.len and segment[len] != '/' and segment[len] != '?' and segment[len] != '#') : (len += 1) {
        if (!isLinkId(segment[len], provider)) break;
    }
    return segment[0..len];
}

fn classifyYoutube(host: []const u8, path_and_more: []const u8, info: *Info) bool {
    const path = pathOf(path_and_more);
    const query = queryOf(path_and_more);
    var id: []const u8 = "";
    if (std.ascii.eqlIgnoreCase(host, "youtu.be")) {
        id = if (path.len > 1 and path[0] == '/') idUntilStop(path[1..], .youtube) else "";
    } else if (std.ascii.startsWithIgnoreCase(path, "/shorts/")) {
        id = idUntilStop(path["/shorts/".len..], .youtube);
    } else if (std.ascii.startsWithIgnoreCase(path, "/embed/")) {
        id = idUntilStop(path["/embed/".len..], .youtube);
    } else if (std.ascii.startsWithIgnoreCase(path, "/live/")) {
        id = idUntilStop(path["/live/".len..], .youtube);
    } else if (std.ascii.startsWithIgnoreCase(path, "/v/")) {
        id = idUntilStop(path["/v/".len..], .youtube);
    } else if (std.ascii.startsWithIgnoreCase(path, "/watch")) {
        id = queryValue(query, "v") orelse "";
        if (id.len > max_id_len) id = "";
        for (id) |unit| {
            if (!isLinkId(unit, .youtube)) {
                id = "";
                break;
            }
        }
    }
    if (id.len < 5) return false;
    var canonical_buffer: [max_canonical_len]u8 = undefined;
    const canonical = std.fmt.bufPrint(&canonical_buffer, "https://www.youtube.com/watch?v={s}", .{id}) catch return false;
    return store(info, .youtube, id, canonical);
}

fn classifyInstagram(path: []const u8, info: *Info) bool {
    const prefixes = [_][]const u8{ "/reel/", "/reels/", "/p/", "/tv/" };
    for (prefixes) |prefix| {
        if (!std.ascii.startsWithIgnoreCase(path, prefix)) continue;
        const id = idUntilStop(path[prefix.len..], .instagram);
        if (id.len < 5) return false;
        var canonical_buffer: [max_canonical_len]u8 = undefined;
        const used_prefix: []const u8 = if (std.ascii.eqlIgnoreCase(prefix, "/reels/")) "/reel/" else prefix;
        const canonical = std.fmt.bufPrint(&canonical_buffer, "https://www.instagram.com{s}{s}/", .{ used_prefix, id }) catch return false;
        return store(info, .instagram, id, canonical);
    }
    return false;
}

fn classifyFacebook(host: []const u8, path_and_more: []const u8, info: *Info) bool {
    const path = pathOf(path_and_more);
    const query = queryOf(path_and_more);
    var canonical_buffer: [max_canonical_len]u8 = undefined;
    var id: []const u8 = "";
    if (std.ascii.eqlIgnoreCase(host, "fb.watch")) {
        id = if (path.len > 1 and path[0] == '/') idUntilStop(path[1..], .facebook) else "";
        if (id.len == 0) return false;
        const canonical = std.fmt.bufPrint(&canonical_buffer, "https://fb.watch/{s}/", .{id}) catch return false;
        return store(info, .facebook, id, canonical);
    }
    if (std.ascii.startsWithIgnoreCase(path, "/watch")) {
        const value = queryValue(query, "v") orelse return false;
        if (value.len == 0 or value.len > max_id_len) return false;
        for (value) |unit| {
            if (!isLinkId(unit, .facebook)) return false;
        }
        const canonical = std.fmt.bufPrint(&canonical_buffer, "https://www.facebook.com/watch?v={s}", .{value}) catch return false;
        return store(info, .facebook, value, canonical);
    }
    if (std.ascii.startsWithIgnoreCase(path, "/share/v/")) {
        id = idUntilStop(path["/share/v/".len..], .facebook);
        if (id.len == 0) return false;
        const canonical = std.fmt.bufPrint(&canonical_buffer, "https://www.facebook.com/share/v/{s}/", .{id}) catch return false;
        return store(info, .facebook, id, canonical);
    }
    if (std.mem.indexOf(u8, path, "/videos/") != null) {
        var last: []const u8 = "";
        var it = std.mem.splitScalar(u8, path, '/');
        while (it.next()) |segment| {
            if (segment.len == 0) continue;
            last = segment;
        }
        if (last.len == 0 or last.len > max_id_len) return false;
        var numeric = true;
        for (last) |unit| {
            if (!std.ascii.isDigit(unit)) numeric = false;
        }
        if (!numeric) return false;
        const canonical = std.fmt.bufPrint(&canonical_buffer, "https://www.facebook.com/videos/{s}/", .{last}) catch return false;
        return store(info, .facebook, last, canonical);
    }
    return false;
}

pub fn classify(url: []const u8) Info {
    var info = Info{};
    var cleaned = std.mem.trim(u8, url, " \t\r\n");
    cleaned = trimTrailingPunctuation(cleaned);
    const original = cleaned;
    if (std.ascii.startsWithIgnoreCase(cleaned, "https://")) {
        cleaned = cleaned[8..];
    } else if (std.ascii.startsWithIgnoreCase(cleaned, "http://")) {
        cleaned = cleaned[7..];
    } else {
        return info;
    }
    if (cleaned.len == 0) return info;
    const parts = splitHostPath(cleaned) orelse return info;
    const provider = providerForHost(parts.host);
    switch (provider) {
        .youtube => _ = classifyYoutube(parts.host, parts.path, &info),
        .instagram => _ = classifyInstagram(pathOf(parts.path), &info),
        .facebook => _ = classifyFacebook(parts.host, parts.path, &info),
        else => {},
    }
    if (info.provider == .none) {
        var id_buffer: [max_id_len]u8 = undefined;
        const id = std.fmt.bufPrint(&id_buffer, "{x}", .{std.hash.Wyhash.hash(0, original)}) catch return info;
        _ = store(&info, if (isImageUrl(original)) .image else .page, id, original);
    }
    return info;
}

pub fn thumbnailUrl(info: *const Info, buffer: []u8) ?[]const u8 {
    if (info.provider != .youtube) return null;
    return std.fmt.bufPrint(buffer, "https://img.youtube.com/vi/{s}/hqdefault.jpg", .{info.idSlice()}) catch null;
}

fn percentEncode(out: []u8, text: []const u8) ?[]const u8 {
    var length: usize = 0;
    for (text) |unit| {
        const safe = std.ascii.isAlphanumeric(unit) or unit == '-' or unit == '.' or unit == '_' or unit == '~';
        if (safe) {
            if (length + 1 > out.len) return null;
            out[length] = unit;
            length += 1;
        } else {
            if (length + 3 > out.len) return null;
            _ = std.fmt.bufPrint(out[length..][0..3], "%{X:0>2}", .{unit}) catch return null;
            length += 3;
        }
    }
    return out[0..length];
}

pub fn oembedEndpoint(info: *const Info, buffer: []u8) ?[]const u8 {
    if (info.provider != .youtube) return null;
    const head = "https://www.youtube.com/oembed?url=";
    const tail = "&format=json";
    const encoded = percentEncode(buffer[head.len .. buffer.len - tail.len], info.canonicalSlice()) orelse return null;
    @memcpy(buffer[0..head.len], head);
    const tail_start = head.len + encoded.len;
    @memcpy(buffer[tail_start..][0..tail.len], tail);
    return buffer[0 .. tail_start + tail.len];
}

fn suffixMatches(host: []const u8, suffix: []const u8) bool {
    return host.len > suffix.len and std.ascii.endsWithIgnoreCase(host, suffix);
}

pub fn siteHost(url: []const u8) []const u8 {
    const offset: usize = if (std.ascii.startsWithIgnoreCase(url, "https://")) 8 else if (std.ascii.startsWithIgnoreCase(url, "http://")) 7 else return "";
    const parts = splitHostPath(url[offset..]) orelse return "";
    return parts.host;
}

pub fn isImageUrl(url: []const u8) bool {
    const offset: usize = if (std.ascii.startsWithIgnoreCase(url, "https://")) 8 else if (std.ascii.startsWithIgnoreCase(url, "http://")) 7 else return false;
    const parts = splitHostPath(url[offset..]) orelse return false;
    const path = pathOf(parts.path);
    for ([_][]const u8{ ".png", ".jpg", ".jpeg", ".gif", ".webp" }) |extension| {
        if (std.ascii.endsWithIgnoreCase(path, extension)) return true;
    }
    return false;
}

pub fn resolveImageUrl(page_url: []const u8, image: []const u8, buffer: []u8) ?[]const u8 {
    if (image.len == 0) return null;
    if (std.ascii.startsWithIgnoreCase(image, "https://") or std.ascii.startsWithIgnoreCase(image, "http://")) return image;
    const scheme_end = std.mem.indexOf(u8, page_url, "://") orelse return null;
    if (std.mem.startsWith(u8, image, "//")) return std.fmt.bufPrint(buffer, "{s}:{s}", .{ page_url[0..scheme_end], image }) catch null;
    if (std.mem.indexOfScalar(u8, image, ':') != null) return null;
    const authority_start = scheme_end + 3;
    const authority_end = std.mem.indexOfScalarPos(u8, page_url, authority_start, '/') orelse page_url.len;
    const origin_end = std.mem.indexOfAny(u8, page_url[authority_start..authority_end], "?#") orelse authority_end - authority_start;
    const origin = page_url[0 .. authority_start + origin_end];
    if (image[0] == '/') return std.fmt.bufPrint(buffer, "{s}{s}", .{ origin, image }) catch null;
    const clean_end = std.mem.indexOfAny(u8, page_url, "?#") orelse page_url.len;
    const slash = std.mem.lastIndexOfScalar(u8, page_url[0..clean_end], '/') orelse return null;
    const base = if (slash >= authority_start) page_url[0 .. slash + 1] else "";
    return if (base.len > 0) std.fmt.bufPrint(buffer, "{s}{s}", .{ base, image }) catch null else std.fmt.bufPrint(buffer, "{s}/{s}", .{ origin, image }) catch null;
}

pub fn isPageFetchAllowed(url: []const u8) bool {
    if (std.mem.indexOfAny(u8, url, " \t\r\n\\") != null) return false;
    const host = siteHost(url);
    if (host.len == 0 or std.mem.indexOfScalar(u8, host, '.') == null) return false;
    if (std.ascii.eqlIgnoreCase(host, "localhost") or std.ascii.endsWithIgnoreCase(host, ".localhost") or std.ascii.endsWithIgnoreCase(host, ".local")) return false;
    if (std.ascii.isDigit(host[0])) {
        var octets = std.mem.splitScalar(u8, host, '.');
        var bytes: [4]u8 = undefined;
        for (&bytes) |*byte| byte.* = std.fmt.parseInt(u8, octets.next() orelse return false, 10) catch return false;
        if (octets.next() != null) return false;
        if (bytes[0] == 0 or bytes[0] == 10 or bytes[0] == 127 or bytes[0] >= 224 or
            (bytes[0] == 169 and bytes[1] == 254) or (bytes[0] == 172 and bytes[1] >= 16 and bytes[1] <= 31) or
            (bytes[0] == 192 and bytes[1] == 168) or (bytes[0] == 100 and bytes[1] >= 64 and bytes[1] <= 127)) return false;
    }
    return true;
}

pub fn isImageFetchAllowed(url: []const u8) bool {
    return isPageFetchAllowed(url);
}

pub fn isStreamUrlAllowed(url: []const u8) bool {
    const cleaned = trimTrailingPunctuation(url);
    if (!std.ascii.startsWithIgnoreCase(cleaned, "https://")) return false;
    const rest = cleaned[8..];
    const host_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
    const host = rest[0..host_end];
    return suffixMatches(host, ".googlevideo.com") or
        suffixMatches(host, ".cdninstagram.com") or
        suffixMatches(host, ".fbcdn.net");
}

pub fn scrapeOgMeta(page: []const u8, key: []const u8) ?[]const u8 {
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, page, search_from, "<meta")) |tag_start| {
        const tag_end = std.mem.indexOfPos(u8, page, tag_start, ">") orelse page.len;
        search_from = tag_start + 5;
        const tag = page[tag_start..tag_end];
        const has_key = std.mem.indexOf(u8, tag, key) orelse continue;
        const before_ok = has_key == 0 or tag[has_key - 1] == '"' or tag[has_key - 1] == '\'';
        const after = has_key + key.len;
        const after_ok = after >= tag.len or tag[after] == '"' or tag[after] == '\'';
        if (!before_ok or !after_ok) continue;
        const content_at = std.mem.indexOf(u8, tag, "content=\"") orelse continue;
        const rest = tag[content_at + "content=\"".len ..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse continue;
        if (end == 0) continue;
        return rest[0..end];
    }
    return null;
}

pub fn extractYoutubeStream(page: []const u8, buffer: []u8) ?[]const u8 {
    const marker = "\"https://www.googlevideo.com/videoplayback";
    const at = std.mem.indexOf(u8, page, marker) orelse return null;
    const start = at + 1;
    var length: usize = 0;
    var index = start;
    while (index < page.len and page[index] != '"' and length < buffer.len) {
        if (page[index] == '\\' and index + 6 <= page.len and
            page[index + 1] == 'u' and page[index + 2] == '0' and
            page[index + 3] == '0' and page[index + 4] == '2' and page[index + 5] == '6')
        {
            buffer[length] = '&';
            length += 1;
            index += 6;
        } else if (page[index] == '\\' and index + 1 < page.len) {
            buffer[length] = page[index + 1];
            length += 1;
            index += 2;
        } else {
            buffer[length] = page[index];
            length += 1;
            index += 1;
        }
    }
    if (length == 0 or length >= buffer.len) return null;
    if (!isStreamUrlAllowed(buffer[0..length])) return null;
    return buffer[0..length];
}

test "classify youtube watch, share and shorts" {
    const watch = classify("https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    try std.testing.expectEqual(Provider.youtube, watch.provider);
    try std.testing.expectEqualStrings("dQw4w9WgXcQ", watch.idSlice());
    try std.testing.expectEqualStrings("https://www.youtube.com/watch?v=dQw4w9WgXcQ", watch.canonicalSlice());

    const share = classify("youtu.be/dQw4w9WgXcQ?t=42");
    try std.testing.expectEqual(Provider.none, share.provider);

    const short = classify("https://youtu.be/dQw4w9WgXcQ?t=42");
    try std.testing.expectEqual(Provider.youtube, short.provider);
    try std.testing.expectEqualStrings("dQw4w9WgXcQ", short.idSlice());

    const shorts = classify("https://youtube.com/shorts/dQw4w9WgXcQ?feature=share");
    try std.testing.expectEqual(Provider.youtube, shorts.provider);

    const mobile = classify("http://m.youtube.com/watch?v=dQw4w9WgXcQ");
    try std.testing.expectEqual(Provider.youtube, mobile.provider);
    try std.testing.expectEqualStrings("https://www.youtube.com/watch?v=dQw4w9WgXcQ", mobile.canonicalSlice());
}

test "classify instagram and facebook" {
    const reel = classify("https://www.instagram.com/reel/Cabcdefghij/");
    try std.testing.expectEqual(Provider.instagram, reel.provider);
    try std.testing.expectEqualStrings("Cabcdefghij", reel.idSlice());
    try std.testing.expectEqualStrings("https://www.instagram.com/reel/Cabcdefghij/", reel.canonicalSlice());

    const reels = classify("https://instagram.com/reels/Cabcdefghij/");
    try std.testing.expectEqual(Provider.instagram, reels.provider);
    try std.testing.expectEqualStrings("https://www.instagram.com/reel/Cabcdefghij/", reels.canonicalSlice());

    const post = classify("https://www.instagram.com/p/Cabcdefghij/?img_index=1");
    try std.testing.expectEqual(Provider.instagram, post.provider);

    const watch = classify("https://www.facebook.com/watch?v=1234567890");
    try std.testing.expectEqual(Provider.facebook, watch.provider);
    try std.testing.expectEqualStrings("1234567890", watch.idSlice());

    const videos = classify("https://www.facebook.com/nike/videos/9876543210/");
    try std.testing.expectEqual(Provider.facebook, videos.provider);
    try std.testing.expectEqualStrings("9876543210", videos.idSlice());

    const share = classify("https://www.facebook.com/share/v/AbCdEf12345/");
    try std.testing.expectEqual(Provider.facebook, share.provider);

    const fbwatch = classify("https://fb.watch/AbCdEf123/");
    try std.testing.expectEqual(Provider.facebook, fbwatch.provider);
}

test "non-video pages are generic without impersonating video providers" {
    try std.testing.expectEqual(Provider.page, classify("https://www.instagram.com/").provider);
    try std.testing.expectEqual(Provider.page, classify("https://www.facebook.com/photo/?fbid=123").provider);
    try std.testing.expectEqual(Provider.page, classify("https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ").provider);
    try std.testing.expectEqual(Provider.page, classify("https://notyoutube.com/watch?v=dQw4w9WgXcQ").provider);
    try std.testing.expectEqual(Provider.none, classify("https://user:pass@youtube.com/watch?v=dQw4w9WgXcQ").provider); // trufflehog:ignore
    try std.testing.expectEqual(Provider.page, classify("https://www.youtube.com/channel/UC1234567890").provider);
    try std.testing.expectEqual(Provider.page, classify("https://youtu.be/ab").provider);
    try std.testing.expectEqual(Provider.page, classify("https://www.youtube.com/watch?v=../../etc").provider);
    try std.testing.expectEqual(Provider.page, classify("https://example.com/watch?v=dQw4w9WgXcQ").provider);
    try std.testing.expectEqual(Provider.none, classify("").provider);
}

test "bare host URLs never panic" {
    try std.testing.expectEqual(Provider.page, classify("https://youtu.be").provider);
    try std.testing.expectEqual(Provider.page, classify("https://fb.watch").provider);
    try std.testing.expectEqual(Provider.page, classify("https://www.instagram.com").provider);
}

test "scrapeOgMeta survives truncated html" {
    try std.testing.expect(scrapeOgMeta("<html><meta property=\"og:video", "og:video") == null);
    try std.testing.expect(scrapeOgMeta("<meta", "og:video") == null);
}

test "classify tolerates pasted punctuation" {
    const pasted = classify("https://youtu.be/dQw4w9WgXcQ.");
    try std.testing.expectEqual(Provider.youtube, pasted.provider);
    const wrapped = classify("https://youtu.be/dQw4w9WgXcQ)");
    try std.testing.expectEqual(Provider.youtube, wrapped.provider);
}

test "endpoints and fetch allowlists" {
    const watch = classify("https://youtu.be/dQw4w9WgXcQ");
    var buffer: [max_canonical_len]u8 = undefined;
    const endpoint = oembedEndpoint(&watch, &buffer).?;
    try std.testing.expectEqualStrings(
        "https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&format=json",
        endpoint,
    );
    var thumb_buffer: [max_canonical_len]u8 = undefined;
    try std.testing.expectEqualStrings(
        "https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
        thumbnailUrl(&watch, &thumb_buffer).?,
    );

    const reel = classify("https://www.instagram.com/reel/Cabcdefghij/");
    try std.testing.expect(thumbnailUrl(&reel, &thumb_buffer) == null);
    try std.testing.expect(oembedEndpoint(&reel, &buffer) == null);

    try std.testing.expect(isPageFetchAllowed("https://www.youtube.com/watch?v=dQw4w9WgXcQ"));
    try std.testing.expect(isPageFetchAllowed("https://img.youtube.com/vi/x/hqdefault.jpg"));
    try std.testing.expect(isPageFetchAllowed("http://www.youtube.com/watch?v=dQw4w9WgXcQ"));
    try std.testing.expect(isImageFetchAllowed("https://img.youtube.com/vi/x/hqdefault.jpg"));
    try std.testing.expect(isImageFetchAllowed("https://scontent-arn2-1.cdninstagram.com/v/x.jpg"));
    try std.testing.expect(isImageFetchAllowed("https://scontent.xx.fbcdn.net/v/x.jpg"));
    try std.testing.expect(isImageFetchAllowed("https://evil.com/.cdninstagram.com/x.jpg"));
    try std.testing.expect(isStreamUrlAllowed("https://rr3---sn-x.googlevideo.com/videoplayback?x=1"));
    try std.testing.expect(isStreamUrlAllowed("https://scontent-arn2-1.cdninstagram.com/v.mp4"));
    try std.testing.expect(!isStreamUrlAllowed("http://rr3---sn-x.googlevideo.com/videoplayback"));
    try std.testing.expect(!isStreamUrlAllowed("https://evil.com/?x=.googlevideo.com"));
}

test "og scraping and stream extraction" {
    const page = "<html><meta property=\"og:video\" content=\"https://scontent-1.cdninstagram.com/v.mp4\" /><meta property=\"og:image\" content=\"https://scontent-1.cdninstagram.com/v.jpg\" /></html>";
    try std.testing.expectEqualStrings("https://scontent-1.cdninstagram.com/v.mp4", scrapeOgMeta(page, "og:video").?);
    try std.testing.expectEqualStrings("https://scontent-1.cdninstagram.com/v.jpg", scrapeOgMeta(page, "og:image").?);
    try std.testing.expect(scrapeOgMeta(page, "og:title") == null);

    const swapped = "<meta content=\"https://scontent-1.cdninstagram.com/v.mp4\" property=\"og:video\">";
    try std.testing.expectEqualStrings("https://scontent-1.cdninstagram.com/v.mp4", scrapeOgMeta(swapped, "og:video").?);

    const watch_page = "{\"args\":{}}\"https://www.googlevideo.com/videoplayback?expire=1\\u0026id=dQw4w9WgXcQ\"";
    var stream_buffer: [512]u8 = undefined;
    const stream = extractYoutubeStream(watch_page, &stream_buffer).?;
    try std.testing.expectEqualStrings("https://www.googlevideo.com/videoplayback?expire=1&id=dQw4w9WgXcQ", stream);
    try std.testing.expect(extractYoutubeStream("no stream here", &stream_buffer) == null);
    try std.testing.expect(extractYoutubeStream("\"https://www.googlevideo.com.evil.com/videoplayback?id=1\"", &stream_buffer) == null);
}

test "generic pages and direct images retain full URL identity" {
    const page = classify("https://example.com/all-ads?a=1&b=2");
    try std.testing.expectEqual(Provider.page, page.provider);
    try std.testing.expectEqualStrings("https://example.com/all-ads?a=1&b=2", page.canonicalSlice());
    try std.testing.expect(!std.mem.eql(u8, page.idSlice(), classify("https://example.com/all-ads?a=2").idSlice()));
    for ([_][]const u8{ "https://screencast2.com/ivu2o.png", "https://example.com/x.JPG?download=1", "http://example.com/x.jpeg#view", "https://example.com/x.gif", "https://example.com/x.webp" }) |url| {
        try std.testing.expect(isImageUrl(url));
        try std.testing.expectEqual(Provider.image, classify(url).provider);
        try std.testing.expect(isImageFetchAllowed(url));
    }
    try std.testing.expect(!isImageUrl("https://example.com/page?file=pic.png"));
    try std.testing.expect(!isImageUrl("https://example.com/pic.png/more"));
    try std.testing.expect(!isImageUrl("file:///pic.png"));
    for ([_][]const u8{ "http://127.0.0.1/pic.png", "https://10.1.2.3/page", "https://localhost/page", "https://app.local/page", "https://user@example.com/page", "file:///page" }) |url| {
        try std.testing.expect(!isPageFetchAllowed(url));
    }
}

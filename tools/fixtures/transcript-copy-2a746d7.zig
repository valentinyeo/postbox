fn copyMarkedTranscripts(a: *App) void {
    var selected: std.ArrayList(usize) = .empty;
    defer selected.deinit(a.allocator);
    for (a.messages[0..a.message_count], 0..) |*message, index| {
        if (isAudio(message) and channelMessageVisible(a, message) and messageMarked(a, message.id.slice())) selected.append(a.allocator, index) catch {
            setTranscriptCopyNotice(a, "Could not copy transcripts");
            return;
        };
    }
    std.mem.sort(usize, selected.items, a, struct {
        fn lessThan(app: *App, left: usize, right: usize) bool {
            const order = std.mem.order(u8, app.messages[left].timestamp.slice(), app.messages[right].timestamp.slice());
            return if (order == .eq) left < right else order == .lt;
        }
    }.lessThan);
    var combined: std.ArrayList(u16) = .empty;
    defer combined.deinit(a.allocator);
    var missing: std.ArrayList(u8) = .empty;
    defer missing.deinit(a.allocator);
    var copied: usize = 0;
    for (selected.items) |index| {
        const message = &a.messages[index];
        const raw: ?[]u8 = raw: {
            if (message.local_path.len == 0) break :raw null;
            const path = std.unicode.utf16LeToUtf8Alloc(a.allocator, message.local_path.slice()) catch break :raw null;
            defer a.allocator.free(path);
            const cache = std.fmt.allocPrint(a.allocator, "{s}.txt", .{path}) catch break :raw null;
            defer a.allocator.free(cache);
            break :raw readFileWin(a.allocator, cache, format_cache.max_bytes);
        };
        defer if (raw) |text| a.allocator.free(text);
        if (raw) |text| {
            if (std.mem.trim(u8, text, " \r\n\t").len > 0 and std.mem.indexOfScalar(u8, text, 0) == null and std.unicode.utf8ValidateSlice(text)) {
                const wide = std.unicode.utf8ToUtf16LeAlloc(a.allocator, text) catch {
                    setTranscriptCopyNotice(a, "Could not copy transcripts");
                    return;
                };
                defer a.allocator.free(wide);
                if (copied > 0) combined.appendSlice(a.allocator, &.{ '\r', '\n', '\r', '\n' }) catch {
                    setTranscriptCopyNotice(a, "Could not copy transcripts");
                    return;
                };
                combined.appendSlice(a.allocator, wide) catch {
                    setTranscriptCopyNotice(a, "Could not copy transcripts");
                    return;
                };
                copied += 1;
                continue;
            }
        }
        if (missing.items.len > 0) missing.appendSlice(a.allocator, ", ") catch return;
        var time: [64]u8 = undefined;
        const len = std.unicode.utf16LeToUtf8(&time, message.time.slice()) catch 0;
        missing.appendSlice(a.allocator, if (len > 0) time[0..len] else message.id.slice()) catch return;
    }
    if (copied > 0 and !copyRawToClipboard(a, combined.items)) {
        setTranscriptCopyNotice(a, "Could not copy transcripts");
        return;
    }
    var buffer: [512]u8 = undefined;
    const notice = if (missing.items.len > 0)
        std.fmt.bufPrint(&buffer, "Copied {d} transcripts. Missing: {s}", .{ copied, missing.items }) catch "Some marked voice messages have no raw transcript"
    else
        std.fmt.bufPrint(&buffer, "Copied {d} transcripts", .{copied}) catch "Transcripts copied";
    setTranscriptCopyNotice(a, notice);
}

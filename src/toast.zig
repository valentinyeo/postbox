const std = @import("std");
const win = @import("win32.zig").c;
const toast_xml = @import("toast_xml.zig");

fn lit(comptime text: []const u8) [*:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}

pub const app_id = "Postbox";
pub const kept = 8;

const HRESULT = i32;
const Hstring = ?*anyopaque;
const Guid = extern struct { a: u32, b: u16, c: u16, d: [8]u8 };

const iid_unknown = Guid{ .a = 0x00000000, .b = 0x0000, .c = 0x0000, .d = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
const iid_agile = Guid{ .a = 0x94ea2b94, .b = 0xe9cc, .c = 0x49e0, .d = .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 } };
const iid_activated_handler = Guid{ .a = 0xab54de2d, .b = 0x97d9, .c = 0x5528, .d = .{ 0xb6, 0xad, 0x10, 0x5a, 0xfe, 0x15, 0x65, 0x30 } };
const iid_toast_statics = Guid{ .a = 0x50ac103f, .b = 0xd235, .c = 0x4598, .d = .{ 0xbb, 0xef, 0x98, 0xfe, 0x4d, 0x1a, 0x3a, 0xd4 } };
const iid_toast_factory = Guid{ .a = 0x04124b20, .b = 0x82c6, .c = 0x4229, .d = .{ 0xb1, 0x09, 0xfd, 0x9e, 0xd4, 0x66, 0x2b, 0x53 } };
const iid_xml_io = Guid{ .a = 0x6cd0e74e, .b = 0xee65, .c = 0x4489, .d = .{ 0x9e, 0xbf, 0xca, 0x43, 0xe8, 0x7b, 0xa6, 0x37 } };

const FnCreateString = *const fn ([*]const u16, u32, *Hstring) callconv(.winapi) HRESULT;
const FnDeleteString = *const fn (Hstring) callconv(.winapi) HRESULT;
const FnGetFactory = *const fn (Hstring, *const Guid, *?*anyopaque) callconv(.winapi) HRESULT;
const FnActivate = *const fn (Hstring, *?*anyopaque) callconv(.winapi) HRESULT;

const Api = struct {
    create_string: FnCreateString,
    delete_string: FnDeleteString,
    get_factory: FnGetFactory,
    activate: FnActivate,
};

var api: ?Api = null;
var api_failed = false;
var notifier: ?*anyopaque = null;
var factory: ?*anyopaque = null;
var held: [kept]?*anyopaque = [_]?*anyopaque{null} ** kept;
var held_next: usize = 0;

fn slot(comptime Fn: type, object: *anyopaque, index: usize) Fn {
    const table: *const [*]const usize = @ptrCast(@alignCast(object));
    return @ptrFromInt(table.*[index]);
}

fn release(object: ?*anyopaque) void {
    const target = object orelse return;
    _ = slot(*const fn (*anyopaque) callconv(.winapi) u32, target, 2)(target);
}

fn queryInterface(object: *anyopaque, iid: *const Guid) ?*anyopaque {
    var out: ?*anyopaque = null;
    if (slot(*const fn (*anyopaque, *const Guid, *?*anyopaque) callconv(.winapi) HRESULT, object, 0)(object, iid, &out) < 0) return null;
    return out;
}

fn loadApi() ?Api {
    if (api) |loaded| return loaded;
    if (api_failed) return null;
    api_failed = true;
    const combase = win.LoadLibraryW(lit("combase.dll")) orelse return null;
    const create_string = win.GetProcAddress(combase, "WindowsCreateString") orelse return null;
    const delete_string = win.GetProcAddress(combase, "WindowsDeleteString") orelse return null;
    const get_factory = win.GetProcAddress(combase, "RoGetActivationFactory") orelse return null;
    const activate = win.GetProcAddress(combase, "RoActivateInstance") orelse return null;
    api = .{
        .create_string = @ptrCast(@alignCast(create_string)),
        .delete_string = @ptrCast(@alignCast(delete_string)),
        .get_factory = @ptrCast(@alignCast(get_factory)),
        .activate = @ptrCast(@alignCast(activate)),
    };
    api_failed = false;
    return api;
}

fn classString(loaded: Api, comptime name: []const u8) ?Hstring {
    var handle: Hstring = null;
    const wide = comptime std.unicode.utf8ToUtf16LeStringLiteral(name);
    if (loaded.create_string(wide, name.len, &handle) < 0) return null;
    return handle;
}

fn activationFactory(loaded: Api, comptime class: []const u8, iid: *const Guid) ?*anyopaque {
    const name = classString(loaded, class) orelse return null;
    defer _ = loaded.delete_string(name);
    var out: ?*anyopaque = null;
    if (loaded.get_factory(name, iid, &out) < 0) return null;
    return out;
}

const Handler = extern struct {
    vtable: *const Table,
    refs: u32,
    hwnd: win.HWND,
    message: u32,
    index: usize,

    const Table = extern struct {
        query: *const fn (*Handler, *const Guid, *?*anyopaque) callconv(.winapi) HRESULT,
        add: *const fn (*Handler) callconv(.winapi) u32,
        drop: *const fn (*Handler) callconv(.winapi) u32,
        invoke: *const fn (*Handler, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };

    const shared = Table{ .query = query, .add = add, .drop = drop, .invoke = invoke };

    fn same(left: *const Guid, right: *const Guid) bool {
        return std.mem.eql(u8, std.mem.asBytes(left), std.mem.asBytes(right));
    }

    fn query(self: *Handler, iid: *const Guid, out: *?*anyopaque) callconv(.winapi) HRESULT {
        if (same(iid, &iid_unknown) or same(iid, &iid_agile) or same(iid, &iid_activated_handler)) {
            _ = @atomicRmw(u32, &self.refs, .Add, 1, .monotonic);
            out.* = self;
            return 0;
        }
        out.* = null;
        return @bitCast(@as(u32, 0x80004002));
    }

    fn add(self: *Handler) callconv(.winapi) u32 {
        return @atomicRmw(u32, &self.refs, .Add, 1, .monotonic) + 1;
    }

    fn drop(self: *Handler) callconv(.winapi) u32 {
        const left = @atomicRmw(u32, &self.refs, .Sub, 1, .acq_rel) - 1;
        if (left == 0) std.heap.page_allocator.destroy(self);
        return left;
    }

    fn invoke(self: *Handler, sender: ?*anyopaque, args: ?*anyopaque) callconv(.winapi) HRESULT {
        _ = sender;
        _ = args;
        if (self.hwnd != null) _ = win.PostMessageW(self.hwnd, self.message, self.index, 0);
        return 0;
    }
};

fn utf16Alloc(text: []const u8, buffer: []u16) ?[]const u16 {
    const length = std.unicode.utf8ToUtf16Le(buffer, text) catch return null;
    return buffer[0..length];
}

fn ensureNotifier(loaded: Api) bool {
    if (notifier != null and factory != null) return true;
    const statics = activationFactory(loaded, "Windows.UI.Notifications.ToastNotificationManager", &iid_toast_statics) orelse return false;
    defer release(statics);
    var id_buffer: [32]u16 = undefined;
    const id = utf16Alloc(app_id, &id_buffer) orelse return false;
    var id_handle: Hstring = null;
    if (loaded.create_string(id.ptr, @intCast(id.len), &id_handle) < 0) return false;
    defer _ = loaded.delete_string(id_handle);
    var made: ?*anyopaque = null;
    if (slot(*const fn (*anyopaque, Hstring, *?*anyopaque) callconv(.winapi) HRESULT, statics, 7)(statics, id_handle, &made) < 0 or made == null) return false;
    const made_factory = activationFactory(loaded, "Windows.UI.Notifications.ToastNotification", &iid_toast_factory) orelse {
        release(made);
        return false;
    };
    notifier = made;
    factory = made_factory;
    return true;
}

fn hkeyAt(value: usize) win.HKEY {
    @setRuntimeSafety(false);
    return @ptrFromInt(value);
}

var registered = false;

fn writeIcon(png: []const u8, out: *[330]u16) ?[]const u16 {
    var local: [260]u16 = undefined;
    const local_len = win.GetEnvironmentVariableW(lit("LOCALAPPDATA"), &local, local.len);
    if (local_len == 0 or local_len >= local.len) return null;
    const suffix = std.unicode.utf8ToUtf16LeStringLiteral("\\Messages\\toast-icon.png");
    const suffix_len = suffix.len;
    if (local_len + suffix_len >= out.len) return null;
    @memcpy(out[0..local_len], local[0..local_len]);
    @memcpy(out[local_len..][0..suffix_len], suffix[0..suffix_len]);
    const total = local_len + suffix_len;
    out[total] = 0;
    const handle = win.CreateFileW(@ptrCast(out), win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    if (handle == win.INVALID_HANDLE_VALUE or handle == null) return null;
    defer _ = win.CloseHandle(handle);
    var done: usize = 0;
    while (done < png.len) {
        var written: win.DWORD = 0;
        if (win.WriteFile(handle, png[done..].ptr, @intCast(png.len - done), &written, null) == 0 or written == 0) return null;
        done += written;
    }
    return out[0..total];
}

pub fn register(display_name: []const u8, icon_png: []const u8) void {
    if (registered) return;
    registered = true;
    var path: [96]u16 = undefined;
    var narrow: [96]u8 = undefined;
    const text = std.fmt.bufPrint(&narrow, "Software\\Classes\\AppUserModelId\\{s}", .{app_id}) catch return;
    const wide_path = utf16Alloc(text, &path) orelse return;
    path[wide_path.len] = 0;
    var key: win.HKEY = null;
    if (win.RegCreateKeyExW(hkeyAt(0x80000001), @ptrCast(&path), 0, null, 0, win.KEY_SET_VALUE, null, &key, null) != win.ERROR_SUCCESS) return;
    defer _ = win.RegCloseKey(key);
    var name: [64]u16 = undefined;
    const name_wide = utf16Alloc(display_name, name[0 .. name.len - 1]) orelse return;
    name[name_wide.len] = 0;
    _ = win.RegSetValueExW(key, lit("DisplayName"), 0, win.REG_SZ, @ptrCast(&name), @intCast((name_wide.len + 1) * 2));
    var icon_path: [330]u16 = undefined;
    if (writeIcon(icon_png, &icon_path)) |icon| {
        _ = win.RegSetValueExW(key, lit("IconUri"), 0, win.REG_SZ, @ptrCast(&icon_path), @intCast((icon.len + 1) * 2));
    }
}

pub fn show(hwnd: win.HWND, message: u32, index: usize, title: []const u8, body: []const u8) bool {
    const loaded = loadApi() orelse return false;
    if (!ensureNotifier(loaded)) return false;
    var xml_utf8: [toast_xml.max_xml_bytes]u8 = undefined;
    const xml = toast_xml.build(&xml_utf8, title, body) orelse return false;
    var xml_wide: [toast_xml.max_xml_bytes]u16 = undefined;
    const wide = utf16Alloc(xml, &xml_wide) orelse return false;

    const document = blk: {
        const class = classString(loaded, "Windows.Data.Xml.Dom.XmlDocument") orelse return false;
        defer _ = loaded.delete_string(class);
        var instance: ?*anyopaque = null;
        if (loaded.activate(class, &instance) < 0) return false;
        break :blk instance orelse return false;
    };
    defer release(document);
    const loader = queryInterface(document, &iid_xml_io) orelse return false;
    defer release(loader);
    var xml_handle: Hstring = null;
    if (loaded.create_string(wide.ptr, @intCast(wide.len), &xml_handle) < 0) return false;
    defer _ = loaded.delete_string(xml_handle);
    if (slot(*const fn (*anyopaque, Hstring) callconv(.winapi) HRESULT, loader, 6)(loader, xml_handle) < 0) return false;

    var notification: ?*anyopaque = null;
    const factory_object = factory orelse return false;
    if (slot(*const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.winapi) HRESULT, factory_object, 6)(factory_object, document, &notification) < 0) return false;
    const toast = notification orelse return false;
    var keep = false;
    defer if (!keep) release(toast);

    const handler = std.heap.page_allocator.create(Handler) catch return false;
    handler.* = .{ .vtable = &Handler.shared, .refs = 1, .hwnd = hwnd, .message = message, .index = index };
    defer _ = Handler.drop(handler);
    var registration: i64 = 0;
    _ = slot(*const fn (*anyopaque, *anyopaque, *i64) callconv(.winapi) HRESULT, toast, 12)(toast, handler, &registration);

    const show_object = notifier orelse return false;
    if (slot(*const fn (*anyopaque, *anyopaque) callconv(.winapi) HRESULT, show_object, 6)(show_object, toast) < 0) return false;

    release(held[held_next]);
    held[held_next] = toast;
    held_next = (held_next + 1) % kept;
    keep = true;
    return true;
}

const std = @import("std");
const win = @import("win32.zig").c;
const contract = @import("edit_contract.zig");
const text_draw = @import("text_draw.zig");
const theme = @import("theme.zig");

pub const class_name = std.unicode.utf8ToUtf16LeStringLiteral(contract.class_name);
const ok: win.HRESULT = 0;
const no_interface: win.HRESULT = @bitCast(@as(u32, 0x80004002));
const failed: win.HRESULT = @bitCast(@as(u32, 0x80004005));
const iid_unknown = guid(0, 0, 0, .{ 0xc0, 0, 0, 0, 0, 0, 0, 0x46 });
const iid_host = guid(0x13e670f4, 0x1a5a, 0x11cf, .{ 0xab, 0xeb, 0, 0xaa, 0, 0xb6, 0x5e, 0xa1 });
const iid_host2 = guid(0x13e670f5, 0x1a5a, 0x11cf, .{ 0xab, 0xeb, 0, 0xaa, 0, 0xb6, 0x5e, 0xa1 });
const iid_services2 = guid(0x8d33f741, 0xcf58, 0x11ce, .{ 0xa8, 0x9d, 0, 0xaa, 0, 0x6c, 0xad, 0xc5 });
const iid_d2d_factory = guid(0x06152247, 0x6f50, 0x465a, .{ 0x92, 0x45, 0x11, 0x8b, 0xfd, 0x3b, 0x60, 0x07 });

const Object = extern struct {
    vtable: [*]const *const anyopaque,

    fn method(self: *Object, comptime index: usize, comptime T: type) T {
        return @ptrCast(self.vtable[index]);
    }

    fn release(self: *Object) void {
        _ = self.method(2, *const fn (*Object) callconv(.winapi) u32)(self);
    }

    fn query(self: *Object, iid: *const win.GUID, out: *?*Object) win.HRESULT {
        return self.method(0, *const fn (*Object, *const win.GUID, *?*Object) callconv(.winapi) win.HRESULT)(self, iid, out);
    }

    fn send(self: *Object, message: u32, wparam: usize, lparam: isize) win.LRESULT {
        var result: win.LRESULT = 0;
        _ = self.method(3, *const fn (*Object, u32, usize, isize, *win.LRESULT) callconv(.winapi) win.HRESULT)(self, message, wparam, lparam, &result);
        return result;
    }

    fn property(self: *Object, mask: u32, bits: u32) void {
        _ = self.method(19, *const fn (*Object, u32, u32) callconv(.winapi) win.HRESULT)(self, mask, bits);
    }

    fn activate(self: *Object, rect: *const win.RECT) win.HRESULT {
        return self.method(9, *const fn (*Object, *const win.RECT) callconv(.winapi) win.HRESULT)(self, rect);
    }

    fn deactivate(self: *Object) void {
        _ = self.method(10, *const fn (*Object) callconv(.winapi) win.HRESULT)(self);
    }

    fn uiActivate(self: *Object, active: bool) void {
        const index: usize = if (active) 11 else 12;
        const activate_fn: *const fn (*Object) callconv(.winapi) win.HRESULT = @ptrCast(self.vtable[index]);
        _ = activate_fn(self);
    }

    fn draw(self: *Object, target: *win.ID2D1DCRenderTarget, rect: *const win.RECT, update: ?*win.RECT) win.HRESULT {
        return self.method(22, *const fn (*Object, *win.ID2D1DCRenderTarget, *const win.RECT, ?*win.RECT, i32) callconv(.winapi) win.HRESULT)(self, target, rect, update, 0);
    }

    fn naturalHeight(self: *Object, width: i32, height: i32) ?i32 {
        var w: win.LONG = @max(1, width);
        var h: win.LONG = @max(1, height);
        var ascent: win.LONG = 0;
        const extent = win.SIZEL{ .cx = contract.himetric(w), .cy = contract.himetric(h) };
        const hr = self.method(21, *const fn (*Object, u32, win.HDC, win.HDC, ?*anyopaque, u32, *const win.SIZEL, *win.LONG, *win.LONG, *win.LONG) callconv(.winapi) win.HRESULT)(self, 1, null, null, null, 0x40000001, &extent, &w, &h, &ascent);
        return if (hr >= 0) h else null;
    }
};

const CreateServices = *const fn (?*Object, *Host, *?*Object) callconv(.winapi) win.HRESULT;
const ShutdownServices = *const fn (*Object) callconv(.winapi) win.HRESULT;
var create_services: ?CreateServices = null;
var shutdown_services: ?ShutdownServices = null;
var factory: ?*win.ID2D1Factory = null;
var registered = false;

fn guid(a: u32, b: u16, c: u16, d: [8]u8) win.GUID {
    return .{ .Data1 = a, .Data2 = b, .Data3 = c, .Data4 = d };
}

fn load(instance: win.HINSTANCE) bool {
    if (registered) return true;
    if (create_services == null) {
        const module = win.LoadLibraryExW(std.unicode.utf8ToUtf16LeStringLiteral("msftedit.dll"), null, win.LOAD_LIBRARY_SEARCH_SYSTEM32) orelse return false;
        var loaded = false;
        defer if (!loaded) {
            _ = win.FreeLibrary(module);
        };
        const create_fn: CreateServices = @ptrCast(win.GetProcAddress(module, "CreateTextServices") orelse return false);
        const shutdown_fn: ShutdownServices = @ptrCast(win.GetProcAddress(module, "ShutdownTextServices") orelse return false);
        create_services = create_fn;
        shutdown_services = shutdown_fn;
        loaded = true;
    }
    if (factory == null) {
        const module = win.LoadLibraryExW(std.unicode.utf8ToUtf16LeStringLiteral("d2d1.dll"), null, win.LOAD_LIBRARY_SEARCH_SYSTEM32) orelse return false;
        var loaded = false;
        defer if (!loaded) {
            _ = win.FreeLibrary(module);
        };
        const create_factory: *const fn (u32, *const win.GUID, ?*const anyopaque, *?*win.ID2D1Factory) callconv(.winapi) win.HRESULT = @ptrCast(win.GetProcAddress(module, "D2D1CreateFactory") orelse return false);
        if (create_factory(0, &iid_d2d_factory, null, &factory) < 0 or factory == null) return false;
        loaded = true;
    }
    var cls = std.mem.zeroes(win.WNDCLASSW);
    cls.style = win.CS_DBLCLKS;
    cls.lpfnWndProc = windowProc;
    cls.hInstance = instance;
    cls.hCursor = win.LoadCursorA(null, @ptrFromInt(32513));
    cls.lpszClassName = class_name;
    if (win.RegisterClassW(&cls) == 0) return false;
    registered = true;
    return true;
}

pub fn create(instance: win.HINSTANCE, parent: win.HWND, id: win.HMENU, style: u32, x: i32, y: i32, width: i32, height: i32) ?win.HWND {
    if (!load(instance)) return null;
    return win.CreateWindowExW(0, class_name, null, style, x, y, width, height, parent, id, instance, null);
}

pub fn contentHeight(hwnd: win.HWND, minimum: i32) i32 {
    const host = fromWindow(hwnd) orelse return minimum;
    const services = host.services orelse return minimum;
    const rect = host.textRect();
    const natural = services.naturalHeight(rect.right - rect.left, rect.bottom - rect.top) orelse return minimum;
    var client: win.RECT = undefined;
    _ = win.GetClientRect(hwnd, &client);
    return contract.contentHeight(natural, rect.top, client.bottom - rect.bottom, minimum);
}

pub fn isComposing(hwnd: ?win.HWND) bool {
    const window = hwnd orelse return false;
    var name: [64]u16 = undefined;
    const count: usize = @intCast(win.GetClassNameW(window, &name, name.len));
    if (!std.mem.eql(u16, name[0..count], class_name)) return false;
    const host = fromWindow(window) orelse return false;
    return host.composing;
}

const Host = extern struct {
    vtable: [*]const *const anyopaque = &host_vtable,
    refs: u32 = 1,
    hwnd: win.HWND,
    services: ?*Object = null,
    target: ?*win.ID2D1DCRenderTarget = null,
    font: win.HFONT = null,
    background: win.COLORREF = 0,
    char_format: win.CHARFORMAT2W = std.mem.zeroes(win.CHARFORMAT2W),
    para_format: win.PARAFORMAT = std.mem.zeroes(win.PARAFORMAT),
    multi: bool,
    enabled: bool = true,
    composing: bool = false,
    caret_null: bool = false,
    active: bool = false,
    limit: u32 = 65536,
    inset: win.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    cue: [256:0]u16 = @splat(0),
    cue_focused: bool = false,
    notifying: bool = false,

    fn textRect(self: *Host) win.RECT {
        var rect: win.RECT = undefined;
        _ = win.GetClientRect(self.hwnd, &rect);
        rect.left += self.inset.left;
        rect.top += self.inset.top;
        rect.right = @max(rect.left, rect.right - self.inset.right);
        rect.bottom = @max(rect.top, rect.bottom - self.inset.bottom);
        return rect;
    }

    fn notify(self: *Host, code: u32) void {
        if (self.notifying) return;
        self.notifying = true;
        defer self.notifying = false;
        const id: usize = @intCast(win.GetDlgCtrlID(self.hwnd));
        _ = win.SendMessageW(win.GetParent(self.hwnd), win.WM_COMMAND, id | (@as(usize, code) << 16), @bitCast(@intFromPtr(self.hwnd)));
    }

    fn invalidate(self: *Host) void {
        _ = win.InvalidateRect(self.hwnd, null, win.FALSE);
    }

    fn setFont(self: *Host, font: win.HFONT) void {
        self.font = font;
        var lf: win.LOGFONTW = std.mem.zeroes(win.LOGFONTW);
        if (win.GetObjectW(font, @sizeOf(win.LOGFONTW), &lf) == 0) return;
        self.char_format.dwMask = @as(u32, win.CFM_FACE) | win.CFM_SIZE | win.CFM_WEIGHT | win.CFM_COLOR | win.CFM_CHARSET;
        self.char_format.yHeight = contract.fontTwips(lf.lfHeight);
        self.char_format.wWeight = @intCast(lf.lfWeight);
        self.char_format.bCharSet = lf.lfCharSet;
        self.char_format.bPitchAndFamily = lf.lfPitchAndFamily;
        self.char_format.szFaceName = lf.lfFaceName;
        self.char_format.crTextColor = theme.current.on_surface;
        if (self.services) |services| {
            services.property(0x20000, 0x20000);
            _ = services.send(win.EM_SETCHARFORMAT, win.SCF_ALL, @bitCast(@intFromPtr(&self.char_format)));
            _ = services.send(win.EM_SETCHARFORMAT, win.SCF_DEFAULT, @bitCast(@intFromPtr(&self.char_format)));
        }
        self.invalidate();
    }

    fn updateColours(self: *Host, dc: win.HDC) void {
        _ = win.SetTextColor(dc, theme.current.on_surface);
        _ = win.SetBkColor(dc, theme.current.surface_container_high);
        _ = win.SendMessageW(win.GetParent(self.hwnd), win.WM_CTLCOLOREDIT, @intFromPtr(dc), @bitCast(@intFromPtr(self.hwnd)));
        const background = win.GetBkColor(dc);
        if (self.background != background) {
            self.background = background;
            if (self.services) |services| services.property(0x4000, 0x4000);
        }
        const foreground = win.GetTextColor(dc);
        if (self.char_format.crTextColor == foreground) return;
        self.char_format.crTextColor = foreground;
        if (self.services) |services| {
            var format = self.char_format;
            format.dwMask = win.CFM_COLOR;
            _ = services.send(win.EM_SETCHARFORMAT, win.SCF_ALL, @bitCast(@intFromPtr(&format)));
            _ = services.send(win.EM_SETCHARFORMAT, win.SCF_DEFAULT, @bitCast(@intFromPtr(&format)));
            services.property(0x4000, 0x4000);
        }
    }

    fn paint(self: *Host, dc: win.HDC) void {
        self.updateColours(dc);
        var client: win.RECT = undefined;
        _ = win.GetClientRect(self.hwnd, &client);
        if (client.right <= 0 or client.bottom <= 0) return;
        if (self.target == null) {
            const properties = win.D2D1_RENDER_TARGET_PROPERTIES{
                .type = win.D2D1_RENDER_TARGET_TYPE_SOFTWARE,
                .pixelFormat = .{ .format = win.DXGI_FORMAT_B8G8R8A8_UNORM, .alphaMode = win.D2D1_ALPHA_MODE_IGNORE },
                .dpiX = 96,
                .dpiY = 96,
                .usage = win.D2D1_RENDER_TARGET_USAGE_NONE,
                .minLevel = win.D2D1_FEATURE_LEVEL_DEFAULT,
            };
            if (factory.?.lpVtbl.*.CreateDCRenderTarget.?(factory.?, &properties, &self.target) < 0) return;
        }
        const target = self.target.?;
        if (target.lpVtbl.*.BindDC.?(target, dc, &client) < 0) return;
        const rt: *win.ID2D1RenderTarget = @ptrCast(target);
        const background = self.background;
        const colour = win.D2D1_COLOR_F{ .r = @as(f32, @floatFromInt(background & 255)) / 255, .g = @as(f32, @floatFromInt((background >> 8) & 255)) / 255, .b = @as(f32, @floatFromInt((background >> 16) & 255)) / 255, .a = 1 };
        if (text_draw.renderingParameters()) |parameters| rt.lpVtbl.*.SetTextRenderingParams.?(rt, @ptrCast(parameters));
        rt.lpVtbl.*.SetTextAntialiasMode.?(rt, win.D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);
        rt.lpVtbl.*.BeginDraw.?(rt);
        rt.lpVtbl.*.Clear.?(rt, &colour);
        const hr = self.services.?.draw(target, &client, null);
        const end_hr = rt.lpVtbl.*.EndDraw.?(rt, null, null);
        if (hr < 0 or end_hr < 0) {
            _ = target.lpVtbl.*.Base.Base.Base.Release.?(@ptrCast(target));
            self.target = null;
            self.invalidate();
            return;
        }
        if (self.cue[0] != 0 and self.services.?.send(win.WM_GETTEXTLENGTH, 0, 0) == 0 and (self.cue_focused or win.GetFocus() != self.hwnd)) {
            const saved = win.SaveDC(dc);
            defer _ = win.RestoreDC(dc, saved);
            _ = win.SelectObject(dc, self.font);
            _ = win.SetTextColor(dc, theme.current.on_surface_variant);
            _ = win.SetBkMode(dc, win.TRANSPARENT);
            var rect = self.textRect();
            _ = text_draw.drawText(dc, &self.cue, -1, &rect, win.DT_SINGLELINE | win.DT_VCENTER | win.DT_END_ELLIPSIS | win.DT_NOPREFIX);
        }
    }
};

fn fromWindow(hwnd: win.HWND) ?*Host {
    const value = win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA);
    return if (value == 0) null else @ptrFromInt(@as(usize, @bitCast(value)));
}

fn windowProc(hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    if (message == win.WM_NCCREATE) {
        const cs: *const win.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        const host = std.heap.page_allocator.create(Host) catch return 0;
        host.* = .{ .hwnd = hwnd, .multi = cs.style & win.ES_MULTILINE != 0, .enabled = cs.style & win.WS_DISABLED == 0, .background = theme.current.surface_container_high };
        host.char_format.cbSize = @sizeOf(win.CHARFORMAT2W);
        host.char_format.dwMask = @as(u32, win.CFM_FACE) | win.CFM_SIZE | win.CFM_WEIGHT | win.CFM_COLOR;
        host.char_format.yHeight = 255;
        host.char_format.wWeight = @intCast(@import("font_config.zig").body_weight);
        const face = std.unicode.utf8ToUtf16LeStringLiteral("IBM Plex Sans");
        @memcpy(host.char_format.szFaceName[0..face.len], face);
        host.char_format.crTextColor = theme.current.on_surface;
        host.para_format.cbSize = @sizeOf(win.PARAFORMAT);
        host.para_format.dwMask = win.PFM_ALIGNMENT;
        host.para_format.wAlignment = win.PFA_LEFT;
        _ = win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, @bitCast(@intFromPtr(host)));
        var unknown: ?*Object = null;
        if (create_services.?(null, host, &unknown) < 0 or unknown == null) {
            _ = win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, 0);
            _ = hostRelease(host);
            return 0;
        }
        const hr = unknown.?.query(&iid_services2, &host.services);
        unknown.?.release();
        if (hr < 0 or host.services == null) {
            _ = win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, 0);
            _ = hostRelease(host);
            return 0;
        }
        const services = host.services.?;
        _ = services.send(win.EM_SETTEXTMODE, win.TM_PLAINTEXT | win.TM_MULTILEVELUNDO, 0);
        _ = services.send(win.EM_SETEVENTMASK, 0, win.ENM_CHANGE | win.ENM_SELCHANGE);
        _ = services.send(win.EM_SETEDITSTYLE, win.SES_LOGICALCARET, win.SES_LOGICALCARET);
        services.property(contract.d2d_write | contract.advanced_input, contract.d2d_write | contract.advanced_input);
        var rect: win.RECT = undefined;
        _ = win.GetClientRect(hwnd, &rect);
        rect.right = @max(rect.right, 1);
        rect.bottom = @max(rect.bottom, 1);
        if (services.activate(&rect) < 0) {
            _ = shutdown_services.?(services);
            services.release();
            host.services = null;
            _ = win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, 0);
            _ = hostRelease(host);
            return 0;
        }
        host.active = true;
        return 1;
    }
    const host = fromWindow(hwnd) orelse return win.DefWindowProcW(hwnd, message, wparam, lparam);
    const services = host.services orelse return win.DefWindowProcW(hwnd, message, wparam, lparam);
    switch (message) {
        win.WM_NCDESTROY => {
            if (host.active) services.deactivate();
            _ = shutdown_services.?(services);
            services.release();
            host.services = null;
            if (host.target) |target| _ = target.lpVtbl.*.Base.Base.Base.Release.?(@ptrCast(target));
            _ = win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, 0);
            _ = hostRelease(host);
            return win.DefWindowProcW(hwnd, message, wparam, lparam);
        },
        win.WM_PAINT => {
            var ps: win.PAINTSTRUCT = undefined;
            const dc = win.BeginPaint(hwnd, &ps);
            defer _ = win.EndPaint(hwnd, &ps);
            const focused = win.GetFocus() == hwnd;
            if (focused) _ = win.HideCaret(hwnd);
            defer if (focused) {
                _ = win.ShowCaret(hwnd);
            };
            host.paint(dc);
            return 0;
        },
        win.WM_PRINTCLIENT => {
            host.paint(@ptrFromInt(wparam));
            return 0;
        },
        win.WM_ERASEBKGND => return 1,
        win.WM_SIZE => {
            services.property(0x100000 | 0x2000 | 0x80000, 0x100000 | 0x2000 | 0x80000);
            host.invalidate();
            return 0;
        },
        win.WM_ENABLE => {
            host.enabled = wparam != 0;
            services.property(4, if (host.enabled) 0 else 4);
            host.invalidate();
            return 0;
        },
        win.WM_SETFOCUS, win.WM_KILLFOCUS => {
            if (message == win.WM_SETFOCUS) services.uiActivate(true);
            const result = services.send(message, wparam, lparam);
            if (message == win.WM_KILLFOCUS) {
                services.uiActivate(false);
                host.composing = false;
            }
            host.notify(if (message == win.WM_SETFOCUS) win.EN_SETFOCUS else win.EN_KILLFOCUS);
            host.invalidate();
            return result;
        },
        win.WM_IME_STARTCOMPOSITION => host.composing = true,
        win.WM_IME_ENDCOMPOSITION => host.composing = false,
        win.WM_GETDLGCODE => return win.DLGC_WANTCHARS | win.DLGC_WANTARROWS | win.DLGC_HASSETSEL,
        win.WM_GETOBJECT => return win.DefWindowProcW(hwnd, message, wparam, lparam),
        win.WM_SETCURSOR => {
            _ = win.SetCursor(win.LoadCursorA(null, @ptrFromInt(32513)));
            return 1;
        },
        else => {},
    }
    switch (contract.messageRoute(message)) {
        .font => {
            if (message == win.WM_GETFONT) return @bitCast(@intFromPtr(host.font));
            host.setFont(@ptrFromInt(wparam));
            return 0;
        },
        .cue => {
            if (message == win.EM_SETCUEBANNER) {
                const input: [*:0]const u16 = @ptrFromInt(@as(usize, @bitCast(lparam)));
                const count = @min(std.mem.len(input), host.cue.len - 1);
                @memcpy(host.cue[0..count], input[0..count]);
                host.cue[count] = 0;
                host.cue_focused = wparam != 0;
                host.invalidate();
                return 1;
            }
            if (wparam == 0 or lparam <= 0) return 0;
            const out: [*]u16 = @ptrFromInt(wparam);
            const count = @min(std.mem.len(@as([*:0]const u16, &host.cue)), @as(usize, @intCast(lparam)) - 1);
            @memcpy(out[0..count], host.cue[0..count]);
            out[count] = 0;
            return 1;
        },
        .rectangle => {
            if (lparam == 0) return 0;
            const rect: *win.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            if (message == win.EM_GETRECT) {
                rect.* = host.textRect();
            } else {
                var client: win.RECT = undefined;
                _ = win.GetClientRect(hwnd, &client);
                host.inset = .{ .left = rect.left, .top = rect.top, .right = client.right - rect.right, .bottom = client.bottom - rect.bottom };
                services.property(0x2000, 0x2000);
                if (message == win.EM_SETRECT) host.invalidate();
            }
            return 0;
        },
        .margins => {
            if (message == win.EM_GETMARGINS) return @as(isize, host.inset.left) | (@as(isize, host.inset.right) << 16);
            if (wparam & win.EC_LEFTMARGIN != 0) host.inset.left = @intCast(@as(usize, @bitCast(lparam)) & 0xffff);
            if (wparam & win.EC_RIGHTMARGIN != 0) host.inset.right = @intCast((@as(usize, @bitCast(lparam)) >> 16) & 0xffff);
            services.property(0x2000, 0x2000);
            host.invalidate();
            return 0;
        },
        .limit => {
            host.limit = if (wparam == 0) 0x7ffffffe else @intCast(@min(wparam, 0x7ffffffe));
            services.property(0x8000, 0x8000);
            return services.send(win.EM_EXLIMITTEXT, 0, host.limit);
        },
        .position => {
            var point: win.POINTL = .{ .x = 0, .y = 0 };
            _ = services.send(win.WM_USER + 38, @intFromPtr(&point), @intCast(wparam));
            const x: u16 = @bitCast(@as(i16, @intCast(std.math.clamp(point.x, -32768, 32767))));
            const y: u16 = @bitCast(@as(i16, @intCast(std.math.clamp(point.y, -32768, 32767))));
            return @as(isize, x) | (@as(isize, y) << 16);
        },
        .text => {
            if (message == win.WM_SETTEXT) {
                const result = services.send(message, wparam, lparam);
                host.notify(win.EN_CHANGE);
                host.invalidate();
                return result;
            }
            if (message == win.WM_GETTEXTLENGTH) {
                const request = win.GETTEXTLENGTHEX{ .flags = win.GTL_PRECISE | win.GTL_NUMCHARS, .codepage = 1200 };
                return services.send(win.EM_GETTEXTLENGTHEX, @intFromPtr(&request), 0);
            }
            if (wparam == 0) return 0;
            const request = win.GETTEXTEX{ .cb = @intCast(@min(wparam, 0x7fffffff) * 2), .flags = win.GT_DEFAULT, .codepage = 1200, .lpDefaultChar = null, .lpUsedDefChar = null };
            const count = services.send(win.EM_GETTEXTEX, @intFromPtr(&request), lparam);
            if (count > 0) {
                const text: [*]u16 = @ptrFromInt(@as(usize, @bitCast(lparam)));
                for (text[0..@intCast(count)]) |*unit| {
                    if (unit.* == '\r') unit.* = '\n';
                }
            }
            return count;
        },
        .native => {},
    }
    var result: win.LRESULT = 0;
    const hr = services.method(3, *const fn (*Object, u32, usize, isize, *win.LRESULT) callconv(.winapi) win.HRESULT)(services, message, wparam, lparam, &result);
    if (hr != 0) return win.DefWindowProcW(hwnd, message, wparam, lparam);
    return result;
}

fn hostQuery(self: *Host, iid: *const win.GUID, out: *?*anyopaque) callconv(.winapi) win.HRESULT {
    out.* = null;
    for ([_]win.GUID{ iid_unknown, iid_host, iid_host2 }) |supported| {
        if (std.mem.eql(u8, std.mem.asBytes(iid), std.mem.asBytes(&supported))) {
            out.* = self;
            _ = hostAddRef(self);
            return ok;
        }
    }
    return no_interface;
}
fn hostAddRef(self: *Host) callconv(.winapi) u32 {
    self.refs += 1;
    return self.refs;
}
fn hostRelease(self: *Host) callconv(.winapi) u32 {
    self.refs -= 1;
    const refs = self.refs;
    if (refs == 0) std.heap.page_allocator.destroy(self);
    return refs;
}
fn getDC(self: *Host) callconv(.winapi) win.HDC {
    return win.GetDC(self.hwnd);
}
fn releaseDC(self: *Host, dc: win.HDC) callconv(.winapi) i32 {
    return win.ReleaseDC(self.hwnd, dc);
}
fn showScrollBar(_: *Host, _: i32, _: win.BOOL) callconv(.winapi) win.BOOL {
    return win.TRUE;
}
fn enableScrollBar(_: *Host, _: i32, _: i32) callconv(.winapi) win.BOOL {
    return win.TRUE;
}
fn setScrollRange(_: *Host, _: i32, _: i32, _: i32, _: win.BOOL) callconv(.winapi) win.BOOL {
    return win.TRUE;
}
fn setScrollPos(_: *Host, _: i32, _: i32, _: win.BOOL) callconv(.winapi) win.BOOL {
    return win.TRUE;
}
fn invalidateRect(self: *Host, rect: [*c]const win.RECT, _: win.BOOL) callconv(.winapi) void {
    _ = win.InvalidateRect(self.hwnd, rect, win.FALSE);
}
fn viewChange(self: *Host, _: win.BOOL) callconv(.winapi) void {
    self.invalidate();
}
fn createCaret(self: *Host, flags: win.HBITMAP, width: i32, height: i32) callconv(.winapi) win.BOOL {
    self.caret_null = @intFromPtr(flags) & 64 != 0;
    return win.CreateCaret(self.hwnd, null, @max(1, width), @max(1, height));
}
fn showCaret(self: *Host, show: win.BOOL) callconv(.winapi) win.BOOL {
    if (show != 0 and self.caret_null) return win.TRUE;
    return if (show != 0) win.ShowCaret(self.hwnd) else win.HideCaret(self.hwnd);
}
fn setCaretPos(_: *Host, x: i32, y: i32) callconv(.winapi) win.BOOL {
    return win.SetCaretPos(x, y);
}
fn setTimer(self: *Host, id: u32, timeout: u32) callconv(.winapi) win.BOOL {
    return if (win.SetTimer(self.hwnd, id, timeout, null) != 0) win.TRUE else win.FALSE;
}
fn killTimer(self: *Host, id: u32) callconv(.winapi) void {
    _ = win.KillTimer(self.hwnd, id);
}
fn scrollWindow(self: *Host, _: i32, _: i32, _: [*c]const win.RECT, _: [*c]const win.RECT, _: win.HRGN, update: [*c]win.RECT, _: u32) callconv(.winapi) void {
    if (update != null) _ = win.GetClientRect(self.hwnd, update);
    self.invalidate();
}
fn setCapture(self: *Host, capture: win.BOOL) callconv(.winapi) void {
    if (capture != 0) {
        _ = win.SetCapture(self.hwnd);
    } else {
        _ = win.ReleaseCapture();
    }
}
fn setFocus(self: *Host) callconv(.winapi) void {
    _ = win.SetFocus(self.hwnd);
}
fn setCursor(_: *Host, cursor: win.HCURSOR, _: win.BOOL) callconv(.winapi) void {
    _ = win.SetCursor(cursor);
}
fn screenToClient(self: *Host, point: *win.POINT) callconv(.winapi) win.BOOL {
    return win.ScreenToClient(self.hwnd, point);
}
fn clientToScreen(self: *Host, point: *win.POINT) callconv(.winapi) win.BOOL {
    return win.ClientToScreen(self.hwnd, point);
}
fn activate(_: *Host, old: [*c]i32) callconv(.winapi) win.HRESULT {
    if (old != null) old.* = 0;
    return ok;
}
fn deactivate(_: *Host, _: i32) callconv(.winapi) win.HRESULT {
    return ok;
}
fn getClientRect(self: *Host, rect: *win.RECT) callconv(.winapi) win.HRESULT {
    if (win.GetClientRect(self.hwnd, rect) == 0) return failed;
    rect.right = @max(rect.left + 1, rect.right);
    rect.bottom = @max(rect.top + 1, rect.bottom);
    return ok;
}
fn getViewInset(self: *Host, rect: *win.RECT) callconv(.winapi) win.HRESULT {
    rect.* = .{
        .left = contract.himetric(self.inset.left),
        .top = contract.himetric(self.inset.top),
        .right = contract.himetric(self.inset.right),
        .bottom = contract.himetric(self.inset.bottom),
    };
    return ok;
}
fn getCharFormat(self: *Host, out: **const win.CHARFORMATW) callconv(.winapi) win.HRESULT {
    out.* = @ptrCast(&self.char_format);
    return ok;
}
fn getParaFormat(self: *Host, out: **const win.PARAFORMAT) callconv(.winapi) win.HRESULT {
    out.* = &self.para_format;
    return ok;
}
fn getSysColor(self: *Host, index: i32) callconv(.winapi) win.COLORREF {
    return switch (index) {
        win.COLOR_WINDOW => self.background,
        win.COLOR_WINDOWTEXT => self.char_format.crTextColor,
        else => win.GetSysColor(index),
    };
}
fn getBackStyle(_: *Host, out: *i32) callconv(.winapi) win.HRESULT {
    out.* = 1;
    return ok;
}
fn getMaxLength(self: *Host, out: *u32) callconv(.winapi) win.HRESULT {
    out.* = self.limit;
    return ok;
}
fn getScrollBars(self: *Host, out: *u32) callconv(.winapi) win.HRESULT {
    out.* = if (self.multi) win.ES_AUTOVSCROLL else win.ES_AUTOHSCROLL;
    return ok;
}
fn getPasswordChar(_: *Host, out: *u16) callconv(.winapi) win.HRESULT {
    out.* = 0;
    return ok;
}
fn getAcceleratorPos(_: *Host, out: *i32) callconv(.winapi) win.HRESULT {
    out.* = -1;
    return ok;
}
fn getExtent(self: *Host, out: *win.SIZEL) callconv(.winapi) win.HRESULT {
    var rect: win.RECT = undefined;
    _ = win.GetClientRect(self.hwnd, &rect);
    out.* = .{ .cx = contract.himetric(@max(1, rect.right)), .cy = contract.himetric(@max(1, rect.bottom)) };
    return ok;
}
fn charFormatChange(self: *Host, format: *const win.CHARFORMATW) callconv(.winapi) win.HRESULT {
    const count = @min(format.cbSize, @sizeOf(win.CHARFORMAT2W));
    @memcpy(std.mem.asBytes(&self.char_format)[0..count], @as([*]const u8, @ptrCast(format))[0..count]);
    self.char_format.cbSize = @sizeOf(win.CHARFORMAT2W);
    return ok;
}
fn paraFormatChange(self: *Host, format: *const win.PARAFORMAT) callconv(.winapi) win.HRESULT {
    const count = @min(format.cbSize, @sizeOf(win.PARAFORMAT));
    @memcpy(std.mem.asBytes(&self.para_format)[0..count], @as([*]const u8, @ptrCast(format))[0..count]);
    self.para_format.cbSize = @sizeOf(win.PARAFORMAT);
    return ok;
}
fn getPropertyBits(self: *Host, mask: u32, out: *u32) callconv(.winapi) win.HRESULT {
    out.* = contract.propertyBits(self.multi, self.enabled) & mask;
    return ok;
}
fn notify(self: *Host, code: u32, data: ?*anyopaque) callconv(.winapi) win.HRESULT {
    if (code == win.EN_CHANGE or code == win.EN_UPDATE or code == win.EN_HSCROLL or code == win.EN_VSCROLL) {
        self.notify(code);
    } else if (data) |value| {
        const header: *win.NMHDR = @ptrCast(@alignCast(value));
        header.* = .{ .hwndFrom = self.hwnd, .idFrom = @intCast(win.GetDlgCtrlID(self.hwnd)), .code = code };
        _ = win.SendMessageW(win.GetParent(self.hwnd), win.WM_NOTIFY, header.idFrom, @bitCast(@intFromPtr(value)));
    }
    return ok;
}
fn immGetContext(self: *Host) callconv(.winapi) win.HIMC {
    return win.ImmGetContext(self.hwnd);
}
fn immReleaseContext(self: *Host, context: win.HIMC) callconv(.winapi) void {
    _ = win.ImmReleaseContext(self.hwnd, context);
}
fn getSelectionBarWidth(_: *Host, out: *i32) callconv(.winapi) win.HRESULT {
    out.* = 0;
    return ok;
}
fn isDoubleClickPending(self: *Host) callconv(.winapi) win.BOOL {
    var message: win.MSG = undefined;
    return win.PeekMessageW(&message, self.hwnd, win.WM_LBUTTONDBLCLK, win.WM_LBUTTONDBLCLK, win.PM_NOREMOVE);
}
fn getWindow(self: *Host, out: *win.HWND) callconv(.winapi) win.HRESULT {
    out.* = self.hwnd;
    return ok;
}
fn setForegroundWindow(self: *Host) callconv(.winapi) win.HRESULT {
    return if (win.SetForegroundWindow(win.GetAncestor(self.hwnd, win.GA_ROOT)) != 0) ok else failed;
}
fn getPalette(_: *Host) callconv(.winapi) win.HPALETTE {
    return null;
}
fn getEastAsianFlags(_: *Host, out: *i32) callconv(.winapi) win.HRESULT {
    out.* = 0;
    return ok;
}
fn setCursor2(_: *Host, cursor: win.HCURSOR, _: win.BOOL) callconv(.winapi) win.HCURSOR {
    return win.SetCursor(cursor);
}
fn freeTextServicesNotification(self: *Host) callconv(.winapi) void {
    self.services = null;
}
fn getEditStyle(_: *Host, _: u32, out: *u32) callconv(.winapi) win.HRESULT {
    out.* = 0;
    return ok;
}
fn getWindowStyles(self: *Host, style: *u32, ex_style: *u32) callconv(.winapi) win.HRESULT {
    style.* = @truncate(@as(usize, @bitCast(win.GetWindowLongPtrW(self.hwnd, win.GWL_STYLE))));
    ex_style.* = @truncate(@as(usize, @bitCast(win.GetWindowLongPtrW(self.hwnd, win.GWL_EXSTYLE))));
    return ok;
}
fn showDropCaret(self: *Host, show: win.BOOL, _: win.HDC, rect: [*c]const win.RECT) callconv(.winapi) win.HRESULT {
    if (show == 0) return destroyCaret(self);
    if (rect == null) return failed;
    if (win.CreateCaret(self.hwnd, null, @max(1, rect.*.right - rect.*.left), @max(1, rect.*.bottom - rect.*.top)) == 0) return failed;
    _ = win.SetCaretPos(rect.*.left, rect.*.top);
    return if (win.ShowCaret(self.hwnd) != 0) ok else failed;
}
fn destroyCaret(_: *Host) callconv(.winapi) win.HRESULT {
    return if (win.DestroyCaret() != 0) ok else failed;
}
fn getHorzExtent(_: *Host, out: *i32) callconv(.winapi) win.HRESULT {
    out.* = 0;
    return ok;
}

const host_vtable = blk: {
    const methods = .{
        hostQuery,
        hostAddRef,
        hostRelease,
        getDC,
        releaseDC,
        showScrollBar,
        enableScrollBar,
        setScrollRange,
        setScrollPos,
        invalidateRect,
        viewChange,
        createCaret,
        showCaret,
        setCaretPos,
        setTimer,
        killTimer,
        scrollWindow,
        setCapture,
        setFocus,
        setCursor,
        screenToClient,
        clientToScreen,
        activate,
        deactivate,
        getClientRect,
        getViewInset,
        getCharFormat,
        getParaFormat,
        getSysColor,
        getBackStyle,
        getMaxLength,
        getScrollBars,
        getPasswordChar,
        getAcceleratorPos,
        getExtent,
        charFormatChange,
        paraFormatChange,
        getPropertyBits,
        notify,
        immGetContext,
        immReleaseContext,
        getSelectionBarWidth,
        isDoubleClickPending,
        getWindow,
        setForegroundWindow,
        getPalette,
        getEastAsianFlags,
        setCursor2,
        freeTextServicesNotification,
        getEditStyle,
        getWindowStyles,
        showDropCaret,
        destroyCaret,
        getHorzExtent,
    };
    var table: [methods.len]*const anyopaque = undefined;
    for (methods, 0..) |method, i| table[i] = @ptrCast(&method);
    break :blk table;
};

test "IGSH-466 native DirectWrite host maps text selection undo rectangles limits and rendering" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    if (win.OleInitialize(null) < 0) return error.OleInitializeFailed;
    defer win.OleUninitialize();
    const instance = win.GetModuleHandleW(null);
    const font_files = @import("font_config.zig").files;
    var paths: [font_files.len][1024:0]u16 = undefined;
    var pointers: [font_files.len][*:0]const u16 = undefined;
    inline for (font_files, 0..) |file, i| {
        const count = win.GetFullPathNameW(std.unicode.utf8ToUtf16LeStringLiteral("assets\\" ++ file), paths[i].len, &paths[i], null);
        try std.testing.expect(count > 0 and count < paths[i].len);
        try std.testing.expect(win.AddFontResourceExW(&paths[i], win.FR_PRIVATE, null) > 0);
        pointers[i] = &paths[i];
    }
    defer {
        text_draw.reset();
        for (&paths) |*path| _ = win.RemoveFontResourceExW(path, win.FR_PRIVATE, null);
    }
    text_draw.setBundledFontPaths(&pointers);
    const parent = win.CreateWindowExW(0, std.unicode.utf8ToUtf16LeStringLiteral("STATIC"), null, win.WS_POPUP, 0, 0, 320, 200, null, null, instance, null) orelse return error.CreateWindowFailed;
    defer _ = win.DestroyWindow(parent);
    _ = win.SetWindowLongPtrW(parent, win.GWLP_WNDPROC, @bitCast(@intFromPtr(&testParentProc)));
    const edit = create(instance, parent, @ptrFromInt(1), win.WS_CHILD | win.ES_MULTILINE | win.ES_AUTOVSCROLL, 0, 0, 200, 80) orelse return error.CreateEditFailed;
    defer _ = win.DestroyWindow(edit);
    const host = fromWindow(edit).?;
    _ = win.SetWindowLongPtrW(parent, win.GWLP_USERDATA, 1);
    try std.testing.expect(!isComposing(parent));
    try std.testing.expect(!isComposing(null));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Host, "vtable"));
    try std.testing.expectEqual(@as(usize, 54), host_vtable.len);
    const font = win.CreateFontW(-17, 0, 0, 0, @import("font_config.zig").body_weight, 0, 0, 0, win.DEFAULT_CHARSET, win.OUT_DEFAULT_PRECIS, win.CLIP_DEFAULT_PRECIS, win.CLEARTYPE_NATURAL_QUALITY, win.DEFAULT_PITCH, std.unicode.utf8ToUtf16LeStringLiteral("IBM Plex Sans")) orelse return error.CreateFontFailed;
    defer _ = win.DeleteObject(font);
    _ = win.SendMessageW(edit, win.WM_SETFONT, @intFromPtr(font), 1);
    try std.testing.expectEqual(@as(win.LRESULT, @bitCast(@intFromPtr(font))), win.SendMessageW(edit, win.WM_GETFONT, 0, 0));
    var format = std.mem.zeroes(win.CHARFORMAT2W);
    format.cbSize = @sizeOf(win.CHARFORMAT2W);
    _ = host.services.?.send(win.EM_GETCHARFORMAT, win.SCF_DEFAULT, @bitCast(@intFromPtr(&format)));
    try std.testing.expectEqual(@as(u16, 500), format.wWeight);
    try std.testing.expectEqual(@as(i32, 255), format.yHeight);
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("IBM Plex Sans"), std.mem.sliceTo(&format.szFaceName, 0));
    const text = std.unicode.utf8ToUtf16LeStringLiteral("one\r\ntwo😀");
    _ = win.SetWindowTextW(edit, text);
    var buffer: [256]u16 = undefined;
    const count: usize = @intCast(win.GetWindowTextW(edit, &buffer, buffer.len));
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("one\ntwo😀"), buffer[0..count]);
    try std.testing.expectEqual(@as(i32, @intCast(count)), win.GetWindowTextLengthW(edit));
    _ = win.SendMessageW(edit, win.EM_SETSEL, 4, 7);
    const replacement = std.unicode.utf8ToUtf16LeStringLiteral("more");
    _ = win.SendMessageW(edit, win.EM_REPLACESEL, 1, @bitCast(@intFromPtr(replacement)));
    var start: u32 = 0;
    var end: u32 = 0;
    _ = win.SendMessageW(edit, win.EM_GETSEL, @intFromPtr(&start), @bitCast(@intFromPtr(&end)));
    try std.testing.expectEqual(@as(u32, 8), start);
    try std.testing.expectEqual(start, end);
    try std.testing.expect(win.SendMessageW(edit, win.EM_UNDO, 0, 0) != 0);
    try std.testing.expect(win.SendMessageW(edit, win.EM_REDO, 0, 0) != 0);
    _ = win.SendMessageW(edit, win.EM_EMPTYUNDOBUFFER, 0, 0);
    try std.testing.expectEqual(@as(isize, 0), win.SendMessageW(edit, win.EM_CANUNDO, 0, 0));
    _ = win.SendMessageW(edit, win.EM_SETSEL, 0, -1);
    _ = win.SendMessageW(edit, win.WM_COPY, 0, 0);
    try std.testing.expect(win.SendMessageW(edit, win.EM_CANPASTE, win.CF_UNICODETEXT, 0) != 0);
    _ = win.SendMessageW(edit, win.WM_CUT, 0, 0);
    try std.testing.expectEqual(@as(i32, 0), win.GetWindowTextLengthW(edit));
    _ = win.SendMessageW(edit, win.WM_PASTE, 0, 0);
    const pasted: usize = @intCast(win.GetWindowTextW(edit, &buffer, buffer.len));
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("one\nmore😀"), buffer[0..pasted]);
    var rect = win.RECT{ .left = 2, .top = 8, .right = 198, .bottom = 72 };
    _ = win.SendMessageW(edit, win.EM_SETRECTNP, 0, @bitCast(@intFromPtr(&rect)));
    var actual: win.RECT = undefined;
    _ = win.SendMessageW(edit, win.EM_GETRECT, 0, @bitCast(@intFromPtr(&actual)));
    try std.testing.expectEqualDeep(rect, actual);
    const position: usize = @bitCast(win.SendMessageW(edit, win.EM_POSFROMCHAR, 4, 0));
    try std.testing.expect(@as(i16, @bitCast(@as(u16, @truncate(position)))) >= rect.left);
    try std.testing.expect(@as(i16, @bitCast(@as(u16, @truncate(position >> 16)))) >= rect.top);
    try std.testing.expect(win.SendMessageW(edit, win.EM_GETLINECOUNT, 0, 0) >= 2);
    _ = win.SendMessageW(edit, win.EM_LINESCROLL, 0, 1);
    try std.testing.expect(win.SendMessageW(edit, win.EM_GETFIRSTVISIBLELINE, 0, 0) >= 0);
    _ = win.SendMessageW(edit, win.EM_SCROLLCARET, 0, 0);
    _ = win.SendMessageW(edit, win.EM_SETMARGINS, win.EC_LEFTMARGIN | win.EC_RIGHTMARGIN, 4 | (6 << 16));
    try std.testing.expectEqual(@as(isize, 4 | (6 << 16)), win.SendMessageW(edit, win.EM_GETMARGINS, 0, 0));
    _ = win.SendMessageW(edit, win.EM_SETRECTNP, 0, @bitCast(@intFromPtr(&rect)));
    _ = win.SendMessageW(edit, win.EM_SETLIMITTEXT, 128, 0);
    try std.testing.expectEqual(@as(u32, 128), host.limit);
    const cue = std.unicode.utf8ToUtf16LeStringLiteral("Filter");
    _ = win.SendMessageW(edit, win.EM_SETCUEBANNER, 1, @bitCast(@intFromPtr(cue)));
    try std.testing.expect(win.SendMessageW(edit, win.EM_GETCUEBANNER, @intFromPtr(&buffer), buffer.len) != 0);
    try std.testing.expectEqualSlices(u16, cue, std.mem.sliceTo(&buffer, 0));
    _ = win.SetWindowTextW(edit, std.unicode.utf8ToUtf16LeStringLiteral("one two three four five six seven eight nine ten"));
    const wide_height = contentHeight(edit, 1);
    _ = win.MoveWindow(edit, 0, 0, 70, 80, 0);
    const narrow_height = contentHeight(edit, 1);
    try std.testing.expect(narrow_height > wide_height);
    _ = win.MoveWindow(edit, 0, 0, 200, 80, 0);
    try std.testing.expectEqual(wide_height, contentHeight(edit, 1));
    const dc = win.CreateCompatibleDC(null) orelse return error.CreateDCFailed;
    defer _ = win.DeleteDC(dc);
    var info = std.mem.zeroes(win.BITMAPINFO);
    info.bmiHeader.biSize = @sizeOf(win.BITMAPINFOHEADER);
    info.bmiHeader.biWidth = 200;
    info.bmiHeader.biHeight = -80;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    var bits: ?*anyopaque = null;
    const bitmap = win.CreateDIBSection(dc, &info, win.DIB_RGB_COLORS, &bits, null, 0) orelse return error.CreateBitmapFailed;
    defer _ = win.DeleteObject(bitmap);
    const old = win.SelectObject(dc, bitmap);
    defer _ = win.SelectObject(dc, old);
    const pixels = @as([*]u32, @ptrCast(@alignCast(bits.?)))[0 .. 200 * 80];
    @memset(pixels, 0xffffffff);
    _ = win.SendMessageW(edit, win.WM_PRINTCLIENT, @intFromPtr(dc), win.PRF_CLIENT);
    _ = win.GdiFlush();
    try std.testing.expect(host.target != null);
    const colour = theme.current.surface_container_high;
    const background = ((colour & 255) << 16) | (colour & 0xff00) | ((colour >> 16) & 255);
    try std.testing.expectEqual(background, pixels[0] & 0xffffff);
    var ink: usize = 0;
    for (pixels) |pixel| {
        if (pixel & 0xffffff != background) ink += 1;
    }
    try std.testing.expect(ink > 100);
}

fn testParentProc(hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    if (message == win.WM_CTLCOLOREDIT) {
        const dc: win.HDC = @ptrFromInt(wparam);
        _ = win.SetTextColor(dc, theme.current.on_surface);
        _ = win.SetBkColor(dc, theme.current.surface_container_high);
        return @bitCast(@intFromPtr(win.GetStockObject(win.BLACK_BRUSH)));
    }
    return win.DefWindowProcW(hwnd, message, wparam, lparam);
}

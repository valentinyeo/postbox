using System;
using System.Runtime.InteropServices;

public static class InlineLinksNative {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] struct MouseInput { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KeyInput { public ushort key, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct InputData { [FieldOffset(0)] public MouseInput mouse; [FieldOffset(0)] public KeyInput key; }
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint type; public InputData data; }
    [StructLayout(LayoutKind.Sequential)] struct CursorInfo { public int size; public uint flags; public IntPtr cursor; public Point position; }
    [DllImport("user32.dll")] static extern uint SendInput(uint count, Input[] input, int size);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern bool GetCursorInfo(ref CursorInfo info);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr LoadCursorW(IntPtr instance, IntPtr name);
    static Input MoveTo(int x, int y) {
        int width = GetSystemMetrics(78), height = GetSystemMetrics(79);
        if (width <= 1 || height <= 1) throw new Exception("Virtual screen unavailable");
        return new Input { data = new InputData { mouse = new MouseInput { x = (int)(((long)x - GetSystemMetrics(76)) * 65535 / (width - 1)), y = (int)(((long)y - GetSystemMetrics(77)) * 65535 / (height - 1)), flags = 0xE001 } } };
    }
    static Input Button(uint flags) { return new Input { data = new InputData { mouse = new MouseInput { flags = flags } } }; }
    static void Owned(int pid, int x, int y) {
        uint owner; GetWindowThreadProcessId(WindowFromPoint(new Point { x = x, y = y }), out owner);
        if (owner != pid) throw new Exception("Mouse target outside owned app");
    }
    static void Send(params Input[] input) {
        if (SendInput((uint)input.Length, input, Marshal.SizeOf(typeof(Input))) != input.Length) throw new Exception("SendInput failed");
    }
    public static void Hover(int pid, int x, int y) { Owned(pid, x, y); Send(MoveTo(x, y)); }
    public static void Click(int pid, int x, int y) { Owned(pid, x, y); Send(MoveTo(x, y), Button(2), Button(4)); }
    public static void Drag(int pid, int x, int y, int endX, int endY) { Owned(pid, x, y); Owned(pid, endX, endY); Send(MoveTo(x, y), Button(2), MoveTo(endX, endY), Button(4)); }
    static Input Key(ushort key, ushort scan, uint flags) { return new Input { type = 1, data = new InputData { key = new KeyInput { key = key, scan = scan, flags = flags } } }; }
    public static void Combo(ushort key) { Send(Key(0x11, 0, 0), Key(key, 0, 0), Key(key, 0, 2), Key(0x11, 0, 2)); }
    public static void ControlClick(int pid, int x, int y) { Owned(pid, x, y); Send(MoveTo(x, y), Key(0x11, 0, 0), Button(2), Button(4), Key(0x11, 0, 2)); }
    public static void Press(ushort key) { Send(Key(key, 0, 0), Key(key, 0, 2)); }
    public static void Text(string text) {
        foreach (char ch in text) Send(Key(0, ch, 4), Key(0, ch, 6));
    }
    public static long[] Cursor() {
        var info = new CursorInfo { size = Marshal.SizeOf(typeof(CursorInfo)) };
        if (!GetCursorInfo(ref info)) throw new Exception("GetCursorInfo failed");
        return new long[] { info.cursor.ToInt64(), LoadCursorW(IntPtr.Zero, new IntPtr(32649)).ToInt64(), info.position.x, info.position.y, info.flags };
    }
}

using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class VerifyTranscriptCopy {
    [DllImport("user32.dll")] static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [StructLayout(LayoutKind.Sequential)]
    struct MouseInput { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct Input { public uint type; public MouseInput mouse; }
    [DllImport("user32.dll")] static extern uint SendInput(uint count, Input[] inputs, int size);
    struct Point { public int X, Y; }
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    static void Button(bool down) {
        var inputs = new Input[] { new Input { mouse = new MouseInput { flags = down ? 2u : 4u } } };
        if (SendInput(1, inputs, Marshal.SizeOf(typeof(Input))) != 1) throw new Exception("Click input failed");
    }
    public static void Click(int pid, int x, int y, byte modifier) {
        uint owner;
        GetWindowThreadProcessId(GetForegroundWindow(), out owner);
        if (owner != pid) throw new Exception("Refusing modifier input outside owned process");
        GetWindowThreadProcessId(WindowFromPoint(new Point { X = x, Y = y }), out owner);
        if (owner != pid) throw new Exception("Refusing click outside owned process");
        keybd_event(modifier, 0, 0, UIntPtr.Zero);
        try {
            Thread.Sleep(50);
            if (!SetCursorPos(x, y)) throw new Exception("Cursor positioning failed");
            Button(true);
            Button(false);
            Thread.Sleep(50);
        } finally { keybd_event(modifier, 0, 2, UIntPtr.Zero); }
    }
}

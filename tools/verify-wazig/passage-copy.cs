using System;
using System.Runtime.InteropServices;

public static class VerifyPassage {
    [StructLayout(LayoutKind.Sequential)]
    struct MouseInput { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct Input { public uint type; public MouseInput mouse; }
    [DllImport("user32.dll")] static extern uint SendInput(uint count, Input[] input, int size);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern uint GetDoubleClickTime();
    static void Mouse(int pid, uint flags, uint data) {
        uint owner; GetWindowThreadProcessId(GetForegroundWindow(), out owner);
        if (owner != pid) throw new Exception("Refusing input to another process");
        var inputs = new Input[] { new Input { mouse = new MouseInput { flags = flags, data = data } } };
        if (SendInput(1, inputs, Marshal.SizeOf(typeof(Input))) != 1) throw new Exception("Mouse input failed");
    }
    public static void Button(int pid, bool down) { Mouse(pid, down ? 2u : 4u, 0); }
    public static void Wheel(int pid, int delta) { Mouse(pid, 0x0800, unchecked((uint)delta)); }
    public static int[] Middle(byte[] image, int stride, int left, int top, int right, int bottom, int dpi) {
        int inset = Math.Max(2, 12 * dpi / 96), bandBottom = -1, bandTop = -1;
        int minX = right, maxX = left;
        if (stride <= 0 || left < 0 || top < 0 || right * 4 > stride || (long)bottom * stride > image.LongLength) throw new Exception("Screenshot does not contain message bubble");
        for (int y = top + 6 * dpi / 96; y < bottom - 5 * dpi / 96; y++) {
            bool ink = false;
            for (int x = left + inset; x < (left + right) / 2; x++) {
                int p = y * stride + x * 4;
                if (image[p] > 170 && image[p + 1] > 170 && image[p + 2] > 170) { ink = true; break; }
            }
            if (ink) {
                if (bandBottom < y - 1) bandTop = y;
                bandBottom = y;
            }
        }
        if (bandTop < 0) throw new Exception("No painted message body");
        for (int y = bandTop; y <= bandBottom; y++) for (int x = left + inset; x < (left + right) / 2; x++) {
            int p = y * stride + x * 4;
            if (image[p] > 170 && image[p + 1] > 170 && image[p + 2] > 170) { minX = Math.Min(minX, x); maxX = Math.Max(maxX, x); }
        }
        if (maxX <= minX) throw new Exception("No message word pixels");
        return new int[] { (minX + maxX) / 2, (bandTop + bandBottom) / 2 };
    }
}

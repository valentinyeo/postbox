using System;
using System.Runtime.InteropServices;
public static class LayoutCapture {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string device, int mode, byte[] settings);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettings(byte[] settings, int flags);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr window, int x, int y, int width, int height, bool repaint);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW")]
    static extern IntPtr ReadRect(IntPtr window, uint message, UIntPtr index, ref Rect rect, uint flags, uint timeout, out UIntPtr result);
    public static Rect GetRect(IntPtr window, uint message, uint index) {
        var rect = new Rect();
        UIntPtr result;
        if (ReadRect(window, message, (UIntPtr)index, ref rect, 2, 2000, out result) == IntPtr.Zero) throw new Exception("Native rectangle read failed");
        if (message == 0x198 && result.ToUInt64() == UIntPtr.MaxValue.ToUInt64()) throw new Exception("List item unavailable");
        return rect;
    }
    public static void Display() {
        var mode = new byte[220];
        BitConverter.GetBytes((short)220).CopyTo(mode, 68);
        if (!EnumDisplaySettings(null, -1, mode)) throw new Exception("Display mode unavailable");
        BitConverter.GetBytes(0x180000).CopyTo(mode, 72);
        BitConverter.GetBytes(1920).CopyTo(mode, 172);
        BitConverter.GetBytes(1080).CopyTo(mode, 176);
        int result = ChangeDisplaySettings(mode, 0);
        if (result != 0) throw new Exception("1920 display failed: " + result);
    }
}

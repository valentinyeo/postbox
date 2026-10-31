using System;
using System.Runtime.InteropServices;
using System.Text;

public static class VerifyInboxTooltip {
    [StructLayout(LayoutKind.Sequential)]
    struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)]
    struct Rect { public int Left, Top, Right, Bottom; }
    delegate bool EnumWindow(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int capacity);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam, uint flags, uint timeout, out UIntPtr result);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool IsWow64Process(IntPtr process, out bool wow64);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualAllocEx(IntPtr process, IntPtr address, UIntPtr size, uint type, uint protection);
    [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr process, IntPtr address, UIntPtr size, uint type);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteProcessMemory(IntPtr process, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr written);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    static string ClassName(IntPtr window) {
        var name = new StringBuilder(256);
        GetClassName(window, name, name.Capacity);
        return name.ToString();
    }
    public static string DescribeWindow(IntPtr window) {
        uint pid; GetWindowThreadProcessId(window, out pid);
        Rect rect; bool hasRect = GetWindowRect(window, out rect);
        var text = new StringBuilder(32768);
        GetWindowText(window, text, text.Capacity);
        return String.Format("hwnd=0x{0:X} class={1} owner_pid={2} visible={3} rect_ok={4} rect=[{5},{6},{7},{8}] GetWindowText={9}",
            window.ToInt64(), ClassName(window), pid, IsWindowVisible(window), hasRect, rect.Left, rect.Top, rect.Right, rect.Bottom, text);
    }
    static ulong Message(IntPtr window, uint message, uint index, IntPtr memory, ref bool safeToFree) {
        UIntPtr result;
        if (SendMessageTimeout(window, message, new UIntPtr(index), memory, 0x23, 500, out result) == IntPtr.Zero) {
            safeToFree = false;
            throw new Exception("SendMessageTimeout 0x" + message.ToString("X") + " failed: " + Marshal.GetLastWin32Error());
        }
        return result.ToUInt64();
    }
    static void WriteMemory(IntPtr process, IntPtr memory, byte[] bytes) {
        UIntPtr written;
        if (!WriteProcessMemory(process, memory, bytes, new UIntPtr((uint)bytes.Length), out written) || written.ToUInt64() != (ulong)bytes.Length)
            throw new Exception("WriteProcessMemory failed: " + Marshal.GetLastWin32Error());
    }
    static byte[] ReadMemory(IntPtr process, IntPtr memory, int size) {
        var bytes = new byte[size];
        UIntPtr read;
        if (!ReadProcessMemory(process, memory, bytes, new UIntPtr((uint)size), out read) || read.ToUInt64() != (ulong)size)
            throw new Exception("ReadProcessMemory failed: " + Marshal.GetLastWin32Error());
        return bytes;
    }
    static string ToolText(IntPtr process, IntPtr window, IntPtr memory, int size, uint message, uint index, ref bool safeToFree) {
        var info = new byte[size];
        Array.Copy(BitConverter.GetBytes(size), info, 4);
        WriteMemory(process, memory, info);
        if (Message(window, message, index, memory, ref safeToFree) == 0) return "no tool";
        info = ReadMemory(process, memory, size);
        IntPtr buffer = IntPtr.Add(memory, size);
        int textOffset = size == 72 ? 48 : 36;
        byte[] pointer = size == 72 ? BitConverter.GetBytes(buffer.ToInt64()) : BitConverter.GetBytes(unchecked((uint)buffer.ToInt64()));
        Array.Copy(pointer, 0, info, textOffset, pointer.Length);
        WriteMemory(process, buffer, new byte[65536]);
        WriteMemory(process, memory, info);
        Message(window, 0x0438, 32768, memory, ref safeToFree);
        var text = Encoding.Unicode.GetString(ReadMemory(process, buffer, 65536));
        int end = text.IndexOf('\0');
        if (end >= 0) text = text.Substring(0, end);
        ulong hwnd = size == 72 ? BitConverter.ToUInt64(info, 8) : BitConverter.ToUInt32(info, 8);
        ulong id = size == 72 ? BitConverter.ToUInt64(info, 16) : BitConverter.ToUInt32(info, 12);
        return String.Format("tool_hwnd=0x{0:X} id=0x{1:X} flags=0x{2:X} TTM_GETTEXT={3}", hwnd, id, BitConverter.ToUInt32(info, 4), text);
    }
    static void TooltipText(StringBuilder output, IntPtr window) {
        uint pid; GetWindowThreadProcessId(window, out pid);
        IntPtr process = OpenProcess(0x1038, false, pid);
        if (process == IntPtr.Zero) {
            output.AppendLine("TTM_GETTEXT unavailable: OpenProcess failed: " + Marshal.GetLastWin32Error());
            return;
        }
        IntPtr memory = IntPtr.Zero;
        bool safeToFree = true;
        try {
            bool wow64;
            if (!IsWow64Process(process, out wow64)) throw new Exception("IsWow64Process failed: " + Marshal.GetLastWin32Error());
            int size = Environment.Is64BitOperatingSystem && !wow64 ? 72 : 48;
            if (IntPtr.Size == 4 && size == 72) throw new Exception("64-bit tooltip requires a 64-bit harness");
            memory = VirtualAllocEx(process, IntPtr.Zero, new UIntPtr((uint)(size + 65536)), 0x3000, 4);
            if (memory == IntPtr.Zero) throw new Exception("VirtualAllocEx failed: " + Marshal.GetLastWin32Error());
            output.AppendLine("current: " + ToolText(process, window, memory, size, 0x043B, 0, ref safeToFree));
            ulong count = Message(window, 0x040D, 0, IntPtr.Zero, ref safeToFree);
            output.AppendLine("tool_count=" + count);
            for (uint index = 0; index < Math.Min(count, 256UL); index++)
                output.AppendLine("tool[" + index + "]: " + ToolText(process, window, memory, size, 0x043A, index, ref safeToFree));
            if (count > 256) output.AppendLine("tool enumeration truncated at 256");
        } catch (Exception error) {
            output.AppendLine("TTM_GETTEXT error: " + error.Message);
        } finally {
            if (memory != IntPtr.Zero && safeToFree) VirtualFreeEx(process, memory, UIntPtr.Zero, 0x8000);
            if (!safeToFree) output.AppendLine("remote allocation retained because a timed-out message may still use it");
            CloseHandle(process);
        }
    }
    public sealed class ToolInfo {
        public ulong owner, id;
        public uint flags;
        public int[] rect;
    }
    public sealed class TooltipInfo {
        public long hwnd;
        public bool visible;
        public ulong autopop_ms;
        public ToolInfo current;
        public ToolInfo[] tools;
    }
    static ToolInfo ReadTool(IntPtr process, IntPtr window, IntPtr memory, int size, uint message, uint index, ref bool safeToFree) {
        var bytes = new byte[size];
        Array.Copy(BitConverter.GetBytes(size), bytes, 4);
        WriteMemory(process, memory, bytes);
        if (Message(window, message, index, memory, ref safeToFree) == 0) return null;
        bytes = ReadMemory(process, memory, size);
        int offset = size == 64 ? 24 : 16;
        return new ToolInfo {
            owner = size == 64 ? BitConverter.ToUInt64(bytes, 8) : BitConverter.ToUInt32(bytes, 8),
            id = size == 64 ? BitConverter.ToUInt64(bytes, 16) : BitConverter.ToUInt32(bytes, 12),
            flags = BitConverter.ToUInt32(bytes, 4),
            rect = new int[] { BitConverter.ToInt32(bytes, offset), BitConverter.ToInt32(bytes, offset + 4), BitConverter.ToInt32(bytes, offset + 8), BitConverter.ToInt32(bytes, offset + 12) }
        };
    }
    public static TooltipInfo[] Tools(int targetPid) {
        var windows = new System.Collections.Generic.List<IntPtr>();
        if (!EnumWindows((window, data) => {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner == targetPid && ClassName(window) == "tooltips_class32") windows.Add(window);
            return true;
        }, IntPtr.Zero)) throw new Exception("EnumWindows failed");
        var result = new System.Collections.Generic.List<TooltipInfo>();
        foreach (IntPtr window in windows) {
            IntPtr process = OpenProcess(0x1038, false, (uint)targetPid);
            if (process == IntPtr.Zero) throw new Exception("OpenProcess failed");
            IntPtr memory = IntPtr.Zero;
            bool safe = true;
            try {
                bool wow64;
                if (!IsWow64Process(process, out wow64)) throw new Exception("IsWow64Process failed");
                // Match the V2 TOOLINFO size used to register Postbox tools.
                int size = Environment.Is64BitOperatingSystem && !wow64 ? 64 : 44;
                if (IntPtr.Size == 4 && size == 64) throw new Exception("64-bit harness required");
                memory = VirtualAllocEx(process, IntPtr.Zero, new UIntPtr((uint)size), 0x3000, 4);
                if (memory == IntPtr.Zero) throw new Exception("VirtualAllocEx failed");
                ToolInfo current = ReadTool(process, window, memory, size, 0x043B, 0, ref safe);
                ulong count = Message(window, 0x040D, 0, IntPtr.Zero, ref safe);
                if (count > 256) throw new Exception("Too many tooltip tools");
                var tools = new System.Collections.Generic.List<ToolInfo>();
                for (uint index = 0; index < count; index++) {
                    ToolInfo tool = ReadTool(process, window, memory, size, 0x043A, index, ref safe);
                    if (tool == null) throw new Exception("Tooltip enumeration failed");
                    tools.Add(tool);
                }
                ulong autopop = Message(window, 0x0415, 2, IntPtr.Zero, ref safe);
                result.Add(new TooltipInfo { hwnd = window.ToInt64(), visible = IsWindowVisible(window), autopop_ms = autopop, current = current, tools = tools.ToArray() });
            } finally {
                if (memory != IntPtr.Zero && safe) VirtualFreeEx(process, memory, UIntPtr.Zero, 0x8000);
                CloseHandle(process);
            }
        }
        return result.ToArray();
    }
    public static string Capture(IntPtr list, int x, int y) {
        var output = new StringBuilder();
        output.AppendLine("utc=" + DateTime.UtcNow.ToString("O"));
        Point cursor;
        bool cursorOk = GetCursorPos(out cursor);
        output.AppendLine(String.Format("GetCursorPos ok={0} point=[{1},{2}]", cursorOk, cursor.X, cursor.Y));
        output.AppendLine("list: " + DescribeWindow(list));
        var hover = new Point { X = x, Y = y };
        output.AppendLine(String.Format("hover_screen=[{0},{1}]", x, y));
        output.AppendLine("WindowFromPoint: " + DescribeWindow(WindowFromPoint(hover)));
        output.AppendLine("foreground: " + DescribeWindow(GetForegroundWindow()));
        bool clientOk = ScreenToClient(list, ref hover);
        output.AppendLine(String.Format("ScreenToClient ok={0} hover_client=[{1},{2}]", clientOk, hover.X, hover.Y));
        UIntPtr hit;
        IntPtr ok = SendMessageTimeout(list, 0x01A9, UIntPtr.Zero, new IntPtr(unchecked((int)(((uint)hover.Y & 0xFFFF) << 16 | ((uint)hover.X & 0xFFFF)))), 0x23, 500, out hit);
        ulong value = hit.ToUInt64();
        output.AppendLine(String.Format("LB_ITEMFROMPOINT ok={0} raw=0x{1:X} index={2} outside={3}", ok != IntPtr.Zero, value, value & 0xFFFF, (value >> 16) & 0xFFFF));
        int count = 0;
        bool enumerated = EnumWindows((window, data) => {
            if (ClassName(window) != "tooltips_class32") return true;
            count++;
            output.AppendLine("tooltip: " + DescribeWindow(window));
            TooltipText(output, window);
            return true;
        }, IntPtr.Zero);
        output.AppendLine(String.Format("EnumWindows ok={0} tooltip_windows={1}", enumerated, count));
        return output.ToString();
    }
}

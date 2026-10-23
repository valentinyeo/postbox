using System;
using System.Runtime.InteropServices;
using System.Text;

public static class VerifyMenus {
    public struct Rect { public int Left, Top, Right, Bottom; }
    public struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)]
    struct MouseInput { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct Input { public uint type; public MouseInput mouse; }
    delegate bool EnumWindow(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, Input[] input, int size);
    public static IntPtr Find(int pid, string name) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((window, data) => {
            uint owner; GetWindowThreadProcessId(window, out owner);
            var text = new StringBuilder(256); GetClassName(window, text, text.Capacity);
            if (owner == pid && IsWindowVisible(window) && text.ToString() == name) { found = window; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static Rect Bounds(IntPtr window) {
        Rect rect;
        if (!GetWindowRect(window, out rect) || rect.Right <= rect.Left || rect.Bottom <= rect.Top) throw new Exception("Missing popup rectangle");
        return rect;
    }
    static void Mouse(int pid, int x, int y, uint flags) {
        uint owner; GetWindowThreadProcessId(WindowFromPoint(new Point { X = x, Y = y }), out owner);
        if (owner != pid) throw new Exception("Refusing mouse input outside owned process");
        if (!SetCursorPos(x, y)) throw new Exception("Cursor positioning failed");
        var input = new Input[] { new Input { type = 0, mouse = new MouseInput { x = 0, y = 0, data = 0, flags = flags, time = 0, extra = UIntPtr.Zero } } };
        if (SendInput(1, input, Marshal.SizeOf(typeof(Input))) != 1) throw new Exception("SendInput failed");
    }
    public static void Click(int pid, int x, int y, bool right) {
        Mouse(pid, x, y, right ? 8u : 2u);
        Mouse(pid, x, y, right ? 16u : 4u);
    }
    public static void Drag(int pid, int x, int y, int endX) {
        Mouse(pid, x, y, 2);
        try {
            System.Threading.Thread.Sleep(40);
            for (int next = x + 2; next <= endX; next += 2) {
                Mouse(pid, next, y, 0x2001);
                System.Threading.Thread.Sleep(10);
            }
        } finally { Mouse(pid, endX, y, 4); }
    }
    static double Linear(int value) {
        double channel = value / 255.0;
        return channel <= 0.04045 ? channel / 12.92 : Math.Pow((channel + 0.055) / 1.055, 2.4);
    }
    public sealed class Measurement {
        public double background, text, contrast, lightTileFraction;
        public int textPixels, pixels;
        public Rect rect;
    }
    public static Measurement Measure(byte[] image, int width, int height, int stride, Rect rect, int screenX, int screenY, int inset, bool clearType = false) {
        int left = rect.Left - screenX + inset, top = rect.Top - screenY + inset;
        int right = rect.Right - screenX - inset, bottom = rect.Bottom - screenY - inset;
        if (stride < width * 4 || image.Length < stride * height || left < 0 || top < 0 || right > width || bottom > height || right - left < 16 || bottom - top < 8) throw new Exception("Screenshot does not contain measurement rectangle");
        int count = (right - left) * (bottom - top), used = 0, neutralCount = 0, lightTiles = 0, tiles = 0;
        var values = new double[count]; var neutral = new double[count]; var tile = new double[256];
        for (int y = top; y < bottom; y += 16) for (int x = left; x < right; x += 16) {
            int tileCount = 0;
            for (int py = y; py < Math.Min(bottom, y + 16); py++) for (int px = x; px < Math.Min(right, x + 16); px++) {
                int offset = py * stride + px * 4;
                int b = image[offset], g = image[offset + 1], r = image[offset + 2];
                double value = 0.2126 * Linear(r) + 0.7152 * Linear(g) + 0.0722 * Linear(b);
                values[used++] = value;
                bool isNeutralBackgroundSample = Math.Max(r, Math.Max(g, b)) - Math.Min(r, Math.Min(g, b)) <= 12;
                if (isNeutralBackgroundSample) {
                    neutral[neutralCount++] = value; tile[tileCount++] = value;
                }
            }
            Array.Sort(tile, 0, tileCount); tiles++; if (tileCount > 0 && tile[tileCount / 2] > 0.5) lightTiles++;
        }
        Array.Sort(values); Array.Sort(neutral, 0, neutralCount);
        double[] textValues = clearType ? values : neutral;
        int textCount = clearType ? count : neutralCount;
        if (textCount < 24) throw new Exception("No measurable neutral text");
        double background = values[count / 2];
        double text = background < 0.5 ? textValues[textCount - 24] : textValues[23];
        int textPixels = 0;
        for (int index = 0; index < textCount; index++) if ((Math.Max(background, textValues[index]) + 0.05) / (Math.Min(background, textValues[index]) + 0.05) >= 4.5) textPixels++;
        return new Measurement {
            background = background, text = text, contrast = (Math.Max(background, text) + 0.05) / (Math.Min(background, text) + 0.05),
            lightTileFraction = (double)lightTiles / tiles, pixels = count, rect = rect, textPixels = textPixels
        };
    }
    public static bool Changed(byte[] before, byte[] after, int width, int height, int stride, Rect rect, int screenX, int screenY) {
        if (width <= 0 || height <= 0 || stride < (long)width * 4 || before.LongLength < (long)stride * height || after.LongLength < (long)stride * height) throw new Exception("Invalid screenshot pixels");
        int left = Math.Max(0, rect.Left - screenX), top = Math.Max(0, rect.Top - screenY);
        int right = Math.Min(width, rect.Right - screenX), bottom = Math.Min(height, rect.Bottom - screenY);
        if (right <= left || bottom <= top) return false;
        long changed = 0;
        for (int y = top; y < bottom; y++) for (int x = left; x < right; x++) {
            int offset = y * stride + x * 4;
            if (before[offset] != after[offset] || before[offset + 1] != after[offset + 1] || before[offset + 2] != after[offset + 2] || before[offset + 3] != after[offset + 3]) changed++;
        }
        return changed * 50 >= (long)(right - left) * (bottom - top);
    }
    public static void Validate(Measurement measurement, bool light) {
        if (light ? measurement.background < 0.7 : measurement.background > 0.05126945837404324 || measurement.lightTileFraction > 0.02) throw new Exception("Unexpected menu background");
        if (measurement.contrast < 4.5 || measurement.textPixels < 24) throw new Exception("Unreadable popup text");
    }
    public static void TestOracle() {
        foreach (bool painted in new[] { false, true }) {
            var before = new byte[240 * 100 * 4];
            var after = (byte[])before.Clone();
            if (painted) for (int y = 20; y < 40; y++) for (int x = 20; x < 60; x++) {
                int offset = (y * 240 + x) * 4;
                after[offset] = after[offset + 1] = after[offset + 2] = 255;
            }
            if (Changed(before, after, 240, 100, 960, new Rect { Right = 240, Bottom = 100 }, 0, 0) != painted) throw new Exception("Popup pixel change control failed");
        }
        foreach (bool light in new[] { false, true }) foreach (bool text in new[] { false, true }) {
            var image = new byte[240 * 100 * 4];
            for (int y = 0; y < 100; y++) for (int x = 0; x < 240; x++) {
                bool foreground = text && y >= 20 && y < 36 && x >= 20 && x < 120 && x % 8 < 3;
                byte value = (byte)(foreground ? (light ? 0 : 255) : (light ? 255 : 26));
                int offset = (y * 240 + x) * 4;
                image[offset] = image[offset + 1] = image[offset + 2] = value; image[offset + 3] = 255;
            }
            var metric = Measure(image, 240, 100, 960, new Rect { Right = 240, Bottom = 100 }, 0, 0, 8);
            foreach (bool expectedLight in new[] { false, true }) {
                bool accepted = true;
                try { Validate(metric, expectedLight); } catch { accepted = false; }
                if (accepted != (text && light == expectedLight)) throw new Exception("Pixel oracle control failed");
            }
        }
        foreach (bool neutralPatch in new[] { false, true }) {
            var image = new byte[240 * 100 * 4];
            for (int y = 0; y < 100; y++) for (int x = 0; x < 240; x++) {
                bool foreground = y >= 20 && y < 36 && x >= 20 && x < 120 && x % 8 < 3;
                bool patch = x >= 160 && y >= 48 && y < 80;
                byte value = (byte)(foreground || patch ? 255 : 26);
                int offset = (y * 240 + x) * 4;
                image[offset] = patch && !neutralPatch ? (byte)0 : value;
                image[offset + 1] = image[offset + 2] = value; image[offset + 3] = 255;
            }
            var metric = Measure(image, 240, 100, 960, new Rect { Right = 240, Bottom = 100 }, 0, 0, 8);
            bool accepted = true;
            try { Validate(metric, false); } catch { accepted = false; }
            if (accepted == neutralPatch) throw new Exception("Colour foreground/light background control failed");
        }
        for (int kind = 0; kind < 3; kind++) {
            var image = new byte[240 * 100 * 4];
            for (int y = 0; y < 100; y++) for (int x = 0; x < 240; x++) {
                bool foreground = kind != 0 && y >= 20 && y < 28 && x >= 20 && x < 60 && x % 8 < 3;
                bool white = kind == 1 && foreground && x == 24;
                int offset = (y * 240 + x) * 4;
                image[offset] = (byte)(foreground ? (white ? 255 : (kind == 1 ? 205 : 70)) : 26);
                image[offset + 1] = (byte)(foreground ? (white ? 255 : (kind == 1 ? 140 : 50)) : 26);
                image[offset + 2] = (byte)(white ? 255 : 26); image[offset + 3] = 255;
            }
            foreach (bool clearType in new[] { false, true }) {
                var metric = Measure(image, 240, 100, 960, new Rect { Right = 240, Bottom = 100 }, 0, 0, 8, clearType);
                bool accepted = true;
                try { Validate(metric, false); } catch { accepted = false; }
                if (accepted != (kind == 1 && clearType)) throw new Exception("ClearType edit text control failed");
            }
        }
    }
    public static Point MessageText(byte[] image, int stride, Rect canvas, int screenX, int screenY) {
        int bands = 0; bool previous = false;
        for (int y = Math.Max(canvas.Top, canvas.Bottom - 100); y < canvas.Bottom - 12; y++) {
            int first = -1;
            for (int x = canvas.Left + 24; x < Math.Min(canvas.Right, canvas.Left + 250); x++) {
                int offset = (y - screenY) * stride + (x - screenX) * 4;
                if (image[offset] > 180 && image[offset + 1] > 180 && image[offset + 2] > 180) { first = x; break; }
            }
            if (first >= 0 && !previous) bands++;
            if (first >= 0 && bands == 2) return new Point { X = first, Y = y + 3 };
            previous = first >= 0;
        }
        throw new Exception("Synthetic message text was not painted");
    }
}

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;

public static class VerifyMenus {
    public struct Rect { public int Left, Top, Right, Bottom; }
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
        uint owner; GetWindowThreadProcessId(WindowFromPoint(new Point(x, y)), out owner);
        if (owner != pid) throw new Exception("Refusing mouse input outside owned process");
        if (!SetCursorPos(x, y)) throw new Exception("Cursor positioning failed");
        var input = new Input[] { new Input { type = 0, mouse = new MouseInput { flags = flags } } };
        if (SendInput(1, input, Marshal.SizeOf<Input>()) != 1) throw new Exception("SendInput failed");
    }
    public static void Click(int pid, int x, int y, bool right) {
        Mouse(pid, x, y, right ? 8u : 2u);
        Mouse(pid, x, y, right ? 16u : 4u);
    }
    public static void Drag(int pid, int x, int y, int endX) {
        Mouse(pid, x, y, 2);
        try {
            for (int next = x + 2; next <= endX; next += 2) Mouse(pid, next, y, 1);
        } finally { Mouse(pid, endX, y, 4); }
    }
    static double Linear(int value) {
        double channel = value / 255.0;
        return channel <= 0.04045 ? channel / 12.92 : Math.Pow((channel + 0.055) / 1.055, 2.4);
    }
    static double Luminance(Color color) { return 0.2126 * Linear(color.R) + 0.7152 * Linear(color.G) + 0.0722 * Linear(color.B); }
    public sealed class Measurement {
        public double background, text, contrast, lightTileFraction;
        public int textPixels, pixels;
        public Rect rect;
    }
    public static Measurement Measure(string path, Rect rect, int screenX, int screenY, int inset) {
        using (var image = new Bitmap(path)) {
            int left = rect.Left - screenX + inset, top = rect.Top - screenY + inset;
            int right = rect.Right - screenX - inset, bottom = rect.Bottom - screenY - inset;
            if (left < 0 || top < 0 || right > image.Width || bottom > image.Height || right - left < 16 || bottom - top < 8) throw new Exception("Screenshot does not contain measurement rectangle");
            var values = new List<double>(); var neutral = new List<double>();
            int lightTiles = 0, tiles = 0;
            for (int y = top; y < bottom; y += 16) for (int x = left; x < right; x += 16) {
                var tile = new List<double>();
                for (int py = y; py < Math.Min(bottom, y + 16); py++) for (int px = x; px < Math.Min(right, x + 16); px++) {
                    Color color = image.GetPixel(px, py); double value = Luminance(color);
                    values.Add(value); tile.Add(value);
                    if (Math.Max(color.R, Math.Max(color.G, color.B)) - Math.Min(color.R, Math.Min(color.G, color.B)) <= 12) neutral.Add(value);
                }
                tile.Sort(); tiles++; if (tile[tile.Count / 2] > 0.5) lightTiles++;
            }
            values.Sort(); neutral.Sort();
            if (neutral.Count < 24) throw new Exception("No measurable neutral text");
            double background = values[values.Count / 2];
            double text = background < 0.5 ? neutral[neutral.Count - 24] : neutral[23];
            return new Measurement {
                background = background, text = text, contrast = (Math.Max(background, text) + 0.05) / (Math.Min(background, text) + 0.05),
                lightTileFraction = (double)lightTiles / tiles, pixels = values.Count, rect = rect,
                textPixels = neutral.Count(value => (Math.Max(background, value) + 0.05) / (Math.Min(background, value) + 0.05) >= 4.5)
            };
        }
    }
    public static void Validate(Measurement measurement, bool light) {
        if (light ? measurement.background < 0.7 : measurement.background > 0.05126945837404324 || measurement.lightTileFraction > 0.02) throw new Exception("Unexpected menu background");
        if (measurement.contrast < 4.5 || measurement.textPixels < 24) throw new Exception("Unreadable popup text");
    }
    public static void TestOracle(string folder) {
        foreach (bool light in new[] { false, true }) foreach (bool text in new[] { false, true }) {
            string path = System.IO.Path.Combine(folder, "pixel-control-" + light + "-" + text + ".png");
            using (var image = new Bitmap(240, 100)) {
                using (var graphics = Graphics.FromImage(image)) {
                    graphics.Clear(light ? Color.White : Color.FromArgb(26, 26, 26));
                    if (text) using (var font = new Font("Arial", 16)) graphics.DrawString("Verification", font, light ? Brushes.Black : Brushes.White, 20, 20);
                }
                image.Save(path);
            }
            var metric = Measure(path, new Rect { Right = 240, Bottom = 100 }, 0, 0, 8);
            foreach (bool expectedLight in new[] { false, true }) {
                bool accepted = true;
                try { Validate(metric, expectedLight); } catch { accepted = false; }
                if (accepted != (text && light == expectedLight)) throw new Exception("Pixel oracle control failed");
            }
            System.IO.File.Delete(path);
        }
    }
    public static Point MessageText(string path, Rect canvas, int screenX, int screenY) {
        using (var image = new Bitmap(path)) {
            int bands = 0; bool previous = false;
            for (int y = Math.Max(canvas.Top, canvas.Bottom - 100); y < canvas.Bottom - 12; y++) {
                int first = -1;
                for (int x = canvas.Left + 24; x < Math.Min(canvas.Right, canvas.Left + 250); x++) {
                    Color color = image.GetPixel(x - screenX, y - screenY);
                    if (color.R > 180 && color.G > 180 && color.B > 180) { first = x; break; }
                }
                if (first >= 0 && !previous) bands++;
                if (first >= 0 && bands == 2) return new Point(first, y + 3);
                previous = first >= 0;
            }
        }
        throw new Exception("Synthetic message text was not painted");
    }
}

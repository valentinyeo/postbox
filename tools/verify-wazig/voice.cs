using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class VerifyVoice {
    public struct Rect { public int Left, Top, Right, Bottom; }
    public struct Point { public int X, Y; }
    [DllImport("user32.dll")] static extern bool InvalidateRect(IntPtr window, ref Rect rect, bool erase);
    [DllImport("user32.dll")] static extern bool RedrawWindow(IntPtr window, IntPtr rect, IntPtr region, uint flags);
    [DllImport("user32.dll")] static extern bool UpdateWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [StructLayout(LayoutKind.Sequential)]
    struct MouseInput { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct Input { public uint type; public MouseInput mouse; }
    [DllImport("user32.dll")] static extern uint SendInput(uint count, Input[] input, int size);

    public sealed class Item {
        public string id;
        public Rect bubble, media, time;
    }

    public sealed class Result {
        public long differing;
        public long outside;
        public List<string> problems = new List<string>();
        public List<string> partialProblems = new List<string>();
        public List<string> fullProblems = new List<string>();
    }

    static void Owned(int pid, IntPtr window) {
        uint owner;
        GetWindowThreadProcessId(window, out owner);
        if (owner != pid) throw new Exception("Refusing to touch a window outside the owned process");
    }

    public static Rect Bounds(int pid, IntPtr canvas) {
        Owned(pid, canvas);
        Rect rect;
        if (!GetWindowRect(canvas, out rect) || rect.Right <= rect.Left || rect.Bottom <= rect.Top) throw new Exception("Missing canvas rectangle");
        return rect;
    }

    public static void FullRepaint(int pid, IntPtr canvas) {
        Owned(pid, canvas);
        if (!RedrawWindow(canvas, IntPtr.Zero, IntPtr.Zero, 0x0001 | 0x0100)) throw new Exception("Full canvas repaint request failed");
    }

    public static void PlaybackRepaint(int pid, IntPtr canvas, Rect[] bubbles) {
        Owned(pid, canvas);
        foreach (var bubble in bubbles) {
            var dirty = bubble;
            if (!InvalidateRect(canvas, ref dirty, false)) throw new Exception("Bubble invalidation failed");
        }
        UpdateWindow(canvas);
    }

    public static void Wheel(int pid, int x, int y, int delta) {
        IntPtr under = WindowFromPoint(new Point { X = x, Y = y });
        Owned(pid, under);
        if (!SetCursorPos(x, y)) throw new Exception("Cursor positioning failed");
        var input = new Input[] { new Input { type = 0, mouse = new MouseInput { x = 0, y = 0, data = unchecked((uint)delta), flags = 0x0800, time = 0, extra = UIntPtr.Zero } } };
        if (SendInput(1, input, Marshal.SizeOf(typeof(Input))) != 1) throw new Exception("Wheel input failed");
    }

    static int Pixel(byte[] image, int stride, int x, int y) {
        int offset = y * stride + x * 4;
        return image[offset] | (image[offset + 1] << 8) | (image[offset + 2] << 16);
    }

    static int Distance(int a, int b) {
        return Math.Max(Math.Abs((a & 255) - (b & 255)), Math.Max(Math.Abs(((a >> 8) & 255) - ((b >> 8) & 255)), Math.Abs(((a >> 16) & 255) - ((b >> 16) & 255))));
    }

    static int Ink(byte[] image, int stride, int ox, int oy, Rect area, int fill) {
        int count = 0;
        for (int y = area.Top; y < area.Bottom; y++) for (int x = area.Left; x < area.Right; x++) {
            if (Distance(Pixel(image, stride, ox + x, oy + y), fill) > 48) count++;
        }
        return count;
    }

    static long Differ(byte[] a, byte[] b, int stride, int ox, int oy, Rect area) {
        long count = 0;
        for (int y = area.Top; y < area.Bottom; y++) for (int x = area.Left; x < area.Right; x++) {
            if (Distance(Pixel(a, stride, ox + x, oy + y), Pixel(b, stride, ox + x, oy + y)) > 1) count++;
        }
        return count;
    }

    static Rect Clip(Rect rect, int width, int height) {
        return new Rect { Left = Math.Max(0, rect.Left), Top = Math.Max(0, rect.Top), Right = Math.Min(width, rect.Right), Bottom = Math.Min(height, rect.Bottom) };
    }

    static bool Empty(Rect rect) { return rect.Right <= rect.Left || rect.Bottom <= rect.Top; }

    static List<string> Inspect(string label, byte[] image, int stride, int ox, int oy, int width, int height, Rect[] all, Item[] voice, int dpi, out long outside) {
        var problems = new List<string>();
        Func<int, int> s = v => (v * dpi + 48) / 96;
        int background = Pixel(image, stride, ox + 4, oy + 4);
        outside = 0;
        for (int y = s(72); y < height; y++) for (int x = 0; x < width - 10; x++) {
            bool inside = false;
            foreach (var rect in all) {
                if (!Empty(rect) && x >= rect.Left - 1 && x <= rect.Right && y >= rect.Top - 1 && y <= rect.Bottom) { inside = true; break; }
            }
            if (!inside && Distance(Pixel(image, stride, ox + x, oy + y), background) > 24) outside++;
        }
        if (outside > 0) problems.Add(label + " has " + outside + " drawn pixels outside every bubble");
        var shown = new List<Item>();
        foreach (var item in voice) if (!Empty(item.bubble) && item.bubble.Bottom > 0 && item.bubble.Top < height) shown.Add(item);
        shown.Sort((a, b) => a.bubble.Top.CompareTo(b.bubble.Top));
        for (int i = 1; i < shown.Count; i++) {
            if (shown[i].bubble.Top < shown[i - 1].bubble.Bottom) problems.Add(label + " bubble " + shown[i].id + " overlaps " + shown[i - 1].id);
        }
        foreach (var item in shown) {
            var b = item.bubble;
            if (b.Left < 0 || b.Right > width - 10) problems.Add(label + " bubble " + item.id + " leaves the canvas sideways");
            int sampleY = (Math.Max(s(72), b.Top) + Math.Min(height, b.Bottom)) / 2;
            int sampleX = b.Left + (sampleY - b.Top < s(16) || b.Bottom - sampleY < s(16) ? s(18) : s(4));
            int fill = Pixel(image, stride, ox + Math.Max(0, Math.Min(width - 1, sampleX)), oy + Math.Max(0, Math.Min(height - 1, sampleY)));
            if (b.Bottom > s(72) && Distance(fill, background) < 6) problems.Add(label + " bubble " + item.id + " has no visible bubble fill");
            if (!Empty(item.media) && (item.media.Left < b.Left || item.media.Right > b.Right || item.media.Top < b.Top || item.media.Bottom > b.Bottom)) problems.Add(label + " player of " + item.id + " is outside its own bubble");
            if (!Empty(item.time) && item.time.Top >= s(72) && item.time.Bottom <= height) {
                var time = Clip(item.time, width, height);
                if (Ink(image, stride, ox, oy, time, fill) < 10) problems.Add(label + " time stamp of " + item.id + " is not visible");
            }
            if (!Empty(item.media) && item.media.Top >= 0 && item.media.Top + s(32) <= height) {
                var circle = new Rect { Left = b.Left + s(12), Top = item.media.Top + s(4), Right = b.Left + s(40), Bottom = item.media.Top + s(32) };
                var glyph = new Rect { Left = b.Left + s(22), Top = item.media.Top + s(12), Right = b.Left + s(32), Bottom = item.media.Top + s(24) };
                int ring = Pixel(image, stride, ox + circle.Left + s(14), oy + circle.Top + s(4));
                if (Distance(ring, fill) < 6) problems.Add(label + " player circle of " + item.id + " is missing from its bubble");
                if (Ink(image, stride, ox, oy, glyph, ring) < 6) problems.Add(label + " play glyph of " + item.id + " is not inside its player circle");
            }
        }
        return problems;
    }

    public static Result Check(byte[] partial, byte[] full, int imageWidth, int imageHeight, int stride, Rect canvas, int screenX, int screenY, Rect[] all, Item[] voice, int dpi) {
        int ox = canvas.Left - screenX, oy = canvas.Top - screenY;
        int width = canvas.Right - canvas.Left, height = canvas.Bottom - canvas.Top;
        if (stride < imageWidth * 4 || ox < 0 || oy < 0 || ox + width > imageWidth || oy + height > imageHeight || partial.Length != full.Length) throw new Exception("Screenshots do not contain the canvas");
        var result = new Result();
        result.differing = Differ(partial, full, stride, ox, oy, new Rect { Left = 0, Top = 0, Right = width, Bottom = height });
        if (result.differing > 16) {
            result.problems.Add("partial repaint of the voice bubbles differs from a full repaint in " + result.differing + " pixels (stale or misplaced drawing)");
            foreach (var item in voice) {
                if (Empty(item.bubble)) continue;
                long changed = Differ(partial, full, stride, ox, oy, Clip(item.bubble, width, height));
                if (changed > 0) result.problems.Add("bubble " + item.id + " differs in " + changed + " pixels after its partial repaint");
            }
        }
        long outside;
        result.partialProblems = Inspect("partial repaint", partial, stride, ox, oy, width, height, all, voice, dpi, out outside);
        result.outside = outside;
        result.fullProblems = Inspect("full repaint", full, stride, ox, oy, width, height, all, voice, dpi, out outside);
        result.outside = Math.Max(result.outside, outside);
        result.problems.AddRange(result.partialProblems);
        result.problems.AddRange(result.fullProblems);
        return result;
    }
}

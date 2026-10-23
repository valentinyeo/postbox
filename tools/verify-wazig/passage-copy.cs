using System;
using System.Collections.Generic;
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
    public sealed class HighlightMeasurement {
        public int left, top, right, bottom, bubble, fill, pixels, required;
        public double contrast;
    }
    static int Pixel(byte[] image, int stride, int x, int y) {
        int p = y * stride + x * 4;
        return image[p] | image[p + 1] << 8 | image[p + 2] << 16;
    }
    static double Linear(int channel) {
        double value = channel / 255.0;
        return value <= 0.04045 ? value / 12.92 : Math.Pow((value + 0.055) / 1.055, 2.4);
    }
    static double Luminance(int color) {
        return 0.2126 * Linear((color >> 16) & 255) + 0.7152 * Linear((color >> 8) & 255) + 0.0722 * Linear(color & 255);
    }
    public static HighlightMeasurement Highlight(byte[] before, byte[] after, int stride, int left, int top, int right, int bottom, int dpi) {
        if (before.Length != after.Length) throw new Exception("Passage screenshots differ in size");
        int[] middle = Middle(before, stride, left, top, right, bottom, dpi);
        int radius = Math.Max(2, 3 * dpi / 96);
        var result = new HighlightMeasurement {
            left = left + Math.Max(2, 12 * dpi / 96), right = (left + right) / 2,
            top = middle[1] - radius, bottom = middle[1] + radius + 1
        };
        if (result.left >= result.right || result.top < top || result.bottom > bottom) throw new Exception("Passage text row is outside its bubble");
        int lastInk = result.left;
        for (int y = result.top; y < result.bottom; y++) for (int x = result.left; x < result.right; x++) {
            int color = Pixel(before, stride, x, y);
            if ((color & 255) > 170 && ((color >> 8) & 255) > 170 && ((color >> 16) & 255) > 170) lastInk = Math.Max(lastInk, x);
        }
        if (lastInk == result.left) throw new Exception("Passage text row has no body ink");
        result.right = lastInk + 1;
        var colors = new Dictionary<int, int>();
        for (int y = result.top; y < result.bottom; y++) for (int x = result.left; x < result.right; x++) {
            int color = Pixel(before, stride, x, y);
            colors[color] = colors.ContainsKey(color) ? colors[color] + 1 : 1;
        }
        int baseline = 0;
        foreach (var color in colors) if (color.Value > baseline) { result.bubble = color.Key; baseline = color.Value; }
        if (baseline * 2 <= (result.right - result.left) * (result.bottom - result.top)) throw new Exception("Passage row has no dominant unselected bubble fill");
        colors.Clear();
        for (int y = result.top; y < result.bottom; y++) for (int x = result.left; x < result.right; x++) {
            if (Pixel(before, stride, x, y) != result.bubble) continue;
            int color = Pixel(after, stride, x, y);
            if (color == result.bubble) continue;
            colors[color] = colors.ContainsKey(color) ? colors[color] + 1 : 1;
        }
        result.fill = result.bubble;
        foreach (var color in colors) if (color.Value > result.pixels) { result.fill = color.Key; result.pixels = color.Value; }
        result.required = Math.Max(24, (baseline + 3) / 4);
        double a = Luminance(result.bubble), b = Luminance(result.fill);
        result.contrast = (Math.Max(a, b) + 0.05) / (Math.Min(a, b) + 0.05);
        return result;
    }
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

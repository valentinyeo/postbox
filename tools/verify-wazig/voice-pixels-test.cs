using System;

public static class VoicePixelsTest {
    const int Width = 200, Height = 160, Stride = Width * 4;
    static VerifyVoice.Rect Rect(int l, int t, int r, int b) {
        return new VerifyVoice.Rect { Left = l, Top = t, Right = r, Bottom = b };
    }
    static void Fill(byte[] image, VerifyVoice.Rect rect, byte b, byte g, byte r) {
        for (int y = rect.Top; y < rect.Bottom; y++) for (int x = rect.Left; x < rect.Right; x++) {
            int offset = y * Stride + x * 4;
            image[offset] = b; image[offset + 1] = g; image[offset + 2] = r; image[offset + 3] = 255;
        }
    }
    static VerifyVoice.Result Check(byte[] partial, byte[] full, VerifyVoice.Rect bubble) {
        var item = new VerifyVoice.Item { id = "voice", bubble = bubble, media = Rect(20, 85, 180, 130), time = Rect(0, 0, 0, 0) };
        return VerifyVoice.Check(partial, full, Width, Height, Stride, Rect(0, 0, Width, Height), 0, 0, new[] { bubble }, new[] { item }, 96);
    }
    static void Require(bool condition, string message) {
        if (!condition) throw new Exception(message);
    }
    public static void Run() {
        var canvas = Rect(0, 0, Width, Height);
        var bubble = Rect(20, 80, 180, 150);
        var full = new byte[Stride * Height];
        Fill(full, canvas, 20, 20, 20);
        Fill(full, bubble, 100, 100, 100);
        Fill(full, Rect(46, 93, 47, 94), 150, 150, 150);
        Fill(full, Rect(42, 97, 48, 99), 240, 240, 240);
        var partial = (byte[])full.Clone();
        Require(Check(partial, full, bubble).problems.Count == 0, "baseline rejected");
        Fill(partial, Rect(60, 100, 90, 101), 101, 99, 101);
        var result = Check(partial, full, bubble);
        Require(result.differing == 0 && result.problems.Count == 0, "one-level RGB shading rejected");
        for (int channel = 0; channel < 3; channel++) {
            partial = (byte[])full.Clone();
            for (int x = 60; x < 77; x++) partial[100 * Stride + x * 4 + channel] += 2;
            result = Check(partial, full, bubble);
            Require(result.differing == 17 && result.problems.Count > 0, "two-level channel change accepted");
        }
        partial = (byte[])full.Clone();
        Fill(partial, Rect(20, 80, 21, 150), 20, 20, 20);
        result = Check(partial, full, bubble);
        Require(result.differing == 70 && result.problems.Count > 0, "shifted bubble edge accepted");
        partial = (byte[])full.Clone();
        Fill(partial, Rect(60, 100, 77, 101), 200, 200, 200);
        result = Check(partial, full, bubble);
        Require(result.differing == 17 && result.problems.Count > 0, "stale drawing accepted");
        partial = (byte[])full.Clone();
        Fill(partial, Rect(42, 97, 48, 99), 150, 150, 150);
        result = Check(partial, partial, bubble);
        Require(result.problems.Exists(p => p.Contains("play glyph")), "missing glyph accepted");
        result = Check(full, full, Rect(20, 80, 201, 150));
        Require(result.problems.Exists(p => p.Contains("leaves the canvas")), "oversized bubble accepted");
        partial = (byte[])full.Clone();
        Fill(partial, Rect(10, 100, 11, 101), 200, 200, 200);
        result = Check(partial, partial, bubble);
        Require(result.outside == 1 && result.problems.Count > 0, "drawing outside bubbles accepted");
        var first = new VerifyVoice.Item { id = "first", bubble = bubble, media = Rect(20, 85, 180, 130) };
        var second = new VerifyVoice.Item { id = "second", bubble = Rect(20, 100, 180, 150) };
        result = VerifyVoice.Check(full, full, Width, Height, Stride, canvas, 0, 0, new[] { bubble }, new[] { first, second }, 96);
        Require(result.problems.Exists(p => p.Contains("overlaps")), "overlapping bubbles accepted");
        bool rejected = false;
        try { VerifyVoice.Check(full, full, Width - 1, Height, Stride, canvas, 0, 0, new[] { bubble }, new[] { first }, 96); }
        catch (Exception) { rejected = true; }
        Require(rejected, "mismatched screenshot geometry accepted");
        Console.WriteLine("VOICE PIXEL CONTROLS PASSED");
    }
}

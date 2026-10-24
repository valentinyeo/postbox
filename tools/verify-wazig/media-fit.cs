using System;
using System.Collections.Generic;

public static class VerifyMediaFit {
    public sealed class Result {
        public int pixels, outside, textBottom = -1, textTop = -1, textRight = -1, timeTop = int.MaxValue, timePixels;
        public List<string> problems = new List<string>();
    }
    static int Scale(int n, int dpi) { return (n * dpi + 48) / 96; }
    static int[] Pixel(byte[] data, int stride, int x, int y) {
        int p = y * stride + x * 4;
        return new int[] { data[p + 2], data[p + 1], data[p] };
    }
    static bool Ink(int[] p) { return Math.Min(p[0], Math.Min(p[1], p[2])) > 110; }
    static int[] TextBand(byte[] data, int stride, int ox, int oy, int[] bubble, int dpi) {
        int top = -1, bottom = -1;
        for (int y = bubble[1] + Scale(6, dpi); y < bubble[3] - Scale(5, dpi); y++) {
            bool ink = false;
            for (int x = bubble[0] + Scale(12, dpi); x < bubble[2] - Scale(60, dpi); x++) {
                if (Ink(Pixel(data, stride, ox + x, oy + y))) { ink = true; break; }
            }
            if (ink) { if (bottom != y - 1) top = y; bottom = y; }
        }
        if (top < 0) throw new Exception("media-fit: missing body text pixels");
        return new int[] { top, bottom };
    }
    public static int WordStep(byte[] data, int stride, int ox, int oy, int[] bubble, int dpi) {
        int[] band = TextBand(data, stride, ox, oy, bubble, dpi);
        var starts = new List<int>();
        bool previous = false;
        for (int x = bubble[0] + Scale(12, dpi); x < bubble[2] - Scale(60, dpi); x++) {
            bool ink = false;
            for (int y = band[0]; y <= band[1]; y++) {
                if (Ink(Pixel(data, stride, ox + x, oy + y))) { ink = true; break; }
            }
            if (ink && !previous) starts.Add(x);
            previous = ink;
        }
        if (starts.Count != 8) throw new Exception("media-fit: calibration must show eight separate M glyphs");
        int step = starts[1] - starts[0];
        for (int i = 2; i < starts.Count; i++) if (starts[i] - starts[i - 1] != step) throw new Exception("media-fit: calibration glyph spacing changed");
        return step;
    }
    public static Result Check(byte[] data, int width, int height, int stride, int ox, int oy, int cw, int ch, int[] bubble, int[] media, string kind, int dpi) {
        var result = new Result();
        if (ox < 0 || oy < 0 || ox + cw > width || oy + ch > height) throw new Exception("media-fit: canvas outside screenshot");
        if (kind == "own") {
            int timeLeft = bubble[2] - Scale(52, dpi), timeRight = bubble[2] - Scale(10, dpi);
            int[] band = TextBand(data, stride, ox, oy, bubble, dpi);
            result.textTop = band[0];
            result.textBottom = band[1];
            for (int y = result.textTop; y <= result.textBottom; y++) {
                for (int x = bubble[0] + Scale(12, dpi); x < bubble[2] - Scale(12, dpi); x++) {
                    var p = Pixel(data, stride, ox + x, oy + y);
                    if (Math.Min(p[0], Math.Min(p[1], p[2])) > 230) result.textRight = Math.Max(result.textRight, x);
                }
            }
            int timeBottom = -1;
            for (int y = result.textTop; y < bubble[3] - Scale(5, dpi); y++) {
                bool ink = false;
                for (int x = timeLeft; x < timeRight; x++) {
                    if (Ink(Pixel(data, stride, ox + x, oy + y))) { ink = true; result.timePixels++; }
                }
                if (ink) { if (timeBottom != y - 1) result.timeTop = y; timeBottom = y; }
            }
            if (result.textBottom < 0 || result.timePixels == 0) result.problems.Add("missing text or time pixels");
            if (result.textRight < timeLeft) result.problems.Add("fixture text did not reach the time box");
            if (result.textBottom >= result.timeTop) result.problems.Add("time overlaps the last text line");
            return result;
        }
        int mw = media[2] - media[0], mh = media[3] - media[1];
        if (mw <= 0 || mh <= 0 || media[0] < bubble[0] + Scale(12, dpi) || media[2] > bubble[2] - Scale(12, dpi) || media[1] < bubble[1] || media[3] > bubble[3]) result.problems.Add("media rect leaves bubble content");
        if (mw > bubble[2] - bubble[0] || mh > Scale(250, dpi)) result.problems.Add("media exceeds width or height cap");
        for (int y = 0; y < ch; y++) for (int x = 0; x < cw; x++) {
            var p = Pixel(data, stride, ox + x, oy + y);
            bool colour = kind == "landscape" ? Math.Abs(p[0] - 32) <= 8 && Math.Abs(p[1] - 176) <= 8 && Math.Abs(p[2] - 208) <= 8 :
                kind == "portrait" ? Math.Abs(p[0] - 176) <= 8 && Math.Abs(p[1] - 64) <= 8 && Math.Abs(p[2] - 208) <= 8 : p[0] > 230 && p[1] > 120 && p[1] < 190 && p[2] < 25;
            if (!colour) continue;
            result.pixels++;
            if (x < media[0] || x >= media[2] || y < media[1] || y >= media[3] || x < bubble[0] || x >= bubble[2] || y < bubble[1] || y >= bubble[3]) result.outside++;
        }
        if (result.pixels == 0) result.problems.Add("downloaded media has no screenshot pixels");
        if (result.outside != 0) result.problems.Add("media pixels spill outside their rectangle or bubble");
        return result;
    }
}

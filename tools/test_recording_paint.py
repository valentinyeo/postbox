import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def extract(source, name):
    start = source.index(f"fn {name}(")
    return source[start:source.index("\n}\n", start) + 3]


def read_source(path):
    revision = os.environ.get("RECORDING_PAINT_REVISION")
    if revision:
        return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT, text=True)
    return (ROOT / path).read_text()


class RecordingPaintTests(unittest.TestCase):
    def test_IGSH_482_strip_paints_to_memory_before_one_blit(self):
        painter = extract(read_source("src/main.zig"), "drawVoiceButton")
        self.assertIn("win.CreateCompatibleDC", painter)
        self.assertIn("win.CreateCompatibleBitmap", painter)
        self.assertEqual(painter.count("win.BitBlt("), 1)
        self.assertIn("paintVoiceButton(a, &buffered)", painter)
        self.assertLess(painter.index("paintVoiceButton(a, &buffered)"), painter.index("win.BitBlt("))
        self.assertNotIn("win.FillRect", painter)
        self.assertIn("win.DeleteDC", painter)
        self.assertIn("win.DeleteObject", painter)
        content = extract(read_source("src/main.zig"), "paintVoiceButton")
        self.assertIn("const hdc = item.hDC", content)
        self.assertIn("session.elapsedMs()", content)
        self.assertIn("session.levelPercent()", content)
        for forbidden in ("InvalidateRect", "RedrawWindow", "SetWindowText", "layout("):
            self.assertNotIn(forbidden, content)

    def test_IGSH_482_voice_background_erase_never_reaches_button_default(self):
        proc = extract(read_source("src/main.zig"), "composerButtonProc")
        self.assertRegex(proc, r"win\.WM_ERASEBKGND\s*=>\s*\{\s*if \(a\.voice_btn\) \|button\| \{\s*if \(button == hwnd\) return 1;\s*\}")
        self.assertLess(proc.index("win.WM_ERASEBKGND"), proc.index("win.CallWindowProcW"))

    def verify_IGSH_482_real_tick_and_lifecycle_runtime(self):
        source = read_source("src/main.zig")
        interval = re.search(r"win\.SetTimer\(hwnd, timer_voice, ([\w.]+), null\)", source).group(1)
        pieces = []
        if interval == "recording_paint.tick_interval_ms":
            pieces.append('const recording_paint = @import("recording_paint.zig");')
        else:
            self.assertTrue(interval.isdecimal())
        if "fn paintVoiceButton(" in source:
            pieces.append(extract(source, "drawVoiceButton"))
        for name in ("invalidateRecordingTick", "tickVoice"):
            if f"fn {name}(" in source:
                pieces.append(extract(source, name))
        timer = source[source.index("win.WM_TIMER =>", source.index("fn tickVoice(")):]
        self.assertRegex(timer, r"if \(wparam == timer_voice\) \{\s*tickVoice\(a\);")
        fixture = (ROOT / "tools/recording_paint_test.zig").read_text()
        if "fn paintVoiceButton(" not in source:
            fixture = fixture[:fixture.index("\nfn paintVoiceButton(")]
        fixture = fixture.replace("const tick_interval_ms = recording_paint.tick_interval_ms;", f"const tick_interval_ms = {interval};")
        zig = os.environ.get("ZIG") or shutil.which("zig")
        self.assertIsNotNone(zig, "Set ZIG to Zig 0.16.0")
        with tempfile.TemporaryDirectory(prefix="recording-paint-") as directory:
            directory = Path(directory)
            if interval == "recording_paint.tick_interval_ms":
                (directory / "recording_paint.zig").write_text(read_source("src/recording_paint.zig"))
            path = directory / "test.zig"
            path.write_text(fixture + "\n" + "\n".join(pieces))
            run = subprocess.run([zig, "test", str(path)], cwd=ROOT, text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            print(run.stdout, end="")
            self.assertEqual(run.returncode, 0, run.stdout)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(RecordingPaintTests)
    suite.addTest(RecordingPaintTests("verify_IGSH_482_real_tick_and_lifecycle_runtime"))
    from test_theme_runtime import ThemeRuntimeTests
    suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(ThemeRuntimeTests))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print("recording paint verification passed")

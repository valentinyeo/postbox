import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ZIG = Path.home() / ".local/zig-0.16.0/zig"
ZIG = shutil.which(os.environ.get("ZIG", str(DEFAULT_ZIG) if DEFAULT_ZIG.exists() else "zig"))


def section(source, start, end):
    first = source.index(start)
    return source[first:source.index(end, first + len(start))]


def verify_wiring(main):
    startup = main[main.index("pub fn main(init: std.process.Init) !void {"):]
    assert startup.index("theme.set(loadTheme());") < startup.index("win.CreateWindowExW(")
    palette = section(main, "fn buildPaletteItems(", "fn ")
    assert 'appendPalette(a, "Theme: AMOLED black", "", command_theme_amoled);' in palette
    assert 'appendPalette(a, "Theme: Green", "", command_theme_green);' in palette
    assert "_ = changeTheme(a, if (command == command_theme_amoled) .amoled else .green);" in main
    control = section(main, "fn controlDispatch(", "fn controlProvider(")
    assert ".theme => {" in control
    assert "request.theme orelse" in control
    assert "if (!changeTheme(a, choice))" in control
    status = section(main, "fn controlStatus(", "fn ")
    assert '\\"theme\\":\\"{s}\\"' in status and "@tagName(theme.choice)" in status
    assert "a.search_pill, fieldColor()," in main
    assert "a.compose_pill, fieldColor()," in main
    assert "win.SetBkColor(hdc, fieldColor())" in main
    assert "if (theme.choice == .amoled) a.brush_bg.? else a.brush_raised.?" in main
    assert "if (!recreateThemeBrushes(a)) return -1;" in main
    assert "const class_brush" not in main
    player = section(main, "fn playerProc(", "fn openPlayerWindow(")
    assert "win.WM_ERASEBKGND =>" in player and "win.CreateSolidBrush(theme.current.surface)" in player
    assert "a.brush_bg.?" not in player


class ThemeRuntimeTests(unittest.TestCase):
    @unittest.skipUnless(ZIG, "Zig compiler not found; install Zig or set ZIG")
    def test_actual_registry_brush_switch_and_redraw_functions(self):
        main = (ROOT / "src/main.zig").read_text()
        source = (ROOT / "tools/theme_runtime_test.zig").read_text()
        source += section(main, "fn loadTheme(", "fn loadFontScale(")
        source += section(main, "fn saveTheme(", "fn saveFontScale(")
        with tempfile.TemporaryDirectory(prefix="theme-runtime-") as directory:
            root = Path(directory)
            (root / "theme.zig").write_text((ROOT / "src/theme.zig").read_text())
            harness = root / "runtime.zig"
            harness.write_text(source)
            result = subprocess.run([ZIG, "test", str(harness)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("All 10 tests passed.", result.stdout + result.stderr)

    def test_startup_palette_control_and_child_paint_wiring_with_removal_controls(self):
        main = (ROOT / "src/main.zig").read_text()
        verify_wiring(main)
        for token in (
            "theme.set(loadTheme());",
            'appendPalette(a, "Theme: AMOLED black", "", command_theme_amoled);',
            'appendPalette(a, "Theme: Green", "", command_theme_green);',
            "_ = changeTheme(a, if (command == command_theme_amoled) .amoled else .green);",
            "if (!changeTheme(a, choice))",
            "a.compose_pill, fieldColor(),",
            "win.SetBkColor(hdc, fieldColor())",
            "if (!recreateThemeBrushes(a)) return -1;",
        ):
            with self.subTest(token=token), self.assertRaises((AssertionError, ValueError)):
                verify_wiring(main.replace(token, "", 1))
        with self.assertRaises(AssertionError):
            verify_wiring(main + "\nconst class_brush = 1;\n")

    def test_no_compile_time_or_noncurrent_theme_colors(self):
        colors = set(re.findall(r"^    (\w+): u32,", (ROOT / "src/theme.zig").read_text(), re.MULTILINE))
        pattern = re.compile(r"theme\.(?:" + "|".join(colors) + r"|@\"error\")(?!\w)")
        self.assertIsNotNone(pattern.search("const stale = theme.surface;"))
        for path in (ROOT / "src").glob("*.zig"):
            if path.name != "theme.zig":
                self.assertIsNone(pattern.search(path.read_text()), str(path))
                self.assertNotRegex(path.read_text(), r"(?m)^const \w+ = theme\.current\.")

    @unittest.skipUnless(ZIG, "Zig compiler not found; install Zig or set ZIG")
    def test_new_zig_tests_reject_pre_theme_code(self):
        with tempfile.TemporaryDirectory(prefix="theme-regression-") as directory:
            root = Path(directory)
            current_theme = (ROOT / "src/theme.zig").read_text()
            current_control = (ROOT / "src/control.zig").read_text()
            baseline_theme = subprocess.check_output(["git", "show", "a735c9f:src/theme.zig"], cwd=ROOT, text=True)
            baseline_control = subprocess.check_output(["git", "show", "a735c9f:src/control.zig"], cwd=ROOT, text=True)
            (root / "theme.zig").write_text(baseline_theme + current_theme[current_theme.index('test "green palette preserves'):])
            result = subprocess.run([ZIG, "test", str(root / "theme.zig")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertRegex(result.stderr, r"undeclared identifier '(?:Palette|green|amoled|Choice)'")
            (root / "theme.zig").write_text(current_theme)
            (root / "control.zig").write_text('const theme = @import("theme.zig");\n' + baseline_control + current_control[current_control.index('test "theme accepts both choices'):])
            result = subprocess.run([ZIG, "test", str(root / "control.zig")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertRegex(result.stderr, r"(?:no field named|has no member named) 'theme'")


if __name__ == "__main__":
    unittest.main(verbosity=2)

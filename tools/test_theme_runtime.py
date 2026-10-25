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


def verify_wiring(main, edit):
    startup = main[main.index("pub fn main(init: std.process.Init) !void {"):]
    assert startup.index("applyTheme(loadTheme());") < startup.index("win.CreateWindowExW(")
    apply = section(main, "fn applyTheme(", "fn changeTheme(")
    for token in ("theme.set(choice);", "@ptrFromInt(135)", "@ptrFromInt(136)",
                  "set_preferred_app_mode(menu_theme.preferredAppMode(choice))", "flush_menu_themes();"):
        assert token in apply
    switch = section(main, "fn changeTheme(", "fn ")
    assert switch.index("applyTheme(choice);") < switch.index("recreateThemeBrushes(a)")
    assert "applyTheme(previous);" in switch
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
    assert "paintPopupInput(&shapes, hwnd, a.palette_edit);" in main
    assert "paintInputField(a, &shapes, hdc, a.compose.?, a.compose_pill);" in main
    field = section(main, "fn paintInputField(", "fn ")
    assert "theme.current.surface_container_high, theme.current.on_surface" in field
    assert "if (win.GetFocus() == control) theme.current.primary else theme.current.outline" in field
    paint = section(main, "fn paintRoundedButton(", "fn ")
    assert "smooth.strokeRoundRect(shapes, rect, radius, radius, frame_color, 1)" in paint
    colors = main[main.index("win.WM_CTLCOLORSTATIC, win.WM_CTLCOLOREDIT, win.WM_CTLCOLORLISTBOX => {"):]
    assert "for ([_]?win.HWND{ a.compose }) |control|" in colors
    assert "win.SetBkColor(hdc, theme.current.surface_container_high)" in colors
    assert "return @bitCast(@intFromPtr(a.brush_raised.?));" in colors
    assert "a.palette_edit = directwrite_edit.create(" in main
    paint = section(edit, "    fn paint(", "    fn contextMenu(")
    assert "win.WM_CTLCOLOREDIT" in paint
    assert "win.SetTextColor(dc, theme.current.on_surface)" in paint
    assert "win.SetBkColor(dc, theme.current.surface_container_high)" in paint
    assert "win.SetDCBrushColor(dc, win.GetBkColor(dc))" in paint
    assert "win.FillRect(dc, &client" in paint
    assert paint.index("win.WM_CTLCOLOREDIT") < paint.index("win.GetBkColor(dc)")
    assert "if (length == 0)" in paint
    assert "win.SetTextColor(dc, theme.current.on_surface_variant)" in paint
    assert "text_draw.drawText(dc, &self.cue" in paint
    assert "win.HideCaret(hwnd)" in edit and "win.ShowCaret(hwnd)" in edit
    assert "id == id_compose and (notification == win.EN_SETFOCUS or notification == win.EN_KILLFOCUS)" in main
    assert "win.InflateRect(&dirty, 1, 1)" in main
    assert "compose_layout.composerBorderRect(@bitCast(rect))" in field
    assert "win.InvalidateRect(hwnd, &dirty, win.FALSE)" in main
    assert "win.SetBkColor(hdc, fieldColor())" in main
    assert "if (theme.choice == .amoled) a.brush_bg.? else a.brush_raised.?" in main
    assert "if (!recreateThemeBrushes(a)) return -1;" in main
    assert "const class_brush" not in main
    player = section(main, "fn playerProc(", "fn openPlayerWindow(")
    assert "win.WM_ERASEBKGND =>" in player and "win.CreateSolidBrush(theme.current.surface)" in player
    assert "a.brush_bg.?" not in player


def verify_amoled_surfaces(main):
    voice = section(main, "fn paintVoiceButton(", "fn ")
    composer = section(main, "fn drawComposerButton(", "fn ")
    for paint in (voice, composer):
        assert "if (theme.choice == .amoled)" in paint
        for state in ("amoled_button", "amoled_button_hover", "amoled_button_pressed"):
            assert "theme." + state in paint
        assert "theme.current.outline_variant" in paint
    for state in ("amoled_send", "amoled_send_hover", "amoled_send_pressed", "amoled_button_text"):
        assert "theme." + state in composer
    field = section(main, "fn paintPopupInput(", "fn ")
    assert "if (theme.choice != .amoled) return;" in field
    assert "theme.current.surface_container_high" in field
    assert "if (win.GetFocus() == edit) theme.current.primary else theme.current.outline, 1)" in field
    for procedure, edit in (("fn emojiProc(", "a.emoji_edit"), ("fn paletteProc(", "a.palette_edit")):
        popup = section(main, procedure, "fn ")
        assert "paintPopupInput(&shapes, hwnd, " + edit + ");" in popup
        assert "win.FrameRect(hdc, &client, a.brush_muted.?)" in popup
        assert "message == win.WM_CTLCOLOREDIT and theme.choice == .amoled" in popup
    tooltip = section(main, "fn updateTooltipTheme(", "fn createTooltips(")
    assert 'win.GetProcAddress(module, "SetWindowTheme")' in tooltip
    assert "win.TTM_SETTIPBKCOLOR" in tooltip and "win.TTM_SETTIPTEXTCOLOR" in tooltip
    assert "updateTooltipTheme(a);" in section(main, "fn changeTheme(", "fn ")


def verify_popup_focus(main):
    field = section(main, "fn paintPopupInput(", "fn ")
    assert "if (win.GetFocus() == edit) theme.current.primary else theme.current.outline" in field
    for procedure, condition in (
        ("emojiProc", "id == id_emoji_edit"),
        ("paletteProc", "id == id_palette_edit"),
    ):
        popup = section(main, "fn " + procedure + "(", "\nfn ")
        command = section(popup, "win.WM_COMMAND => {", "return 0;")
        assert "if (" + condition + " and (notification == win.EN_SETFOCUS or notification == win.EN_KILLFOCUS))" in command
        assert "win.InvalidateRect(hwnd, null, win.FALSE);" in command
    assert "fn telegramLoginProc(" not in main
    assert "fn slackSetupProc(" not in main


class ThemeRuntimeTests(unittest.TestCase):
    def test_IGSH_461_popup_focus_and_disabled_input_wiring_with_negative_controls(self):
        main = (ROOT / "src/main.zig").read_text()
        verify_popup_focus(main)
        for token in (
            "if (win.GetFocus() == edit) theme.current.primary else theme.current.outline",
            "id == id_emoji_edit and (notification == win.EN_SETFOCUS",
            "id == id_palette_edit and (notification == win.EN_SETFOCUS",
            "win.InvalidateRect(hwnd, null, win.FALSE);",
        ):
            with self.subTest(token=token), self.assertRaises((AssertionError, ValueError)):
                verify_popup_focus(main.replace(token, ""))

    def test_retired_login_dialogs_cannot_return(self):
        main = (ROOT / "src/main.zig").read_text()
        for procedure in ("telegramLoginProc", "slackSetupProc"):
            with self.subTest(procedure=procedure), self.assertRaises(AssertionError):
                verify_popup_focus(main + "\nfn " + procedure + "() void {}\n")

    @unittest.skipUnless(ZIG, "Zig compiler not found; install Zig or set ZIG")
    def test_IGSH_461_popup_paint_passes_and_rejects_main_before_fix(self):
        current = (ROOT / "src/main.zig").read_text()
        baseline = subprocess.check_output(["git", "show", "3b7591c:src/main.zig"], cwd=ROOT, text=True)
        harness = (ROOT / "tools/theme_popup_test.zig").read_text()
        with tempfile.TemporaryDirectory(prefix="theme-popup-") as directory:
            root = Path(directory)
            (root / "theme.zig").write_text((ROOT / "src/theme.zig").read_text())
            for source, passes in ((current, True), (baseline, False)):
                with self.subTest(passes=passes):
                    path = root / "popup.zig"
                    path.write_text(harness + section(source, "fn paintPopupInput(", "\nfn "))
                    result = subprocess.run([ZIG, "test", str(path), "--test-filter", "IGSH-461"], capture_output=True, text=True)
                    output = result.stdout + result.stderr
                    if passes:
                        self.assertEqual(result.returncode, 0, output)
                        self.assertRegex(output, r"All [0-9]+ tests passed\.")
                    else:
                        self.assertNotEqual(result.returncode, 0, output)
                        self.assertIn("FAIL (TestExpectedEqual)", output)
                        self.assertIn("IGSH-461 AMOLED popup input keeps its raised fill and follows focus in both directions", output)
        with self.assertRaises(AssertionError):
            verify_popup_focus(baseline)

    def test_IGSH_461_amoled_surface_wiring_with_negative_controls(self):
        main = (ROOT / "src/main.zig").read_text()
        verify_amoled_surfaces(main)
        for token in (
            "theme.amoled_button_hover",
            "theme.amoled_button_pressed",
            "theme.amoled_send_hover",
            "theme.amoled_send_pressed",
            "paintPopupInput(&shapes, hwnd, a.emoji_edit);",
            "paintPopupInput(&shapes, hwnd, a.palette_edit);",
            "if (theme.choice != .amoled) return;",
            "win.TTM_SETTIPBKCOLOR",
            "updateTooltipTheme(a);",
        ):
            with self.subTest(token=token), self.assertRaises((AssertionError, ValueError)):
                verify_amoled_surfaces(main.replace(token, ""))

    @unittest.skipUnless(ZIG, "Zig compiler not found; install Zig or set ZIG")
    def test_actual_registry_brush_switch_and_redraw_functions(self):
        main = (ROOT / "src/main.zig").read_text()
        source = (ROOT / "tools/theme_runtime_test.zig").read_text()
        source += section(main, "fn loadTheme(", "fn loadFontScale(")
        source += section(main, "fn saveTheme(", "fn saveFontScale(")
        with tempfile.TemporaryDirectory(prefix="theme-runtime-") as directory:
            root = Path(directory)
            (root / "theme.zig").write_text((ROOT / "src/theme.zig").read_text())
            (root / "menu_theme.zig").write_text((ROOT / "src/menu_theme.zig").read_text())
            harness = root / "runtime.zig"
            harness.write_text(source)
            result = subprocess.run([ZIG, "test", str(harness)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout + result.stderr, r"All [0-9]+ tests passed\.")
            for original, broken in (
                ("_ = win.EnumThreadWindows(win.GetCurrentThreadId(), redrawThemeWindow, 0);", ""),
                ("win.RDW_ALLCHILDREN", "0"),
            ):
                with self.subTest(original=original):
                    self.assertEqual(source.count(original), 1)
                    harness.write_text(source.replace(original, broken))
                    result = subprocess.run([ZIG, "test", str(harness)], capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_IGSH_505_startup_palette_control_and_child_paint_wiring_with_removal_controls(self):
        main = (ROOT / "src/main.zig").read_text()
        edit = (ROOT / "src/directwrite_edit.zig").read_text()
        verify_wiring(main, edit)
        for token in (
            "applyTheme(loadTheme());",
            "applyTheme(choice);",
            "applyTheme(previous);",
            "theme.set(choice);",
            "@ptrFromInt(135)",
            "@ptrFromInt(136)",
            "set_preferred_app_mode(menu_theme.preferredAppMode(choice))",
            "flush_menu_themes();",
            'appendPalette(a, "Theme: AMOLED black", "", command_theme_amoled);',
            'appendPalette(a, "Theme: Green", "", command_theme_green);',
            "_ = changeTheme(a, if (command == command_theme_amoled) .amoled else .green);",
            "if (!changeTheme(a, choice))",
            "paintPopupInput(&shapes, hwnd, a.palette_edit);",
            "paintInputField(a, &shapes, hdc, a.compose.?, a.compose_pill);",
            "if (win.GetFocus() == control) theme.current.primary else theme.current.outline",
            "smooth.strokeRoundRect(shapes, rect, radius, radius, frame_color, 1)",
            "for ([_]?win.HWND{ a.compose }) |control|",
            "win.SetBkColor(hdc, theme.current.surface_container_high)",
            "a.palette_edit = directwrite_edit.create(",
            "win.InvalidateRect(hwnd, &dirty, win.FALSE)",
            "win.SetBkColor(hdc, fieldColor())",
            "if (!recreateThemeBrushes(a)) return -1;",
        ):
            with self.subTest(token=token), self.assertRaises((AssertionError, ValueError)):
                verify_wiring(main.replace(token, ""), edit)
        for token in (
            "win.WM_CTLCOLOREDIT",
            "win.SetTextColor(dc, theme.current.on_surface)",
            "win.SetBkColor(dc, theme.current.surface_container_high)",
            "win.SetDCBrushColor(dc, win.GetBkColor(dc))",
            "win.FillRect(dc, &client",
            "if (length == 0)",
            "win.SetTextColor(dc, theme.current.on_surface_variant)",
            "text_draw.drawText(dc, &self.cue",
            "win.HideCaret(hwnd)",
            "win.ShowCaret(hwnd)",
        ):
            with self.subTest(token=token), self.assertRaises((AssertionError, ValueError)):
                verify_wiring(main, edit.replace(token, ""))
        with self.assertRaises(AssertionError):
            verify_wiring(main + "\nconst class_brush = 1;\n", edit)

    def test_no_compile_time_or_noncurrent_theme_colors(self):
        colors = set(re.findall(r"^    (\w+): u32,", (ROOT / "src/theme.zig").read_text(), re.MULTILINE))
        pattern = re.compile(r"theme\.(?:" + "|".join(colors) + r"|@\"error\")(?!\w)")
        self.assertIsNotNone(pattern.search("const stale = theme.surface;"))
        for path in (ROOT / "src").glob("*.zig"):
            if path.name != "theme.zig":
                self.assertIsNone(pattern.search(path.read_text()), str(path))
                self.assertNotRegex(path.read_text(), r"(?m)^const \w+ = theme\.current\.")

    @unittest.skipUnless(ZIG, "Zig compiler not found; install Zig or set ZIG")
    def test_IGSH_461_tests_reject_old_default_and_glaring_fills(self):
        source = (ROOT / "src/theme.zig").read_text()
        for original, broken, test_name in (
            ("value orelse return .amoled", "value orelse return .green", "IGSH-461 default missing"),
            ("amoled_button = hex(0x262626)", "amoled_button = hex(0xbfbfbf)", "IGSH-461 AMOLED composer button"),
            ("amoled_send = hex(0x555555)", "amoled_send = hex(0xe6e6e6)", "IGSH-461 AMOLED composer button"),
        ):
            self.assertIn(original, source)
            with self.subTest(original=original), tempfile.TemporaryDirectory(prefix="amoled-control-") as directory:
                path = Path(directory) / "theme.zig"
                path.write_text(source.replace(original, broken))
                result = subprocess.run([ZIG, "test", str(path), "--test-filter", test_name], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertRegex(result.stdout + result.stderr, r"FAIL \(Test(?:UnexpectedResult|ExpectedEqual)\)")

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

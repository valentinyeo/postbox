import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    revision = os.environ.get("REPAINT_REVISION")
    if revision:
        return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT, text=True)
    return (ROOT / path).read_text()


def function(text, name):
    start = text.index(f"fn {name}(")
    return text[start:text.index("\n}\n", start) + 3]


def verify_buffered(text, name, dirty):
    painter = function(text, name)
    assert "paint_buffer.Buffer.init(" in painter, f"IGSH-510 {name} must buffer painting"
    assert dirty in painter, f"IGSH-510 {name} must use the update rectangle"
    assert "defer surface.deinit();" in painter
    assert painter.index("paint_buffer.Buffer.init(") < painter.index("win.FillRect(")
    assert "surface.hdc" in painter
    assert "win.CreateCompatibleBitmap" not in painter


class RepaintTests(unittest.TestCase):
    def test_IGSH_510_desktop_canvas_and_rows_render_into_dirty_buffers(self):
        main = source("src/main.zig")
        for text, name, dirty in ((main, "mainProc", "paint.rcPaint"),
                                  (main, "drawCanvas", "paint.rcPaint"),
                                  (main, "drawChat", "screen_item.rcItem"),
                                  (main, "drawComposerButton", "screen_item.rcItem")):
            with self.subTest(painter=name):
                verify_buffered(text, name, dirty)
        for name in ("mainProc", "canvasProc"):
            self.assertIn("win.WM_ERASEBKGND => return 1", function(main, name))
        proc = function(main, "composerButtonProc")
        erase = proc.split("win.WM_ERASEBKGND => {", 1)[1].split("win.WM_MOUSEMOVE", 1)[0]
        self.assertTrue(erase.rstrip().endswith("return 1;\n        },"))

    def test_IGSH_510_typing_keeps_drafts_shortcodes_and_only_dirties_its_chat_row(self):
        main = source("src/main.zig")
        handler = main.split("id == id_compose and notification == win.EN_CHANGE", 1)[1].split("} else if", 1)[0]
        for required in ("saveComposerDraft(a);", "layoutComposer(a);", "shortcodeUpdate(a);"):
            self.assertIn(required, handler)
        self.assertNotIn("layout(a,", handler)
        draft = function(main, "saveComposerDraft")
        self.assertIn("win.LB_GETITEMRECT", draft)
        self.assertIn("win.InvalidateRect(list, &row, win.FALSE)", draft)
        self.assertNotIn("win.InvalidateRect(list, null", draft)
        layout = function(main, "layoutRegion")
        self.assertIn("win.InvalidateRect(main_hwnd, dirty, win.FALSE)", layout)
        self.assertIn("layoutRegion(a, width, height, null)", function(main, "layout"))
        composer = function(main, "layoutComposer")
        self.assertIn("@min(a.compose_strip_top, height - sizes.strip_height)", composer)
        self.assertIn("layoutRegion(a, a.compose_client_width, height, &dirty)", composer)

    def test_IGSH_510_gdi_and_smooth_shapes_share_the_dirty_clip(self):
        buffer = source("src/paint_buffer.zig")
        self.assertIn("win.IntersectClipRect(memory, rect.left, rect.top, rect.right, rect.bottom)", buffer)
        self.assertIn("win.BitBlt(self.target, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top", buffer)
        shapes = source("src/smooth_shapes.zig")
        opened = function(shapes, "open")
        self.assertIn("win.GetClipBox(ctx.hdc, &clip)", opened)
        self.assertIn("f.GdipSetClipRect(graphics", opened)
        self.assertIn("@floatFromInt(clip.left)", opened)
        self.assertIn("@floatFromInt(clip.top)", opened)
        build = source("build.zig")
        self.assertIn('@embedFile("tools/repaint_test.zig")', build)
        self.assertIn('sourceSection("\\n                saveComposerDraft(a);"', build)
        self.assertIn("test_step.dependOn(&b.addRunArtifact(repaint_tests).step)", build)

    def test_IGSH_510_source_guards_reject_unbuffered_and_whole_surface_regressions(self):
        main = source("src/main.zig")
        verify_buffered(main, "drawCanvas", "paint.rcPaint")
        for old, new in (("paint_buffer.Buffer.init(", "paint_buffer.Buffer.bypass("),
                         ("paint.rcPaint", "client"),
                         ("defer surface.deinit();", "surface.deinit();")):
            with self.subTest(regression=new), self.assertRaises(AssertionError):
                verify_buffered(main.replace(old, new), "drawCanvas", "paint.rcPaint")

    def test_ISSUE_545_brush_failure_never_blits_an_undrawn_buffer(self):
        main = source("src/main.zig")
        for name in ("mainProc", "drawCanvas", "drawChat", "drawComposerButton"):
            painter = function(main, name)
            if name == "mainProc":
                painter = painter[painter.index("win.WM_PAINT => {"):]
            start = painter.index("paint_buffer.Buffer.init(")
            before_fill = painter[start:painter.index("win.FillRect(", start)]
            with self.subTest(painter=name):
                self.assertNotIn("return", before_fill)
                self.assertNotIn("orelse", before_fill)
        chat = function(main, "drawChat")
        brush = chat.index("const background = win.CreateSolidBrush(")
        self.assertIn("orelse return;", chat[brush:chat.index("paint_buffer.Buffer.init(")])

    def test_ISSUE_545_row_sized_buffer_offsets_the_viewport_and_ci_runs_the_pixel_test(self):
        buffer = source("src/paint_buffer.zig")
        self.assertIn("win.CreateCompatibleBitmap(target, rect.right - rect.left, rect.bottom - rect.top)", buffer)
        self.assertNotIn("client.right, client.bottom", buffer)
        self.assertLess(buffer.index("win.SetViewportOrgEx(memory, -rect.left, -rect.top, null)"),
                        buffer.index("win.IntersectClipRect(memory"))
        shapes = source("src/smooth_shapes.zig")
        self.assertIn('test "ISSUE-545 row-sized buffer places GDI and GDI+ pixels where unbuffered painting does"', shapes)
        self.assertIn('@import("paint_buffer.zig")', shapes)
        ci = source(".github/workflows/ci.yml")
        windows = ci.split("  unfurl-verification:", 1)[1].split("\n  notify-release:", 1)[0]
        self.assertIn("runs-on: windows-latest", windows)
        self.assertIn("zig test src/smooth_shapes.zig -lc -lgdi32 -luser32 -lmsimg32 --test-filter ISSUE-545", windows)
        self.assertIn("ISSUE_545", source("tools/repaint_test.zig"))


if __name__ == "__main__":
    unittest.main()

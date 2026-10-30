from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def verify_defaults(main, config):
    assert re.search(r'pub const default_scale: i32 = 100;', config)
    assert 'font_scale: i32 = @import("font_config.zig").default_scale,' in main
    load = main.split('fn loadFontScale() i32 {', 1)[1].split('\n}', 1)[0]
    assert 'if (result != win.ERROR_SUCCESS) return @import("font_config.zig").default_scale;' in load
    assert 'return @import("font_config.zig").savedScale(value);' in load
    assert 'command_font_reset, command_font_default => setFontScale(a, @import("font_config.zig").default_scale)' in main
    setter = main.split('fn setFontScale(a: *App, scale: i32) void {', 1)[1].split('\n}', 1)[0]
    assert 'a.font_scale = next;' in setter
    assert 'saveFontScale(next);' in setter


class FontScaleTests(unittest.TestCase):
    def test_approved_default_and_reset_share_scale(self):
        verify_defaults((ROOT / 'src/main.zig').read_text(), (ROOT / 'src/font_config.zig').read_text())

    def test_rejects_historical_undersized_default(self):
        historical = lambda path: subprocess.check_output(['git', 'show', f'b41ee91:{path}'], cwd=ROOT, text=True)
        with self.assertRaises(AssertionError):
            verify_defaults(historical('src/main.zig'), historical('src/font_config.zig'))


if __name__ == '__main__':
    unittest.main()

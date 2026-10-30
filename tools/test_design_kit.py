from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DesignKitTests(unittest.TestCase):
    def test_approved_graphite_replaces_the_material_palette(self):
        source = (ROOT / 'src/theme.zig').read_text()
        for literal in ('0x0f1512', '0x88d6ba'):
            self.assertTrue(literal not in source, literal)
        palette = source[source.index('pub const amoled: Palette = .{'):].split('\n};', 1)[0]
        for field, token in {
            'surface': 'ReaderBackground', 'surface_container_low': 'ReaderPanel',
            'surface_container': 'ReaderControl', 'surface_container_high': 'ReaderCard',
            'surface_container_highest': 'ReaderRaised', 'on_surface': 'ReaderForeground',
            'on_surface_variant': 'ReaderHint', 'outline': 'ReaderOutline',
            'outline_variant': 'ReaderOutline', 'primary': 'ReaderForeground',
            'primary_container': 'ReaderUserCard', 'sidebar_surface': 'ReaderPanel',
            'sidebar_divider': 'ReaderOutline',
        }.items():
            with self.subTest(field=field):
                self.assertIn(f'.{field} = design.{token}', palette)
        self.assertIn('pub const radius_bubble: i32 = design.bubble_radius;', source)
        self.assertIn('pub const selected_row_radius: i32 = design.row_radius;', source)
        self.assertIn('pub const radius_card: i32 = design.menu_radius;', source)

    def test_voice_play_glyph_uses_readable_dark_ink_on_the_light_control(self):
        source = (ROOT / 'src/main.zig').read_text()
        self.assertTrue('win.CreateSolidBrush(if (theme.choice == .amoled) theme.send_text else theme.current.on_primary)' in source)

    def test_native_probes_follow_the_shared_font_and_measured_row_size(self):
        border = (ROOT / 'tools/verify-wazig/composer-border.ps1').read_text()
        archive = (ROOT / 'tools/verify-wazig/archive-presentation.ps1').read_text()
        self.assertIn('pub const body_size:', border)
        self.assertIn('$bodySize * $scale * $dpi', border)
        self.assertIn('$height = [int]$rowHeight.ToUInt64()', archive)
        self.assertNotIn('64 * [VerifyWindow]', archive)
        passage = (ROOT / 'tools/verify-wazig/passage-copy.ps1').read_text()
        self.assertIn('[VerifyPassage]::TestGradientOracle()', passage)

    def test_native_font_proof_reads_the_waited_metrics_object(self):
        source = (ROOT / 'tools/verify-wazig/journey-sidebar-surface.ps1').read_text()
        self.assertIn('$metrics = Wait-Until {', source)
        self.assertIn('{ return $metrics }', source)
        self.assertIn("$metrics.icon_face -ceq 'Segoe Fluent Icons'", source)

    def test_native_controls_use_shared_font_and_icon_roles(self):
        source = (ROOT / 'src/main.zig').read_text()
        self.assertTrue('lit("Segoe Fluent Icons")' in source)
        self.assertTrue('scaledFontHeight(theme.type_body,' in source)
        self.assertTrue('scaledFontHeight(theme.type_title,' in source)
        self.assertTrue('px(a, theme.sidebar_width)' in source)
        config = (ROOT / 'src/font_config.zig').read_text()
        self.assertIn('rowGeometry(dpi, a.font_row_height, a.font_small_height, a.font_time_height)', source)
        self.assertIn('win.LB_SETITEMHEIGHT, 0, @intCast(a.chat_row_geometry.height)', source)
        self.assertIn('const row = a.chat_row_geometry;', source)
        self.assertIn('@max(name_height, time_height)', config)
        self.assertIn('@max(@divTrunc(24 * dpi + 48, 96), preview_height)', config)
        self.assertTrue('px(a, theme.bubble_max_width)' in source)
        self.assertNotIn('Theme: Green', source)
        self.assertNotIn('Theme: AMOLED black', source)


if __name__ == '__main__':
    unittest.main(verbosity=2)

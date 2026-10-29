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
        for field, value in {
            'surface': '101010', 'surface_container_low': '181818',
            'surface_container': '1f1f1f', 'surface_container_high': '262626',
            'surface_container_highest': '353535', 'on_surface': 'f2f2f2',
            'on_surface_variant': '8a8a8a', 'outline': '2e2e2e',
            'outline_variant': '2a2a2a', 'primary': '89b4f8',
            'primary_container': '414141', 'sidebar_surface': '181818',
            'sidebar_divider': '2a2a2a',
        }.items():
            with self.subTest(field=field):
                self.assertRegex(palette.lower(), rf'\.{field} = hex\(0x{value}\)')
        self.assertRegex(source, r'pub const radius_bubble: i32 = 20;')
        self.assertRegex(source, r'pub const selected_row_radius: i32 = 10;')
        self.assertIn('pub const radius_card: i32 = 16;', source)

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
        self.assertTrue('px(a, theme.chat_row_height)' in source)
        self.assertTrue('px(a, theme.bubble_max_width)' in source)
        self.assertNotIn('Theme: Green', source)
        self.assertNotIn('Theme: AMOLED black', source)


if __name__ == '__main__':
    unittest.main(verbosity=2)

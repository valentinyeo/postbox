import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ComposerPasteScroll(unittest.TestCase):
    def test_igsh_1775_composer_returns_to_top_when_everything_fits(self):
        source = (ROOT / 'src' / 'main.zig').read_text(encoding='utf-8')
        body = re.search(r'fn composeRevealTop\(a: \*App\) void \{(.*?)\n\}\n', source, re.S)
        self.assertIsNotNone(body)
        self.assertIn('info.total <= info.page', body.group(1))
        self.assertIn('setComposeTop(hwnd, 0)', body.group(1))
        layout = re.search(r'fn layoutComposer\(a: \*App\) void \{(.*?)\n\}\n', source, re.S).group(1)
        self.assertIn('composeRevealTop(a)', layout)
        region = re.search(r'fn layoutRegion\(.*?\n\}\n', source, re.S).group(0)
        self.assertIn('composeRevealTop(a)', region)
        self.assertIn('\\"first_line\\":{d}', source)

    def test_igsh_1775_journey_pastes_a_numbered_list_with_ctrl_v(self):
        journey = (ROOT / 'tools' / 'verify-wazig' / 'journey-drafts.ps1').read_text(encoding='utf-8')
        self.assertIn("Set-Clipboard -Value $numbered", journey)
        self.assertIn("Send-Keys $session '^v'", journey)
        self.assertIn('composer.first_line -eq 0', journey)
        self.assertIn('composer.lines -eq 6', journey)


if __name__ == '__main__':
    unittest.main()

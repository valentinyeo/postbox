import copy
import hashlib
from pathlib import Path
import re
import runpy
import unittest


ROOT = Path(__file__).resolve().parents[1]
check = runpy.run_path(str(ROOT / 'tools/verify-wazig/check-archive-presentation.py'))['check_fixture_palette']


class ArchivePaletteProofTests(unittest.TestCase):
    def setUp(self):
        self.theme = (ROOT / 'src/theme.zig').read_bytes().decode('utf-8')
        self.tokens = (ROOT / 'src/design_tokens.zig').read_bytes().decode('utf-8')
        original = re.search(r'pub const amoled: Palette = \.\{.*?\n\};', self.theme, re.S).group()
        resolved = []
        def invert(match):
            value = re.search(r'pub const ' + match[1] + r': u32 = 0x([0-9a-fA-F]{6});', self.tokens)[1]
            resolved.append(value.lower())
            return f'hex(0x{0xffffff - int(value, 16):06x})'
        self.palette = dict(kind='inverted AMOLED fixture palette', production_rendering=True,
                            original=original, light=re.sub(r'design\.(Reader\w+)', invert, original),
                            resolved_original=resolved, token_source=self.tokens, token_sha256=hashlib.sha256(self.tokens.encode()).hexdigest())

    def test_symbolic_source_and_inversion(self):
        check(self.palette, self.theme, self.tokens)
        for change in ('wrong token', 'missing token', 'bad inversion', 'bad hash'):
            with self.subTest(change=change):
                palette = copy.deepcopy(self.palette)
                theme, tokens = self.theme, self.tokens
                if change == 'wrong token':
                    palette['original'] = palette['original'].replace('design.ReaderBackground', 'design.ReaderCard', 1)
                elif change == 'missing token':
                    tokens = tokens.replace('pub const ReaderBackground:', 'pub const MissingBackground:')
                    palette['token_source'] = tokens
                    palette['token_sha256'] = hashlib.sha256(tokens.encode()).hexdigest()
                elif change == 'bad inversion':
                    palette['light'] = palette['light'].replace('hex(0x', 'hex(0x0', 1)
                else:
                    palette['token_sha256'] = '0' * 64
                with self.assertRaises(AssertionError):
                    check(palette, theme, tokens)


if __name__ == '__main__':
    unittest.main()

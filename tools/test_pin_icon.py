import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def section(source, name):
    match = re.search(r'fn ' + name + r'\([^\n]*\) [^{]+\{', source)
    assert match, 'IGSH-494 missing ' + name
    start = match.end()
    depth = 1
    for index in range(start, len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index]
    raise AssertionError('IGSH-494 unterminated ' + name)


def verify(source, smooth):
    assert not re.search(r'pin_glyph|0xDCCC|0xDCCD|0x1[Ff]4[Cc][CcDd]|📌|📍|\\u\{1[fF]4[cC][cCdD]\}', source), 'IGSH-494 old emoji pin drawing remains'
    helper = section(source, 'drawPinIcon')
    for name in ('pinned', 'unpinned'):
        assert 'pin_icon.' + name in helper, 'shared Fluent pin glyph missing ' + name
    assert 'if (unpin)' in helper
    assert 'drawFluentIcon(a, shapes.hdc,' in helper
    renderer = section(source, 'drawFluentIcon')
    for token in ('a.font_icon', 'text_draw.drawText', 'win.TRANSPARENT', 'win.SelectObject(hdc, previous_font)'):
        assert token in renderer, 'shared Fluent renderer missing ' + token
    assert not re.search(r'win\.(CreatePen|MoveToEx|LineTo|Polygon|Polyline)|smooth\.strokePolyline', helper)
    row = section(source, 'drawChat')
    pinned = row.split('if (pinned_chat) {', 1)[1].split('}', 1)[0]
    assert 'drawPinIcon(a, &shapes,' in pinned, 'IGSH-494 chat pin must call drawPinIcon'
    assert 'row_muted, false)' in pinned, 'IGSH-494 pin must follow themed row colours'
    assert len(re.findall(r'\bdrawPinIcon\(', source)) == 2, 'IGSH-494 update the pin-site inventory for every new drawing site'
    mic = section(source, 'drawMicIcon')
    assert 'drawFluentIcon(a, hdc,' in mic and '0xE720' in mic
    assert 'scaledFontHeight(theme.icon_size, 100, dpi)' in source
    assert 'src/pin_icon_test.zig' in (ROOT / 'build.zig').read_text()


class PinIconTest(unittest.TestCase):
    def test_00_shared_font_rejects_the_real_cd773f1_vector_renderer(self):
        source = (ROOT / 'src/main.zig').read_text()
        smooth = (ROOT / 'src/smooth_shapes.zig').read_text()
        start = source.index('fn drawPinIcon(')
        end = source.index('\nfn drawMicIcon(', start)
        old = (ROOT / 'tools/fixtures/pin-before-fluent.txt').read_text()
        with self.assertRaises(AssertionError):
            verify(source[:start] + old + source[end:], smooth)
        verify(source, smooth)
        print('PIN RED CONTROL VERIFIED: cd773f1 legacy vector rejected')

    def test_IGSH_494_every_pin_site_uses_the_shared_Fluent_font(self):
        verify((ROOT / 'src/main.zig').read_text(), (ROOT / 'src/smooth_shapes.zig').read_text())

    def test_IGSH_494_rejects_legacy_pin_emoji(self):
        source = (ROOT / 'src/main.zig').read_text()
        smooth = (ROOT / 'src/smooth_shapes.zig').read_text()
        for legacy in ('const pin_glyph = 0;', 'const legacy = "📌";', 'const legacy = 0xDCCC;'):
            with self.subTest(legacy=legacy), self.assertRaisesRegex(AssertionError, 'old emoji pin drawing remains'):
                verify(source + '\n' + legacy, smooth)

    def test_IGSH_494_rejects_bypassing_the_helper_and_shared_font(self):
        source = (ROOT / 'src/main.zig').read_text()
        smooth = (ROOT / 'src/smooth_shapes.zig').read_text()
        verify(source, smooth)
        for old, new in (('drawPinIcon(a, &shapes,', 'drawOldPin(a, &shapes,'), ('drawFluentIcon(a, shapes.hdc,', 'drawLegacyIcon(a, shapes.hdc,'), ('row_muted, false)', '0x000000, false)')):
            with self.subTest(bypass=new), self.assertRaises(AssertionError):
                verify(source.replace(old, new), smooth)


if __name__ == '__main__':
    unittest.main()

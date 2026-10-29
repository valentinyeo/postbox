from pathlib import Path
import os
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '1db70d8ca4c22e27226d7771ebb12192bfa4d4b6'


def section(source, name):
    marker = f'fn {name}('
    assert marker in source, f'ISSUE-533 missing {name}'
    start = source.index(marker)
    return source[start:source.index('\n}\n', start) + 3]


def read_source():
    revision = os.environ.get('REACTION_LAYOUT_REVISION')
    if revision:
        return subprocess.check_output(['git', 'show', f'{revision}:src/main.zig'], cwd=ROOT, text=True)
    return (ROOT / 'src/main.zig').read_text()


def verify(source):
    size = section(source, 'reactionChipSize')
    measure = section(source, 'measureMessage')
    paint = section(source, 'drawCanvas')
    for token in (
        'if (message.reaction.len == 0) return .{ .cx = 0, .cy = 0 };',
        'mixedSliceWidth(hdc, font, a.font_emoji orelse font, textLineHeight(hdc, font), fontAscent(hdc, font), message.reaction.slice())',
        'width - px(a, 36)',
        'text_width, false, 0, 0, null)',
        '.cx = text_width + px(a, 12), .cy = text_height + px(a, 8)',
    ):
        assert token in size, f'ISSUE-533 chip measurement missing {token}'
    assert 'return @max(height, min_height) + @max(0, reactionChipSize(hdc, a, message, width).cy - px(a, 4));' in measure, 'ISSUE-533 row must reserve the chip overhang after the minimum bubble height'
    for token in (
        'const reaction_size = reactionChipSize(hdc, a, message, width);',
        'const bubble_height = height - sender_height - @max(0, reaction_size.cy - px(a, 4));',
        '.bottom = bubble_top + bubble_height };',
        'const chip_left = if (message.from_me) right - px(a, 12) - reaction_size.cx else left + px(a, 12);',
        'const chip_top = message.bubble_hit.bottom - px(a, 4);',
        '.bottom = chip_top + reaction_size.cy',
        'smooth.fillRoundRect(&shapes, chip,',
        'reaction_size.cx - px(a, 12), true, chip.left + px(a, 6), chip.top + px(a, 4), null)',
        'total_height += measureMessageCached(',
        'cursor_y = y - messageGap(a, index);',
    ):
        assert token in paint, f'ISSUE-533 chip painting or row placement missing {token}'
    assert 'y + height - timeBandHeight(hdc, a)' not in paint, 'ISSUE-533 reaction is back inside the message text'
    assert 'message.reaction.len' in section(source, 'measureTag'), 'ISSUE-533 adding or removing reactions must invalidate the row cache'


class ReactionLayoutTests(unittest.TestCase):
    def test_ISSUE_533_reaction_chip_has_its_own_measured_space(self):
        verify(read_source())

    def test_ISSUE_533_rejects_original_overlap(self):
        original = subprocess.check_output(['git', 'show', f'{BASELINE}:src/main.zig'], cwd=ROOT, text=True)
        with self.assertRaisesRegex(AssertionError, 'ISSUE-533 missing reactionChipSize'):
            verify(original)

    def test_ISSUE_533_rejects_broken_row_chip_and_timestamp_bounds(self):
        source = read_source()
        verify(source)
        for old, new in (
            ('return @max(height, min_height) + @max(0, reactionChipSize(hdc, a, message, width).cy - px(a, 4));', 'return @max(height, min_height);'),
            ('message.bubble_hit.bottom - px(a, 4)', 'y + px(a, 6)'),
            ('const bubble_height = height - sender_height - @max(0, reaction_size.cy - px(a, 4));', 'const bubble_height = height;'),
            ('chip.top + px(a, 4), null)', 'y + px(a, 6), null)'),
            ('.bottom = bubble_top + bubble_height };', '.bottom = bubble_top + height };'),
        ):
            with self.subTest(issue='ISSUE-533', mutation=new):
                self.assertIn(old, source)
                with self.assertRaisesRegex(AssertionError, 'ISSUE-533'):
                    verify(source.replace(old, new))

    def test_ISSUE_533_chip_fits_row_at_100_and_150_percent(self):
        source = read_source()
        verify(source)
        size = section(source, 'reactionChipSize')
        padding = int(re.search(r'\.cy = text_height \+ px\(a, (\d+)\)', size).group(1))
        paint = section(source, 'drawCanvas')
        overlap = int(re.search(r'const chip_top = message.bubble_hit.bottom - px\(a, (\d+)\)', paint).group(1))
        inset = int(re.search(r'chip.top \+ px\(a, (\d+)\), null\)', paint).group(1))
        self.assertIn('return @divTrunc(v * dpi + 48, 96);', section(source, 'px'))
        for dpi in (96, 144):
            def px(value):
                return (value * dpi + 48) // 96
            for bubble_height in (px(24), px(48), px(300)):
                for reaction_height in (px(20), px(40), px(80)):
                    with self.subTest(issue='ISSUE-533', dpi=dpi, bubble=bubble_height, reaction=reaction_height):
                        chip_height = reaction_height + px(padding)
                        row_height = bubble_height + max(0, chip_height - px(overlap))
                        chip_top = bubble_height - px(overlap)
                        reaction_top = chip_top + px(inset)
                        self.assertGreaterEqual(reaction_top, bubble_height)
                        self.assertLessEqual(reaction_top + reaction_height, chip_top + chip_height)
                        self.assertEqual(chip_top + chip_height, row_height)
                self.assertEqual(bubble_height + max(0, 0 - px(overlap)), bubble_height)


if __name__ == '__main__':
    unittest.main(verbosity=2)

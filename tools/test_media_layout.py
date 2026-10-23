from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def section(source, name):
    start = source.index(f'fn {name}(')
    return source[start:source.index('\n}\n', start) + 3]


def verify_column(source):
    width = section(source, 'messageBubbleWidth')
    for token in (
        'a.displayed_jid.slice()',
        'a.chats[a.selected_chat].jid.slice()',
        'std.mem.endsWith(u8, chat_jid, "@g.us")',
        'const max_width = @max(1, available_width - left_inset - px(a, 24));',
        'return @min(max_width, std.math.clamp(@divTrunc(available_width * 7, 10), px(a, 280), px(a, 620)));',
    ):
        assert token in width, f'IGSH-714 message column missing {token}'
    assert 'bitmap' not in width, 'IGSH-714 bitmap dimensions must not choose the message column'
    paint = section(source, 'drawCanvas')
    scroll = section(source, 'scrollToSelectedMessage')
    measure = section(source, 'measureMessage')
    for token in (
        'const bubble_width = messageBubbleWidth(a, available_width);',
        'const right = left + bubble_width;',
        'media_layout.fit(message.bitmap_width, message.bitmap_height, bubble_width - px(a, 24), px(a, 250))',
        '.right = image_left + display.width, .bottom = image_top + display.height',
        'text_top += display.height + px(a, 8);',
    ):
        assert token in paint, f'IGSH-714 painting missing {token}'
    assert 'const bubble_width = messageBubbleWidth(a, client.right - client.left);' in scroll, 'IGSH-714 scrolling must use the same column'
    assert 'media_layout.fit(message.bitmap_width, message.bitmap_height, text_width, px(a, 250))' in measure, 'IGSH-714 measurement must fit the same content width'
    return width


class MediaLayoutTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'src/main.zig').read_text()

    def test_IGSH_714_column_and_media_use_canvas_bounds(self):
        width = verify_column(self.source)
        group_inset, direct_inset = map(int, re.search(r'@as\(i32, (\d+)\) else @as\(i32, (\d+)\)', width).groups())
        right_inset = int(re.search(r'available_width - left_inset - px\(a, (\d+)\)', width).group(1))
        numerator, denominator, minimum, maximum = map(int, re.search(r'available_width \* (\d+), (\d+)\), px\(a, (\d+)\), px\(a, (\d+)\)', width).groups())
        for dpi in (96, 144, 192):
            def px(value):
                return (value * dpi + 48) // 96
            for available in (px(317), px(682), px(1200)):
                for inset in (group_inset, direct_inset):
                    preferred = min(px(maximum), max(px(minimum), available * numerator // denominator))
                    bubble = min(max(1, available - px(inset) - px(right_inset)), preferred)
                    incoming_left = px(inset)
                    own_left = available - bubble - px(right_inset)
                    with self.subTest(dpi=dpi, available=available, inset=inset):
                        self.assertGreater(bubble - px(24), 0)
                        self.assertGreaterEqual(own_left, 0)
                        self.assertLessEqual(incoming_left + bubble, available - px(right_inset))
                        self.assertLessEqual(own_left + bubble, available)
                        if preferred <= available - px(inset) - px(right_inset):
                            self.assertEqual(bubble, preferred)

    def test_IGSH_714_rejects_uncapped_or_inconsistent_columns(self):
        verify_column(self.source)
        for old, new in (
            ('return @min(max_width, std.math.clamp(', 'return @max(max_width, std.math.clamp('),
            ('const bubble_width = messageBubbleWidth(a, available_width);', 'const bubble_width = message.bitmap_width;'),
            ('const bubble_width = messageBubbleWidth(a, client.right - client.left);', 'const bubble_width = 280;'),
            ('bubble_width - px(a, 24), px(a, 250))', 'message.bitmap_width, px(a, 250))'),
            ('.right = image_left + display.width, .bottom = image_top + display.height', '.right = image_left + message.bitmap_width, .bottom = image_top + message.bitmap_height'),
        ):
            with self.subTest(mutation=new):
                self.assertIn(old, self.source)
                with self.assertRaisesRegex(AssertionError, 'IGSH-714'):
                    verify_column(self.source.replace(old, new))

    def test_IGSH_714_measurement_and_paint_use_the_same_time_box(self):
        rect = section(self.source, 'messageTimeRect')
        paint = section(self.source, 'drawCanvas')
        for edge in ('left', 'right', 'bottom'):
            pattern = rf'\.{edge} = [^,}}]*? - px\(a, (\d+)\)'
            self.assertEqual(re.search(pattern, rect).group(1), re.search(pattern, paint[paint.rindex('var time_rect ='):]).group(1))
        self.assertIn('media_layout.needsTimeLine(last_line_right, time_width_with_gap, text_width)', section(self.source, 'measureMessage'))

    def test_IGSH_714_wrapper_retains_signature_and_shares_the_core_loop(self):
        wrapper = section(self.source, 'wrapMixedSink')
        self.assertIn('top: i32, sink: ?*const Message) i32 {', wrapper)
        self.assertIn('return wrapMixedSinkExtent(hdc, a, text_ptr, len, max_width, draw, left, top, sink, null);', wrapper)
        core = section(self.source, 'wrapMixedSinkExtent')
        self.assertIn('if (last_line_right) |extent| extent.* = last_right - left;', core)
        measure = section(self.source, 'measureMessage')
        self.assertIn('text_width, false, 0, 0, message, &last_line_right)', measure)
        self.assertIn('media_layout.needsTimeLine(last_line_right, time_width_with_gap, text_width)', measure)


if __name__ == '__main__':
    unittest.main(verbosity=2)

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
        'const max_width = @max(1, column_width - left_inset - px(a, 24));',
        'return @min(max_width, std.math.clamp(@divTrunc(column_width * 7, 10), px(a, 280), px(a, theme.bubble_max_width)));',
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


def verify_resize(source):
    for token in (
        '$app = Get-App $Session',
        '$window = $app.MainWindowHandle',
        '[VerifyWindow]::ShowWindow($window, 9)',
        '$attempt -lt 8;',
        'if ($canvasWidth -eq 320) { break }',
        '[VerifyVoice]::Bounds($Session.pid, $window)',
        '$requestedWidth = $width + 320 - $canvasWidth',
        '[VerifyWindow]::SetWindowPos($window, [IntPtr]::Zero, 0, 0, $requestedWidth, $height, 6)',
        '$canvasWidth -ge 300 -and $canvasWidth -le 340',
        "'media-fit-resize.json'",
        'window_before = $width; canvas_before = $canvasWidth; requested_window = $requestedWidth',
    ):
        assert token in source, f'IGSH-714 measured resize missing {token}'
    assert 'Send-Keys' not in source, 'IGSH-714 resize must not depend on system-menu keys'


class MediaFitResizeTests(unittest.TestCase):
    def setUp(self):
        self.journey = (ROOT / 'tools/verify-wazig/media-fit.ps1').read_text()

    def test_IGSH_714_owned_native_resize_retains_narrow_assertions(self):
        verify_resize(self.journey)
        self.assertIn("foreach ($size in @('wide', 'narrow'))", self.journey)
        self.assertIn('$wide.bubble[2] - $wide.bubble[0] -gt $narrow.bubble[2] - $narrow.bubble[0]', self.journey)
        self.assertIn('$narrow.bubble[2] - $narrow.bubble[0] - $padding -lt $wide.media[2] - $wide.media[0]', self.journey)
        validator = (ROOT / 'tools/verify-wazig/check-media-fit-evidence.py').read_text()
        for token in (
            "resize = read('media-fit-resize.json')",
            "resize['target'] == 320 and 300 <= resize['canvas'] <= 340",
            "row['canvas'][2] == resize['canvas']",
            "step['requested_window'] == step['window_before'] + resize['target'] - step['canvas_before']",
            "resize['steps'][-1]['canvas_after'] == resize['canvas']",
        ):
            self.assertIn(token, validator)

    def test_IGSH_714_corrections_converge_with_real_sidebar_clamps_and_borders(self):
        verify_resize(self.journey)
        source = (ROOT / 'src/main.zig').read_text()
        layout = section(source, 'layoutRegion')
        self.assertIn('const left_width = @min(px(a, theme.sidebar_width), @max(0, width - px(a, 280)));', layout)
        minimum = 280
        maximum = int(re.search(r'pub const sidebar_width: i32 = (\d+);', (ROOT / 'src/theme.zig').read_text()).group(1))
        self.assertIn('const chat_width = width - left_width - 1;', layout)
        self.assertIn('chat_width - panel_width', layout)
        target = int(re.search(r'\$requestedWidth = \$width \+ (\d+) - \$canvasWidth', self.journey).group(1))
        attempts = int(re.search(r'\$attempt -lt (\d+)', self.journey).group(1))
        for dpi in (96, 120, 144, 192):
            px = lambda n: (n * dpi + 48) // 96
            for border in (0, px(16), px(32)):
                def canvas(outer):
                    client = outer - border
                    sidebar = min(px(maximum), max(0, client - px(minimum)))
                    return client - sidebar - 1
                for initial in (border + px(minimum) + 182, 604, 1024, 1160, 3840):
                    width = initial
                    for attempt in range(attempts):
                        current = canvas(width)
                        if current == target:
                            break
                        width += target - current
                    with self.subTest(dpi=dpi, border=border, initial=initial):
                        self.assertEqual(canvas(width), target)
                        self.assertTrue(300 <= canvas(width) <= 340)
        self.assertEqual(478 - 16 - 280 - 1, 181)

    def test_IGSH_714_old_resize_and_weakened_band_are_rejected(self):
        verify_resize(self.journey)
        for old, new in (
            ('$requestedWidth = $width + 320 - $canvasWidth', '$requestedWidth = 600'),
            ('$canvasWidth -ge 300 -and $canvasWidth -le 340', '$canvasWidth -ge 180 -and $canvasWidth -le 340'),
            ('[VerifyWindow]::SetWindowPos', '[VerifyWindow]::ShowWindow'),
            ('$attempt -lt 8;', '$attempt -lt 80'),
        ):
            with self.subTest(mutation=new), self.assertRaisesRegex(AssertionError, 'IGSH-714'):
                verify_resize(self.journey.replace(old, new))
        with self.assertRaisesRegex(AssertionError, 'IGSH-714'):
            verify_resize(self.journey + "\nSend-Keys $Session '{RIGHT}{LEFT 4}{ENTER}'\n")


class MediaLayoutTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'src/main.zig').read_text()

    def test_IGSH_714_column_and_media_use_canvas_bounds(self):
        width = verify_column(self.source)
        group_inset, direct_inset = map(int, re.search(r'@as\(i32, (\d+)\) else @as\(i32, (\d+)\)', width).groups())
        right_inset = int(re.search(r'column_width - left_inset - px\(a, (\d+)\)', width).group(1))
        numerator, denominator, minimum = map(int, re.search(r'column_width \* (\d+), (\d+)\), px\(a, (\d+)\)', width).groups())
        tokens = (ROOT / 'src/theme.zig').read_text()
        maximum = int(re.search(r'pub const bubble_max_width: i32 = (\d+);', tokens).group(1))
        column_limit = int(re.search(r'pub const chat_column_width: i32 = (\d+);', tokens).group(1))
        for dpi in (96, 144, 192):
            def px(value):
                return (value * dpi + 48) // 96
            for available in (px(317), px(682), px(1200)):
                for inset in (group_inset, direct_inset):
                    column = min(available, px(column_limit))
                    inset_center = max(0, (available - column) // 2)
                    preferred = min(px(maximum), max(px(minimum), column * numerator // denominator))
                    bubble = min(max(1, column - px(inset) - px(right_inset)), preferred)
                    incoming_left = inset_center + px(inset)
                    own_left = inset_center + column - bubble - px(right_inset)
                    with self.subTest(dpi=dpi, available=available, inset=inset):
                        self.assertGreater(bubble - px(24), 0)
                        self.assertGreaterEqual(own_left, 0)
                        self.assertLessEqual(incoming_left + bubble, available - px(right_inset))
                        self.assertLessEqual(own_left + bubble, available)
                        if preferred <= column - px(inset) - px(right_inset):
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
        self.assertIn('if (last_line_right) |extent| extent.* = list_layout.last_right;', core)
        measure = section(self.source, 'measureMessage')
        self.assertIn('text_width, false, 0, 0, message, &last_line_right)', measure)
        self.assertIn('media_layout.needsTimeLine(last_line_right, time_width_with_gap, text_width)', measure)


if __name__ == '__main__':
    unittest.main(verbosity=2)

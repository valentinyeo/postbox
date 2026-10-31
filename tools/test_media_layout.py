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
        'const gutter = if (groupChat(a)) px(a, 42) else @as(i32, 0);',
        'return @max(1, @min(px(a, theme.bubble_max_width), @min(available_width - px(a, 48), chatColumn(a, available_width).right - chatColumn(a, available_width).left - gutter)));',
    ):
        assert token in width, f'IGSH-714 message column missing {token}'
    column = section(source, 'chatColumn')
    assert 'compose_layout.messageColumn(available_width' in column
    helper = (ROOT / 'src/compose_layout.zig').read_text()
    helper = helper[helper.index('pub fn messageColumn('):]
    helper = helper[:helper.index('\n}\n') + 3]
    assert 'max(0, @divTrunc(pane_width - scale(@import("theme.zig").chat_column_width, dpi), 2))' in helper
    assert 'scale(column_margin, dpi)' in helper
    assert 'bitmap' not in width, 'IGSH-714 bitmap dimensions must not choose the message column'
    paint = section(source, 'drawCanvas')
    scroll = section(source, 'scrollToSelectedMessage')
    measure = section(source, 'measureMessage')
    for token in (
        'const bubble_width = messageBubbleWidth(a, available_width);',
        'const right = left + width;',
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
        '$requestedWidth = $width + $gain * (320 - $canvasWidth)',
        '[VerifyWindow]::SetWindowPos($window, [IntPtr]::Zero, 0, 0, $requestedWidth, $height, 6)',
        '$canvasWidth -ge 300 -and $canvasWidth -le 340',
        "'media-fit-resize.json'",
        'window_before = $width; canvas_before = $canvasWidth; gain = $gain; requested_window = $requestedWidth',
        '$gain = if ($canvasWidth -lt $sidebarLimit) { 2 } else { 1 }',
        '$sidebarLimit = [int][Math]::Floor((300 * $dpi + 48) / 96)',
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
            "step['requested_window'] == step['window_before'] + step['gain'] * (resize['target'] - step['canvas_before'])",
            "resize['steps'][-1]['canvas_after'] == resize['canvas']",
        ):
            self.assertIn(token, validator)

    def test_IGSH_714_corrections_converge_with_real_sidebar_clamps_and_borders(self):
        verify_resize(self.journey)
        source = (ROOT / 'src/main.zig').read_text()
        layout = section(source, 'layoutRegion')
        self.assertIn('const left_width = @min(px(a, theme.sidebar_width), @divTrunc(width, 2));', layout)
        minimum = 280
        maximum = int(re.search(r'pub const sidebar_width: i32 = (\d+);', (ROOT / 'src/theme.zig').read_text()).group(1))
        self.assertIn('const chat_width = width - left_width - 1;', layout)
        self.assertIn('chat_width - panel_width', layout)
        target = int(re.search(r'\$requestedWidth = \$width \+ \$gain \* \((\d+) - \$canvasWidth\)', self.journey).group(1))
        attempts = int(re.search(r'\$attempt -lt (\d+)', self.journey).group(1))
        for dpi in (96, 120, 144, 192):
            px = lambda n: (n * dpi + 48) // 96
            for border in (0, px(16), px(32)):
                def canvas(outer):
                    client = outer - border
                    sidebar = min(px(maximum), client // 2)
                    return client - sidebar - 1
                for initial in (border + px(minimum) + 182, 604, 1024, 1160, 3840):
                    width = initial
                    for attempt in range(attempts):
                        current = canvas(width)
                        if current == target:
                            break
                        gain = 2 if current < px(maximum) else 1
                        width += gain * (target - current)
                    with self.subTest(dpi=dpi, border=border, initial=initial):
                        self.assertEqual(canvas(width), target)
                        self.assertTrue(300 <= canvas(width) <= 340)
        self.assertEqual(478 - 16 - 280 - 1, 181)

    def test_IGSH_714_old_resize_and_weakened_band_are_rejected(self):
        verify_resize(self.journey)
        for old, new in (
            ('$requestedWidth = $width + $gain * (320 - $canvasWidth)', '$requestedWidth = 600'),
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
        self.assertIn('pub const bubble_max_width: i32 = @divTrunc(design.column_width * 6, 10);', (ROOT / 'src/theme.zig').read_text())
        column_width = int(re.search(r'pub const column_width: i32 = (\d+);', (ROOT / 'src/design_tokens.zig').read_text()).group(1))
        maximum = column_width * 6 // 10
        inset = int(re.search(r'available_width - px\(a, (\d+)\)', width).group(1))
        margin = int(re.search(r'pub const column_margin: i32 = (\d+);', (ROOT / 'src/compose_layout.zig').read_text()).group(1))
        for dpi in (96, 144, 192):
            px = lambda value: (value * dpi + 48) // 96
            for available in (px(317), px(682), px(1200), px(1600), px(2560)):
                outer = max(0, (available - px(column_width)) // 2)
                incoming_left = outer + min(px(margin), available // 2)
                incoming_right = max(incoming_left, available - outer - min(px(margin), available // 2))
                column = incoming_right - incoming_left
                bubble = max(1, min(px(maximum), available - px(inset), column))
                own_left = incoming_right - bubble
                with self.subTest(dpi=dpi, available=available):
                    self.assertGreater(bubble - px(28), 0)
                    self.assertGreaterEqual(own_left, incoming_left)
                    self.assertLessEqual(incoming_left + bubble, incoming_right)
                    self.assertLessEqual(own_left + bubble, available)

    def test_IGSH_714_rejects_uncapped_or_inconsistent_columns(self):
        verify_column(self.source)
        for old, new in (
            ('return @max(1, @min(px(a, theme.bubble_max_width),', 'return @max(1, @max(px(a, theme.bubble_max_width),'),
            ('const bubble_width = messageBubbleWidth(a, available_width);', 'const bubble_width = message.bitmap_width;'),
            ('const bubble_width = messageBubbleWidth(a, client.right - client.left);', 'const bubble_width = 280;'),
            ('bubble_width - px(a, 24), px(a, 250))', 'message.bitmap_width, px(a, 250))'),
            ('.right = image_left + display.width, .bottom = image_top + display.height', '.right = image_left + message.bitmap_width, .bottom = image_top + message.bitmap_height'),
        ):
            with self.subTest(mutation=new):
                self.assertIn(old, self.source)
                with self.assertRaisesRegex(AssertionError, 'IGSH-714'):
                    verify_column(self.source.replace(old, new))

    def test_IGSH_1120_sender_time_stays_outside_the_bubble(self):
        paint = section(self.source, 'drawCanvas')
        self.assertIn('const bubble_top = y + sender_height;', paint)
        self.assertIn('.top = y + px(a, 1)', paint)
        self.assertIn('.bottom = sender_rect.bottom', paint)
        self.assertNotIn('messageTimeRect', section(self.source, 'measureMessage'))
        self.assertNotIn('time_width_with_gap', section(self.source, 'measureMessage'))

    def test_IGSH_714_wrapper_retains_signature_and_shares_the_core_loop(self):
        wrapper = section(self.source, 'wrapMixedSink')
        self.assertIn('top: i32, sink: ?*const Message) i32 {', wrapper)
        self.assertIn('return wrapMixedSinkExtent(hdc, a, text_ptr, len, max_width, draw, left, top, sink, null);', wrapper)
        core = section(self.source, 'wrapMixedSinkExtent')
        self.assertIn('if (last_line_right) |extent| extent.* = list_layout.last_right;', core)
        measure = section(self.source, 'measureMessage')
        self.assertIn('text_width, false, 0, 0, message)', measure)
        self.assertIn('return formattedMessage(hdc, a, message, max_width, draw, left, top, last_line_right);', core)


if __name__ == '__main__':
    unittest.main(verbosity=2)

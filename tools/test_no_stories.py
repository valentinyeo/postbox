from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
UI = re.compile(r'\b(?:command_status|id_status_row|status_row(?:_height)?|status_ui|status_actions|openStatuses|closeStatuses|openStatusContact|replyToStatus|stepStatus|statusBack)\b|"(?:Status|Stories|Recent updates|Viewed updates|open-status|statuses)"')
TRANSPORT = re.compile(r'\b(?:statuses|status_seen|status_view|status_list|status_viewed|status_seen_retries|status_refresh_requested|status_last_refresh_ms|status_gen|refreshStatuses|applyStatuses|enqueueStatusSeen|applyStatusSeen|autoDownloadStatus|showStatusMedia|persistStatusViewed|markStatusViewed)\b|status@broadcast|status-viewed\.txt|"status"\s*,\s*"(?:list|seen)"')


def reject(source, pattern):
    match = pattern.search(source)
    if match:
        raise AssertionError(f'IGSH-538 removed stories integration: {match.group()}')


class NoStoriesTests(unittest.TestCase):
    def test_IGSH_538_no_status_entry_point_or_view(self):
        for path in (ROOT / 'src').glob('*.zig'):
            if path.name.endswith('_test.zig'):
                continue
            with self.subTest(ticket='IGSH-538', source=path.name):
                source = re.sub(r'(?ms)^test "[^\n]*\n.*?^}\n', '', path.read_text())
                reject(source, UI)
        self.assertFalse((ROOT / 'src/status_ui.zig').exists())
        self.assertFalse((ROOT / 'src/status_view.zig').exists())
        self.assertNotIn('src/status_view.zig', (ROOT / 'build.zig').read_text())

    def test_IGSH_538_no_status_fetch_poll_receipt_media_or_cache(self):
        for path in (ROOT / 'src').glob('*.zig'):
            if path.name.endswith('_test.zig'):
                continue
            with self.subTest(ticket='IGSH-538', source=path.name):
                reject(re.sub(r'(?ms)^test "[^\n]*\n.*?^}\n', '', path.read_text()), TRANSPORT)

    def test_IGSH_538_guards_reject_reintroduced_entry_points_and_fetches(self):
        for token in ('command_status', 'id_status_row', 'status_ui.paint(a)', '"Status"', '"open-status"', '"statuses"'):
            with self.subTest(ticket='IGSH-538', entry=token):
                with self.assertRaisesRegex(AssertionError, 'IGSH-538'):
                    reject(token, UI)
        for token in ('refreshStatuses(a, false)', 'statuses', 'status_seen', 'status_view', 'status@broadcast', '"status", "list"', '"status", "seen"', 'status-viewed.txt'):
            with self.subTest(ticket='IGSH-538', request=token):
                with self.assertRaisesRegex(AssertionError, 'IGSH-538'):
                    reject(token, TRANSPORT)

    def test_IGSH_538_both_themes_share_gap_free_sidebar_layout(self):
        main = (ROOT / 'src/main.zig').read_text()
        start = main.index('fn layout(')
        wrapper = main[start:main.index('\nfn ', start + 1)]
        self.assertIn('layoutRegion(a, width, height, null)', wrapper)
        start = main.index('fn layoutRegion(')
        layout = main[start:main.index('\nfn ', start + 1)]
        self.assertNotIn('search_height', layout)
        self.assertIn('win.MoveWindow(hwnd, 0, header_height, left_width - scrollbar_width, list_bottom - header_height, win.TRUE)', layout)
        self.assertNotIn('theme.choice', layout)
        self.assertNotIn('activeChatView', layout)
        self.assertNotIn('win.SW_HIDE', layout)
        self.assertNotIn('status_height', layout)
        self.assertIn('const list_bottom = if (updateCardVisible(a)) updateCardRect(a).top - px(a, 4) else height;', layout)


if __name__ == '__main__':
    unittest.main(verbosity=2)

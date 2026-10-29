from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import hashlib
import importlib.util
import json
import runpy
from pathlib import Path
import tempfile
import threading
from urllib.parse import quote, urlencode
import unittest


ROOT = Path(__file__).resolve().parents[1]


class FakeWaBridgeArchiveTests(unittest.TestCase):
    fixture = 'fake-wa-bridge.py'
    prefix = '/v1'

    def setUp(self):
        spec = importlib.util.spec_from_file_location('archive_bridge_fixture', ROOT / 'tools/verify-wazig' / self.fixture)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        bridge = getattr(module, 'bridge', module)
        self.alpha = module.ALPHA
        self.beta = module.BETA
        self.jids = [f'{bridge.ACCOUNT}:{chat}' if module is bridge else chat for chat in [self.alpha, self.beta]]
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        server = ThreadingHTTPServer(('127.0.0.1', 0), module.Handler)
        server.daemon_threads = True
        server.state = bridge.State(Path(self.temp.name) / 'requests.jsonl')
        self.addCleanup(server.server_close)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        self.connection = HTTPConnection('127.0.0.1', server.server_port, timeout=5)
        self.addCleanup(self.connection.close)
        self.headers = {'Authorization': f'Bearer {bridge.KEY}', 'Content-Type': 'application/json', 'Connection': 'close'}
        self.account = bridge.ACCOUNT if module is bridge else None

    def request(self, method, path, body=None):
        self.connection.request(method, self.prefix + path, body=None if body is None else json.dumps(body), headers=self.headers)
        response = self.connection.getresponse()
        data = json.loads(response.read())
        self.connection.close()
        self.assertEqual(response.status, 200, data)
        return data

    def archive(self, chat, archived):
        body = dict(chat=chat, archived=archived)
        if self.account is not None:
            body['account'] = self.account
        self.assertEqual(self.request('POST', '/archive', body), {'status': 'ok'})

    def assert_views(self, archived_jids):
        for archived in [False, True]:
            with self.subTest(archived=archived):
                rows = self.request('GET', '/chats?archived=' + str(archived).lower())
                expected = [jid for jid in self.jids if (jid in archived_jids) == archived]
                self.assertEqual([row['jid'] for row in rows], expected)
                for row in rows:
                    self.assertIs(row['archived'], archived)
                    alpha = row['jid'] == self.jids[0]
                    self.assertEqual(row['name'], 'Verification Alpha' if alpha else 'Verification Beta')
                    self.assertEqual(row['kind'], 'direct')
                    self.assertEqual(row['unread_count'], 2 if alpha else 0)
                    if self.account is None:
                        self.assertEqual(row['provider'], 'slack' if alpha else 'whatsapp')

    def assert_archive_cycle(self, chat, jid):
        self.assert_views([])
        self.archive(chat, True)
        self.assert_views([jid])
        self.archive(chat, False)
        self.assert_views([])

    def test_batch_archive_reports_failure_and_still_updates_later_chat(self):
        body = dict(account=self.account or '', chats=[dict(chat='unknown'), dict(chat=self.beta)], archived=True)
        reply = self.request('POST', '/archive-batch', body)
        self.assertEqual([row['chat'] for row in reply['results']], ['unknown', self.beta])
        self.assertEqual([row['ok'] for row in reply['results']], [False, True])
        self.assertTrue(reply['results'][0]['error'])
        self.assert_views([self.jids[1]])
        body.update(chats=[dict(chat=self.beta)], archived=False)
        self.assertEqual(self.request('POST', '/archive-batch', body)['results'], [dict(chat=self.beta, ok=True)])
        self.assert_views([])

    def test_archive_beta_keeps_alpha_and_unarchive_restores_beta(self):
        self.assert_archive_cycle(self.beta, self.jids[1])

    def test_archive_alpha_keeps_beta_and_unarchive_restores_alpha(self):
        self.assert_archive_cycle(self.alpha, self.jids[0])

    def test_unarchive_one_chat_preserves_the_other_archive(self):
        self.archive(self.alpha, True)
        self.archive(self.beta, True)
        self.assert_views(self.jids)
        self.archive(self.alpha, False)
        self.assert_views([self.jids[1]])
        self.archive(self.beta, False)
        self.assert_views([])


class FakeUnifiedHubArchiveTests(FakeWaBridgeArchiveTests):
    fixture = 'fake-hub.py'
    prefix = '/v1/wazig'


class FakeHubArchiveGroupTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('hub_archive_fixture', ROOT / 'tools/verify-wazig/fake-hub.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.group = module.ARCHIVE_GROUP
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        server = ThreadingHTTPServer(('127.0.0.1', 0), module.HubArchiveHandler)
        server.daemon_threads = True
        server.state = module.bridge.State(Path(self.temp.name) / 'requests.jsonl')
        server.state.archive_incoming = 0
        server.state.plain_dms = {}
        server.state.archive_stamp = '2026-10-10T11:00:00Z'
        self.module = module
        self.addCleanup(server.server_close)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        self.port = server.server_port
        self.headers = {'Authorization': f'Bearer {module.bridge.KEY}', 'Content-Type': 'application/json', 'Connection': 'close'}

    def request(self, method, path, body=None, status=200):
        connection = HTTPConnection('127.0.0.1', self.port, timeout=5)
        self.addCleanup(connection.close)
        connection.request(method, path, body=None if body is None else json.dumps(body), headers=self.headers)
        response = connection.getresponse()
        data = json.loads(response.read())
        self.assertEqual(response.status, status, data)
        return data

    def jids(self, archived):
        return [row['jid'] for row in self.request('GET', '/v1/wazig/chats?archived=' + archived)]

    def test_archive_live_stream_delivers_a_frame_without_waiting_for_eof(self):
        connection = HTTPConnection('127.0.0.1', self.port, timeout=2)
        self.addCleanup(connection.close)
        connection.request('GET', '/v1/wazig/events', headers=self.headers)
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        self.assertEqual(response.getheader('Transfer-Encoding'), 'chunked')
        self.assertEqual(response.read(6), b'id: 1\n')
        connection.close()

    def test_business_notification_fixture_keeps_archive_until_client_acknowledges(self):
        self.request('POST', '/fixture/notification-baseline', {})
        archived = 'business:notification-archived@s.whatsapp.net'
        self.assertIn(archived, self.jids('true'))
        self.request('POST', '/fixture/notification-archived', {})
        self.assertIn(archived, self.jids('true'))
        messages = self.request('GET', '/v1/wazig/messages?chat=' + quote(archived))
        self.assertEqual(messages[0]['MsgID'], 'NOTIFY-archived')
        self.assertFalse(messages[0]['FromMe'])
        self.request('POST', '/v1/wazig/archive', dict(chat=archived, archived=False))
        self.assertNotIn(archived, self.jids('true'))
        self.assertIn(archived, self.jids('false'))
        self.request('POST', '/fixture/notification-inbox', {})
        messages = self.request('GET', '/v1/wazig/messages?chat=business:notification-inbox@s.whatsapp.net')
        self.assertEqual(messages[0]['MsgID'], 'NOTIFY-inbox')
        self.request('POST', '/fixture/notification-clear', {})
        self.assertNotIn(archived, self.jids('false'))

    def test_group_stays_in_inbox_for_the_hub_and_only_moves_its_row_time_on_incoming(self):
        self.assertIn(self.group, self.jids('false'))
        self.assertNotIn(self.group, self.jids('true'))
        before = {row['jid']: row['last_message_ts'] for row in self.request('GET', '/v1/wazig/chats?archived=false')}
        self.request('POST', '/fixture/archive-incoming', {})
        after = {row['jid']: row['last_message_ts'] for row in self.request('GET', '/v1/wazig/chats?archived=false')}
        self.assertIn(self.group, after)
        self.assertGreater(after[self.group], before[self.group])
        self.assertNotIn(self.group, self.jids('true'))

    def test_whatsapp_archive_and_unarchive_follow_provider_state(self):
        self.request('POST', '/fixture/plain-dms', {})
        for chat in (self.group, self.module.PLAIN_REACTED, self.module.PLAIN_NEWER):
            for archived in (True, False):
                self.request('POST', '/v1/wazig/archive', dict(chat=chat, archived=archived))
                self.assertEqual(chat in self.jids('true'), archived)
                self.assertEqual(chat in self.jids('false'), not archived)

    def test_provider_batch_updates_only_whatsapp_rows(self):
        self.request('POST', '/fixture/plain-dms', {})
        self.request('POST', '/fixture/telegram-dm', {})
        chat = self.module.PLAIN_REACTED
        telegram = self.module.ARCHIVE_TELEGRAM
        reply = self.request('POST', '/v1/wazig/archive-batch',
                             dict(account='', chats=[dict(chat=chat), dict(chat=telegram)], archived=True))
        self.assertEqual(reply['results'], [dict(chat=chat, ok=True), dict(chat=telegram, ok=False)])
        self.assertIn(chat, self.jids('true'))
        self.assertIn(telegram, self.jids('false'))

    def test_phone_unarchive_changes_provider_state(self):
        self.request('POST', '/fixture/plain-dms', {})
        chat = self.module.PLAIN_REACTED
        self.request('POST', '/v1/wazig/archive', dict(chat=chat, archived=True))
        self.request('POST', '/fixture/phone-unarchive', {})
        self.assertIn(chat, self.jids('false'))
        self.assertNotIn(chat, self.jids('true'))

    def test_plain_direct_chats_gain_a_later_reaction_or_only_a_later_row_time(self):
        reacted, newer = self.module.PLAIN_REACTED, self.module.PLAIN_NEWER
        self.assertNotIn(reacted, self.jids('false'))
        self.request('POST', '/fixture/plain-dms', {})
        self.assertIn(reacted, self.jids('false'))
        self.assertIn(newer, self.jids('false'))
        for chat in (reacted, newer):
            before = self.request('GET', '/v1/wazig/messages?chat=' + chat)
            self.assertEqual([row['FromMe'] for row in before], [False])
        event = self.request('POST', '/fixture/plain-activity', {})
        self.assertEqual(event['chats'], [reacted, newer])
        self.assertFalse(event['archived'])
        rows = {row['jid']: row for row in self.request('GET', '/v1/wazig/chats?archived=false')}
        first = self.request('GET', '/v1/wazig/messages?chat=' + reacted)
        self.assertEqual(first[0]['ReactionToID'], 'PLAIN-INCOMING')
        self.assertTrue(first[0]['FromMe'])
        self.assertEqual(first[1]['Timestamp'], '2026-10-10T11:30:00Z')
        self.assertEqual(rows[reacted]['last_message_ts'], first[0]['Timestamp'])
        second = self.request('GET', '/v1/wazig/messages?chat=' + newer)
        self.assertFalse(second[0]['FromMe'])
        self.assertNotIn('ReactionToID', second[0])
        self.assertEqual(second[0]['Timestamp'], '2026-10-10T11:00:00Z')
        self.assertGreater(rows[newer]['last_message_ts'], second[0]['Timestamp'])
        self.assertEqual(self.jids('true'), [])

    def test_plain_whatsapp_and_local_telegram_receive_new_incoming(self):
        self.request('POST', '/fixture/plain-dms', {})
        self.request('POST', '/fixture/telegram-dm', {})
        newer, telegram = self.module.PLAIN_NEWER, self.module.ARCHIVE_TELEGRAM
        before = {row['jid']: row['last_message_ts'] for row in self.request('GET', '/v1/wazig/chats?archived=false')}
        event = self.request('POST', '/fixture/plain-incoming', {})
        rows = {row['jid']: row for row in self.request('GET', '/v1/wazig/chats?archived=false')}
        for chat in (newer, telegram):
            self.assertFalse(rows[chat]['archived'])
            self.assertGreater(rows[chat]['last_message_ts'], before[chat])
            self.assertEqual(rows[chat]['last_message_ts'], event['last_message_ts'])
            messages = self.request('GET', '/v1/wazig/messages?chat=' + chat)
            self.assertFalse(messages[0]['FromMe'])
            self.assertEqual(messages[0]['Timestamp'], event['last_message_ts'])
        self.assertEqual(rows[telegram]['provider'], 'telegram')
        self.assertEqual(rows[telegram]['account'], 'telegram')
        self.assertEqual(self.jids('true'), [])

    def test_telegram_archive_write_is_rejected_like_every_other_archive_write(self):
        self.request('POST', '/fixture/telegram-dm', {})
        for archived in (True, False):
            result = self.request('POST', '/v1/wazig/archive',
                                  dict(chat=self.module.ARCHIVE_TELEGRAM, archived=archived), status=400)
            self.assertEqual(result, {'error': 'unexpected archive fixture write'})
            self.assertIn(self.module.ARCHIVE_TELEGRAM, self.jids('false'))
            self.assertNotIn(self.module.ARCHIVE_TELEGRAM, self.jids('true'))


class FakeMixedPagingTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('mixed_paging_fixture', ROOT / 'tools/verify-wazig/fake-hub.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        server = ThreadingHTTPServer(('127.0.0.1', 0), self.module.MixedLidHandler)
        server.daemon_threads = True
        server.state = self.module.bridge.State(Path(self.temp.name) / 'requests.jsonl')
        self.addCleanup(server.server_close)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        self.port = server.server_port
        self.headers = {'Authorization': f'Bearer {self.module.bridge.KEY}', 'Connection': 'close'}

    def page(self, limit, before=None):
        query = {'chat': self.module.MIXED, 'limit': limit}
        if before is not None:
            query['before'] = before
        connection = HTTPConnection('127.0.0.1', self.port, timeout=5)
        self.addCleanup(connection.close)
        connection.request('GET', '/v1/wazig/messages?' + urlencode(query), headers=self.headers)
        response = connection.getresponse()
        data = json.loads(response.read())
        self.assertEqual(response.status, 200, data)
        return data

    def cursor(self, row, prefix=''):
        return f"{prefix}{row['MsgID']}:{row['Timestamp']}"

    def test_first_page_is_the_newest_eighty_with_the_phone_and_lid_texts(self):
        first = self.page(80)
        self.assertEqual(len(first), 80)
        self.assertEqual([row['Text'] for row in first[:4]], self.module.MIXED_TEXTS)
        self.assertEqual({row['ChatJID'] for row in first}, {self.module.MIXED, self.module.MIXED_LID})

    def test_cursor_pages_walk_all_rows_once_each_after_dedupe_and_end_empty(self):
        seen = {}
        before = None
        sizes = []
        while True:
            rows = self.page(80, before)
            sizes.append(len(rows))
            if not rows:
                break
            for row in rows:
                seen.setdefault(row['MsgID'], row)
            oldest = min(rows, key=lambda row: row['Timestamp'])
            before = self.cursor(oldest)
        self.assertEqual(len(seen), 250)
        self.assertEqual(sizes[-1], 0)
        self.assertIn('MIXED-250', seen)

    def test_cursor_excludes_its_own_row_and_serves_rows_sharing_its_timestamp(self):
        rows = self.module.mixed_rows()
        tied = [row for row in rows if row['Timestamp'] == rows[self.module.MIXED_TIED_INDEX]['Timestamp']]
        self.assertEqual(len(tied), 2)
        page = self.page(80, self.cursor(rows[self.module.MIXED_TIED_INDEX]))
        ids = [row['MsgID'] for row in page]
        self.assertNotIn(rows[self.module.MIXED_TIED_INDEX]['MsgID'], ids)
        self.assertIn(rows[self.module.MIXED_TIED_INDEX - 1]['MsgID'], ids)
        self.assertTrue(all(row['Timestamp'] <= rows[self.module.MIXED_TIED_INDEX]['Timestamp'] for row in page))
        self.assertEqual(ids, sorted(ids, key=lambda value: int(value.removeprefix('MIXED-'))))

    def test_account_prefix_and_bare_timestamp_cursors_are_accepted(self):
        rows = self.module.mixed_rows()
        prefixed = self.page(80, self.cursor(rows[200], 'personal:'))
        plain = self.page(80, self.cursor(rows[200]))
        self.assertEqual(prefixed, plain)
        bare = self.page(80, rows[200]['Timestamp'])
        self.assertEqual(bare[0]['MsgID'], rows[200]['MsgID'])

    def test_limit_caps_the_page_and_a_cursor_before_the_oldest_row_is_empty(self):
        rows = self.module.mixed_rows()
        self.assertEqual(len(self.page(10, self.cursor(rows[100]))), 10)
        self.assertEqual(self.page(80, self.cursor(rows[249])), [])


class TelegramAvatarEvidenceTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('telegram_avatar_fixture', ROOT / 'tools/verify-wazig/fake-hub.py')
        self.hub = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.hub)
        self.check = runpy.run_path(str(ROOT / 'tools/verify-wazig/check-telegram-evidence.py'))
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.folder = Path(temp.name)
        self.cache = self.folder / 'final-data/avatars'
        self.cache.mkdir(parents=True)
        self.requests = []
        for index, chat in enumerate(self.check['AVATAR_IDS']):
            route = '/v1/wazig/avatar/' + quote(chat, safe='')
            row = dict(method='GET', path=route, authorized=True, status=404)
            path = self.cache / f'{index:016x}.img'
            if chat in self.check['AVATAR_COLOURS']:
                image = self.hub.telegram_avatar_png(chat)
                path.write_bytes(image)
                row.update(status=200, sha256=hashlib.sha256(image).hexdigest())
            else:
                path.with_suffix('.img.none').touch()
            self.requests.extend([row, dict(method='GET', path=route, authorized=False, status=401)])

    def screenshot(self, dpi=96, missing_photo=False, bad_fallback=False, blank_initial=False):
        px = lambda value: (value * dpi + 48) // 96
        layout = dict(dpi=dpi, ids=self.check['AVATAR_IDS'], row_height=px(56), top_index=0,
                      list_x=10, list_y=10, client_width=px(180), client_height=5 * px(56))
        (self.folder / 'telegram-avatars-layout.json').write_text(json.dumps(layout))
        rows = [[(0, 0, 0)] * (px(180) + 20) for _ in range(5 * px(56) + 20)]
        for index, chat in enumerate(layout['ids']):
            colour = self.check['AVATAR_COLOURS'].get(chat, (53, 53, 53))
            if missing_photo and chat in self.check['AVATAR_COLOURS']:
                colour = (53, 53, 53)
            if bad_fallback and chat not in self.check['AVATAR_COLOURS']:
                colour = next(iter(self.check['AVATAR_COLOURS'].values()))
            left, top = 10 + px(12), 10 + index * px(56) + px(8)
            for y in range(px(40)):
                for x in range(px(40)):
                    if (x - (px(40) - 1) / 2) ** 2 + (y - (px(40) - 1) / 2) ** 2 < (px(40) / 2) ** 2:
                        ink = chat not in self.check['AVATAR_COLOURS'] and not blank_initial and px(16) <= x < px(20) and px(13) <= y < px(25)
                        rows[top + y][left + x] = (255, 255, 255) if ink else colour
        self.check['png']['write_png'](self.folder / 'linked.png', rows)

    def test_fixture_returns_distinct_solid_photos_no_photo_and_unauthorized(self):
        handler = object.__new__(self.hub.TelegramHandler)
        replies = []
        handler.respond = lambda status, data, content_type='application/json', **extra: replies.append((status, data, content_type, extra))
        for chat in self.check['AVATAR_IDS']:
            handler.path = '/v1/wazig/avatar/' + quote(chat, safe='')
            for key in ['', 'wrong-key', self.hub.bridge.KEY]:
                handler.headers = {'Authorization': 'Bearer ' + key}
                handler.do_GET()
                status, data, content_type, extra = replies[-1]
                if key != self.hub.bridge.KEY:
                    self.assertEqual(status, 401)
                elif chat in self.check['AVATAR_COLOURS']:
                    self.assertEqual((status, content_type), (200, 'image/png'))
                    self.assertEqual(extra['sha256'], hashlib.sha256(data).hexdigest())
                    image = self.folder / 'response.png'
                    image.write_bytes(data)
                    width, height, rows = self.check['png']['read_png'](image)
                    self.assertEqual((width, height), (64, 64))
                    self.assertEqual(self.check['png']['measure'](rows, self.check['AVATAR_COLOURS'][chat], 0), 1)
                else:
                    self.assertEqual((status, data), (404, {'error': 'no avatar'}))

    def test_pixel_controls_at_supported_dpis(self):
        for dpi in [96, 120, 144, 192]:
            with self.subTest(dpi=dpi):
                self.screenshot(dpi)
                self.check['check_avatar_pixels'](self.folder, capture=True)
                self.check['check_avatar_pixels'](self.folder)

    def test_pixel_checker_rejects_missing_photos_wrong_fallback_and_blank_initials(self):
        for option in ['missing_photo', 'bad_fallback', 'blank_initial']:
            with self.subTest(option=option):
                self.screenshot(**{option: True})
                with self.assertRaises(AssertionError):
                    self.check['check_avatar_pixels'](self.folder, capture=True)

    def test_pixel_checker_rejects_a_crop_not_from_the_screenshot(self):
        self.screenshot()
        self.check['check_avatar_pixels'](self.folder, capture=True)
        crop = self.folder / 'avatar-telegram-user-1001.png'
        self.check['png']['write_png'](crop, [[(0, 0, 0)] * 42 for _ in range(42)])
        with self.assertRaises(AssertionError):
            self.check['check_avatar_pixels'](self.folder)

    def test_request_and_disk_cache_positive_control(self):
        self.check['check_avatar_requests'](self.folder, self.requests)

    def test_cache_checker_rejects_no_fetches_repeats_and_missing_auth_probes(self):
        for rows in [[], self.requests + [self.requests[0]], self.requests[1:], [row for row in self.requests if row['authorized']]]:
            with self.subTest(rows=len(rows)):
                with self.assertRaises(AssertionError):
                    self.check['check_avatar_requests'](self.folder, rows)

    def test_cache_checker_rejects_missing_or_wrong_bytes_and_missing_negative_cache(self):
        path = self.cache / '0000000000000000.img'
        image = path.read_bytes()
        path.unlink()
        with self.assertRaises(AssertionError):
            self.check['check_avatar_requests'](self.folder, self.requests)
        path.write_bytes(b'wrong bytes')
        with self.assertRaises(AssertionError):
            self.check['check_avatar_requests'](self.folder, self.requests)
        path.write_bytes(image)
        next(self.cache.glob('*.none')).unlink()
        with self.assertRaises(AssertionError):
            self.check['check_avatar_requests'](self.folder, self.requests)


if __name__ == '__main__':
    unittest.main()

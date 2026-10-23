from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
from urllib.parse import urlencode
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
        server.state.archive_group_archived = False
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

    def request(self, method, path, body=None):
        connection = HTTPConnection('127.0.0.1', self.port, timeout=5)
        self.addCleanup(connection.close)
        connection.request(method, path, body=None if body is None else json.dumps(body), headers=self.headers)
        response = connection.getresponse()
        data = json.loads(response.read())
        self.assertEqual(response.status, 200, data)
        return data

    def jids(self, archived):
        return [row['jid'] for row in self.request('GET', '/v1/wazig/chats?archived=' + archived)]

    def test_group_moves_to_archived_view_and_returns_to_inbox_on_incoming(self):
        self.assertIn(self.group, self.jids('false'))
        self.assertNotIn(self.group, self.jids('true'))
        self.request('POST', '/v1/wazig/archive', dict(chat=self.group, archived=True))
        self.assertIn(self.group, self.jids('true'))
        self.assertNotIn(self.group, self.jids('false'))
        self.request('POST', '/fixture/archive-incoming', {})
        self.assertIn(self.group, self.jids('false'))
        self.assertNotIn(self.group, self.jids('true'))

    def test_plain_direct_chats_gain_a_later_reaction_or_a_later_incoming_message_when_archived(self):
        reacted, newer = self.module.PLAIN_REACTED, self.module.PLAIN_NEWER
        self.assertNotIn(reacted, self.jids('false'))
        self.request('POST', '/fixture/plain-dms', {})
        self.assertIn(reacted, self.jids('false'))
        self.assertIn(newer, self.jids('false'))
        for chat in (reacted, newer):
            before = self.request('GET', '/v1/wazig/messages?chat=' + chat)
            self.assertEqual([row['FromMe'] for row in before], [False])
            self.request('POST', '/v1/wazig/archive', dict(chat=chat, archived=True))
            self.assertIn(chat, self.jids('true'))
            self.assertNotIn(chat, self.jids('false'))
        rows = {row['jid']: row for row in self.request('GET', '/v1/wazig/chats?archived=true')}
        first = self.request('GET', '/v1/wazig/messages?chat=' + reacted)
        self.assertEqual(first[0]['ReactionToID'], 'PLAIN-INCOMING')
        self.assertTrue(first[0]['FromMe'])
        self.assertEqual(first[1]['Timestamp'], '2026-10-10T11:30:00Z')
        self.assertEqual(rows[reacted]['last_message_ts'], first[0]['Timestamp'])
        second = self.request('GET', '/v1/wazig/messages?chat=' + newer)
        self.assertFalse(second[0]['FromMe'])
        self.assertNotIn('ReactionToID', second[0])
        self.assertGreater(second[0]['Timestamp'], '2026-10-23T00:00:00Z')
        self.request('POST', '/v1/wazig/archive', dict(chat=newer, archived=False))
        self.assertIn(newer, self.jids('false'))


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


if __name__ == '__main__':
    unittest.main()

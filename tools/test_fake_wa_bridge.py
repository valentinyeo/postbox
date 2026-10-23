from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
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
        server.state.archive_stamp = '2026-10-10T11:00:00Z'
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


if __name__ == '__main__':
    unittest.main()

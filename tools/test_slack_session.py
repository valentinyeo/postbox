import base64
from contextlib import contextmanager
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fake_slack_session', ROOT / 'tools/verify-wazig/fake-slack.py')
slack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(slack)


@contextmanager
def server():
    with ThreadingHTTPServer(('127.0.0.1', 0), slack.Handler) as http:
        http.daemon_threads = True
        http.state = slack.State()
        thread = threading.Thread(target=http.serve_forever)
        thread.start()
        try:
            yield http, f'http://127.0.0.1:{http.server_port}'
        finally:
            http.shutdown()
            thread.join()


def call(base, method, fields=None, cookie=slack.COOKIE, token=slack.TOKEN):
    body = urlencode(dict(token=token, **(fields or {}))).encode()
    request = Request(base + '/api/' + method, data=body, headers={
        'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': 'd=' + cookie,
    })
    with urlopen(request) as response:
        return json.load(response)


def read_frame(reader):
    first, length = reader.read(2)
    if length == 126:
        length = struct.unpack('!H', reader.read(2))[0]
    if first != 0x81:
        raise AssertionError('expected text frame')
    return json.loads(reader.read(length))


class SlackSessionTests(unittest.TestCase):
    def test_list_read_send_and_replies_require_both_credentials(self):
        with server() as (http, base):
            self.assertEqual(call(base, 'conversations.list')['channels'][0]['id'], slack.CHANNEL)
            self.assertEqual(call(base, 'users.list')['members'][0]['id'], slack.USER)
            self.assertEqual(call(base, 'conversations.history', dict(channel=slack.CHANNEL))['messages'][0]['ts'], slack.BASELINE)
            sent = call(base, 'chat.postMessage', dict(channel=slack.CHANNEL, text='Fake + & outgoing', client_msg_id='fake-client-id'))
            self.assertEqual(sent['ts'], slack.SENT)
            history = call(base, 'conversations.replies', dict(channel=slack.CHANNEL))['messages']
            self.assertEqual(history[-1]['text'], 'Fake + & outgoing')
            self.assertTrue(all(row['authorized'] and row['cookie_present'] for row in http.state.requests))
            self.assertEqual(call(base, 'conversations.list', cookie='')['error'], 'invalid_auth')
            self.assertEqual(call(base, 'chat.postMessage', token='xoxc-fake-rejected')['error'], 'invalid_auth')
            request = Request(base + '/api/conversations.list', headers={'Authorization': 'Bearer ' + slack.TOKEN})
            with self.assertRaises(HTTPError) as rejected:
                urlopen(request)
            self.assertEqual(rejected.exception.code, 405)

    def test_rtm_upgrade_rejects_missing_cookie_and_emits_raw_message(self):
        with server() as (http, base):
            endpoint = call(base, 'rtm.connect')['url']
            self.assertEqual(endpoint, base.replace('http:', 'ws:') + '/rtm')
            request = Request(base + '/rtm', headers={'Upgrade': 'websocket'})
            with self.assertRaises(HTTPError) as rejected:
                urlopen(request)
            self.assertEqual(rejected.exception.code, 401)
            with socket.create_connection(('127.0.0.1', http.server_port)) as stream:
                key = base64.b64encode(b'fake-slack-nonce!').decode()
                stream.sendall((f'GET /rtm HTTP/1.1\r\nHost: 127.0.0.1:{http.server_port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\nCookie: d={slack.COOKIE}\r\n\r\n').encode())
                with stream.makefile('rb') as reader:
                    self.assertIn(b'101', reader.readline())
                    while reader.readline() != b'\r\n':
                        pass
                    self.assertEqual(read_frame(reader), dict(type='hello'))
                    ping = json.dumps(dict(type='ping', id=1)).encode()
                    mask = b'fake'
                    stream.sendall(bytes([0x81, 0x80 | len(ping)]) + mask + bytes(byte ^ mask[i % 4] for i, byte in enumerate(ping)))
                    self.assertEqual(read_frame(reader)['type'], 'message')
                    with urlopen(Request(base + '/fixture/live', data=b'')) as response:
                        self.assertTrue(json.load(response)['ok'])
                    event = read_frame(reader)
                    self.assertEqual(event['type'], 'message')
                    self.assertEqual(event['text'], 'Fake Slack incoming')
                    self.assertNotIn('envelope_id', event)
                    stream.sendall(b'\x88\x80' + b'fake')
                    self.assertEqual(reader.read(2), b'\x88\x00')
            self.assertEqual(http.state.acks, 0)

    def test_fixture_logs_only_auth_booleans_not_credentials(self):
        with server() as (http, base):
            call(base, 'auth.test')
            log = json.dumps(http.state.requests)
            self.assertNotIn(slack.TOKEN, log)
            self.assertNotIn(slack.COOKIE, log)
            self.assertTrue(http.state.requests[0]['authorized'])


class EvidenceTests(unittest.TestCase):
    def test_session_evidence_rejects_missing_import_socket_cookie_message_or_test_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            def write(name, value):
                (folder / name).write_text(json.dumps(value), encoding='utf-8')
            write('session.json', dict(feature='slack-session', sha256='fake-build-hash', commit='fake-commit'))
            state = dict(slack_connected=True, selected=dict(provider='slack'), chat_count=1, sync='stopped', pending_sends=0, pending_archives=0, production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True)
            for name in ['doctor.json', 'before.state.json', 'after.state.json', 'side-effects.json']:
                write(name, state)
            write('slack-server-state.json', dict(sent=1, acks=0, live=True))
            for name, text in [('history', 'Fake Slack history'), ('sent', 'Fake Slack outgoing'), ('live', 'Fake Slack incoming')]:
                write(name + '.messages.json', dict(messages=[dict(text=text)]))
            for name in ['before', 'history', 'sent', 'after']:
                (folder / (name + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n' + b'fake-image-fixture')
            rows = [dict(path=path, authorized=True, cookie_present=True) for path in ['/api/conversations.list', '/api/conversations.history', '/api/chat.postMessage', '/api/rtm.connect', '/rtm']]
            requests = folder / 'bridge-requests.jsonl'
            requests.write_text('\n'.join(json.dumps(row) for row in rows), encoding='utf-8')
            count = sum(path.read_text().count('test "IGSH-464 session') for path in [ROOT / 'src/slack_session.zig', ROOT / 'src/slack_session_test.zig'])
            tests = folder / 'slack-session-tests.log'
            tests.write_text(f'{count}/{count} tests passed', encoding='utf-8')
            (folder / 'slack-proof.log').write_text('import-dpapi-list-badge-history-send-rtm-cookie PASS', encoding='utf-8')
            (folder / 'cleanup.txt').write_text('CLEANUP PASSED', encoding='utf-8')
            (folder / 'result.txt').write_text('JOURNEY PASSED: slack-session', encoding='utf-8')
            command = [sys.executable, str(ROOT / 'tools/verify-wazig/check-evidence.py'), str(folder)]
            passed = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(passed.returncode, 0, passed.stderr)
            self.assertIn('EVIDENCE VERIFIED', passed.stdout)
            for target, broken in [
                (tests, b'0/0 tests passed'),
                (folder / 'after.png', b'not a screenshot'),
                (folder / 'live.messages.json', b'{"messages":[]}'),
                (requests, '\n'.join(json.dumps(dict(row, cookie_present=False)) for row in rows).encode()),
            ]:
                with self.subTest(target=target.name):
                    previous = target.read_bytes()
                    target.write_bytes(broken)
                    rejected = subprocess.run(command, capture_output=True, text=True)
                    self.assertNotEqual(rejected.returncode, 0)
                    target.write_bytes(previous)
            (folder / 'final-data').mkdir()
            (folder / 'final-data/slack-session-import.json').write_text('fake-unconsumed-import', encoding='utf-8')
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()

import base64
from contextlib import contextmanager
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import socket
import struct
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


if __name__ == '__main__':
    unittest.main()

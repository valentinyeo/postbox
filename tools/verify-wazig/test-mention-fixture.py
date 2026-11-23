import io
import json
from pathlib import Path
import runpy
import threading
from types import SimpleNamespace
import unittest


fixture = runpy.run_path(str(Path(__file__).with_name('fake-hub.py')))


class MentionFixtureShapes(unittest.TestCase):
    def test_acknowledged_send_returns_in_newest_first_history(self):
        handler = fixture['SlackMentionsHandler'].__new__(fixture['SlackMentionsHandler'])
        handler.server = SimpleNamespace(state=SimpleNamespace(lock=threading.Lock(), sends={}, stamp='2026-11-23T10:00:00Z'))
        handler.authorized = lambda: True
        replies = []
        handler.respond = lambda status, data, **extra: replies.append((status, data, extra))
        handler.path = '/v1/wazig/messages?chat=slack%3Afixture-mentions%3Achannel'
        handler.do_GET()
        self.assertEqual(5, len(replies[-1][1]))
        body = dict(chat=fixture['MENTIONS_CHAT'], text='<@U4A59H6UT> hello', client_id='1' * 32, reply_to='')
        payload = json.dumps(body).encode()
        handler.path = '/v1/wazig/send'
        handler.headers = {'Content-Length': str(len(payload))}
        handler.rfile = io.BytesIO(payload)
        handler.do_POST()
        self.assertEqual('MENTION-SENT', replies[-1][1]['msg_id'])
        handler.path = '/v1/wazig/messages?chat=slack%3Afixture-mentions%3Achannel'
        handler.do_GET()
        status, rows, extra = replies[-1]
        self.assertEqual(200, status)
        self.assertEqual(6, len(rows))
        self.assertEqual('MENTION-SENT', rows[0]['MsgID'])
        self.assertTrue(rows[0]['FromMe'])
        self.assertEqual(body['text'], rows[0]['Text'])
        self.assertEqual(body['chat'], rows[0]['ChatJID'])
        self.assertGreater(rows[0]['Timestamp'], rows[1]['Timestamp'])
        self.assertEqual(1, sum(row['FromMe'] for row in rows))
        self.assertIn(rows[0], extra['rows'])


if __name__ == '__main__':
    unittest.main()

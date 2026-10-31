import importlib.util
import json
from pathlib import Path
import runpy
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


class SignalBridgeHubTest(unittest.TestCase):
    def test_signal_bridge_journey(self):
        root = Path(__file__).parent
        spec = importlib.util.spec_from_file_location('signal_hub_fixture', root / 'fake-hub.py')
        fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture)
        registry = json.loads((root / 'journeys.json').read_text())
        config = next(row for row in registry['journeys'] if row['name'] == 'signal')['hub_handler']
        namespace = vars(fixture)
        if config['file'] != 'fake-hub.py':
            namespace = runpy.run_path(str(root / config['file']), init_globals=namespace)
        with tempfile.TemporaryDirectory() as directory:
            state = fixture.bridge.State(Path(directory) / 'requests.jsonl')
            state.reactions = {}
            state.signal_events = []
            state.signal_read = set()
            state.signal_reaction = None
            server = fixture.ThreadingHTTPServer(('127.0.0.1', 0), namespace[config['class']])
            server.daemon_threads = True
            server.state = state
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            origin = f'http://127.0.0.1:{server.server_port}'

            def request(path, body=None, content_type='application/json', authorized=True):
                headers = {'Content-Type': content_type}
                if authorized:
                    headers['Authorization'] = 'Bearer fixture-key-not-a-secret'
                if isinstance(body, dict):
                    body = json.dumps(body).encode()
                try:
                    with urlopen(Request(origin + '/v1/wazig/' + path, body, headers)) as response:
                        return response.status, json.load(response)
                except HTTPError as error:
                    return error.code, json.load(error)

            try:
                self.assertEqual(request('chats', authorized=False)[0], 401)
                status, chats = request('chats?archived=false')
                self.assertEqual(status, 200)
                self.assertTrue(all(row['provider'] == 'signal' for row in chats))
                chat = chats[0]['jid']
                history_path = 'messages?' + urlencode({'chat': chat, 'limit': 80, 'before': ''})
                status, history = request(history_path)
                self.assertEqual(status, 200)
                message = history[-1]['MsgID']
                text = dict(chat=chat, text='Synthetic text', reply_to=message, client_id='fixture-text')
                status, sent = request('send', text)
                self.assertEqual(status, 200)
                self.assertEqual(sent['status'], 'sent')
                self.assertEqual(sent['client_id'], text['client_id'])
                self.assertEqual(request('send', text)[1]['msg_id'], sent['msg_id'])
                boundary = 'synthetic-boundary'
                fields = dict(chat=chat, text='Synthetic caption', reply_to=message, client_id='fixture-file')
                payload = b''.join((f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n').encode()
                                   for name, value in fields.items())
                payload += (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="synthetic.txt"\r\n'
                            'Content-Type: application/octet-stream\r\n\r\nSynthetic file bytes\r\n'
                            f'--{boundary}--\r\n').encode()
                status, uploaded = request('send', payload, f'multipart/form-data; boundary={boundary}')
                self.assertEqual(status, 200)
                status, rows = request(history_path)
                self.assertEqual(status, 200)
                outgoing = next(row for row in rows if row['MsgID'] == uploaded['msg_id'])
                self.assertEqual(outgoing['Filename'], 'synthetic.txt')
                self.assertEqual(outgoing['MimeType'], 'text/plain')
                self.assertEqual(outgoing['MediaType'], 'document')
                self.assertEqual(outgoing['quoted_msg_id'], message)
                self.assertEqual(next(row for row in rows if row['MsgID'] == sent['msg_id'])['quoted_msg_id'], message)
                self.assertEqual(state.signal_events, [('msg', chat), ('msg', chat)])
                image_payload = payload.replace(b'fixture-file', b'fixture-image').replace(b'synthetic.txt', b'synthetic.png').replace(b'Synthetic file bytes', state.image)
                status, image_reply = request('send', image_payload, f'multipart/form-data; boundary={boundary}')
                self.assertEqual(status, 200)
                image = next(row for row in request(history_path)[1] if row['MsgID'] == image_reply['msg_id'])
                self.assertEqual((image['MediaType'], image['MimeType'], image['Filename']), ('image', 'image/png', 'synthetic.png'))
                reaction = dict(chat=chat, msg=message, emoji='👍', client_id='fixture-react')
                self.assertEqual(request('react', reaction)[0], 200)
                self.assertTrue(any(row.get('ReactionEmoji') == '👍' for row in request(history_path)[1]))
                self.assertEqual(request('mark-read', dict(chat=chat, message_id=message))[0], 200)
                self.assertEqual(next(row for row in request('chats')[1] if row['jid'] == chat)['unread_count'], 0)
                self.assertEqual(len(state.sends), 3)
                self.assertEqual(state.signal_events[-2:], [('reaction', chat), ('read', chat)])
            finally:
                server.shutdown()
                server.server_close()
                worker.join()


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SignalBridgeHubTest))
    if not result.wasSuccessful():
        raise SystemExit(1)
    print('Signal hub contract passed')

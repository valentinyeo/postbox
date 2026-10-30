import importlib.util
import io
import json
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace

path = Path(__file__).parent / 'verify-wazig' / 'fake-hub.py'
spec = importlib.util.spec_from_file_location('identity_fixture', path)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class IdentityFixtureTest(unittest.TestCase):
    def setUp(self):
        self.state = SimpleNamespace(lock=threading.Condition(), stamp='2026-01-02T00:00:00Z')
        self.handler = object.__new__(fixture.Handler)
        self.handler.server = SimpleNamespace(state=self.state)
        self.handler.authorized = lambda: True
        self.responses = []
        self.handler.respond = lambda status, data, **extra: self.responses.append((status, data, extra))

    def post(self, body, content_type):
        self.handler.path = '/v1/wazig/send'
        self.handler.headers = {'Content-Length': str(len(body)), 'Content-Type': content_type}
        self.handler.rfile = io.BytesIO(body)
        self.handler.do_POST()
        return self.responses[-1]

    def test_text_mutation_preserves_first_operation(self):
        body = {'chat': fixture.ALPHA, 'text': 'Identity fixture', 'reply_to': 'parent', 'client_id': 'a' * 32}
        encode = lambda value: json.dumps(value).encode()
        self.assertEqual(self.post(encode(body), 'application/json')[0], 409)
        changed = dict(body, reply_to='other')
        status, result, _ = self.post(encode(changed), 'application/json')
        self.assertEqual((status, result['error']), (409, 'identity payload mismatch'))
        self.assertEqual(self.state.identity_attempts[body['client_id']], 1)
        self.assertEqual(self.state.identity_payloads[body['client_id']], body)
        self.assertEqual(self.post(encode(body), 'application/json')[0], 409)
        self.assertEqual(self.state.identity_attempts[body['client_id']], 2)

    def test_file_mutation_preserves_first_operation(self):
        def multipart(filename, payload):
            pieces = []
            fields = {'account': 'hub', 'chat': fixture.ALPHA, 'text': 'Identity file',
                      'reply_to': 'parent', 'client_id': 'b' * 32, 'ptt': 'false'}
            for name, value in fields.items():
                pieces.append(f'--boundary\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
            pieces.append(f'--boundary\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode())
            pieces.append(payload + b'\r\n--boundary--\r\n')
            return b''.join(pieces)
        content_type = 'multipart/form-data; boundary=boundary'
        original = multipart('original.png', b'\x89PNG\r\n\x1a\noriginal')
        self.assertEqual(self.post(original, content_type)[0], 409)
        changed = multipart('other.png', b'\x89PNG\r\n\x1a\noriginal')
        status, result, _ = self.post(changed, content_type)
        self.assertEqual((status, result['error']), (409, 'identity payload mismatch'))
        self.assertEqual(self.state.identity_file_attempts['b' * 32], 1)
        self.assertEqual(self.state.identity_file_payloads['b' * 32][0]['file'], 'original.png')
        self.assertEqual(self.post(original, content_type)[0], 409)
        self.assertEqual(self.state.identity_file_attempts['b' * 32], 2)


if __name__ == '__main__':
    unittest.main()

import http.client
import json
from pathlib import Path
import runpy
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer


TOOLS = Path(__file__).parent / 'verify-wazig'
namespace = runpy.run_path(str(TOOLS / 'fake-hub.py'))
handler = runpy.run_path(str(TOOLS / 'icon-hints-fixture.py'), init_globals=namespace)['IconHintsHandler']
check_no_send = runpy.run_path(str(TOOLS / 'check-icon-hints-evidence.py'))['check_no_send']


class IconHintSendBoundaryTests(unittest.TestCase):
    def test_all_send_body_formats_are_logged_and_rejected(self):
        cases = (
            ('application/json', b'{"chat":"fixture","text":"hello"}'),
            ('multipart/form-data; boundary=fixture', b'--fixture\r\nContent-Disposition: form-data; name="file"; filename="voice.ogg"\r\n\r\nOggS\x00\xff\r\n--fixture--\r\n'),
            ('application/json', b'{malformed\xff'),
        )
        for content_type, body in cases:
            with self.subTest(content_type=content_type, body=body):
                with tempfile.TemporaryDirectory() as temporary:
                    path = Path(temporary) / 'requests.jsonl'
                    server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
                    server.state = namespace['bridge'].State(path)
                    thread = threading.Thread(target=server.serve_forever, daemon=True)
                    thread.start()
                    try:
                        connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=5)
                        try:
                            connection.request('POST', '/v1/wazig/send', body=body, headers={
                                'Authorization': 'Bearer fixture-key-not-a-secret',
                                'Content-Type': content_type,
                            })
                            response = connection.getresponse()
                            self.assertEqual(response.status, 403)
                            self.assertTrue(response.will_close)
                            response.read()
                        finally:
                            connection.close()
                    finally:
                        server.shutdown()
                        thread.join()
                        server.server_close()
                    rows = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()]
                    self.assertEqual(len(rows), 1)
                    self.assertEqual(rows[0]['method'], 'POST')
                    self.assertEqual(rows[0]['wire_path'], '/v1/wazig/send')
                    self.assertEqual(rows[0]['status'], 403)
                    with self.assertRaises(AssertionError):
                        check_no_send(rows)


if __name__ == '__main__':
    unittest.main()

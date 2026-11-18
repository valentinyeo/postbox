from datetime import datetime
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import runpy
import struct
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.parse import quote, urlencode
import zlib


FIXTURES = Path(__file__).resolve().parent / 'verify-wazig'
with patch.object(sys, 'path', [str(FIXTURES), *sys.path]):
    import real_size_seed as seed
    HUB = runpy.run_path(str(FIXTURES / 'fake-hub.py'))
    FIXTURE = runpy.run_path(str(FIXTURES / 'real-size-fixture.py'), init_globals=HUB)
    VALIDATOR = runpy.run_path(str(FIXTURES / 'evidence-real-size.py'))


class RealSizeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def log(self):
        return (' '.join(f'seeded_{key}={value}' for key, value in seed.COUNTS.items()) + '\n' +
                f'app_inbox_chats={len(seed.INBOX)}\napp_archived_chats={len(seed.ARCHIVED)}\n' +
                ''.join(f'step={step} finished=true\n' for step in VALIDATOR['STEPS']))

    def test_seed_is_repeatable_and_counts_actual_rows(self):
        again = runpy.run_path(str(FIXTURES / 'real_size_seed.py'))
        self.assertEqual((seed.CHATS, seed.MESSAGES, seed.COUNTS), (again['CHATS'], again['MESSAGES'], again['COUNTS']))
        rows = [row for chat in seed.CHATS for row in seed.MESSAGES[chat['jid']]]
        self.assertEqual(seed.COUNTS, dict(chats=len(seed.CHATS), messages=len(rows),
                                         voice=sum(row.get('MediaType') == 'audio' for row in rows),
                                         images=sum(row.get('MediaType') == 'image' for row in rows),
                                         groups=sum(chat['provider'] == 'whatsapp' and chat['kind'] == 'group' for chat in seed.CHATS)))
        stamps = [datetime.fromisoformat(row['Timestamp'].replace('Z', '+00:00')) for row in rows]
        self.assertGreaterEqual((max(stamps) - min(stamps)).days, 59)
        self.assertLessEqual((max(stamps) - min(stamps)).days, 61)
        self.assertGreaterEqual(len(seed.MESSAGES[seed.BUSY]), 1500)
        self.assertEqual(len({row['MsgID'] for row in rows}), len(rows))
        self.assertTrue(any(chat['unread'] for chat in seed.CHATS))
        self.assertTrue(any(chat['archived'] for chat in seed.CHATS))
        self.assertGreaterEqual(sum(chat['provider'] == 'slack' for chat in seed.CHATS), 3)
        self.assertTrue(any(row.get('MediaType') == 'document' for row in rows))
        self.assertTrue(any(row.get('quoted_msg_id') for row in rows))
        for chat in seed.CHATS:
            if chat['kind'] == 'group':
                self.assertTrue(all(row['SenderName'].startswith('Seed Sender') for row in seed.MESSAGES[chat['jid']]))

    def test_size_guard_rejects_changed_counts_and_each_missing_step(self):
        path = self.folder / 'run.log'
        log = self.log()
        path.write_text(log)
        VALIDATOR['check_size'](self.folder)
        for key, value in seed.COUNTS.items():
            with self.subTest(key=key):
                path.write_text(log.replace(f'seeded_{key}={value}', f'seeded_{key}={value - 1}'))
                with self.assertRaisesRegex(AssertionError, 'Real-size seeded_'):
                    VALIDATOR['check_size'](self.folder)
                path.write_text(log)
                with patch.dict(seed.COUNTS, {key: VALIDATOR['MINIMUMS'][key] - 1}):
                    path.write_text(self.log())
                    with self.assertRaisesRegex(AssertionError, 'Real-size seed shrank'):
                        VALIDATOR['check_size'](self.folder)
        for step in VALIDATOR['STEPS']:
            with self.subTest(step=step):
                path.write_text(log.replace(f'step={step} finished=true\n', ''))
                with self.assertRaisesRegex(AssertionError, 'steps missing'):
                    VALIDATOR['check_size'](self.folder)

    def start_server(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), FIXTURE['RealSizeHandler'])
        server.daemon_threads = True
        server.state = HUB['bridge'].State(self.folder / 'requests.jsonl')
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        return server

    def get(self, server, path, authorized=True):
        connection = HTTPConnection('127.0.0.1', server.server_port, timeout=5)
        try:
            connection.request('GET', path, headers={'Authorization': 'Bearer ' + HUB['bridge'].KEY} if authorized else {})
            response = connection.getresponse()
            payload = response.read()
            return response.status, response.getheader('Content-Type'), payload
        finally:
            connection.close()

    def test_wire_seed_pagination_and_valid_media(self):
        server = self.start_server()
        self.assertEqual(self.get(server, '/fixture/seed', False)[0], 401)
        self.assertEqual(json.loads(self.get(server, '/fixture/seed')[2]), seed.MANIFEST)
        for archived, expected in [(False, seed.INBOX), (True, seed.ARCHIVED)]:
            status, _, payload = self.get(server, '/v1/wazig/chats?' + urlencode(dict(archived=str(archived).lower(), limit=500)))
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(payload), expected)
        total = 0
        for chat in seed.CHATS:
            found = []
            before = ''
            while True:
                status, _, payload = self.get(server, '/v1/wazig/messages?' + urlencode(dict(chat=chat['jid'], limit=80, before=before)))
                self.assertEqual(status, 200)
                rows = json.loads(payload)
                if not rows:
                    break
                self.assertLessEqual(len(rows), 80)
                found.extend(rows)
                before = rows[-1]['MsgID'] + ':' + rows[-1]['Timestamp']
            self.assertEqual(found, list(reversed(seed.MESSAGES[chat['jid']])))
            total += len(found)
        self.assertEqual(total, seed.COUNTS['messages'])
        for row in seed.MESSAGES[seed.VOICE]:
            if 'MediaType' not in row:
                continue
            path = '/v1/wazig/media/' + quote(seed.VOICE, safe='') + '/' + row['MsgID']
            status, mime, payload = self.get(server, path)
            self.assertEqual((status, mime), (200, row['MimeType']))
            if row['MediaType'] == 'audio':
                self.assertEqual(payload, (FIXTURES / 'voice-note.ogg').read_bytes())
                self.assertTrue(payload.startswith(b'OggS') and b'OpusHead' in payload)
            elif row['MediaType'] == 'image':
                self.assertTrue(payload.startswith(b'\x89PNG\r\n\x1a\n'))
                size = struct.unpack('>I', payload[33:37])[0]
                self.assertEqual(len(zlib.decompress(payload[41:41 + size])), 64 * (1 + 96 * 3))
        groups = json.loads(self.get(server, '/v1/wazig/groups')[2])
        self.assertEqual(len(groups), seed.COUNTS['groups'])
        self.assertEqual(self.get(server, '/v1/wazig/messages?chat=missing')[0], 404)
        self.assertEqual(self.get(server, '/v1/wazig/media/missing/missing')[0], 404)

    def evidence(self):
        def save(name, value):
            (self.folder / name).write_text(json.dumps(value))
        (self.folder / 'run.log').write_text(self.log())
        save('session.json', dict(feature='real-size', sha256='fixture-hash', commit='fixture-commit'))
        save('result.json', dict(feature='real-size', status='passed'))
        save('seed.json', seed.MANIFEST)
        for phase, rows in [('inbox', seed.INBOX), ('archived', seed.ARCHIVED), ('after', seed.INBOX)]:
            save(f'{phase}.chats.json', dict(total=len(rows), chats=[dict(id=row['jid'], archived=row['archived']) for row in rows]))
        save('list-scroll.json', dict(top_index=290, native_count=len(seed.INBOX), state=dict(selected=dict(id=seed.INBOX[-1]['jid']))))
        for phase, count in [('busy', 80), ('busy-top', 1000)]:
            save(f'{phase}.messages.json', dict(chat=dict(id=seed.BUSY), messages=[dict(id=row['MsgID'], bubble=[0, 80, 100, 120]) for row in seed.MESSAGES[seed.BUSY][-count:]]))
        save('search.json', dict(query='Orchard', focused=True, palette=True, native_count=len(seed.SEARCH), labels=[row['name'] for row in seed.SEARCH], rows=[dict(id=row['jid']) for row in seed.SEARCH]))
        for phase, chat in [('voice', seed.VOICE), ('group', seed.GROUP)]:
            save(f'{phase}.messages.json', dict(chat=dict(id=chat), messages=[dict(id=row['MsgID'], media_type=row.get('MediaType', ''), local=True, from_me=row['FromMe'], sender=row['SenderName'], quoted_msg_id=row.get('quoted_msg_id', '')) for row in seed.MESSAGES[chat]]))
        save('real-size.requests.json', [dict(status=200, seed=seed.MANIFEST), dict(status=200, rows=seed.INBOX), dict(status=200, rows=seed.ARCHIVED),
                                         dict(status=200, chat=seed.BUSY, message_ids=[row['MsgID'] for row in seed.MESSAGES[seed.BUSY]]),
                                         dict(status=200, wire_path='/v1/wazig/media/fixture/audio', sha256='fixture-hash')])
        for phase in ('before', 'list-scrolled', 'busy', 'busy-top', 'search', 'voice', 'group', 'archived', 'after'):
            (self.folder / f'{phase}.png').write_bytes(HUB['bridge'].png() + bytes(10000))
            save(f'{phase}.state.json', dict(chat_count=len(seed.ARCHIVED if phase == 'archived' else seed.INBOX), show_archived=phase == 'archived'))
        save('side-effects.json', dict(pending_sends=0, pending_archives=0, sync='stopped', production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'result.txt').write_text('JOURNEY PASSED: real-size')
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: fixture')

    def test_validator_accepts_complete_evidence_and_rejects_lost_rows(self):
        self.evidence()
        VALIDATOR['check_evidence'](self.folder)
        for name, key in [('inbox.chats.json', 'chats'), ('busy-top.messages.json', 'messages'), ('search.json', 'rows')]:
            with self.subTest(name=name):
                path = self.folder / name
                original = path.read_text()
                data = json.loads(original)
                data[key].pop(0)
                path.write_text(json.dumps(data))
                with self.assertRaises(AssertionError):
                    VALIDATOR['check_evidence'](self.folder)
                path.write_text(original)
        path = self.folder / 'busy-top.messages.json'
        data = json.loads(path.read_text())
        data['messages'][0]['bubble'] = [0, 0, 0, 0]
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(AssertionError, 'not painted'):
            VALIDATOR['check_evidence'](self.folder)


if __name__ == '__main__':
    unittest.main()

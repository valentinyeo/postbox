from copy import deepcopy
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

    def start_server(self, handler=None):
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler or FIXTURE['RealSizeHandler'])
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

    def test_background_merge_preserves_owned_rows_and_rejects_collisions(self):
        own_chats = json.loads((FIXTURES / 'search-queries.json').read_text())['rows']
        own_messages = {own_chats[0]['jid']: [dict(MsgID='OWN', Text='Keep exactly', FromMe=True)]}
        original = deepcopy((own_chats, own_messages, seed.CHATS, seed.MESSAGES))
        chats, messages = seed.merge_background(own_chats, own_messages)
        self.assertEqual((own_chats, own_messages, seed.CHATS, seed.MESSAGES), original)
        self.assertEqual(chats[:len(own_chats)], own_chats)
        self.assertIs(messages[own_chats[0]['jid']], own_messages[own_chats[0]['jid']])
        added = chats[len(own_chats):]
        added_messages = {row['jid']: messages[row['jid']] for row in added}
        self.assertEqual(seed.count_rows(added, added_messages), seed.COUNTS)
        self.assertEqual(len({row['jid'] for row in chats}), len(chats))
        self.assertEqual({row['ChatJID'] for rows in added_messages.values() for row in rows}, set(added_messages))
        self.assertTrue(all(not row['unread'] and row['unread_count'] == 0 for row in added))
        self.assertLess(max(row['last_message_ts'] for row in added), '2026-01-01T00:00:00Z')
        fixture = json.loads((FIXTURES / 'search-queries.json').read_text())
        excluded = [case['query'] for case in fixture['queries']] + [
            fixture['message'], 'Fixture Sender', 'Fixture Voice', 'voice-note.ogg',
            *(f'voice-{number}.ogg' for number in range(1, 6)),
            'First words of the original', 'Synthetic whatsapp reply', 'Synthetic slack reply']
        searchable = '\n'.join(str(row[key]) for row in added for key in ('jid', 'name', 'account'))
        searchable += json.dumps(added_messages)
        for word in excluded:
            with self.subTest(word=word):
                self.assertNotIn(word.lower(), searchable.lower())
        for owned_chats, owned_messages in [([added[0]], {}), ([], {added[0]['jid']: []})]:
            with self.assertRaises(ValueError):
                seed.merge_background(owned_chats, owned_messages)

    def test_main_seeds_only_default_journeys(self):
        from unittest.mock import Mock
        for mode in ('search', 'voice', 'reply', 'palette-archived'):
            with self.subTest(mode=mode):
                server = Mock(server_port=1234)
                with patch.dict(HUB['main'].__globals__, ThreadingHTTPServer=Mock(return_value=server),
                                voice_playback_bytes=lambda: b'fixture'), \
                        patch.dict('os.environ', GITHUB_ACTIONS='true'), \
                        patch.object(sys, 'argv', ['fake-hub.py', '--' + mode, '--port-file', str(self.folder / 'port'),
                                                  '--log', str(self.folder / 'requests.jsonl')]):
                    HUB['main']()
                if mode == 'palette-archived':
                    self.assertFalse(hasattr(server.state, 'background_chats'))
                else:
                    self.assertEqual(seed.count_rows(server.state.background_chats, server.state.background_messages), seed.COUNTS)

    def test_default_journey_wire_rows_are_unchanged_beside_background(self):
        registry = json.loads((FIXTURES / 'journeys.json').read_text())['journeys']
        for mode in ('search', 'voice', 'reply'):
            with self.subTest(mode=mode):
                config = next(row['hub_handler'] for row in registry if row['name'] == mode)
                namespace = HUB if config['file'] == 'fake-hub.py' else runpy.run_path(str(FIXTURES / config['file']), init_globals=HUB)
                server = self.start_server(namespace[config['class']])
                paths = ['/v1/wazig/chats', '/v1/wazig/chats?archived=true']
                own = [json.loads(self.get(server, path)[2]) for path in paths]
                histories = {row['jid']: json.loads(self.get(server, '/v1/wazig/messages?' + urlencode(dict(chat=row['jid'])))[2])
                             for rows in own for row in rows}
                server.state.background_chats, server.state.background_messages = seed.merge_background([], {})
                self.assertEqual(self.get(server, '/fixture/seed', False)[0], 401)
                counts = json.loads(self.get(server, '/fixture/seed')[2])
                self.assertEqual(counts, seed.COUNTS)
                for path, original in zip(paths, own):
                    shown = json.loads(self.get(server, path)[2])
                    self.assertEqual(shown[:len(original)], original)
                    expected = [row for row in server.state.background_chats if row['archived'] == ('archived=true' in path)]
                    self.assertEqual(shown[len(original):], expected)
                    self.assertEqual(len({row['jid'] for row in shown}), len(shown))
                for jid, original in histories.items():
                    self.assertEqual(json.loads(self.get(server, '/v1/wazig/messages?' + urlencode(dict(chat=jid)))[2]), original)
                messages = server.state.background_messages
                for jid, rows in messages.items():
                    shown = json.loads(self.get(server, '/v1/wazig/messages?' + urlencode(dict(chat=jid, limit=1600)))[2])
                    self.assertEqual(shown, list(reversed(rows)))
                row = next(row for rows in messages.values() for row in rows if row.get('MediaType') == 'audio')
                path = '/v1/wazig/media/' + quote(row['ChatJID'], safe='') + '/' + row['MsgID']
                self.assertEqual(self.get(server, path)[2], (FIXTURES / 'voice-note.ogg').read_bytes())
                server.state.background_messages.pop(next(iter(messages)))
                self.assertLess(json.loads(self.get(server, '/fixture/seed')[2])['messages'], counts['messages'])

    def test_background_counts_must_be_logged_and_loaded(self):
        chats, _ = seed.merge_background([], {})
        inbox = [dict(id=row['jid']) for row in chats if not row['archived']]
        (self.folder / 'before.chats.json').write_text(json.dumps(dict(total=len(inbox), chats=inbox)))
        (self.folder / 'seed.json').write_text(json.dumps(seed.COUNTS))
        path = self.folder / 'run.log'
        log = ' '.join(f'seeded_{key}={value}' for key, value in seed.COUNTS.items())
        path.write_text(log)
        seed.check_background_size(self.folder)
        for key, value in seed.COUNTS.items():
            for changed in ('', f'seeded_{key}={value - 1}', f'seeded_{key}={value} seeded_{key}={value}'):
                with self.subTest(key=key, changed=changed):
                    path.write_text(log.replace(f'seeded_{key}={value}', changed))
                    with self.assertRaisesRegex(AssertionError, 'Real-size seeded_'):
                        seed.check_background_size(self.folder)
        for key, value in [('chats', 299), ('messages', 5999)]:
            with patch.dict(seed.COUNTS, {key: value}), self.assertRaisesRegex(AssertionError, 'seed shrank'):
                seed.check_background_size(self.folder)
        path.write_text(log)
        (self.folder / 'before.chats.json').write_text(json.dumps(dict(total=len(inbox) - 1, chats=inbox[1:])))
        with self.assertRaisesRegex(AssertionError, 'chats missing'):
            seed.check_background_size(self.folder)

    def test_each_default_validator_rejects_unseeded_evidence(self):
        (self.folder / 'run.log').write_text('seeded_chats=2 seeded_messages=2')
        for name, function in [('check-search-evidence.py', 'check_evidence'), ('evidence-voice.py', None),
                               ('check-reply-evidence.py', 'check_reply')]:
            with self.subTest(name=name), patch.object(sys, 'argv', [name, str(self.folder)]):
                with self.assertRaisesRegex(AssertionError, 'Real-size seeded_'):
                    checker = runpy.run_path(str(FIXTURES / name))
                    if function:
                        checker[function](self.folder)

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

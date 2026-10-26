from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('palette_validator', ROOT / 'tools/verify-wazig/check-palette-archived-evidence.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class PaletteArchivedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.views = [dict(provider='whatsapp', account='personal', label='WhatsApp'), dict(provider='slack', account='T0PALETTE', label='Slack Palette Workspace')]
        self.write('session.json', dict(feature='palette-archived', sha256='synthetic-hash', commit='synthetic-commit'))
        self.write('result.json', dict(feature='palette-archived', status='passed'))
        self.write('view-order.json', self.views)
        matrix = []
        names = {key: name for key, (chat, name) in validator.ARCHIVED.items()}

        def row(step, view, query, expected, labels):
            return dict(step=step, view=view, query=query, expected=expected, found=True, index=labels.index(expected), matches=1, rows=len(labels), labels=labels)

        matrix.append(row('a0-inbox-control', 'combined inbox', validator.INBOX['delta'], validator.INBOX['delta'], [validator.INBOX['delta']]))
        self.screen('a0-inbox-control')
        for key, name in names.items():
            expected = validator.label(name)
            matrix.append(row(f'a-all-{key}', 'combined inbox', name, expected, ['Show archived chats', expected]))
            self.screen(f'a-all-{key}')
            self.write(f'a-all-{key}.palette.json', dict(labels=['Show archived chats', expected], index=1))
        matrix.append(dict(step='a-all-crowded', informational=True, rows=4, labels=[]))
        self.screen('a-all-crowded')
        for position, view in enumerate(self.views, 1):
            self.screen(f'b-view-{position}')
            for key, name in names.items():
                expected = validator.label(name)
                matrix.append(row(f'b-{position}-{key}', view['label'], name, expected, [expected]))
                self.screen(f'b-{position}-{key}')
            for slug, name in validator.INBOX.items():
                matrix.append(row(f'b-{position}-inbox-{slug}', view['label'], name, name, [name]))
        self.write('palette-archived.json', dict(row_limit=10, views=self.views, matrix=matrix, failures=[]))
        self.write('frequency-results.json', dict(frequent=validator.label(names['telegram']), rare=validator.label(names['whatsapp']), labels=[validator.label(names[key]) for key in ['telegram', 'whatsapp', 'slack', 'signal']], row_height=40))
        self.write('frequency-badges.json', dict.fromkeys(names, 80))
        self.screen('frequency-results')
        self.requests = [dict(method='GET', authorized=True, status=200, wire_path='/v1/wazig/chats?archived=true&limit=500')]
        for key, (chat, name) in validator.ARCHIVED.items():
            self.requests.append(self.history(chat))
            for scope in ['all', 'own']:
                self.screen(f'c-{scope}-{key}', selected=dict(id=chat, archived=True))
                self.screen(f'c-{scope}-{key}-palette')
        self.requests.append(dict(method='POST', authorized=True, status=200, wire_path='/v1/wazig/mark-read', body=dict(chat='x')))
        self.save_requests()
        self.write('side-effects.json', dict(pending_sends=0, pending_archives=0, sync='stopped', show_archived=False, current_view=dict(inbox=True), production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'hub-proof.log').write_text('palette-archived archived-scan-request PASS\npalette-archived palette-archived-all PASS\n')
        (self.folder / 'actions.log').write_text('\n'.join('keys: ' + key for key in ['%i', '%1', '^k', '{ENTER}']))
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: synthetic validator input')
        (self.folder / 'result.txt').write_text('JOURNEY PASSED: palette-archived')

    def history(self, chat):
        return dict(method='GET', authorized=True, status=200, wire_path='/v1/wazig/messages?chat=' + chat.replace(':', '%3A'))

    def screen(self, name, selected=None):
        (self.folder / f'{name}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'fixture' * 2000)
        (self.folder / f'{name}.uia.txt').write_text('MessagesZig | Combined inbox - Wazig v0.0.526')
        self.write(f'{name}.state.json', dict(selected=selected or {}))

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value), encoding='utf-8')

    def save_requests(self):
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in self.requests))
        self.write('palette-archived.requests.json', self.requests)

    def validate(self):
        return subprocess.run([sys.executable, str(ROOT / 'tools/verify-wazig/check-evidence.py'), str(self.folder)], capture_output=True, text=True)

    def test_complete_evidence(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PALETTE ARCHIVED EVIDENCE VERIFIED', result.stdout)

    def test_rejects_missing_row_fold_and_failures(self):
        path = self.folder / 'palette-archived.json'
        original = path.read_text()
        for mutate in [lambda m: m['a-all-telegram'].update(found=False),
                       lambda m: m['b-2-slack'].update(index=10),
                       lambda m: m['b-1-inbox-zeta'].update(matches=2),
                       lambda m: m['b-2-inbox-delta'].update(found=False)]:
            journey = json.loads(original)
            mutate({row['step']: row for row in journey['matrix']})
            path.write_text(json.dumps(journey))
            self.assertNotEqual(self.validate().returncode, 0)
        journey = json.loads(original)
        journey['failures'] = [dict(step='c-all-telegram')]
        path.write_text(json.dumps(journey))
        self.assertNotEqual(self.validate().returncode, 0)

    def test_rejects_unarchive_missing_history_and_unselected_chat(self):
        self.requests.append(dict(method='POST', authorized=True, status=200, wire_path='/v1/wazig/archive', body=dict(chat='telegram:user:7001001', archived=False)))
        self.save_requests()
        self.assertNotEqual(self.validate().returncode, 0)
        self.requests.pop()
        self.requests = [row for row in self.requests if 'messages' not in row['wire_path']]
        self.save_requests()
        self.assertNotEqual(self.validate().returncode, 0)
        self.requests.extend(self.history(chat) for chat, name in validator.ARCHIVED.values())
        self.save_requests()
        self.assertEqual(self.validate().returncode, 0)
        self.screen('c-own-telegram', selected=dict(id='other', archived=True))
        self.assertNotEqual(self.validate().returncode, 0)

    def test_rejects_rare_first_and_missing_icons(self):
        path = self.folder / 'frequency-results.json'
        frequency = json.loads(path.read_text())
        frequency['labels'].reverse()
        path.write_text(json.dumps(frequency))
        self.assertNotEqual(self.validate().returncode, 0)
        frequency['labels'].reverse()
        path.write_text(json.dumps(frequency))
        self.write('frequency-badges.json', dict.fromkeys(validator.ARCHIVED, 0))
        self.assertNotEqual(self.validate().returncode, 0)

    def test_fake_hub_serves_archived_and_inbox_rows(self):
        spec = importlib.util.spec_from_file_location('palette_hub', ROOT / 'tools/verify-wazig/fake-hub.py')
        hub = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(hub)
        server = ThreadingHTTPServer(('127.0.0.1', 0), hub.PaletteArchivedHandler)
        server.daemon_threads = True
        server.state = hub.bridge.State(self.folder / 'hub.jsonl')
        self.addCleanup(server.server_close)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        headers = {'Authorization': f'Bearer {hub.bridge.KEY}', 'Content-Type': 'application/json', 'Connection': 'close'}

        def call(method, path, body=None):
            connection = HTTPConnection('127.0.0.1', server.server_port, timeout=5)
            try:
                connection.request(method, path, json.dumps(body) if body is not None else None, headers)
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        status, inbox = call('GET', '/v1/wazig/chats?limit=500')
        self.assertEqual((status, [row['name'] for row in inbox]), (200, list(validator.INBOX.values())))
        status, archived = call('GET', '/v1/wazig/chats?archived=true&limit=500')
        self.assertEqual([row['name'] for row in archived], [name for chat, name in validator.ARCHIVED.values()])
        self.assertEqual([row['jid'] for row in archived], [chat for chat, name in validator.ARCHIVED.values()])
        self.assertTrue(all(row['archived'] for row in archived) and not any(row['archived'] for row in inbox))
        self.assertEqual({row['provider'] for row in inbox + archived}, {'whatsapp', 'telegram', 'slack', 'signal'})
        for chat, name in validator.ARCHIVED.values():
            status, rows = call('GET', '/v1/wazig/messages?chat=' + chat.replace(':', '%3A'))
            self.assertEqual((status, rows[0]['ChatJID']), (200, chat))
        self.assertEqual(call('GET', '/v1/wazig/messages?chat=nope')[0], 404)
        self.assertEqual(call('POST', '/v1/wazig/archive', dict(chat='x', archived=False))[0], 200)
        logged = [json.loads(line) for line in (self.folder / 'hub.jsonl').read_text().splitlines()]
        self.assertTrue(any(row['method'] == 'POST' and row['wire_path'] == '/v1/wazig/archive' and row['body']['chat'] == 'x' for row in logged))

    def test_journey_wiring_and_selectors(self):
        journey = (ROOT / 'tools/verify-wazig/palette-archived.ps1').read_text(encoding='utf-8')
        runner = (ROOT / 'tools/verify-wazig/run.ps1').read_text(encoding='utf-8')
        registry = json.loads((ROOT / 'tools/verify-wazig/journeys.json').read_text())
        entry = next(row for row in registry['journeys'] if row['name'] == 'palette-archived')
        self.assertEqual(entry['chats'], 4)
        self.assertIn('$journey.chats', runner)
        runner += (ROOT / 'tools/verify-wazig' / entry['script']).read_text()
        self.assertIn('Invoke-PaletteArchivedJourney $session', runner)
        for required in ["'1064'", "'1072'", 'Read-ListLabels', 'Get-PaletteWindow', "'%i'", 'view_order', 'selected.id', '/v1/wazig/archive', '/v1/wazig/messages']:
            self.assertIn(required, journey)
        for forbidden in ['WM_COMMAND', 'SendMessage', 'PostMessage', 'Start-Sleep', '/fixture/']:
            self.assertNotIn(forbidden, journey)


if __name__ == '__main__':
    unittest.main()

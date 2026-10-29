import ast
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SlackSortEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.write('session.json', dict(feature='slack-sort', sha256='synthetic-hash', commit='synthetic-commit'))
        self.write('result.json', dict(feature='slack-sort', status='passed'))
        initial = dict(zip(['fixture-alpha', 'fixture-gamma', 'fixture-beta', 'fixture-unknown'],
                           ['2026-01-01T01:00:00Z', '2026-01-01T02:00:00Z', '2026-01-01T03:00:00Z', '']))
        orders = dict(before=['fixture-beta', 'fixture-gamma', 'fixture-alpha', 'fixture-unknown'],
                      after=['fixture-alpha', 'fixture-beta', 'fixture-gamma', 'fixture-unknown'],
                      sent=['fixture-gamma', 'fixture-alpha', 'fixture-beta', 'fixture-unknown'])
        for stage, order in orders.items():
            times = dict(initial)
            if stage != 'before':
                times['fixture-alpha'] = '2026-01-01T04:00:00Z'
            if stage == 'sent':
                times['fixture-gamma'] = '2026-01-01T05:00:00Z'
            self.write(f'{stage}.chats.json', dict(total=4, chats=[dict(id=chat, provider='slack', last_message_time=times[chat]) for chat in order]))
            self.write(f'{stage}.navigation.json', order)
            self.write(f'{stage}.state.json', dict(view='slack', selected=dict(id='fixture-gamma')))
            (self.folder / f'{stage}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'fixture' * 2000)
            (self.folder / f'{stage}.uia.txt').write_text('MessagesZig | Combined inbox - Postbox v0.0.526')
        (self.folder / 'hub-proof.log').write_text('\n'.join(f'slack-sort {stage}-last-message-order PASS' for stage in orders))
        requests = [dict(method='SSE', kind='msg', wire_path='/v1/wazig/events'),
                    dict(method='POST', authorized=True, wire_path='/fixture/live', status=200),
                    dict(method='POST', authorized=True, wire_path='/v1/wazig/send', status=200,
                         body=dict(chat='fixture-gamma', text='Synthetic Slack outgoing'))]
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in requests))
        self.write('side-effects.json', dict(chat_count=4, pending_sends=0, pending_archives=0, sync='stopped', slack_connected=False,
                                            production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'actions.log').write_text('\n'.join('keys: ' + key for key in ['^2', '^{TAB}', '^+{TAB}', 'Compose message', 'Synthetic Slack outgoing', '{ENTER}']))
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: synthetic validator input')
        (self.folder / 'result.txt').write_text('JOURNEY PASSED: slack-sort')
        wa_orders = {'wa-before': ['wa-beta', 'wa-gamma', 'wa-alpha', 'wa-unknown'],
                     'wa-sent': ['wa-gamma', 'wa-beta', 'wa-alpha', 'wa-unknown'],
                     'wa-stale': ['wa-gamma', 'wa-beta', 'wa-alpha', 'wa-unknown'],
                     'wa-phone': ['wa-alpha', 'wa-gamma', 'wa-beta', 'wa-unknown']}
        for stage, order in wa_orders.items():
            times = {chat.replace('fixture-', 'wa-'): stamp for chat, stamp in initial.items()}
            if stage != 'wa-before':
                times['wa-gamma'] = '2026-01-01T05:00:00'
            if stage == 'wa-phone':
                times['wa-alpha'] = '2026-01-01T06:00:00'
            self.write(f'{stage}.chats.json', dict(chats=[dict(id=chat, provider='whatsapp', last_message_time=times[chat]) for chat in order]))
            (self.folder / f'{stage}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'fixture' * 2000)
            with (self.folder / 'hub-proof.log').open('a') as stream:
                stream.write(f'\nslack-sort {stage}-last-message-order PASS')
        self.write('stale-provider.json', {'wa-gamma': '2026-01-01T02:00:00Z'})
        with (self.folder / 'bridge-requests.jsonl').open('a') as stream:
            for row in [dict(method='POST', authorized=True, wire_path='/v1/wazig/send', status=200,
                             body=dict(chat='wa-gamma', text='https://example.com/sent-order')),
                        dict(method='POST', authorized=True, wire_path='/fixture/phone', status=200)]:
                stream.write('\n' + json.dumps(row))


    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value), encoding='utf-8')

    def validate(self):
        return subprocess.run([sys.executable, str(ROOT / 'tools/verify-wazig/check-evidence.py'), str(self.folder)], capture_output=True, text=True)

    def test_complete_synthetic_evidence_passes(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EVIDENCE VERIFIED: Slack last message ordering', result.stdout)

    def test_rejects_false_order_time_navigation_status_and_isolation(self):
        cases = [('before.chats.json', lambda v: v['chats'].reverse()),
                 ('after.chats.json', lambda v: v['chats'][3].update(last_message_time='2026-01-01T06:00:00Z')),
                 ('sent.navigation.json', lambda v: v.reverse()),
                 ('result.json', lambda v: v.update(status='failed')),
                 ('after.state.json', lambda v: v.update(selected=dict(id='fixture-alpha'))),
                 ('side-effects.json', lambda v: v.update(pending_sends=1)),
                 ('wa-sent.chats.json', lambda v: v['chats'].reverse()),
                 ('wa-stale.chats.json', lambda v: v['chats'][0].update(last_message_time='2026-01-01T02:00:00Z')),
                 ('wa-phone.chats.json', lambda v: v['chats'].reverse()),
                 ('stale-provider.json', lambda v: v.update({'wa-gamma': '2026-01-01T06:00:00Z'}))]
        for name, mutate in cases:
            with self.subTest(name=name):
                path = self.folder / name
                original = path.read_text()
                value = json.loads(original)
                mutate(value)
                self.write(name, value)
                self.assertNotEqual(self.validate().returncode, 0)
                path.write_text(original)

    def test_rejects_missing_screenshot_and_incoming_delivery(self):
        (self.folder / 'after.png').unlink()
        self.assertNotEqual(self.validate().returncode, 0)
        (self.folder / 'after.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'fixture' * 2000)
        path = self.folder / 'bridge-requests.jsonl'
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        path.write_text('\n'.join(json.dumps(row) for row in rows if row['method'] != 'SSE'))
        self.assertNotEqual(self.validate().returncode, 0)

    def test_fixture_python_syntax(self):
        ast.parse((ROOT / 'tools/verify-wazig/fake-hub.py').read_text())


class SlackArchiveEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.session = dict(feature='slack-archive', sha256='synthetic-hash', commit='synthetic-commit',
                            pid=42, startTicks='2', root='synthetic-profile', id='synthetic-id')
        self.write('session.json', self.session)
        self.write('result.json', dict(feature='slack-archive', status='passed'))
        self.target = dict(id='fixture-alpha', account='fixture-account', provider='slack', archived=False, unread_count=0,
                           archive_label='', last_message_time='2026-01-01T01:00:00Z')
        other = dict(self.target, id='fixture-beta')
        incoming = dict(self.target, unread_count=1, last_message_time='2026-01-01T02:00:00Z')
        rearchived = dict(incoming, archived=True, archive_label='Archived', unread_count=0)
        stages = dict(before=(False, [self.target, other]),
                      archived=(True, [dict(self.target, archived=True, archive_label='Archived')]),
                      rearchived=(True, [rearchived]), restart=(True, [rearchived]),
                      unarchived=(False, [dict(rearchived, archived=False, archive_label=''), other]),
                      **{'incoming-inbox': (False, [incoming, other]), 'incoming-archive-empty': (True, []),
                         'unarchived-archive': (True, [])})
        for stage in ['archived-inbox', 'before-incoming', 'rearchived-inbox', 'restart-inbox']:
            stages[stage] = (False, [other])
        for stage, (archived, rows) in stages.items():
            self.write(f'{stage}.state.json', dict(show_archived=archived, chat_count=len(rows), pending_archives=0, pending_sends=0, selected=self.target))
            self.write(f'{stage}.chats.json', dict(archived=archived, total=len(rows), chats=rows))
            (self.folder / f'{stage}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'fixture' * 2000)
            (self.folder / f'{stage}.uia.txt').write_text('MessagesZig | Combined inbox - Postbox v0.0.526')
        self.write('restart.json', dict(old_pid=41, old_start='1', new_pid=42, new_start='2', root=self.session['root'], id=self.session['id'], sha256=self.session['sha256']))
        for name, row in [('slack-archive-state.txt', self.target), ('slack-rearchive-state.txt', rearchived)]:
            (self.folder / name).write_text('\t'.join([row['provider'], row['account'], row['id'], '0', row['last_message_time']]) + '\n')
        self.requests = [
            dict(method='POST', path='/fixture/live', wire_path='/fixture/live', authorized=True, incoming=1),
            dict(method='SSE', path='/v1/wazig/events', wire_path='/v1/wazig/events', kind='msg', chat='fixture-alpha',
                 incoming=1, ts=incoming['last_message_time']),
            dict(method='GET', path='/v1/wazig/chats?archived=false', wire_path='/v1/wazig/chats?archived=false', authorized=True,
                 incoming=1, archived=False, rows=[dict(jid='fixture-alpha', archived=False, unread_count=1,
                                                      last_message_ts=incoming['last_message_time'])])]
        self.write_requests()
        self.write('side-effects.json', dict(chat_count=2, show_archived=False, pending_sends=0, pending_archives=0, sync='stopped', slack_connected=False,
                                            production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'actions.log').write_text('\n'.join('keys: ' + key for key in ['^2', '^+{HOME}', '^e', 'Show archived chats', 'Show inbox chats', 'Refresh', '^e', '^e']) + '\n')
        (self.folder / 'hub-proof.log').write_text('slack-archive local-archive-incoming-restart-unarchive PASS')
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: synthetic validator input')
        (self.folder / 'result.txt').write_text('JOURNEY PASSED: slack-archive')

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value), encoding='utf-8')

    def write_requests(self):
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in self.requests))

    def validate(self):
        return subprocess.run([sys.executable, str(ROOT / 'tools/verify-wazig/check-evidence.py'), str(self.folder)], capture_output=True, text=True)

    def test_complete_evidence_passes(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EVIDENCE VERIFIED: local Slack archive', result.stdout)

    def test_rejects_archive_request_even_when_failed(self):
        for method in ['GET', 'POST']:
            self.requests.append(dict(method=method, path='/v1/wazig/archive', wire_path='/v1/wazig/archive', authorized=True, status=400, body=dict(chat='fixture-alpha')))
            self.write_requests()
            self.assertNotEqual(self.validate().returncode, 0)
            self.requests.pop()

    def test_rejects_sticky_archive_lost_restart_wrong_account_and_incomplete_unarchive(self):
        for name, mutate in [
            ('incoming-inbox.chats.json', lambda v: v['chats'][0].update(archived=True, archive_label='Archived')),
            ('restart.chats.json', lambda v: v['chats'][0].update(archived=False)),
            ('incoming-inbox.chats.json', lambda v: v['chats'][0].update(account='another-account')),
            ('unarchived.chats.json', lambda v: v['chats'][0].update(archived=True)),
            ('result.json', lambda v: v.update(status='failed')),
            ('restart.json', lambda v: v.update(root='another-profile'))]:
            with self.subTest(name=name):
                path = self.folder / name
                original = path.read_text()
                value = json.loads(original)
                mutate(value)
                self.write(name, value)
                self.assertNotEqual(self.validate().returncode, 0)
                path.write_text(original)

    def test_rejects_missing_live_delivery_and_false_provider_archive_flag(self):
        original = list(self.requests)
        for method in ['POST', 'SSE']:
            with self.subTest(method=method):
                self.requests = [row for row in original if row['method'] != method]
                self.write_requests()
                self.assertNotEqual(self.validate().returncode, 0)
        self.requests = original
        self.requests[-1]['rows'][0]['archived'] = True
        self.write_requests()
        self.assertNotEqual(self.validate().returncode, 0)

    def test_rejects_keep_archived_state(self):
        for name in ['slack-archive-state.txt', 'slack-rearchive-state.txt']:
            with self.subTest(name=name):
                path = self.folder / name
                original = path.read_text()
                fields = original.rstrip('\n').split('\t')
                fields[3] = '1'
                path.write_text('\t'.join(fields) + '\n')
                self.assertNotEqual(self.validate().returncode, 0)
                path.write_text(original)

    def test_rejects_kept_archived_label(self):
        for stage in ['archived', 'rearchived', 'restart']:
            with self.subTest(stage=stage):
                name = f'{stage}.chats.json'
                path = self.folder / name
                original = path.read_text()
                value = json.loads(original)
                value['chats'][0]['archive_label'] = 'Kept archived'
                self.write(name, value)
                self.assertNotEqual(self.validate().returncode, 0)
                path.write_text(original)

    def test_rejects_missing_required_screenshot(self):
        (self.folder / 'restart.png').unlink()
        self.assertNotEqual(self.validate().returncode, 0)

    def test_fake_hub_delivers_one_newer_message_and_unarchived_rows(self):
        import importlib.util
        import io
        from types import SimpleNamespace

        spec = importlib.util.spec_from_file_location('archive_fixture', ROOT / 'tools/verify-wazig/fake-hub.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        handler = object.__new__(module.SlackArchiveHandler)
        state = module.bridge.State(self.folder / 'fixture.jsonl')
        state.archive_incoming = 0
        handler.server = SimpleNamespace(state=state)
        handler.headers = {'Content-Length': '2'}
        handler.authorized = lambda: True
        replies = []
        handler.respond = lambda status, data, **extra: replies.append((status, data, extra))
        handler.wfile = io.BytesIO()
        handler.path = '/fixture/live'
        handler.rfile = io.BytesIO(b'{}')
        handler.do_POST()
        self.assertEqual(state.archive_incoming, 1)
        handler.event(2, 'msg', 1)
        handler.path = '/v1/wazig/chats?archived=false'
        handler.do_GET()
        alpha = replies[-1][1][0]
        self.assertFalse(alpha['archived'])
        self.assertEqual(alpha['unread_count'], 1)
        self.assertGreater(alpha['last_message_ts'], handler.stamp(0))
        handler.path = '/v1/wazig/messages?chat=fixture-alpha'
        handler.do_GET()
        self.assertEqual(len({row['MsgID'] for row in replies[-1][1]}), 2)
        self.assertEqual(handler.wfile.getvalue().count(b'"kind": "msg"'), 1)


if __name__ == '__main__':
    unittest.main()

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
            (self.folder / f'{stage}.uia.txt').write_text('MessagesZig | Wazig Messages v0.0.526')
        (self.folder / 'hub-proof.log').write_text('\n'.join(f'slack-sort {stage}-last-message-order PASS' for stage in orders))
        requests = [dict(method='SSE', kind='msg', wire_path='/v1/wazig/events'),
                    dict(method='POST', authorized=True, wire_path='/fixture/live', status=200),
                    dict(method='POST', authorized=True, wire_path='/v1/wazig/send', status=200,
                         body=dict(chat='fixture-gamma', text='Synthetic Slack outgoing'))]
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in requests))
        self.write('side-effects.json', dict(chat_count=4, pending_sends=0, pending_archives=0, sync='stopped', slack_connected=False,
                                            production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'actions.log').write_text('\n'.join('keys: ' + key for key in ['%1', '^{TAB}', '^+{TAB}', 'Compose message', 'Synthetic Slack outgoing', '{ENTER}']))
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: synthetic validator input')
        (self.folder / 'result.txt').write_text('JOURNEY PASSED: slack-sort')

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
                 ('side-effects.json', lambda v: v.update(pending_sends=1))]
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


if __name__ == '__main__':
    unittest.main()

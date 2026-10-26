import ast
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PARENT = '1740000000.000100'


class SlackThreadsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.write('session.json', dict(feature='slack-threads', sha256='synthetic-hash', commit='synthetic-commit', pid=2, root='fixture', id='fixture-id'))
        self.write('result.json', dict(feature='slack-threads', status='passed'))
        self.write('restart.json', dict(old_start='1', new_start='2', new_pid=2, root='fixture', id='fixture-id', sha256='synthetic-hash'))
        base = dict(parent_id=PARENT, parent_reply_line='30 replies', inline_replies=0, threads_option='on', open=False, replies=0)
        for stage in ['threads-on', 'thread-panel', 'thread-reply', 'threads-off', 'threads-restart']:
            state = dict(base)
            if stage in ('thread-panel', 'thread-reply'):
                state.update(open=True, replies=30)
            if stage in ('threads-off', 'threads-restart'):
                state.update(parent_reply_line='', inline_replies=30, threads_option='off')
            self.write(f'{stage}.state.json', dict(selected=dict(provider='slack', id='slack:fixture-threads:channel'), slack_threads=state))
            if stage != 'thread-reply':
                self.write(f'{stage}.json', dict(state, **({'restarted': True} if stage == 'threads-restart' else {})))
            (self.folder / f'{stage}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'fixture' * 2000)
            (self.folder / f'{stage}.uia.txt').write_text('MessagesZig | Combined inbox - Wazig v0.0.526')
        self.requests = [dict(method='POST', authorized=True, wire_path='/v1/wazig/send', status=200,
                             body=dict(chat='slack:fixture-threads:channel', text='Synthetic thread reply', reply_to=PARENT))]
        self.save_requests()
        self.write('side-effects.json', dict(pending_sends=0, pending_archives=0, sync='stopped', production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'actions.log').write_text('\n'.join('keys: ' + key for key in ['^2', '^{UP}', '{ENTER}', 'Synthetic thread reply', '{ESC}', '^k', 'Slack threads like Slack for this account', 'Quit Messages']))
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: synthetic validator input')
        (self.folder / 'result.txt').write_text('JOURNEY PASSED: slack-threads')

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value), encoding='utf-8')

    def save_requests(self):
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in self.requests))

    def validate(self):
        return subprocess.run([sys.executable, str(ROOT / 'tools/verify-wazig/check-evidence.py'), str(self.folder)], capture_output=True, text=True)

    def test_complete_evidence(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EVIDENCE VERIFIED: Slack threads', result.stdout)

    def test_rejects_broken_feature_measurements_and_restart(self):
        cases = [('threads-on.json', dict(inline_replies=30)), ('threads-on.json', dict(parent_reply_line='')),
                 ('thread-panel.json', dict(replies=29)), ('thread-panel.json', dict(open=False)),
                 ('threads-off.json', dict(inline_replies=0)), ('threads-off.json', dict(parent_reply_line='30 replies')),
                 ('threads-restart.json', dict(threads_option='on')), ('threads-restart.json', dict(restarted=False)),
                 ('restart.json', dict(new_start='1')), ('result.json', dict(status='failed')),
                 ('side-effects.json', dict(pending_sends=1))]
        for name, mutation in cases:
            with self.subTest(name=name, mutation=mutation):
                path = self.folder / name
                original = path.read_text()
                self.write(name, dict(json.loads(original), **mutation))
                self.assertNotEqual(self.validate().returncode, 0)
                path.write_text(original)

    def test_rejects_unscoped_send(self):
        self.requests[0]['body']['reply_to'] = ''
        self.save_requests()
        self.assertNotEqual(self.validate().returncode, 0)

    def test_rejects_missing_screenshot_and_cleanup(self):
        for name in ['thread-panel.png', 'cleanup.txt']:
            path = self.folder / name
            original = path.read_bytes()
            path.unlink()
            self.assertNotEqual(self.validate().returncode, 0)
            path.write_bytes(original)

    def test_fixture_has_exactly_thirty_replies_and_two_normal_messages(self):
        spec = importlib.util.spec_from_file_location('thread_fixture', ROOT / 'tools/verify-wazig/fake-hub.py')
        fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture)
        rows = fixture.thread_rows()
        self.assertEqual(len(rows), 33)
        self.assertEqual(sum(row.get('thread_ts') == PARENT for row in rows), 30)
        parent, = [row for row in rows if row['MsgID'] == PARENT]
        self.assertEqual(parent['reply_count'], 30)
        self.assertEqual(len({row['MsgID'] for row in rows}), 33)
        ast.parse((ROOT / 'tools/verify-wazig/fake-hub.py').read_text())

    def test_single_chat_baseline_and_native_edit_keyboard_routing(self):
        runner = (ROOT / 'tools/verify-wazig/run.ps1').read_text()
        registry = json.loads((ROOT / 'tools/verify-wazig/journeys.json').read_text())
        entry = next(row for row in registry['journeys'] if row['name'] == 'slack-threads')
        self.assertEqual(entry['chats'], 1)
        self.assertIn('$journey.chats', runner)
        runner += (ROOT / 'tools/verify-wazig' / entry['script']).read_text()
        source = (ROOT / 'src/main.zig').read_text()
        keyboard = source.split('fn handleKeyboard(', 1)[1].split('fn jumpToLatestMessage(', 1)[0]
        self.assertLess(keyboard.index('sendMessageFrom(a, true);'), keyboard.index('if (a.thread_compose != null and focus == a.thread_compose.?) return false;'))
        self.assertLess(keyboard.index('if (a.thread_compose != null and focus == a.thread_compose.?) return false;'), keyboard.index("if (key == win.VK_RETURN or key == 'C')"))
        self.assertIn('pending.reply_to.set(reply_to);', source)
        self.assertIn('const reply_to = if (thread) a.thread_parent.slice() else a.reply_to.slice();', source)
        self.assertIn('if (chat.provider == .slack)', source.split('fn applyMessageData(', 1)[1])
        self.assertIn('slack.threadsSettingKey(a.allocator, slackThreadsAccount(a))', source)

    def test_journey_requires_missing_current_app_state(self):
        journey = (ROOT / 'tools/verify-wazig/slack-threads.ps1').read_text()
        self.assertIn('.slack_threads.parent_reply_line', journey)
        self.assertIn("'30 replies'", journey)


if __name__ == '__main__':
    unittest.main()

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PARENT = '1740000000.000100'
CHAT = 'slack:fixture-threads:channel'
STAGES = ['broadcast-unticked', 'broadcast-ticked', 'broadcast-reset', 'broadcast-thread-result', 'broadcast-chat-result']


def source(name):
    return (ROOT / name).read_text(encoding='utf-8')


def function(text, name):
    start = text.index(f'fn {name}(')
    return text[start:text.index('\nfn ', start + 1)]


class SlackThreadBroadcastEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.write('session.json', dict(feature='slack-thread-broadcast', sha256='synthetic-hash', commit='synthetic-commit', pid=2, root='fixture', id='fixture-id'))
        self.write('result.json', dict(feature='slack-thread-broadcast', status='passed'))
        base = dict(parent_id=PARENT, parent_reply_line='30 replies', inline_replies=0, loose_replies=0, threads_option='on', open=True, replies=30,
                    broadcast_shown=True, broadcast_checked=False, broadcast_label='Also send to Verification Threads')
        for stage in STAGES:
            state = dict(base)
            if stage == 'broadcast-ticked':
                state.update(broadcast_checked=True)
            if stage == 'broadcast-chat-result':
                state.update(open=False, replies=0, broadcast_shown=False, broadcast_label='')
            self.write(f'{stage}.state.json', dict(selected=dict(provider='slack', id=CHAT), slack_threads=state))
            if stage in STAGES[:3]:
                self.write(f'{stage}.json', state)
            (self.folder / f'{stage}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + stage.encode() * 2000)
            (self.folder / f'{stage}.uia.txt').write_text('MessagesZig | Combined inbox - Postbox v0.0.526')
        self.write('broadcast-messages.json', [dict(text='Synthetic broadcast reply', quoted_msg_id=PARENT), dict(text='Synthetic broadcast reply', quoted_msg_id='')])
        self.requests = [
            dict(method='POST', authorized=True, wire_path='/v1/wazig/send', status=200,
                 body=dict(chat=CHAT, text='Synthetic plain thread reply', reply_to=PARENT)),
            dict(method='POST', authorized=True, wire_path='/v1/wazig/send', status=200,
                 body=dict(chat=CHAT, text='Synthetic broadcast reply', reply_to=PARENT, reply_broadcast=True))]
        self.save_requests()
        self.write('side-effects.json', dict(pending_sends=0, pending_archives=0, sync='stopped', production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'actions.log').write_text('\n'.join('keys: ' + key for key in ['%2', '^{UP}', '{ENTER}', '{TAB}', 'Synthetic plain thread reply', 'Synthetic broadcast reply', '{ESC}', '^k', 'Refresh']))
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: synthetic validator input')
        (self.folder / 'result.txt').write_text('JOURNEY PASSED: slack-thread-broadcast')

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value), encoding='utf-8')

    def save_requests(self):
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in self.requests))

    def validate(self):
        return subprocess.run([sys.executable, str(ROOT / 'tools/verify-wazig/check-evidence.py'), str(self.folder)], capture_output=True, text=True)

    def test_complete_evidence(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EVIDENCE VERIFIED: Slack thread broadcast', result.stdout)

    def test_rejects_wrong_checkbox_state_and_label(self):
        cases = [('broadcast-unticked.json', dict(broadcast_checked=True)), ('broadcast-ticked.json', dict(broadcast_checked=False)),
                 ('broadcast-reset.json', dict(broadcast_checked=True)), ('broadcast-unticked.json', dict(broadcast_shown=False)),
                 ('broadcast-unticked.json', dict(broadcast_label='Also send to the chat')),
                 ('result.json', dict(status='failed')), ('side-effects.json', dict(pending_sends=1))]
        for name, mutation in cases:
            with self.subTest(name=name, mutation=mutation):
                path = self.folder / name
                original = path.read_text()
                self.write(name, dict(json.loads(original), **mutation))
                self.assertNotEqual(self.validate().returncode, 0)
                path.write_text(original)

    def test_rejects_wrong_hub_flag(self):
        for index, mutation in [(0, dict(reply_broadcast=True)), (1, dict(reply_broadcast=False)), (1, dict(reply_to=''))]:
            with self.subTest(index=index, mutation=mutation):
                saved = json.loads(json.dumps(self.requests))
                self.requests[index]['body'].update(mutation)
                self.save_requests()
                self.assertNotEqual(self.validate().returncode, 0)
                self.requests = saved
                self.save_requests()
        self.requests[1]['body'].pop('reply_broadcast')
        self.save_requests()
        self.assertNotEqual(self.validate().returncode, 0)

    def test_rejects_missing_chat_row_and_screenshot(self):
        self.write('broadcast-messages.json', [dict(text='Synthetic broadcast reply', quoted_msg_id=PARENT)])
        self.assertNotEqual(self.validate().returncode, 0)
        self.write('broadcast-messages.json', [dict(text='Synthetic broadcast reply', quoted_msg_id=PARENT), dict(text='Synthetic broadcast reply', quoted_msg_id='')])
        for name in ['broadcast-ticked.png', 'cleanup.txt']:
            path = self.folder / name
            original = path.read_bytes()
            path.unlink()
            self.assertNotEqual(self.validate().returncode, 0)
            path.write_bytes(original)

    def test_fixture_rejects_a_flag_that_does_not_match_the_text(self):
        spec = importlib.util.spec_from_file_location('broadcast_fixture', ROOT / 'tools/verify-wazig/fake-hub.py')
        fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture)
        self.assertEqual(fixture.BROADCAST_TEXT, 'Synthetic broadcast reply')
        handler = source('tools/verify-wazig/fake-hub.py').split('class SlackThreadBroadcastHandler', 1)[1].split('\nTICK_CHATS', 1)[0]
        self.assertIn("(text == BROADCAST_PLAIN and 'reply_broadcast' not in body)", handler)
        self.assertIn('(text == BROADCAST_TEXT and broadcast is True)', handler)
        self.assertIn('BROADCAST_CHANNEL_ID', handler)


class SlackThreadBroadcastSourceTests(unittest.TestCase):
    def test_flag_travels_from_entry_to_hub_body(self):
        outbox = source('src/outbox.zig')
        self.assertIn('reply_broadcast: bool = false,', outbox)
        self.assertIn('.reply_broadcast = if (entry.reply_broadcast) true else null', outbox)
        self.assertIn('.emit_null_optional_fields = false', outbox)
        snapshot = source('src/unified_snapshot.zig')
        self.assertIn('reply_broadcast: ?bool = null,', snapshot)
        self.assertIn('wire.reply_broadcast orelse false', snapshot)
        self.assertIn('if (e.reply_broadcast and (e.reply_to.len == 0 or e.file.len != 0)) return false;', snapshot)
        hub = source('src/hub.zig')
        self.assertIn('pub fn sendBroadcast(', hub)
        self.assertIn('.reply_broadcast = true', hub)
        self.assertIn('if (reply_to.len == 0) return error.InvalidSend;', hub)
        main = source('src/main.zig')
        self.assertIn('entry.reply_broadcast = thread and a.thread_broadcast and key.provider == .slack;', main)
        self.assertIn('job.reply_broadcast = record.entry.reply_broadcast;', main)
        self.assertIn('if (job.reply_broadcast) hub.sendBroadcast(', main)

    def test_plain_send_keeps_the_old_hub_request(self):
        hub = source('src/hub.zig')
        send = hub.split('pub fn send(', 1)[1].split('\npub fn sendBroadcast(', 1)[0]
        self.assertNotIn('reply_broadcast', send)
        self.assertIn('reply_broadcast', source('src/hub_test.zig'))

    def test_checkbox_resets_and_is_slack_hub_only(self):
        main = source('src/main.zig')
        self.assertIn('return unifiedHub(a) and a.thread_parent.len > 0 and a.selected_chat < a.chat_count and a.chats[a.selected_chat].provider == .slack;', main)
        self.assertIn('thread_broadcast: bool = false,', main)
        send = function(main, 'sendUnifiedMessage')
        self.assertIn('a.thread_broadcast = false;', send)
        close = function(main, 'closeSlackThread')
        self.assertIn('a.thread_broadcast = false;', close)
        self.assertIn('label.set(a.allocator, "Also send to ");', main)

    def test_checkbox_is_custom_drawn_and_keyboard_reachable(self):
        main = source('src/main.zig')
        paint = function(main, 'threadCheckProc')
        self.assertIn('smooth.fillRoundRect(&shapes, box, corner, corner, theme.current.primary);', paint)
        self.assertIn('smooth.strokeRoundRect(&shapes, box, corner, corner, theme.current.outline, px(a, 2));', paint)
        self.assertIn('theme.radius_inline', paint)
        for raw in ['win.RoundRect(', 'win.Ellipse(', 'win.CreateRoundRectRgn(']:
            self.assertNotIn(raw, paint)
        self.assertIn('win.GetFocus() == hwnd', paint)
        keyboard = main.split('fn handleKeyboard(', 1)[1].split('fn jumpToLatestMessage(', 1)[0]
        self.assertIn('toggleThreadBroadcast(a);', keyboard)
        self.assertIn('key == win.VK_TAB', keyboard)
        self.assertIn('lit("MessagesThreadCheck")', main)

    def test_status_exposes_the_checkbox_for_the_journey(self):
        status = function(source('src/main.zig'), 'controlSlackThreads')
        for field in ['broadcast_shown', 'broadcast_checked', 'broadcast_label']:
            self.assertIn(field, status)

    def test_journey_is_registered_for_pull_requests(self):
        registry = json.loads(source('tools/verify-wazig/journeys.json'))
        entry = next(row for row in registry['journeys'] if row['name'] == 'slack-thread-broadcast')
        self.assertTrue(entry['pr'] and entry['evidence'])
        self.assertEqual(entry['hub'], 'slack-thread-broadcast')
        self.assertEqual(entry['hub_handler']['class'], 'SlackThreadBroadcastHandler')
        journey = source('tools/verify-wazig/slack-thread-broadcast.ps1')
        for fragment in ['broadcast_checked', "'Also send to Verification Threads'", "'{TAB}'", 'reply_broadcast', 'broadcast-chat-result']:
            self.assertIn(fragment, journey)


if __name__ == '__main__':
    unittest.main()

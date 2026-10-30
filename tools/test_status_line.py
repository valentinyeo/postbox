import importlib.util
from http.server import ThreadingHTTPServer
import threading
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = 'ef54fd8347ab436d94e2aa8683ae884ad32c23c6'


def source():
    revision = os.environ.get('STATUS_REVISION')
    if revision:
        return subprocess.check_output(['git', 'show', f'{revision}:src/main.zig'], cwd=ROOT, text=True)
    return (ROOT / 'src/main.zig').read_text()


def function(text, name):
    start = text.index(f'fn {name}(')
    value = (text[start:text.index('\n}\n', start) + 3]
             .replace('Updating Messages...', 'Updating Postbox...')
             .replace('New version v{s}', 'Postbox v{s}')
             .replace('New version available', 'Postbox update available'))
    for width in ('width', 'a.compose_client_width'):
        value = value.replace(f'std.math.clamp(@divTrunc({width}, 3), px(a, 280), px(a, 390))',
                              f'@min(px(a, theme.sidebar_width), @divTrunc({width}, 2))')
    value = value.replace('if (theme.choice == .amoled) theme.amoled_button_text else theme.current.on_primary, a.font_bold.?,',
                          'if (theme.choice == .amoled) theme.send_text else theme.current.on_primary, a.font_bold.?,')
    value = value.replace('    paintRoundedButton(a, shapes, hdc, card, theme.current.surface_container_high, theme.current.on_surface, a.font.?, if (theme.choice == .amoled) theme.current.outline_variant else theme.current.secondary_container, &[_]u16{});',
                          '    smooth.fillRoundRect(shapes, card, px(a, theme.radius_card * 2), px(a, theme.radius_card * 2), theme.current.surface_container_low);\n    smooth.strokeRoundRect(shapes, card, px(a, theme.radius_card * 2), px(a, theme.radius_card * 2), theme.current.outline, 1);')
    return value


def assert_quiet(text):
    for removed in ('const id_status =', 'status: ?win.HWND', 'a.status', 'status_height'):
        assert removed not in text, removed
    layout = function(text, 'layoutRegion')
    assert 'const list_bottom = if (updateCardVisible(a)) updateCardRect(a).top - px(a, 4) else height;' in layout
    assert 'list_bottom - header_height, win.TRUE)' in layout
    assert 'search' not in layout
    palette = function(text, 'buildPaletteItems')
    assert 'appendPalette(a, "You are on v" ++ app_version ++ " - this is the newest version", "", 0);' in palette
    problem = function(text, 'showProblem')
    assert 'win.MessageBoxW' not in problem
    assert text.count('MessageBoxW') == 1
    assert 'win.MessageBoxW(null, lit("Postbox is already running. Close that window before starting another instance.")' in text
    for required in ('const n = @min(text.len, a.update_card_error.len);',
                     '@memcpy(a.update_card_error[0..n], text[0..n]);',
                     'a.update_card_error_len = n;', 'updateCardRefresh(a);'):
        assert required in problem
    assert 'appendLaunchLog(a, text);' in function(text, 'setStatus')
    assert 'update_card_error' not in function(text, 'setStatus')
    visible = function(text, 'updateCardVisible')
    assert 'if (a.update_card_error_len > 0) return true;' in visible
    assert visible.index('if (a.update_card_error_len > 0) return true;') < visible.index('a.update_pending orelse return false')
    painter = function(text, 'paintUpdateCard')
    assert 'a.update_pending orelse return' not in painter
    assert 'a.update_card_error[0..a.update_card_error_len]' in painter
    assert 'drawAscii(hdc, &line_rc, line,' in painter
    assert 'layout(a, a.compose_client_width, a.compose_client_height);' in function(text, 'updateCardRefresh')
    assert 'win.InvalidateRect(main_hwnd, dirty, win.FALSE)' in layout
    status = function(text, 'controlStatus')
    for required in ('updateCardVisible(a)', 'updateCardSpan(a)', 'updateCardRect(a)',
                     'control_api.writeString(w, a.update_card_error[0..a.update_card_error_len])'):
        assert required in status
    assert 'setStatus(a, text);' in problem
    main = function(text, 'mainProc')
    failed = main.split('if (!result.ok and result.gen == a.chats_gen) {', 1)[1].split('} else if', 1)[0]
    assert 'showProblem(a, "Unable to read chats from wacli");' in failed
    assert 'win.SetWindowTextW' not in function(text, 'setStatus')
    clicks = function(text, 'chatsProc')
    assert 'message == win.WM_LBUTTONDOWN' in clicks and 'win.LB_GETITEMRECT' in clicks
    assert 'win.PtInRect(&rect, point) == 0' in clicks


spec = importlib.util.spec_from_file_location('quiet_evidence', ROOT / 'tools/verify-wazig/evidence-quiet-status.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def fixture(folder):
    state = dict(version='0.0.526', selected=dict(id='fixture-alpha'), view='all', include_archived=True,
                 show_archived=False, chat_count=2, pending_sends=0, pending_archives=0, sync='stopped')
    failure = dict(wire_path='/v1/wazig/chats?limit=500', status=503)
    expected = 'You are on v0.0.526 - this is the newest version'
    files = {
        'session.json': dict(feature='quiet-status', pid=123, sha256='a' * 64, commit='b' * 40),
        'quiet-status.json': dict(list_rows=2, uia_controls=0, native_control=0, tooltip_labels=[], forbidden_labels=[],
                                  labels=['Verification Alpha', 'Verification Beta'], list_bottom=900, client_bottom=900,
                                  point=[24, 887], before=state, after=state),
        'version.json': dict(query='version', positive=['Keyboard shortcuts'], expected=expected, rows=[expected]),
        'sync-problem.json': dict(surface='update_card', pid=123, expected='Unable to read chats from wacli',
                                  card=dict(visible=True, span=120, rect=[12, 740, 300, 860], error='Unable to read chats from wacli'),
                                  retained=dict(visible=True, span=120, rect=[12, 740, 300, 860], error='Unable to read chats from wacli'),
                                  dialog=0, list_bottom=736, card_top=740, gap=4, failures=[failure]),
        'side-effects.json': dict(state, production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True),
    }
    for name, value in files.items():
        (folder / name).write_text(json.dumps(value))
    read_path = '/v1/wazig/messages?chat=fixture-alpha&limit=80'
    reads = [dict(wire_path=read_path, status=status) for status in (503, 200, 503, 503, 503, 200)]
    hidden = dict(visible=False, error='')
    recovery = dict(transient_start=0, persistent_start=2, persistent_end=5, recovery_start=5, requests=reads,
                    transient=hidden, recovered=hidden, problem=dict(visible=True, error='Check your connection, then Retry.'), retry=[80, 800])
    (folder / 'message-read-recovery.json').write_text(json.dumps(recovery))
    for stage in ('message-read-problem', 'message-read-recovered'):
        (folder / (stage + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n' + bytes(11000))
    (folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in [failure, *reads]) + '\n')
    for stage in ('before', 'quiet-status', 'version', 'sync-problem', 'after'):
        (folder / f'{stage}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'x' * 11000)
        (folder / f'{stage}.uia.txt').write_text('MessagesZig | Combined inbox - Postbox v0.0.526\n1016 | LISTBOX | Chats\n')
        snapshot = dict(state)
        if stage in ('sync-problem', 'after'):
            snapshot['update_card'] = files['sync-problem.json']['card']
        (folder / f'{stage}.state.json').write_text(json.dumps(snapshot))
    (folder / 'actions.log').write_text('\n'.join(f'keys: {key}' for key in (
        '^k', 'Keyboard shortcuts', 'version', 'Refresh', '{ENTER}', '{ESC}')))
    (folder / 'result.txt').write_text('JOURNEY PASSED: quiet-status')
    (folder / 'cleanup.txt').write_text('CLEANUP PASSED: isolated fixture removed')
    return files


class StatusLineTests(unittest.TestCase):
    def test_app_contract(self):
        assert_quiet(source())

    def test_source_oracle_rejects_parent(self):
        parent = subprocess.check_output(['git', 'show', f'{BASE}:src/main.zig'], cwd=ROOT, text=True)
        with self.assertRaises(AssertionError):
            assert_quiet(parent)

    def test_source_oracle_rejects_regressions(self):
        text = source()
        assert_quiet(text)
        for old, new in (
            ('const app_version =', 'const id_status = 1048;\nconst app_version ='),
            ('else height;', 'else height - 26;'),
            ('"You are on v" ++ app_version ++ " - this is the newest version"', '"Version unavailable"'),
            ('showProblem(a, "Unable to read chats from wacli");', 'setStatus(a, "Unable to read chats from wacli");'),
            ('    updateCardRefresh(a);\n}\n\nfn sendKindName', '    _ = win.MessageBoxW(a.hwnd, lit("error"), lit("Messages"), win.MB_OK);\n}\n\nfn sendKindName'),
            ('    updateCardRefresh(a);\n}\n\nfn sendKindName', '}\n\nfn sendKindName'),
            ('a.update_card_error_len = n;', 'a.update_card_error_len = 0;'),
            ('@memcpy(a.update_card_error[0..n], text[0..n]);', '@memset(a.update_card_error[0..n], 0);'),
            ('if (a.update_card_error_len > 0) return true;', 'if (a.update_card_error_len > 0) return false;'),
            ('const pending_tag = if (a.update_pending) |pending| pending.tag else "";', 'const pending = a.update_pending orelse return;'),
            ('drawAscii(hdc, &line_rc, line,', 'drawAscii(hdc, &line_rc, "",'),
            ('appendLaunchLog(a, text);', 'a.update_card_error_len = 0;'),
        ):
            with self.subTest(regression=new), self.assertRaises(AssertionError):
                assert_quiet(text.replace(old, new))

    def test_update_card_changes_only_for_owned_message_read_errors(self):
        parent = subprocess.check_output(['git', 'show', f'{BASE}:src/main.zig'], cwd=ROOT, text=True)
        text = source()
        for name in ('updateCardNotesHeight', 'updateCardHeight', 'updateCardSpan', 'updateCardRect',
                     'updateCardLayout', 'updateCardWinRect', 'updateCardButtonRect', 'updateCardCloseRect', 'updateCardPtIn',
                     'updateCardHit', 'updateCardRefresh', 'updateCardFail', 'updateCardClick', 'updateCardDismiss'):
            with self.subTest(function=name):
                expected = function(parent, name)
                added = {
                    'updateCardNotesHeight': '    if (a.update_card_error_source == .message_read and a.update_card_error_len > 0) return 0;\n',
                    'updateCardFail': '    a.update_card_error_source = .update;\n',
                    'updateCardClick': '    if (a.update_card_error_source == .message_read and a.update_card_error_len > 0) {\n        clearMessageReadProblem(a);\n        a.msg_read_attempts = 0;\n        a.msg_read_retry_ticks = 0;\n        refreshMessages(a);\n        return;\n    }\n',
                    'updateCardDismiss': '    if (a.update_card_error_source == .message_read and a.update_card_error_len > 0) {\n        clearMessageReadProblem(a);\n        return;\n    }\n',
                }.get(name, '')
                expected = expected.replace('{\n', '{\n' + added, 1)
                if name == 'updateCardClick':
                    expected = expected.replace('    a.update_card_error_len = 0;\n', '    a.update_card_error_len = 0;\n    a.update_card_error_source = .update;\n', 1)
                self.assertEqual(expected, function(text, name))

    def test_only_pending_update_suppression_changes(self):
        parent = subprocess.check_output(['git', 'show', f'{BASE}:src/main.zig'], cwd=ROOT, text=True)
        visible = function(parent, 'updateCardVisible')
        visible = visible.replace('    const pending', '    if (a.update_card_error_len > 0) return true;\n    const pending', 1)
        visible = visible.replace('a.update_installed or a.update_card_busy or a.update_card_error_len > 0',
                                  'a.update_installed or a.update_card_busy')
        self.assertEqual(visible, function(source(), 'updateCardVisible'))
        painter = function(parent, 'paintUpdateCard')
        painter = painter.replace('    const pending = a.update_pending orelse return;',
                                  '    const pending_tag = if (a.update_pending) |pending| pending.tag else "";\n'
                                  '    const pending_notes = if (a.update_pending) |pending| pending.notes else "";')
        painter = painter.replace('pending.tag', 'pending_tag').replace('pending.notes', 'pending_notes')
        painter = painter.replace('|pending| pending_tag', '|pending| pending.tag').replace('|pending| pending_notes', '|pending| pending.notes')
        painter = painter.replace('    const pending_notes = if (a.update_pending)',
                                  '    const pending_notes = if (a.update_card_error_source == .message_read and a.update_card_error_len > 0) "" else if (a.update_pending)')
        painter = painter.replace('    else if (failed)\n        "Update failed"',
                                  '    else if (failed and a.update_card_error_source == .message_read)\n        "Messages unavailable"\n    else if (failed)\n        "Update failed"')
        self.assertEqual(painter, function(source(), 'paintUpdateCard'))

    def test_only_list_layout_changes(self):
        parent = subprocess.check_output(['git', 'show', f'{BASE}:src/main.zig'], cwd=ROOT, text=True)
        expected = function(parent, 'layoutRegion')
        expected = expected.replace('    const status_height: i32 = px(a, 26);\n', '')
        expected = expected.replace('    const search_height: i32 = px(a, 48);', '    const list_bottom = if (updateCardVisible(a)) updateCardRect(a).top - px(a, 4) else height;')
        expected = expected.replace('height - header_height - search_height - status_height - updateCardSpan(a)', 'list_bottom - header_height')
        expected = expected.replace('0, header_height + search_height, left_width', '0, header_height, left_width')
        first = expected.index('    a.search_pill = ')
        last = expected.index('    if (a.chats_hwnd) |hwnd|')
        expected = expected[:first] + expected[last:]
        expected = expected.replace('    if (a.status) |hwnd| _ = win.MoveWindow(hwnd, px(a, 12), height - status_height, left_width - px(a, 24), status_height, win.TRUE);\n', '')
        expected = expected.replace('a.voice_active);', 'a.voice_active, a.last_dictation_state == .recording or a.last_dictation_state == .transcribing);')
        self.assertEqual(expected, function(source(), 'layoutRegion'))

    def test_real_fixture_failure_and_recovery(self):
        spec = importlib.util.spec_from_file_location('quiet_hub', ROOT / 'tools/verify-wazig/fake-hub.py')
        hub = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(hub)
        with tempfile.TemporaryDirectory() as temp:
            server = ThreadingHTTPServer(('127.0.0.1', 0), hub.QuietStatusHandler)
            server.daemon_threads = True
            server.state = hub.bridge.State(Path(temp) / 'requests.jsonl')
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            origin = f'http://127.0.0.1:{server.server_port}'
            headers = dict(Authorization=f'Bearer {hub.bridge.KEY}')
            try:
                with urlopen(Request(origin + '/v1/wazig/chats', headers=headers)) as reply:
                    self.assertEqual(reply.status, 200)
                with self.assertRaises(HTTPError) as rejected:
                    urlopen(Request(origin + '/fixture/sync-failure', data=b'{}'))
                self.assertEqual(rejected.exception.code, 401)
                with urlopen(Request(origin + '/fixture/sync-failure', data=b'{}', headers=headers)) as reply:
                    self.assertTrue(json.load(reply)['sync_failure'])
                with self.assertRaises(HTTPError) as failed:
                    urlopen(Request(origin + '/v1/wazig/chats', headers=headers))
                self.assertEqual(failed.exception.code, 503)
                with urlopen(Request(origin + '/fixture/sync-recover', data=b'{}', headers=headers)) as reply:
                    self.assertFalse(json.load(reply)['sync_failure'])
                with urlopen(Request(origin + '/v1/wazig/chats', headers=headers)) as reply:
                    self.assertEqual(reply.status, 200)
                endpoint = origin + '/fixture/message-failures'
                messages = origin + '/v1/wazig/messages?chat=' + hub.ALPHA + '&limit=80'
                for count, failures in ((1, 1), (-1, 3)):
                    with urlopen(Request(endpoint, data=json.dumps(dict(count=count)).encode(), headers=headers)) as reply:
                        self.assertEqual(json.load(reply)['count'], count)
                    for _ in range(failures):
                        with self.assertRaises(HTTPError) as failed:
                            urlopen(Request(messages, headers=headers))
                        self.assertEqual(failed.exception.code, 503)
                with urlopen(Request(endpoint, data=b'{"count":0}', headers=headers)) as reply:
                    self.assertEqual(reply.status, 200)
                with urlopen(Request(messages, headers=headers)) as reply:
                    self.assertEqual(reply.status, 200)
            finally:
                server.shutdown()
                server.server_close()
                worker.join()

    def test_evidence_positive_control(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            fixture(folder)
            validator.check_quiet_status(folder)

    def test_evidence_rejects_wrong_behavior(self):
        mutations = [
            ('quiet-status.json', 'uia_controls', 1),
            ('quiet-status.json', 'native_control', 7),
            ('quiet-status.json', 'tooltip_labels', ['Syncing messages']),
            ('quiet-status.json', 'labels', ['You are on v0.0.526 - this is the newest version']),
            ('quiet-status.json', 'labels', ['Syncing messages']),
            ('quiet-status.json', 'list_bottom', 874),
            ('quiet-status.json', 'list_rows', 0),
            ('version.json', 'rows', ['You are on v0.0.525 - this is the newest version']),
            ('version.json', 'rows', []),
            ('version.json', 'rows', ['Version 0.0.526']),
            ('version.json', 'positive', []),
            ('sync-problem.json', 'surface', 'dialog'),
            ('sync-problem.json', 'dialog', 123),
            ('sync-problem.json', 'card', dict(visible=False, span=0, rect=[12, 740, 300, 860], error='Unable to read chats from wacli')),
            ('sync-problem.json', 'card', dict(visible=True, span=120, rect=[12, 740, 300, 860], error='Syncing messages')),
            ('sync-problem.json', 'retained', dict(visible=True, span=120, rect=[12, 740, 300, 860], error='')),
            ('sync-problem.json', 'list_bottom', 900),
            ('sync-problem.json', 'pid', 999),
            ('sync-problem.json', 'failures', []),
        ]
        for name, key, value in mutations:
            with self.subTest(file=name, key=key, value=value), tempfile.TemporaryDirectory() as temp:
                folder = Path(temp)
                files = fixture(folder)
                files[name][key] = value
                (folder / name).write_text(json.dumps(files[name]))
                with self.assertRaises(AssertionError):
                    validator.check_quiet_status(folder)

    def test_evidence_rejects_missing_card_in_screen_snapshot(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            fixture(folder)
            state = json.loads((folder / 'sync-problem.state.json').read_text())
            state['update_card']['error'] = ''
            (folder / 'sync-problem.state.json').write_text(json.dumps(state))
            with self.assertRaises(AssertionError):
                validator.check_quiet_status(folder)

    def test_evidence_rejects_click_action_and_no_forced_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            files = fixture(folder)
            quiet = json.loads(json.dumps(files['quiet-status.json']))
            quiet['after']['selected']['id'] = 'fixture-beta'
            (folder / 'quiet-status.json').write_text(json.dumps(quiet))
            with self.assertRaises(AssertionError):
                validator.check_quiet_status(folder)
            fixture(folder)
            (folder / 'bridge-requests.jsonl').write_text('')
            with self.assertRaises(AssertionError):
                validator.check_quiet_status(folder)

    def test_archive_proof_no_longer_depends_on_removed_control(self):
        text = source()
        self.assertIn('\\"bulk_selected_count\\":{d}', function(text, 'controlStatus'))
        for name, expected in (('archive-bulk', 'bulk_selected_count -eq 2'), ('archive-inbox', 'bulk_selected_count -eq $workload')):
            script = (ROOT / f'tools/verify-wazig/journey-{name}.ps1').read_text()
            self.assertNotIn('1048', script)
            self.assertNotIn('statusHandle', script)
            self.assertIn(expected, script)
            self.assertIn('bulk_selected_count -eq 0', script)
        self.assertIn('fn showProblem(', (ROOT / 'src/chat_reconcile_test.zig').read_text())

    def test_message_recovery_evidence_rejects_hidden_persistent_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            fixture(folder)
            value = json.loads((folder / 'message-read-recovery.json').read_text())
            value['recovered'] = value['problem']
            (folder / 'message-read-recovery.json').write_text(json.dumps(value))
            with self.assertRaises(AssertionError):
                validator.check_quiet_status(folder)

    def test_message_recovery_requires_success_after_the_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            fixture(folder)
            value = json.loads((folder / 'message-read-recovery.json').read_text())
            value['requests'][0]['status'], value['requests'][1]['status'] = 200, 503
            (folder / 'message-read-recovery.json').write_text(json.dumps(value))
            rows = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text().splitlines()]
            rows[1:] = value['requests']
            (folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in rows))
            with self.assertRaises(AssertionError):
                validator.check_quiet_status(folder)

    def test_completed_message_recovery_is_not_invalidated_by_later_reads(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            fixture(folder)
            with (folder / 'bridge-requests.jsonl').open('a') as log:
                log.write(json.dumps(dict(wire_path='/v1/wazig/messages?chat=fixture-alpha&limit=80', status=200)) + '\n')
            validator.check_quiet_status(folder)

    def test_message_recovery_cannot_forge_captured_request_history(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            fixture(folder)
            value = json.loads((folder / 'message-read-recovery.json').read_text())
            value['requests'][0]['status'] = 200
            (folder / 'message-read-recovery.json').write_text(json.dumps(value))
            with self.assertRaises(AssertionError):
                validator.check_quiet_status(folder)

    def test_message_retry_card_is_not_an_update_action(self):
        text = source()
        click = function(text, 'updateCardClick')
        read = click.index('a.update_card_error_source == .message_read')
        self.assertLess(read, click.index('if (a.update_pending == null'))
        branch = click[read:click.index('if (a.update_pending == null')]
        self.assertIn('clearMessageReadProblem(a);', branch)
        self.assertIn('refreshMessages(a);', branch)
        self.assertIn('return;', branch)
        self.assertNotIn('startUpdateInstall', branch)
        self.assertIn('a.update_card_error_source = .update;', click[click.index('if (a.update_pending == null'):])
        offer = function(text, 'mainProc').split('if (is_new_offer) {', 1)[1].split('}', 1)[0]
        self.assertIn('a.update_card_error_source = .update;', offer)
        paint = function(text, 'paintUpdateCard')
        self.assertIn('failed and a.update_card_error_source == .message_read', paint)
        self.assertIn('"Messages unavailable"', paint)
        self.assertIn('"Update failed"', paint)
        self.assertIn('a.update_card_error_source = .update;', function(text, 'updateCardFail'))
        clear = function(text, 'clearMessageReadProblem')
        self.assertLess(clear.index('a.update_card_error_source != .message_read'), clear.index('a.update_card_error_len = 0'))

    def test_journey_is_registered_and_drives_real_input(self):
        registry = json.loads((ROOT / 'tools/verify-wazig/journeys.json').read_text())
        journey = next(row for row in registry['journeys'] if row['name'] == 'quiet-status')
        self.assertTrue(journey['pr'] and journey['evidence'])
        script = (ROOT / 'tools/verify-wazig' / journey['script']).read_text()
        for required in ('[VerifyWindow]::GetDlgItem($handle, 1048)', 'Read-ListLabels $paletteList',
                         '[VerifyMenus]::Click', '[VerifyMenus]::Hover', 'tooltips_class32',
                         "Invoke-PaletteCommand $session 'Refresh'", '/fixture/sync-failure',
                         "'#32770'", 'sync failure reaches existing sidebar update card', '$state.update_card.error -ceq $expectedProblem',
                         '$retained.error -ceq $expectedProblem', "surface = 'update_card'", "Send-Keys $session '{ESC}'"):
            self.assertIn(required, script)
        for forbidden in ('WM_COMMAND', 'WriteText(', 'PostMessage', 'InvokePattern'):
            self.assertNotIn(forbidden, script)


if __name__ == '__main__':
    unittest.main()

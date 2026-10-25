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
    return text[start:text.index('\n}\n', start) + 3]


def assert_quiet(text):
    for removed in ('const id_status =', 'status: ?win.HWND', 'a.status', 'status_height'):
        assert removed not in text, removed
    layout = function(text, 'layoutRegion')
    assert 'const list_bottom = if (updateCardVisible(a)) updateCardRect(a).top - px(a, 4) else height;' in layout
    assert 'list_bottom - header_height - search_height, win.TRUE)' in layout
    palette = function(text, 'buildPaletteItems')
    assert 'appendPalette(a, "You are on v" ++ app_version ++ " - this is the newest version", "", 0);' in palette
    problem = function(text, 'showProblem')
    assert 'win.MessageBoxW' not in problem
    assert text.count('MessageBoxW') == 1
    assert 'win.MessageBoxW(null, lit("Messages is already running. Close that window before starting another instance.")' in text
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
    (folder / 'bridge-requests.jsonl').write_text(json.dumps(failure) + '\n')
    for stage in ('before', 'quiet-status', 'version', 'sync-problem', 'after'):
        (folder / f'{stage}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'x' * 11000)
        (folder / f'{stage}.uia.txt').write_text('MessagesZig | Combined inbox - Wazig v0.0.526\n1016 | LISTBOX | Chats\n')
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

    def test_update_card_unchanged(self):
        parent = subprocess.check_output(['git', 'show', f'{BASE}:src/main.zig'], cwd=ROOT, text=True)
        text = source()
        for name in ('updateCardNotesHeight', 'updateCardHeight', 'updateCardSpan', 'updateCardRect',
                     'updateCardLayout', 'updateCardWinRect', 'updateCardButtonRect', 'updateCardCloseRect', 'updateCardPtIn',
                     'updateCardHit', 'updateCardRefresh', 'updateCardFail', 'updateCardClick', 'updateCardDismiss', 'handleKeyboard'):
            with self.subTest(function=name):
                self.assertEqual(function(parent, name), function(text, name))

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
        self.assertEqual(painter, function(source(), 'paintUpdateCard'))

    def test_only_list_layout_changes(self):
        parent = subprocess.check_output(['git', 'show', f'{BASE}:src/main.zig'], cwd=ROOT, text=True)
        expected = function(parent, 'layoutRegion')
        expected = expected.replace('    const status_height: i32 = px(a, 26);\n', '')
        expected = expected.replace('    const search_height: i32 = px(a, 48);', '    const search_height: i32 = px(a, 48);\n    const list_bottom = if (updateCardVisible(a)) updateCardRect(a).top - px(a, 4) else height;')
        expected = expected.replace('height - header_height - search_height - status_height - updateCardSpan(a)', 'list_bottom - header_height - search_height')
        expected = expected.replace('    if (a.status) |hwnd| _ = win.MoveWindow(hwnd, px(a, 12), height - status_height, left_width - px(a, 24), status_height, win.TRUE);\n', '')
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

import copy
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import importlib.util
import json
import re
import runpy
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools/verify-wazig'
spec = importlib.util.spec_from_file_location('show_archived_hub', TOOLS / 'fake-hub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class ShowArchivedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.views = [dict(provider=p, account=a, label=a, inbox=False) for p, a in hub.SHOW_ARCHIVED_ACCOUNTS]
        self.requests = [dict(method='GET', status=200, authorized=True, wire_path='/v1/wazig/chats?archived=true')]
        self.write('session.json', dict(feature='show-archived', sha256='hash', commit='commit', pid=2, startTicks='new', root='isolated', id='id'))
        self.write('result.json', dict(feature='show-archived', status='passed'))
        self.write('show-archived-views.json', self.views)
        self.write('show-archived-restart.json', dict(old_pid=1, old_start='old', new_pid=2, new_start='new', root='isolated', id='id', sha256='hash'))
        for name, enabled in [('inbox-off', False), ('inbox-on', True), ('inbox-warm-off', False), ('inbox-warm-on', True), ('inbox-kept', True), ('inbox-return', True), ('restart-inbox', True), ('after', True)]:
            self.capture(name, enabled)
        for position, view in enumerate(self.views, 1):
            for phase, enabled in [('off', False), ('on', True), ('archived', True), ('unarchived', True)]:
                self.capture(f'view-{position}-{phase}', enabled, view, phase == 'archived')
            if position != 1:
                self.capture(f'view-{position}-disabled', False, view)
        for name, enabled, view in [('palette-off', False, self.views[0]), ('palette-on', True, self.views[0]), ('account-one-kept', True, self.views[0]),
                                    ('account-two-off', False, self.views[1]), ('restart-one', True, self.views[0]), ('restart-two', False, self.views[1])]:
            self.capture(name, enabled, view)
        archived = [self.control(row) for row in hub.show_archived_rows() if row['archived']]
        self.write('archived-only.state.json', dict(show_archived=True, chat_count=len(archived)))
        self.write('archived-only.chats.json', dict(chats=archived))
        self.write('side-effects.json', dict(pending_sends=0, pending_archives=0, sync='stopped', include_archived=True, show_archived=False, current_view=dict(inbox=True), production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'preferences.txt').write_text('ShowArchived:all : 1\nShowArchived:whatsapp:personal : 1')
        (self.folder / 'actions.log').write_text('\n'.join('keys: ' + key for key in ('%i', '%1', '%2', '%3', '%4', '%5', '%a', '^e', '^k', '{ENTER}')))
        (self.folder / 'hub-proof.log').write_text('show-archived show-archived-all PASS')
        (self.folder / 'result.txt').write_text('JOURNEY PASSED: show-archived')
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: synthetic evidence')
        timing_names = [('inbox-on', True), ('inbox-warm-off', False), ('inbox-warm-on', True)]
        for position in range(1, 6):
            timing_names.append((f'view-{position}-on', True))
            timing_names.extend([('palette-off', False), ('palette-on', True)] if position == 1 else [(f'view-{position}-disabled', False)])
        lines = []
        for index, (name, enabled) in enumerate(timing_names):
            line = f'1000 archive-toggle: include={str(enabled).lower()} rebuilds=1 rebuild_ms=2 fetches=0 fetch_ms=0 first_paint_ms=7 paints=1'
            lines.append(line)
            self.write(f'{name}.toggle.json', dict(name=name, index=index, line=line))
        (self.folder / 'final-data').mkdir()
        (self.folder / 'final-data/launch-log.txt').write_text('\n'.join(lines))
        self.save_requests()
        self.presentation()

    def presentation(self, light=False):
        pixels = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))
        checker = runpy.run_path(str(TOOLS / 'check-archive-presentation.py'))
        background = (255, 255, 255) if light else (0, 0, 0)
        foreground = (0, 0, 0) if light else (255, 255, 255)
        dimmed = tuple((text * 180 + back * 75) // 255 for text, back in zip(foreground, background))
        for scope in ('sidebar', 'inbox'):
            rows = self.read('view-1-on.chats.json')['chats']
            for mode in ('dim', 'hover', 'selected'):
                name = f'archive-{scope}-{mode}'
                selected = rows[2] if mode == 'selected' else rows[0]
                state = dict(include_archived=True, show_archived=False, selected=selected, search='', current_view=dict(inbox=scope == 'inbox'))
                self.write(f'{name}.state.json', state)
                self.write(f'{name}.chats.json', dict(chats=rows))
                self.write(f'{name}.layout.json', dict(dpi=96, row_height=64, top=0, x=0, y=0, width=240, height=256, mode=mode, rows=rows, selected=selected['id'], colour_model='theme-foreground-mix', foreground_weight=180))
                image = [[background] * 240 for _ in range(256)]
                for index, row in enumerate(rows):
                    colour = dimmed if row['archived'] and mode == 'dim' else foreground
                    for y in range(index * 64 + 16, index * 64 + 26):
                        image[y][70:170] = [colour] * 100
                pixels['write_png'](self.folder / f'{name}.png', image)
                checker['check_scene'](self.folder, name, capture=True)
        for name, enabled, activated in [('archive-palette-on', True, True), ('archive-palette-off', False, True), ('archive-palette-restored', True, False), ('palette-switch', True, True)]:
            expected = 'Toggle archived chats in this view: ' + ('On' if enabled else 'Off')
            self.write(f'{name}.palette.json', dict(query='archive', enabled=enabled, activated=activated, expected=expected, labels=[expected], index=0))
            self.write(f'{name}.state.json', dict(include_archived=enabled))
            (self.folder / f'{name}.png').write_bytes(b'\x89PNG\r\n\x1a\n')
        identities = [f"{row['provider']}|{row['account']}|{row['id']}|{row['archived']}" for row in rows]
        self.write('archive-identities.json', dict(before=identities, after=identities))
        state = self.read('inbox-warm-on.state.json')
        rows = self.read('inbox-warm-on.chats.json')['chats']
        state['pending_archives'] = 0
        self.write('archive-footer.json', dict(before=state, after=state, rows=rows, point=[150, 243], rect=[100, 230, 238, 256]))
        self.write('archive-footer.state.json', state)
        self.write('archive-footer.chats.json', dict(chats=rows))
        (self.folder / 'archive-footer.uia.txt').write_text('MessagesZig | Combined inbox - Wazig v0.0.526\n1016 | ListBox | Chats')
        pixels['write_png'](self.folder / 'archive-footer.png', [[(0, 0, 0)] * 240 for _ in range(256)])

    def control(self, row):
        account = next(account for provider, account in hub.SHOW_ARCHIVED_ACCOUNTS if provider == row['provider'] and
                       (row['jid'].startswith(account + ':') or provider != 'whatsapp'))
        return dict(id=row['jid'], name=row['name'], provider=row['provider'], account='hub-cache', view_account=account,
                    archived=row['archived'], unread=row['unread'], archive_label='Archived' if row['archived'] else '', last_message_time=row['last_message_ts'])

    def capture(self, name, enabled, view=None, changed=False):
        rows = [self.control(row) for row in hub.show_archived_rows()]
        rows = [row for row in rows if (row['unread'] if view is None else row['provider'] == view['provider'] and row['view_account'] == view['account'])]
        rows = [row for row in rows if enabled or not row['archived']]
        rows.sort(key=lambda row: row['last_message_time'], reverse=True)
        if changed:
            rows[0].update(archived=True, archive_label='Archived')
        self.write(f'{name}.chats.json', dict(chats=rows))
        self.write(f'{name}.state.json', dict(include_archived=enabled, show_archived=False, unread_only=view is None,
                                             chat_count=len(rows), current_view=view or dict(inbox=True), selected=rows[0], search=''))
        (self.folder / f'{name}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'x' * 11000)
        (self.folder / f'{name}.uia.txt').write_text('MessagesZig | Combined inbox - Wazig v0.0.526\n1016 | ListBox | Chats')

    def write(self, name, data):
        (self.folder / name).write_text(json.dumps(data), encoding='utf-8')

    def read(self, name):
        return json.loads((self.folder / name).read_text())

    def save_requests(self):
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in self.requests))

    def validate(self):
        return subprocess.run([sys.executable, str(TOOLS / 'check-evidence.py'), str(self.folder)], capture_output=True, text=True)

    def test_complete_evidence_dispatch(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('SHOW ARCHIVED EVIDENCE VERIFIED', result.stdout)

    def test_rejects_filter_marking_isolation_restart_and_palette_regressions(self):
        mutations = [('inbox-off.chats.json', lambda value: value['chats'][0].update(archived=True)),
                     ('inbox-on.chats.json', lambda value: value['chats'][0].update(unread=False)),
                     ('view-4-on.chats.json', lambda value: value['chats'][-1].update(archive_label='')),
                     ('view-2-off.state.json', lambda value: value.update(include_archived=True)),
                     ('restart-two.state.json', lambda value: value.update(include_archived=True)),
                     ('restart-one.state.json', lambda value: value.update(include_archived=False)),
                     ('archive-palette-off.palette.json', lambda value: value.update(expected='Toggle archived chats in this view: On')),
                     ('show-archived-restart.json', lambda value: value.update(root='another-profile')),
                     ('view-3-unarchived.state.json', lambda value: value['selected'].update(archived=True)),
                     ('inbox-on.chats.json', lambda value: value['chats'].reverse())]
        for name, mutate in mutations:
            with self.subTest(name=name, mutation=mutate):
                original = self.read(name)
                broken = copy.deepcopy(original)
                mutate(broken)
                self.write(name, broken)
                self.assertNotEqual(self.validate().returncode, 0)
                self.write(name, original)
        self.assertEqual(self.validate().returncode, 0)

    def test_rejects_missing_repeated_or_slow_path_timing_evidence(self):
        name = 'inbox-warm-on.toggle.json'
        original = self.read(name)
        for line in [original['line'].replace('rebuilds=1', 'rebuilds=3'),
                     original['line'].replace('fetch_ms=0', 'fetch_ms=42'),
                     original['line'].replace('paints=1', 'paints=0'),
                     original['line'].replace('paints=1', 'paints=2'),
                     original['line'].replace('first_paint_ms=7', 'first_paint_ms=1')]:
            launch_path = self.folder / 'final-data/launch-log.txt'
            launch = launch_path.read_text()
            lines = launch.splitlines()
            lines[original['index']] = line
            launch_path.write_text('\n'.join(lines))
            self.write(name, dict(original, line=line))
            self.assertNotEqual(self.validate().returncode, 0)
            launch_path.write_text(launch)
        self.write(name, dict(original, index=0))
        self.assertNotEqual(self.validate().returncode, 0)
        (self.folder / name).unlink()
        self.assertNotEqual(self.validate().returncode, 0)
        self.write(name, original)
        self.assertEqual(self.validate().returncode, 0)

    def test_rejects_any_network_archive_for_any_provider(self):
        original = copy.deepcopy(self.requests)
        for provider in ('whatsapp', 'slack', 'telegram', 'signal'):
            chat = next(row['jid'] for row in hub.show_archived_rows() if row['provider'] == provider)
            for path in ('/v1/wazig/archive', '/v1/wazig/archive-batch'):
                self.requests = original + [dict(method='POST', authorized=True, status=200, wire_path=path, body=dict(chat=chat, archived=True))]
                self.save_requests()
                self.assertNotEqual(self.validate().returncode, 0)
        self.requests = original
        self.save_requests()
        self.assertEqual(self.validate().returncode, 0)

    def test_fixture_filters_and_rejects_every_archive_write(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), hub.ShowArchivedHandler)
        server.daemon_threads = True
        server.state = hub.bridge.State(self.folder / 'fixture.jsonl')
        self.addCleanup(server.server_close)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)

        def call(method, path, body=None):
            connection = HTTPConnection('127.0.0.1', server.server_port, timeout=5)
            try:
                connection.request(method, path, json.dumps(body) if body is not None else None,
                                   {'Authorization': f'Bearer {hub.bridge.KEY}', 'Connection': 'close'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        status, normal = call('GET', '/v1/wazig/chats')
        status2, archived = call('GET', '/v1/wazig/chats?archived=true')
        self.assertEqual((status, status2, len(normal), len(archived)), (200, 200, 10, 10))
        self.assertEqual({row['provider'] for row in archived}, {'whatsapp', 'slack', 'telegram', 'signal'})
        self.assertEqual(sum(row['unread'] for row in archived), 5)
        for provider in ('whatsapp', 'slack', 'signal', 'telegram'):
            chat = next(row['jid'] for row in normal if row['provider'] == provider)
            self.assertEqual(call('POST', '/v1/wazig/archive', dict(chat=chat, archived=True))[0], 400)
        self.assertEqual(len(call('GET', '/v1/wazig/chats?archived=true')[1]), 10)
        self.assertEqual(call('GET', '/v1/wazig/messages?chat=' + normal[1]['jid'] + '&limit=20')[1][0]['FromMe'], False)

    def test_app_exposes_palette_switch_without_footer(self):
        source = (ROOT / 'src/main.zig').read_text()
        for required in ('command_include_archived', '"Toggle archived chats in this view: On"',
                         '"Toggle archived chats in this view: Off"', '\\"include_archived\\"', '\\"archive_label\\"'):
            self.assertIn(required, source)
        for removed in ('id_include_archived', 'include_archived_button', 'drawSetupButton', 'updateViewArchiveButton', '"Show archived:'):
            self.assertNotIn(removed, source)
        self.archive_colour_contract(source)
        theme = (ROOT / 'src/theme.zig').read_text()
        self.assertIn('pub const archived_row_foreground_weight: u8 = 180;', theme)
        mix = theme.split('pub fn archivedRowColor(', 1)[1].split('\n}\n', 1)[0]
        for required in ('const weight: u32 = archived_row_foreground_weight;',
                         'inline for ([_]u5{ 0, 8, 16 })',
                         '(color >> shift) & 0xff', '(current.surface_container_low >> shift) & 0xff',
                         '((foreground * weight + background * (255 - weight)) / 255) << shift'):
            self.assertIn(required, mix)
        shortcut = source.split('fn handleKeyboard(', 1)[1].split('fn jumpToLatestMessage(', 1)[0]
        self.assertIn("alt and !control and !shift and key == 'A'", shortcut)

    def test_rejects_old_footer_and_undimmed_or_still_dim_interactions(self):
        tree = self.folder / 'archive-footer.uia.txt'
        original = tree.read_text()
        tree.write_text(original + '\n1146 | Button | Show archived: On')
        self.assertNotEqual(self.validate().returncode, 0)
        tree.write_text(original)
        tree.write_text(original + '\n1008 | RICHEDIT50W | Search All Ctrl+F')
        self.assertNotEqual(self.validate().returncode, 0)
        tree.write_text(original)
        footer = self.read('archive-footer.json')
        broken = copy.deepcopy(footer)
        broken['after']['include_archived'] = False
        self.write('archive-footer.json', broken)
        self.assertNotEqual(self.validate().returncode, 0)
        self.write('archive-footer.json', footer)
        pixels = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))
        checker = runpy.run_path(str(TOOLS / 'check-archive-presentation.py'))
        for light in (False, True):
            self.presentation(light=light)
            self.assertEqual(self.validate().returncode, 0)
            background = (255, 255, 255) if light else (0, 0, 0)
            foreground = (0, 0, 0) if light else (255, 255, 255)
            dimmed = tuple((text * 180 + back * 75) // 255 for text, back in zip(foreground, background))
            for scope in ('sidebar', 'inbox'):
                for mode in (('dim',) if light else ('dim', 'hover', 'selected')):
                    name = f'archive-{scope}-{mode}'
                    image_path = self.folder / f'{name}.png'
                    original = image_path.read_bytes()
                    _, _, image = pixels['read_png'](image_path)
                    colour = foreground if mode == 'dim' else dimmed
                    for y in range(2 * 64 + 16, 2 * 64 + 26):
                        image[y][70:170] = [colour] * 100
                    pixels['write_png'](image_path, image)
                    with self.subTest(light=light, scope=scope, mode=mode):
                        message = 'theme colour mix' if mode == 'dim' else 'archived row came back dimmed when hovered or selected'
                        with self.assertRaisesRegex(AssertionError, message):
                            checker['check_scene'](self.folder, name, capture=True)
                    image_path.write_bytes(original)
            self.assertEqual(self.validate().returncode, 0)

    def test_dim_text_colour_tolerates_cleartype_channel_differences(self):
        checker = runpy.run_path(str(TOOLS / 'check-archive-presentation.py'))
        pixels = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))
        for light in (False, True):
            self.presentation(light=light)
            colour = (0, 0, 32) if light else (255, 255, 223)
            expected = [75, 75, 97] if light else [180, 180, 157]
            for scope in ('sidebar', 'inbox'):
                name = f'archive-{scope}-dim'
                image_path = self.folder / f'{name}.png'
                _, _, image = pixels['read_png'](image_path)
                rows = self.read(f'{name}.chats.json')['chats']
                for index, row in enumerate(rows):
                    if not row['archived']:
                        for y in range(index * 64 + 16, index * 64 + 26):
                            image[y][70:170] = [colour] * 100
                pixels['write_png'](image_path, image)
                with self.subTest(light=light, scope=scope):
                    metrics = checker['check_scene'](self.folder, name, capture=True)
                    self.assertEqual(metrics['expected_dim_text'], expected)
                    self.assertEqual(metrics['archived']['text'], [75, 75, 75] if light else [180, 180, 180])
                    self.assertAlmostEqual(metrics['colour_mix_error'], abs(sum(expected) / 3 - sum(metrics['archived']['text']) / 3))
                    self.assertLessEqual(metrics['colour_mix_error'], 12)
            self.assertEqual(self.validate().returncode, 0)

    def test_full_strength_text_colour_tolerates_cleartype_channel_differences(self):
        checker = runpy.run_path(str(TOOLS / 'check-archive-presentation.py'))
        pixels = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))
        for light in (False, True):
            self.presentation(light=light)
            colour = (0, 0, 22) if light else (255, 255, 233)
            for scope in ('sidebar', 'inbox'):
                for mode in ('hover', 'selected'):
                    name = f'archive-{scope}-{mode}'
                    image_path = self.folder / f'{name}.png'
                    _, _, image = pixels['read_png'](image_path)
                    for y in range(2 * 64 + 16, 2 * 64 + 26):
                        image[y][70:170] = [colour] * 100
                    pixels['write_png'](image_path, image)
                    with self.subTest(light=light, scope=scope, mode=mode):
                        metrics = checker['check_scene'](self.folder, name, capture=True)
                        self.assertEqual(metrics['full_strength_colour_distance'], 22)
                        self.assertEqual(metrics['archived']['text'], list(colour))
                        self.assertGreaterEqual(sum(metrics['archived']['text']) / 3, sum(metrics['live']['text']) / 3 - 20)
            self.assertEqual(self.validate().returncode, 0)

    def test_full_strength_text_colour_accepts_background_difference_and_rejects_dimming(self):
        checker = runpy.run_path(str(TOOLS / 'check-archive-presentation.py'))
        pixels = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))
        for scope in ('sidebar', 'inbox'):
            for mode in ('hover', 'selected'):
                name = f'archive-{scope}-{mode}'
                image_path = self.folder / f'{name}.png'
                _, _, image = pixels['read_png'](image_path)
                for y in range(2 * 64, 3 * 64):
                    image[y] = [(38, 38, 38)] * 240
                for level in (255, 235, 234, 180):
                    for y in range(2 * 64 + 16, 2 * 64 + 26):
                        image[y][70:170] = [(level, level, level)] * 100
                    pixels['write_png'](image_path, image)
                    with self.subTest(scope=scope, mode=mode, level=level):
                        if level in (234, 180):
                            with self.assertRaisesRegex(AssertionError, 'archived row came back dimmed when hovered or selected'):
                                checker['check_scene'](self.folder, name, capture=True)
                        else:
                            metrics = checker['check_scene'](self.folder, name, capture=True)
                            self.assertEqual(sum(metrics['live']['text']) / 3, 255)
                            self.assertEqual(sum(metrics['archived']['text']) / 3, level)
                            self.assertNotEqual(metrics['archived']['background'], metrics['live']['background'])
                            self.assertLess(metrics['archived']['contrast'], metrics['live']['contrast'] * 0.9)
                for y in range(2 * 64 + 16, 2 * 64 + 26):
                    image[y][70:170] = [(255, 255, 255)] * 100
                pixels['write_png'](image_path, image)
                checker['check_scene'](self.folder, name, capture=True)
        self.assertEqual(self.validate().returncode, 0)

    def archive_colour_contract(self, source):
        row = source.split('fn drawChat(', 1)[1].split('\nfn transcriptLineKind(', 1)[0]
        self.assertIn('paint_buffer.Buffer.init(', row)
        self.assertIn('const dimmed = chat.archived and !selected and !bulk_selected and !hovered;', row)
        block = row.split('if (dimmed) {', 1)[1].split('}', 1)[0]
        for colour in ('row_text', 'row_muted', 'row_primary'):
            self.assertIn(f'{colour} = theme.archivedRowColor({colour});', block)
        for forbidden in ('CreateCompatibleDC', 'CreateCompatibleBitmap', 'AlphaBlend'):
            self.assertNotIn(forbidden, row)

    def test_colour_source_guards_reject_overlay_and_missing_dimming(self):
        source = (ROOT / 'src/main.zig').read_text()
        self.archive_colour_contract(source)
        for old, new in [('and !hovered;', ';'), ('and !selected', ''), ('and !bulk_selected', ''),
                         ('row_text = theme.archivedRowColor(row_text);', ''),
                         ('row_muted = theme.archivedRowColor(row_muted);', ''),
                         ('row_primary = theme.archivedRowColor(row_primary);', ''),
                         ('if (dimmed) {', 'if (false) {'),
                         ('const dimmed = chat.archived', 'const dimmed = false'),
                         ('var row_text =', 'win.CreateCompatibleDC(); var row_text ='),
                         ('var row_text =', 'win.CreateCompatibleBitmap(); var row_text ='),
                         ('var row_text =', 'win.AlphaBlend(); var row_text =')]:
            with self.subTest(regression=new), self.assertRaises((AssertionError, IndexError)):
                self.archive_colour_contract(source.replace(old, new))

    def test_colour_mix_oracle_rejects_wrong_mix_and_model(self):
        checker = runpy.run_path(str(TOOLS / 'check-archive-presentation.py'))
        pixels = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))
        for light in (False, True):
            self.presentation(light=light)
            name = 'archive-sidebar-dim'
            image_path = self.folder / f'{name}.png'
            original = image_path.read_bytes()
            _, _, image = pixels['read_png'](image_path)
            expected_level = 75 if light else 180
            for offset in (-30, -13, -12, 12, 13, 30):
                level = expected_level + offset
                for y in range(2 * 64 + 16, 2 * 64 + 26):
                    image[y][70:170] = [(level, level, level)] * 100
                pixels['write_png'](image_path, image)
                with self.subTest(light=light, offset=offset):
                    if abs(offset) > 12:
                        with self.assertRaisesRegex(AssertionError, 'theme colour mix'):
                            checker['check_scene'](self.folder, name, capture=True)
                    else:
                        metrics = checker['check_scene'](self.folder, name, capture=True)
                        self.assertEqual(metrics['colour_mix_error'], 12)
            for y in range(2 * 64, 3 * 64):
                image[y] = [(240, 240, 240) if light else (15, 15, 15)] * 240
            for y in range(2 * 64 + 16, 2 * 64 + 26):
                image[y][70:170] = [(expected_level, expected_level, expected_level)] * 100
            pixels['write_png'](image_path, image)
            with self.subTest(light=light, mutation='background'), self.assertRaisesRegex(AssertionError, 'row background changed'):
                checker['check_scene'](self.folder, name, capture=True)
            image_path.write_bytes(original)
            layout = self.read(f'{name}.layout.json')
            for key, value in [('colour_model', 'alpha-overlay'), ('foreground_weight', 255)]:
                self.write(f'{name}.layout.json', dict(layout, **{key: value}))
                with self.subTest(light=light, key=key), self.assertRaises(AssertionError):
                    checker['check_scene'](self.folder, name, capture=True)
            self.write(f'{name}.layout.json', layout)
            metrics = checker['check_scene'](self.folder, name, capture=True)
            self.assertEqual(checker['check_scene'](self.folder, name), metrics)
            self.assertEqual(metrics['polarity'], 'light' if light else 'dark')
            self.assertEqual(metrics['colour_mix_error'], 0)

    def test_toggle_path_contract_and_baseline_negative_control(self):
        def contract(source):
            refilter = source.split('fn refilterChats(', 1)[1].split('fn loadViewArchiveSetting(', 1)[0]
            toggle = source.split('fn toggleViewArchived(', 1)[1].split('fn switchChatView(', 1)[0]
            self.assertIn('a.chats_raw_flags == 1 or a.chats_raw_flags == flags', refilter)
            self.assertIn('refreshVisibleChats(a)', refilter)
            self.assertNotIn('refreshMessages(a)', toggle)
            self.assertIn('reconcileOpenChat(a)', toggle)
            self.assertIn('archive-toggle: include={} rebuilds={d}', source)
            self.assertIn('defer logArchiveTogglePaint(a);', source)
        contract((ROOT / 'src/main.zig').read_text())
        baseline = subprocess.check_output(['git', 'show', 'f4e1301:src/main.zig'], cwd=ROOT, text=True)
        with self.assertRaises(AssertionError):
            contract(baseline)

    def test_shortcut_was_free_at_journey_commit_with_occupied_control(self):
        try:
            baseline = subprocess.check_output(['git', 'show', 'HEAD~1:src/main.zig'], cwd=ROOT, text=True)
        except (subprocess.CalledProcessError, OSError):
            self.skipTest('shortcut history control no longer available')
        if 'Alt+A' in baseline:
            self.skipTest('shortcut history control no longer available')
        def occupied(key):
            return bool(re.search(r"if \(alt and !control and !shift and key == '" + key + r"'\)", baseline))
        self.assertTrue(occupied('I'))
        self.assertFalse(occupied('A'))
        self.assertNotIn('Alt+A', baseline)
        self.assertIn("if (control and !alt and !shift and key == 'A')", baseline)

    def test_changed_feature_code_has_no_comments(self):
        result = subprocess.run(['node', str(ROOT / 'tools/strip-comments.mjs'), '--check', str(ROOT)], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('No code comments found.', result.stdout)

    def test_registry_wires_pr_matrix_map_and_keyboard_journey(self):
        registry = json.loads((TOOLS / 'journeys.json').read_text())
        entry = next(row for row in registry['journeys'] if row['name'] == 'show-archived')
        self.assertTrue(entry['pr'] and entry['evidence'])
        self.assertEqual(entry['validator'], dict(file='check-show-archived-evidence.py', function='check_show_archived'))
        self.assertEqual(entry['hub_handler']['class'], 'ShowArchivedHandler')
        self.assertIn('Invoke-ShowArchivedJourney $session $start', (TOOLS / entry['script']).read_text())
        journey = (TOOLS / 'show-archived.ps1').read_text()
        for required in ("'%i'", "'%a'", "'^e'", 'WAZIG_VERIFY_RESTART', 'Assert-ArchiveFooterRemoved', 'Invoke-ArchivePresentation', 'Show archived chats'):
            self.assertIn(required, journey)
        for forbidden in ('WM_COMMAND', 'SendMessage', 'PostMessage', '.SetValue(', '/fixture/'):
            self.assertNotIn(forbidden, journey)
        workflow = (ROOT / '.github/workflows/verify.yml').read_text()
        self.assertIn("row['pr']", workflow)
        self.assertIn('matrix: ${{ fromJSON(needs.plan.outputs.matrix) }}', workflow)
        self.assertIn('feature=show-archived', (ROOT / '.claude/skills/verify-wazig/features/show-archived.md').read_text())


if __name__ == '__main__':
    unittest.main()

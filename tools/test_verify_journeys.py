import contextlib
import copy
import hashlib
import io
import json
import os
import re
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml


ROOT = Path(__file__).resolve().parents[1]


class JourneyRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ['tools/verify-wazig', '.claude/skills/verify-wazig', 'src']:
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns('__pycache__'))
        for name in ['tools/check_private_markers.py', '.github/workflows/verify.yml', 'CHANGELOG.md']:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        self.tools = self.root / 'tools/verify-wazig'
        self.registry_path = self.tools / 'journeys.json'
        self.registry = json.loads(self.registry_path.read_text())
        self.workflow = yaml.safe_load((self.root / '.github/workflows/verify.yml').read_text())

    def save_registry(self):
        self.registry_path.write_text(json.dumps(self.registry))

    def check_map(self):
        return subprocess.run([sys.executable, str(self.tools / 'check-map.py')], cwd=self.root,
                              capture_output=True, text=True)

    def assert_map_passes(self):
        result = self.check_map()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('JOURNEY REGISTRY VERIFIED', result.stdout)

    def plan(self, event='schedule', feature='search'):
        step = next(step for step in self.workflow['jobs']['plan']['steps'] if step.get('id') == 'matrix')
        output = self.root / 'plan-output'
        output.write_text('')
        result = subprocess.run([sys.executable, '-c', step['run']], cwd=self.root, capture_output=True,
                                text=True, env=dict(os.environ, EVENT_NAME=event, FEATURE=feature, GITHUB_OUTPUT=str(output)))
        return result, output.read_text()

    def test_current_registry_passes(self):
        self.assert_map_passes()

    def test_removed_archive_commands_and_jobs_fail_map(self):
        path = self.root / 'src/main.zig'
        original = path.read_text()
        for removed in ['resurface_probe', 'enqueueResurfaceProbe', 'applyResurfaceProbe',
                        'command_keep_archived', 'toggleKeepArchived', 'Archive and keep archived', 'Allow resurfacing']:
            with self.subTest(removed=removed):
                path.write_text(original + f'\nconst removed_archive_path = "{removed}";\n')
                self.assertIn('removed archive resurfacing path or command', self.check_map().stderr)
        path.write_text(original)
        self.assert_map_passes()

    def test_build_source_section_markers_still_exist_in_order(self):
        build = (ROOT / 'build.zig').read_text()
        source = (ROOT / 'src/main.zig').read_text()
        markers = re.findall(r'sourceSection\(("(?:[^"\\]|\\.)*"), ("(?:[^"\\]|\\.)*")\)', build)
        self.assertTrue(markers)
        for start, end in markers:
            start, end = json.loads(start), json.loads(end)
            with self.subTest(start=start, end=end):
                position = source.index(start)
                self.assertGreaterEqual(source.index(end, position + len(start)), position + len(start))

    def test_main_added_journeys_keep_fixture_modes_and_checks(self):
        entries = {row['name']: row for row in self.registry['journeys']}
        bulk = entries['archive-bulk']
        self.assertTrue(bulk['pr'] and bulk['provider'])
        self.assertEqual(bulk['prepare'], entries['archive']['prepare'])
        self.assertIsNone(bulk['hub'])
        media = entries['media-fit']
        self.assertTrue(media['pr'] and media['evidence'])
        self.assertEqual((media['hub'], media['chats']), ('media-fit', 1))
        self.assertEqual(media['hub_handler']['class'], 'MediaFitHandler')
        self.assertEqual(media['library'], 'media-fit.ps1')
        self.assertEqual(media['validator'], dict(file='check-media-fit-evidence.py', function='check_media_fit'))
        passage = entries['passage-copy']
        self.assertTrue(passage['pr'] and passage['evidence'])
        self.assertEqual((passage['hub'], passage['chats']), ('passage-copy', 2))
        self.assertEqual(passage['hub_handler']['class'], 'PassageCopyHandler')
        validator = (self.tools / passage['validator']['file']).read_text()
        self.assertIn("assert timestamps == sorted(timestamps) and len(set(timestamps)) == 7", validator)
        self.assertIn("assert check['actual'] == check['expected'] == '\\r\\n'.join(blocks)", validator)
        self.assertIn("assert actions.count('held drag beyond canvas 1024 bottom') == 2", validator)
        self.assertIn('check-chat-rows.ps1', (self.root / '.github/workflows/verify.yml').read_text())

    def test_main_added_journey_configuration_regressions_fail(self):
        entries = {row['name']: row for row in self.registry['journeys']}
        for name, key, broken in [('archive-bulk', 'provider', False), ('archive-bulk', 'pr', False),
                                  ('archive-bulk', 'prepare', 'prepare-menus.ps1'),
                                  ('passage-copy', 'evidence', False), ('passage-copy', 'pr', False),
                                  ('passage-copy', 'chats', 3), ('passage-copy', 'hub', 'wrong-mode'),
                                  ('passage-copy', 'hub_handler', dict(file='fake-hub.py', **{'class': 'Handler'})),
                                  ('media-fit', 'pr', False), ('media-fit', 'evidence', False),
                                  ('media-fit', 'chats', 2), ('media-fit', 'hub', 'wrong-mode'),
                                  ('media-fit', 'hub_handler', dict(file='fake-hub.py', **{'class': 'Handler'})),
                                  ('media-fit', 'validator', dict(file='evidence-voice.py'))]:
            with self.subTest(name=name, key=key):
                original = entries[name][key]
                entries[name][key] = broken
                self.save_registry()
                self.assertNotEqual(self.check_map().returncode, 0)
                entries[name][key] = original
        self.save_registry()
        self.assert_map_passes()

    def test_removed_chat_rows_workflow_check_fails(self):
        path = self.root / '.github/workflows/verify.yml'
        path.write_text(path.read_text().replace('check-chat-rows.ps1', 'missing-rows.ps1'))
        self.assertNotEqual(self.check_map().returncode, 0)

    def test_registry_entry_without_wiring_fails(self):
        row = copy.deepcopy(self.registry['journeys'][0])
        row.update(name='extra-journey', script='journey-extra-journey.ps1')
        self.registry['journeys'].append(row)
        self.save_registry()
        result = self.check_map()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('feature maps must match', result.stderr)

    def test_removed_fake_hub_switch_fails(self):
        path = self.tools / 'fake-hub.py'
        path.write_text(path.read_text().replace('for mode in journeys:\n',
            "for mode in journeys:\n        if mode == 'mixed-lid':\n            continue\n"))
        result = self.check_map()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing fake-hub switch', result.stderr)
        self.assertIn('mixed-lid', result.stderr)

    def test_missing_map_script_handler_or_validator_fails(self):
        paths = ['.claude/skills/verify-wazig/features/search.md',
                 'tools/verify-wazig/journey-search.ps1',
                 'tools/verify-wazig/check-signal-evidence.py']
        for filename in paths:
            with self.subTest(filename=filename):
                path = self.root / filename
                original = path.read_bytes()
                path.unlink()
                self.assertNotEqual(self.check_map().returncode, 0)
                path.write_bytes(original)
        path = self.tools / 'fake-hub.py'
        path.write_text(path.read_text().replace('class MixedLidHandler(Handler):', 'class MissingHandler(Handler):'))
        result = self.check_map()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing fake-hub handler', result.stderr)

    def test_unregistered_map_and_duplicate_names_fail(self):
        path = self.root / '.claude/skills/verify-wazig/features/extra.md'
        path.write_text('unregistered')
        self.assertNotEqual(self.check_map().returncode, 0)
        path.unlink()
        self.registry['journeys'].append(self.registry['journeys'][0])
        self.save_registry()
        self.assertIn('duplicate or empty registry journeys', self.check_map().stderr)

    def test_hand_maintained_catalogs_fail(self):
        for filename in ['SKILL.md', 'INDEX.md', 'features/README.md']:
            with self.subTest(filename=filename):
                path = self.root / '.claude/skills/verify-wazig' / filename
                original = path.read_text()
                path.write_text(original + '\n| [search](search.md) | hand-maintained |\n')
                self.assertIn('hand-maintained journey table', self.check_map().stderr)
                path.write_text(original)

    def test_plan_yaml_and_nightly_matrix(self):
        verify = self.workflow['jobs']['verify']
        self.assertEqual(verify['needs'], 'plan')
        self.assertEqual(verify['strategy']['matrix'], '${{ fromJSON(needs.plan.outputs.matrix) }}')
        evidence = next(step for step in verify['steps'] if step.get('name') == 'Validate surviving journey evidence')
        self.assertEqual(evidence['if'], 'matrix.evidence')
        result, output = self.plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        matrix = json.loads(output.removeprefix('matrix='))
        self.assertEqual(matrix['include'], [dict(feature=row['name'], evidence=row['evidence'])
                                            for row in self.registry['journeys']])
        self.assertEqual(json.loads(result.stdout), matrix)

    def test_plan_dispatch_accepts_every_registered_name_and_rejects_unknown(self):
        for row in self.registry['journeys']:
            with self.subTest(name=row['name']):
                result, output = self.plan('workflow_dispatch', row['name'])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(output.removeprefix('matrix=')),
                                 dict(include=[dict(feature=row['name'], evidence=row['evidence'])]))
        for name in ['unknown-journey', "search'); throw 'invalid", 'Search']:
            result, output = self.plan('workflow_dispatch', name)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Unknown verification journey:', result.stderr)
            self.assertEqual(output, '')

    def test_wrong_verification_triggers_fail_map(self):
        path = self.root / '.github/workflows/verify.yml'
        original = path.read_text()
        for changed in [original.replace('  schedule:', '  push:'),
                        original.replace('  schedule:', '  pull_request:\n  schedule:'),
                        original.replace('selected = journeys', "selected = [row for row in journeys if row['pr']]")]:
            with self.subTest(changed=changed != original):
                self.assertNotEqual(changed, original)
                path.write_text(changed)
                self.assertNotEqual(self.check_map().returncode, 0)
        path.write_text(original)

    def test_plan_without_plan_matrix_fails_map(self):
        path = self.root / '.github/workflows/verify.yml'
        path.write_text(path.read_text().replace('fromJSON(needs.plan.outputs.matrix)', 'fromJSON(inputs.feature)'))
        self.assertIn('verify must use plan-job matrix', self.check_map().stderr)

    def test_all_fake_hub_switches_select_registered_handlers(self):
        namespace = runpy.run_path(str(self.tools / 'fake-hub.py'))
        parser, journeys = namespace['journey_parser']()
        for mode, row in journeys.items():
            with self.subTest(mode=mode):
                args = parser.parse_args(['--' + mode, '--port-file', 'port', '--log', 'log'])
                self.assertEqual(args.mode, mode)
                config = row['hub_handler']
                loaded = namespace if config['file'] == 'fake-hub.py' else runpy.run_path(str(self.tools / config['file']), init_globals=namespace)
                self.assertIn(config['class'], loaded)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(['--mixed-lid', '--voice', '--port-file', 'port', '--log', 'log'])

    def test_new_journey_only_changes_registry_and_own_files(self):
        before = {str(path.relative_to(self.root)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in self.root.rglob('*') if path.is_file()}
        row = dict(name='extra-journey', pr=True, evidence=True, hub='extra-mode', chats=7,
                   hub_handler={'file': 'extra-hub.py', 'class': 'ExtraHandler'},
                   script='journey-extra-journey.ps1', maximize=True,
                   validator={'file': 'check-extra-evidence.py', 'function': 'check_extra'})
        self.registry['journeys'].append(row)
        self.save_registry()
        (self.tools / row['script']).write_text("Assert-That $true 'Synthetic extra journey'\n")
        (self.tools / 'extra-hub.py').write_text('class ExtraHandler(Handler):\n    pass\n')
        (self.tools / 'check-extra-evidence.py').write_text(
            "def check_extra(folder):\n    assert (folder / 'extra-proof').read_text() == 'proof'\n    print('EXTRA EVIDENCE VERIFIED')\n")
        (self.root / '.claude/skills/verify-wazig/features/extra-journey.md').write_text(
            '# Extra journey\n\n## Sub-features\n\nSynthetic fixture.\n\n## How to get to it (user POV)\n\nSynthetic entry.\n\n'
            '## Driving it with PowerShell UI Automation\n\nDispatch feature=extra-journey.\n\n## Gotchas\n\nSynthetic only.\n')
        self.assert_map_passes()
        changed = [name for name, digest in before.items()
                   if hashlib.sha256((self.root / name).read_bytes()).hexdigest() != digest]
        self.assertEqual(changed, ['tools/verify-wazig/journeys.json'])
        result, output = self.plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(dict(feature='extra-journey', evidence=True), json.loads(output.removeprefix('matrix='))['include'])
        namespace = runpy.run_path(str(self.tools / 'fake-hub.py'))
        server = unittest.mock.Mock()
        server.server_port = 1234
        with patch.dict(os.environ, GITHUB_ACTIONS='true'), patch.object(sys, 'argv', ['fake-hub.py', '--extra-mode',
                '--port-file', str(self.root / 'port'), '--log', str(self.root / 'log')]), \
                patch.dict(namespace['main'].__globals__, ThreadingHTTPServer=server):
            namespace['main']()
        self.assertEqual(server.call_args.args[1].__name__, 'ExtraHandler')
        marker_namespace = runpy.run_path(str(self.root / 'tools/check_private_markers.py'))
        self.assertIn('.claude/skills/verify-wazig/features/extra-journey.md', marker_namespace['PUBLIC_SKILL_PATHS'])
        (self.root / 'session.json').write_text(json.dumps({'feature': 'extra-journey'}))
        (self.root / 'extra-proof').write_text('proof')
        result = subprocess.run([sys.executable, str(self.tools / 'check-evidence.py'), str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('EXTRA EVIDENCE VERIFIED', result.stdout)
        (self.root / 'extra-proof').unlink()
        self.assertNotEqual(subprocess.run([sys.executable, str(self.tools / 'check-evidence.py'), str(self.root)],
                                          capture_output=True).returncode, 0)


class HubArchiveEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.checker = runpy.run_path(str(ROOT / 'tools/verify-wazig/check-hub-archive-evidence.py'))

    def fixture(self):
        c = self.checker
        def write(chat, archived):
            return dict(method='POST', wire_path='/v1/wazig/archive', status=200, body=dict(chat=chat, archived=archived))
        return [write(c['PLAIN_REACTED'], True), write(c['PLAIN_REACTED'], False), write(c['PLAIN_REACTED'], True),
                dict(method='POST', wire_path='/fixture/phone-unarchive'),
                dict(method='GET', wire_path='/v1/wazig/chats', rows=[dict(jid=c['PLAIN_REACTED'], archived=False)]),
                write(c['PLAIN_NEWER'], True), dict(method='POST', wire_path='/fixture/plain-incoming'),
                dict(method='GET', wire_path='/v1/wazig/chats', rows=[dict(jid=c['PLAIN_NEWER'], archived=False)]),
                write(c['OTHER'], True), write(c['PLAIN_NEWER'], True), write(c['PLAIN_REACTED'], True),
                write(c['PLAIN_REACTED'], False), write(c['PLAIN_REACTED'], True)]

    def test_provider_actions_and_phone_events(self):
        self.checker['check_provider_requests'](self.fixture())

    def test_missing_or_failed_provider_write_is_rejected(self):
        for index, row in enumerate(self.fixture()):
            if row['wire_path'] != '/v1/wazig/archive':
                continue
            for failure in ('missing', 'failed'):
                rows = self.fixture()
                if failure == 'missing':
                    rows.pop(index)
                else:
                    rows[index]['status'] = 502
                with self.assertRaises(AssertionError):
                    self.checker['check_provider_requests'](rows)

    def test_kept_and_telegram_writes_are_rejected(self):
        for chat in (self.checker['GROUP'], self.checker['TELEGRAM']):
            rows = self.fixture()
            rows.append(dict(method='POST', wire_path='/v1/wazig/archive', status=200, body=dict(chat=chat, archived=True)))
            with self.assertRaisesRegex(AssertionError, 'KEPT_AND_OTHER_PROVIDERS_STAY_LOCAL'):
                self.checker['check_provider_requests'](rows)

    def test_missing_phone_or_incoming_state_is_rejected(self):
        for index in (4, 7):
            rows = self.fixture()
            rows[index]['rows'][0]['archived'] = True
            with self.assertRaises(AssertionError):
                self.checker['check_provider_requests'](rows)


class HubLocalArchiveJourneyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def fixture(self, provider, version='0.0.526'):
        title = provider.title()
        chat = 'telegram:user:1001' if provider == 'telegram' else 'signal:fixture-contact'
        limited = 'telegram:user:1002' if provider == 'telegram' else 'signal:fixture-limited'
        count = 5 if provider == 'telegram' else 4
        message = '1001' if provider == 'telegram' else 'fixture-sender:1001'
        other_ids = [limited, 'telegram:user:9001', 'telegram:chat:2001', 'telegram:channel:3001'] if provider == 'telegram' else [limited, 'signal:fixture-captcha', 'signal:fixture-group']
        rows = [dict(id=identity, provider=provider, view_account=provider, archived=False, saved=identity == 'telegram:user:9001', unread=False) for identity in [chat, *other_ids]]
        gates = ['linked-chats', 'history', 'mark-read', 'media', 'react', 'send-text', 'send-file', 'live-events', 'limited', 'local-archive-unarchive']
        if provider == 'telegram':
            gates += ['avatars', 'reply']
        else:
            gates += ['captcha', 'inbox']
        data = {
            'session.json': dict(feature=provider, sha256='fixture', commit='fixture', expected_version=version, pid=1234),
            'doctor.json': dict(version=version),
            'result.json': dict(feature=provider, status='passed'),
            'marks.json': dict(brand_blue_pixels=21),
            'palette.json': ['Show Telegram'],
            'telegram-avatars-layout.json': dict(ids=[row['id'] for row in rows]),
            'file.json': dict(sha256='fixture-file', size=10),
            'side-effects.json': dict(pending_sends=0, pending_archives=0, sync='stopped', slack_connected=False,
                                      production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True),
        }
        if provider == 'telegram':
            for phase in ('before-clear', 'after-clear', 'after-palette', 'before-archive'):
                selected = limited if phase in ('before-clear', 'after-clear') else chat
                data[f'telegram-archive-{phase}.json'] = dict(
                    phase=phase, foreground_hwnd=100, foreground_process_id=1234, gui_thread_ok=True, gui_thread_id=12,
                    focused_hwnd=101, focused_process_id=1234, focused_native_process_id=1234,
                    focused_class='RICHEDIT50W', focused_automation_id='1032', focused_text='',
                    composer_hwnd=101, composer_process_id=1234, composer_class='RICHEDIT50W',
                    composer_automation_id='1032', composer_text='', selected=dict(id=selected), bulk_selected_count=0)
        names = ['linked', 'history', 'read', 'reacted', 'text', 'file', 'live', 'limited', 'after', 'archived-inbox', 'archived', 'unarchived-archive']
        names += ['reply'] if provider == 'telegram' else ['captcha']
        for name in names:
            selected_rows = copy.deepcopy(rows)
            if name == 'archived-inbox':
                selected_rows = selected_rows[1:]
            elif name == 'archived':
                selected_rows = [dict(rows[0], archived=True)]
            elif name == 'unarchived-archive':
                selected_rows = []
            data[f'{name}.state.json'] = dict(version=version, view=provider, current_view=dict(provider=provider, account=provider, label=title, inbox=False),
                                            chat_count=len(selected_rows), show_archived=name in ('archived', 'unarchived-archive'),
                                            pending_archives=0, pending_sends=0, theme='amoled', selected=dict(id=chat))
            data[f'{name}.chats.json'] = dict(total=len(selected_rows), chats=selected_rows)
            (self.folder / f'{name}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + bytes(10000))
            (self.folder / f'{name}.uia.txt').write_text(f'MessagesZig | {title} - Postbox v{version}')
        if provider == 'signal':
            data['inbox.state.json'] = dict(version=version, view='inbox', current_view=dict(provider='', account='', label='Combined inbox', inbox=True), chat_count=len(rows))
            data['inbox.chats.json'] = dict(total=len(rows), chats=copy.deepcopy(rows))
            (self.folder / 'inbox.png').write_bytes(b'\x89PNG\r\n\x1a\n' + bytes(10000))
        data['history.messages.json'] = dict(chat=dict(id=chat), messages=[dict(id=message.replace('1001', '1000'), text=f'Synthetic {title} history')])
        data['reacted.messages.json'] = dict(messages=[dict(id=message, reaction='\U0001f44d')])
        data['live.messages.json'] = dict(messages=[dict(id=message.replace('1001', '1002'), text=f'Synthetic {title} live')])
        requests = [dict(method='POST', path='/v1/wazig/mark-read', body=dict(chat=chat, message_id=message), status=200),
                    dict(method='GET', path='/v1/wazig/media/fixture', status=200),
                    dict(method='POST', path='/v1/wazig/react', body=dict(chat=chat, msg=message, emoji='\U0001f44d', client_id='fixture'), status=200),
                    dict(method='SSE', path='/v1/wazig/events', kind='message' if provider == 'telegram' else 'msg', chat=chat)]
        for name in ['text', 'file'] + (['reply'] if provider == 'telegram' else []):
            text = f'Synthetic {title} ' + ('outgoing' if name == 'text' else name)
            body = dict(chat=chat, text=text, reply_to=message if name == 'reply' else '', client_id='fixture')
            if name == 'file':
                body['file'] = 'fixture.png'
            requests.append(dict(method='POST', path='/v1/wazig/send', body=body, status=200, accepted=True,
                                 multipart=name == 'file', file_sha256='fixture-file', file_size=10))
            data[f'{name}.messages.json'] = dict(messages=[dict(text=text, from_me=True, media_type='image' if name == 'file' else '')])
        failures = [('limited', limited, 429, f'{provider} rate limited')]
        if provider == 'signal':
            failures.append(('captcha', 'signal:fixture-captcha', 403, 'signal captcha required'))
        for name, identity, code, reason in failures:
            requests.append(dict(method='POST', path='/v1/wazig/send', body=dict(chat=identity), status=code))
            data[f'{name}.messages.json'] = dict(chat=dict(id=identity), messages=[dict(send_state='failed', text=reason)])
        for row in requests:
            row['authorized'] = True
        self.requests = requests
        self.data = data
        self.chat = chat
        self.provider = provider
        self.checker = runpy.run_path(str(ROOT / f'tools/verify-wazig/check-{provider}-evidence.py'))
        keys = ['^2' if provider == 'telegram' else '^3', '%k', 'Compose message', 'Attach photo or file',
                f'Synthetic {title} outgoing', f'Synthetic {title} file', 'Synthetic rejected send', 'Like', '{ENTER}']
        if provider == 'telegram':
            keys += ['Verification Telegram']
        keys += ['^e', 'Show archived chats', '^e', 'Show inbox chats']
        if provider == 'telegram':
            keys += ['Reply to selected message', 'Synthetic Telegram reply']
        else:
            keys += ['%i']
        actions = ''.join(f'keys: {key}\n' for key in keys)
        if provider == 'telegram':
            actions = actions.replace('keys: Verification Telegram\n', 'telegram-clear: begin\ntelegram-clear: end\nkeys: Verification Telegram\n')
        (self.folder / 'actions.log').write_text(actions)
        (self.folder / 'hub-proof.log').write_text('\n'.join(f'{provider} {gate} PASS' for gate in gates))
        (self.folder / 'result.txt').write_text(f'JOURNEY PASSED: {provider}')
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED:')

    def check(self):
        for name, value in self.data.items():
            (self.folder / name).write_text(json.dumps(value))
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in self.requests))
        check = self.checker[f'check_{self.provider}']
        with patch.dict(check.__globals__, check_avatar_pixels=lambda folder: None, check_avatar_requests=lambda folder, requests: None):
            check(self.folder)

    def test_both_local_archive_journeys_pass(self):
        for provider in ('telegram', 'signal'):
            with self.subTest(provider=provider):
                self.fixture(provider)
                self.check()

    def test_telegram_focus_and_bulk_observations_reject_wrong_input(self):
        for phase, field, value in [
            ('before-clear', 'focused_hwnd', 102),
            ('before-clear', 'focused_native_process_id', 9999),
            ('before-clear', 'foreground_process_id', 9999),
            ('before-clear', 'gui_thread_ok', False),
            ('before-clear', 'focused_automation_id', '1016'),
            ('after-clear', 'composer_text', 'not cleared'),
            ('after-clear', 'focused_hwnd', 102),
            ('after-clear', 'bulk_selected_count', 5),
            ('after-palette', 'selected', dict(id='telegram:user:1002')),
            ('before-archive', 'bulk_selected_count', 5),
        ]:
            with self.subTest(phase=phase, field=field):
                self.fixture('telegram')
                self.data[f'telegram-archive-{phase}.json'][field] = value
                with self.assertRaises(AssertionError):
                    self.check()

    def test_telegram_clear_requires_keys_only_for_nonempty_composer(self):
        marker = 'telegram-clear: begin\ntelegram-clear: end\n'
        key = 'keys: ^a{BACKSPACE}\n'
        for nonempty, logged in ((False, False), (True, True), (False, True), (True, False)):
            with self.subTest(nonempty=nonempty, logged=logged):
                self.fixture('telegram')
                before = self.data['telegram-archive-before-clear.json']
                before['composer_text'] = before['focused_text'] = 'retained draft' if nonempty else ''
                path = self.folder / 'actions.log'
                actions = path.read_text()
                if logged:
                    actions = actions.replace(marker, 'telegram-clear: begin\n' + key + 'telegram-clear: end\n')
                path.write_text(actions)
                if nonempty == logged:
                    self.check()
                else:
                    with self.assertRaises(AssertionError):
                        self.check()

    def test_telegram_clear_rejects_missing_or_reordered_boundaries(self):
        for replacement in ('', 'telegram-clear: end\ntelegram-clear: begin\n'):
            with self.subTest(replacement=replacement):
                self.fixture('telegram')
                path = self.folder / 'actions.log'
                path.write_text(path.read_text().replace('telegram-clear: begin\ntelegram-clear: end\n', replacement))
                with self.assertRaises(AssertionError):
                    self.check()

    def test_signal_chats_missing_from_combined_inbox_fail(self):
        for defect in ('empty', 'other-provider'):
            with self.subTest(defect=defect):
                self.fixture('signal')
                if defect == 'empty':
                    self.data['inbox.chats.json'] = dict(total=0, chats=[])
                    self.data['inbox.state.json']['chat_count'] = 0
                else:
                    for row in self.data['inbox.chats.json']['chats']:
                        row['provider'] = 'whatsapp'
                with self.assertRaises(AssertionError):
                    self.check()

    def test_telegram_exact_pr_and_release_versions_pass(self):
        for version in ('0.0.526', '0.9.203', '0.9.204'):
            with self.subTest(version=version):
                self.fixture('telegram', version)
                self.check()

    def test_telegram_wrong_title_control_or_capture_version_fails(self):
        for defect in ('title', 'control', 'capture'):
            with self.subTest(defect=defect):
                self.fixture('telegram', '0.9.204')
                if defect == 'title':
                    (self.folder / 'linked.uia.txt').write_text('MessagesZig | Telegram - Postbox v0.0.526')
                elif defect == 'control':
                    self.data['doctor.json']['version'] = '0.0.526'
                else:
                    self.data['linked.state.json']['version'] = '0.0.526'
                with self.assertRaises(AssertionError):
                    self.check()

    def test_any_archive_post_for_target_fails(self):
        for provider in ('telegram', 'signal'):
            for status in (200, 502):
                with self.subTest(provider=provider, status=status):
                    self.fixture(provider)
                    self.requests.append(dict(method='POST', path='/v1/wazig/archive', body=dict(chat=self.chat), status=status, authorized=True))
                    with self.assertRaisesRegex(AssertionError, 'must stay local'):
                        self.check()

    def test_missing_or_wrong_archive_transition_fails(self):
        for provider in ('telegram', 'signal'):
            for name in ('archived-inbox', 'archived', 'unarchived-archive', 'after'):
                for defect in ('wrong-row', 'pending', 'wrong-view', 'wrong-count'):
                    with self.subTest(provider=provider, name=name, defect=defect):
                        self.fixture(provider)
                        state = self.data[f'{name}.state.json']
                        rows = self.data[f'{name}.chats.json']['chats']
                        if defect == 'wrong-row':
                            if name in ('archived', 'after'):
                                next(row for row in rows if row['id'] == self.chat)['id'] = 'wrong-chat'
                            elif rows:
                                rows[0]['id'] = self.chat
                            else:
                                rows.append(dict(id=self.chat, provider=provider, archived=False))
                        elif defect == 'pending':
                            state['pending_archives'] = 1
                        elif defect == 'wrong-view':
                            state['show_archived'] = not state['show_archived']
                        else:
                            state['chat_count'] += 1
                        with self.assertRaises(AssertionError):
                            self.check()

    def test_wrong_target_provider_or_archive_flag_fails(self):
        for provider in ('telegram', 'signal'):
            for name in ('archived', 'after'):
                for field, value in [('provider', 'whatsapp'), ('archived', name != 'archived')]:
                    with self.subTest(provider=provider, name=name, field=field):
                        self.fixture(provider)
                        next(row for row in self.data[f'{name}.chats.json']['chats'] if row['id'] == self.chat)[field] = value
                        with self.assertRaises(AssertionError):
                            self.check()

    def test_missing_archive_capture_proof_or_shortcut_fails(self):
        for provider in ('telegram', 'signal'):
            for filename in ('archived.png', 'archived-inbox.state.json', 'unarchived-archive.chats.json', 'hub-proof.log', 'actions.log'):
                with self.subTest(provider=provider, filename=filename):
                    self.fixture(provider)
                    if filename in self.data:
                        self.data.pop(filename)
                        (self.folder / filename).unlink(missing_ok=True)
                    else:
                        (self.folder / filename).write_text('')
                    with self.assertRaises((AssertionError, FileNotFoundError)):
                        self.check()

    def test_journeys_pin_ctrl_e_and_local_archive_transitions(self):
        for provider in ('telegram', 'signal'):
            source = (ROOT / f'tools/verify-wazig/{provider}.ps1').read_text()
            self.assertEqual(source.count("Send-Keys $Session '^e'"), 2)
            for fragment in ["'Show archived chats'", "'Show inbox chats'", 'Save-Screen $Session archived-inbox',
                             'Save-Screen $Session archived', 'Save-Screen $Session unarchived-archive',
                             "Hub-Pass $Session local-archive-unarchive", "$_.method -eq 'POST'"]:
                self.assertIn(fragment, source)
            self.assertNotIn('archive-unsupported', source)
            self.assertNotIn('unsupported archive settled', source)


class ChatListAlignmentTests(unittest.TestCase):
    def test_hanging_indent_evidence_rejects_old_layout_and_weight(self):
        check = runpy.run_path(str(ROOT / 'tools/verify-wazig/evidence-chat-lists.py'), run_name='alignment_test')['check_alignment']
        items = [dict(marker_x=10 + depth, text_x=20 + depth, ink_x=21 + depth,
                      continuations=[dict(x=20 + depth, ink_x=21 + depth, y=30)])
                 for depth in [0, 0, 0, 0, 0, 0, 4, 8]]
        checks = [dict(stage=stage, body_weight=400, font_height=height, items=copy.deepcopy(items))
                  for stage, height in [('baseline', -14), ('larger', -16)]]
        check(checks)
        for mutation in ['weight', 'left-edge', 'marker-edge', 'pixels', 'nesting', 'missing-wrap']:
            broken = copy.deepcopy(checks)
            row = broken[0]
            if mutation == 'weight':
                row['body_weight'] = 500
            elif mutation == 'left-edge':
                row['items'][0]['continuations'][0]['x'] = 0
            elif mutation == 'marker-edge':
                row['items'][0]['continuations'][0]['x'] = row['items'][0]['marker_x']
            elif mutation == 'pixels':
                row['items'][0]['continuations'][0]['ink_x'] -= 5
            elif mutation == 'nesting':
                row['items'][6]['text_x'] = row['items'][5]['text_x']
            else:
                row['items'][0]['continuations'] = []
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                check(broken)



class AttachmentPickerTests(unittest.TestCase):
    def test_owned_attachment_picker_ignores_unavailable_global_focus(self):
        source = (ROOT / 'tools/verify-wazig/harness.ps1').read_text()
        helper = re.search(r'function Get-AttachmentPicker\(\$Session\) \{[\s\S]*?\n\}', source)
        self.assertIsNotNone(helper, 'Attachment selection must use process-owned native dialogs')
        for feature in ('telegram', 'signal'):
            journey = (ROOT / f'tools/verify-wazig/{feature}.ps1').read_text()
            self.assertRegex(journey, r"\$picker = Wait-Until \{\s+Get-AttachmentPicker \$Session\s+\} 'owned attachment picker'")
            self.assertNotIn('AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())', journey)
            for required in ('Attachment WM_SETTEXT failed', 'Attachment filename was not set', 'Attachment BM_CLICK timed out'):
                self.assertIn(required, journey)
        if not shutil.which('pwsh'):
            self.skipTest('PowerShell runtime is exercised by GitHub CI')
        fixture = r"""
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
namespace Windows.Automation {
    public enum TreeScope { Children, Descendants }
    public class AutomationElement {
        public static string ProcessIdProperty = "process";
        public static string ClassNameProperty = "class";
    }
    public class PropertyCondition {
        public string Property;
        public object Value;
        public PropertyCondition(string property, object value) { Property = property; Value = value; }
    }
    public class AndCondition {
        public PropertyCondition[] Rules;
        public AndCondition(PropertyCondition first, PropertyCondition second) { Rules = new[] { first, second }; }
    }
}
public class VerifyWindow {
    public static IntPtr GetForegroundWindow() { throw new InvalidOperationException("Global focus is unavailable"); }
    public static IntPtr FindWindowEx(IntPtr parent, IntPtr after, string name, string title) { return IntPtr.Zero; }
}
public class FixtureElement {
    public FixtureElement Current { get { return this; } }
    public int ProcessId;
    public string ClassName;
    public int NativeWindowHandle;
    public FixtureElement(int pid, string name, int handle) { ProcessId = pid; ClassName = name; NativeWindowHandle = handle; }
}
public class FixtureRoot {
    public static bool ZeroHandle;
    public FixtureElement FindFirst(Windows.Automation.TreeScope scope, Windows.Automation.AndCondition condition) {
        if (scope != Windows.Automation.TreeScope.Descendants) throw new InvalidOperationException("Dialog belongs beneath the verified app");
        foreach (var item in new[] { new FixtureElement(99, "#32770", 1), new FixtureElement(42, "OtherWindow", 2), new FixtureElement(42, "#32770", ZeroHandle ? 0 : 3) }) {
            bool matches = true;
            foreach (var rule in condition.Rules) {
                object value = rule.Property == "process" ? (object)item.ProcessId : item.ClassName;
                if (!Object.Equals(rule.Value, value)) matches = false;
            }
            if (matches) return item;
        }
        return null;
    }
}
'@
function Get-Window($Session) {
    if ($null -eq $Session) { throw 'Missing verified session' }
    return [FixtureRoot]::new()
}
"""
        assertions = r"""
$found = Get-AttachmentPicker @{ pid = 42 }
if ($null -eq $found -or $found.ToInt64() -ne 3) { throw 'Did not select the owned dialog in the application tree' }
$missing = Get-AttachmentPicker @{ pid = 43 }
if ($null -ne $missing) { throw 'Accepted a dialog from another process' }
if ($missing) { throw 'Missing dialog prematurely completed the wait' }
[FixtureRoot]::ZeroHandle = $true
$zero = Get-AttachmentPicker @{ pid = 42 }
if ($null -ne $zero) { throw 'Zero handle prematurely completed the wait' }
Write-Output 'OWNED_PICKER_OK'
"""
        desktop_child_lookup = r"""
function Get-AttachmentPicker($Session) {
    $dialog = [VerifyWindow]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, '#32770', $null)
    if ($dialog -ne [IntPtr]::Zero) { return $dialog }
    return $null
}
"""
        broken = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', fixture + desktop_child_lookup + assertions], capture_output=True, text=True)
        self.assertNotEqual(broken.returncode, 0, broken.stdout + broken.stderr)
        self.assertIn('Did not select the owned dialog', broken.stderr)
        self.assertNotIn('OWNED_PICKER_OK', broken.stdout)
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', fixture + helper.group() + assertions], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OWNED_PICKER_OK', result.stdout)
        print('OWNED_PICKER_RUNTIME_OK')



class AppearanceVersionTests(unittest.TestCase):
    def fixture(self, folder, version):
        session = dict(feature='appearance', sha256='fixture-binary', commit='fixture-commit',
                       expected_version=version, expected_product='Postbox')
        state = dict(version=version, chat_count=3, pending_sends=0, pending_archives=0,
                     sync='stopped', search='', theme='amoled', production_preferences_absent=True,
                     whatsapp_store_absent=True, telegram_store_absent=True)
        files = {'session.json': session, 'side-effects.json': state,
                 'text-scale.json': dict(initial_saved=False, larger=110, reset=100,
                                        baseline_points=10, larger_points=12, reset_points=10)}
        files['shared-design.json'] = dict(width=1920, height=1032, draft='Shared design check',
                                           foreground_pixels=100, raised_pixels=3000,
                                           pill=dict(width=116, height=32))
        files['dictation-transcript.json'] = dict(expected='Shared design check Go forward ten meters.',
                                                  actual='Shared design check Go forward ten meters.')
        for name in ('before', 'action', 'text-larger', 'after', 'group-senders'):
            files[name + '.state.json'] = state
            (folder / (name + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n' + name.encode() * 11000)
            (folder / (name + '.uia.txt')).write_text(f'MessagesZig | Combined inbox - Postbox v{version}\n')
        for name, value in files.items():
            (folder / name).write_text(json.dumps(value))
        (folder / 'group-layout.txt').write_text('GROUP_LAYOUT_OK: fixture')
        (folder / 'group-senders.messages.json').write_text(json.dumps(dict(messages=[dict(id=name) for name in ('GROUP-FIRST', 'GROUP-SAME', 'GROUP-DAY', 'GROUP-OTHER', 'GROUP-QUOTE', 'GROUP-OWN')])))
        (folder / 'result.txt').write_text('JOURNEY PASSED: appearance')
        (folder / 'cleanup.txt').write_text('CLEANUP PASSED: fixture removed')
        (folder / 'preferences.txt').write_text('FontScale 100')
        keys = ('^k', 'Theme: Graphite', 'Make text larger', '{ENTER}', '^0')
        (folder / 'actions.log').write_text('\n'.join('keys: ' + key for key in keys))

    def run_oracle(self, folder, source=None):
        script = ROOT / 'tools/verify-wazig/evidence-palette.py'
        if source is not None:
            script = folder / 'historical-validator.py'
            script.write_text(source)
        return subprocess.run([sys.executable, str(script), str(folder)], capture_output=True, text=True)

    def test_published_version_passes_and_historical_fixed_version_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            self.fixture(folder, '1.2.345')
            result = self.run_oracle(folder)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            old = subprocess.check_output(['git', 'show', '2653484:tools/verify-wazig/evidence-palette.py'], cwd=ROOT, text=True)
            self.assertNotEqual(self.run_oracle(folder, old).returncode, 0)

    def test_actual_dictation_transcript_is_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            self.fixture(folder, '1.2.345')
            (folder / 'run.log').write_text('')
            self.assertEqual(self.run_oracle(folder).returncode, 0)
            (folder / 'dictation-transcript.json').write_text(json.dumps(dict(
                expected='Shared design check Go forward ten meters.', actual='Shared design check')))
            (folder / 'run.log').write_text('recorded PCM reaches the production composer')
            self.assertNotEqual(self.run_oracle(folder).returncode, 0)

    def test_wrong_installed_version_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            self.fixture(folder, '0.0.526')
            session = json.loads((folder / 'session.json').read_text())
            session['expected_version'] = '1.2.345'
            (folder / 'session.json').write_text(json.dumps(session))
            self.assertNotEqual(self.run_oracle(folder).returncode, 0)


if __name__ == '__main__':
    unittest.main()

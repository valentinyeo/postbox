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

    def plan(self, event='pull_request', feature='search'):
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

    def test_plan_yaml_and_pr_matrix(self):
        verify = self.workflow['jobs']['verify']
        self.assertEqual(verify['needs'], 'plan')
        self.assertEqual(verify['strategy']['matrix'], '${{ fromJSON(needs.plan.outputs.matrix) }}')
        evidence = next(step for step in verify['steps'] if step.get('name') == 'Validate surviving journey evidence')
        self.assertEqual(evidence['if'], 'matrix.evidence')
        result, output = self.plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        matrix = json.loads(output.removeprefix('matrix='))
        self.assertEqual(matrix['include'], [dict(feature=row['name'], evidence=row['evidence'])
                                            for row in self.registry['journeys'] if row['pr']])
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
            'session.json': dict(feature=provider, sha256='fixture', commit='fixture', expected_version=version),
            'doctor.json': dict(version=version),
            'result.json': dict(feature=provider, status='passed'),
            'marks.json': dict(brand_blue_pixels=21),
            'palette.json': ['Show Telegram'],
            'telegram-avatars-layout.json': dict(ids=[row['id'] for row in rows]),
            'file.json': dict(sha256='fixture-file', size=10),
            'side-effects.json': dict(pending_sends=0, pending_archives=0, sync='stopped', slack_connected=False,
                                      production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True),
        }
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
                f'Synthetic {title} outgoing', f'Synthetic {title} file', 'Synthetic rejected send', 'Like', '{ENTER}',
                '^e', 'Show archived chats', '^e', 'Show inbox chats']
        if provider == 'telegram':
            keys += ['Reply to selected message', 'Synthetic Telegram reply']
        else:
            keys += ['%i']
        (self.folder / 'actions.log').write_text(''.join(f'keys: {key}\n' for key in keys))
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


if __name__ == '__main__':
    unittest.main()

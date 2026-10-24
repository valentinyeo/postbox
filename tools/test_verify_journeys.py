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
                self.assertIn(row['hub_handler']['class'], namespace)
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
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.checker = runpy.run_path(str(ROOT / 'tools/verify-wazig/check-hub-archive-evidence.py'))
        self.reacted = self.checker['PLAIN_REACTED']
        self.newer = self.checker['PLAIN_NEWER']
        self.data = {
            'plain-dms.json': dict(chats=[self.reacted, self.newer], last_message_ts={
                self.reacted: '2026-10-10T11:30:00Z', self.newer: '2026-10-10T11:00:00Z'}),
            'plain.requests.json': [self.write(self.reacted, True), self.write(self.newer, True),
                                    dict(method='GET', wire_path='/v1/wazig/chats?archived=true&limit=500', status=200)],
            'plain-scan.json': dict(elapsed_ms=360000, requests_before=2),
        }
        for name, archived, chats in [('plain-inbox', False, [self.checker['OTHER']]),
                                     ('plain-archived', True, [self.checker['GROUP'], self.reacted, self.newer])]:
            self.data[f'{name}.state.json'] = dict(show_archived=archived, chat_count=len(chats))
            self.data[f'{name}.chats.json'] = dict(total=len(chats), chats=[dict(id=chat, archived=archived) for chat in chats])
            (self.folder / f'{name}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + bytes(10000))
        (self.folder / 'plain-archive-state.txt').write_text('')
        (self.folder / 'hub-proof.log').write_text('hub-archive plain PASS')

    def write(self, chat, archived):
        return dict(method='POST', wire_path='/v1/wazig/archive', status=200, body=dict(chat=chat, archived=archived))

    def check(self):
        self.checker['check_plain'](self.folder, self.data.__getitem__, 0)

    def test_plain_chats_stay_archived(self):
        self.check()

    def test_legacy_plain_entry_evidence_fails(self):
        for chat in (self.reacted, self.newer):
            (self.folder / 'plain-archive-state.txt').write_text(f'{chat}\t0\tbaseline\n')
            with self.assertRaisesRegex(AssertionError, 'must not persist an entry'):
                self.check()

    def test_old_app_incoming_unarchive_and_reaction_unarchive_fail(self):
        for chat in [self.reacted, self.newer]:
            with self.subTest(chat=chat):
                self.data['plain.requests.json'].append(self.write(chat, False))
                with self.assertRaisesRegex(AssertionError, 'unarchived without a user action'):
                    self.check()
                self.data['plain.requests.json'].pop()

    def test_short_wait_or_missing_archived_scan_fails(self):
        self.data['plain-scan.json']['elapsed_ms'] = 359999
        with self.assertRaises(AssertionError):
            self.check()
        self.data['plain-scan.json']['elapsed_ms'] = 360000
        self.data['plain.requests.json'].pop()
        with self.assertRaisesRegex(AssertionError, 'archived scan never ran'):
            self.check()

    def test_inbox_return_or_missing_archived_chat_fails(self):
        for chat in [self.reacted, self.newer]:
            with self.subTest(chat=chat):
                rows = self.data['plain-inbox.chats.json']['chats']
                rows.append(dict(id=chat, archived=False))
                with self.assertRaises(AssertionError):
                    self.check()
                rows.pop()
                rows = self.data['plain-archived.chats.json']['chats']
                saved = rows[:]
                rows[:] = [row for row in rows if row['id'] != chat]
                with self.assertRaises(AssertionError):
                    self.check()
                rows[:] = saved


class HubTelegramArchiveEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.checker = runpy.run_path(str(ROOT / 'tools/verify-wazig/check-hub-archive-evidence.py'))
        self.telegram = self.checker['TELEGRAM']
        self.newer = self.checker['PLAIN_NEWER']
        self.other = self.checker['OTHER']
        group, reacted = self.checker['GROUP'], self.checker['PLAIN_REACTED']
        self.all_chats = [group, self.other, reacted, self.newer, self.telegram]
        self.data = {
            'telegram-dm.json': dict(chat=self.telegram, provider='telegram', account='telegram'),
            'plain-incoming.json': dict(chats=[self.newer, self.telegram], archived=False, last_message_ts='2026-10-10T14:00:00Z'),
            'telegram.requests.json': [
                dict(wire_path='/v1/wazig/chats?archived=false&limit=250', status=200,
                     rows=[dict(jid=chat, last_message_ts='2026-10-10T13:00:00Z', archived=False) for chat in (self.newer, self.telegram)]),
                self.write(reacted), self.write(self.newer), self.write(self.other),
                dict(wire_path='/fixture/plain-incoming', status=200),
                dict(wire_path='/v1/wazig/chats?archived=false&limit=250', status=200,
                     rows=[dict(jid=chat, last_message_ts='2026-10-10T14:00:00Z', archived=False) for chat in (self.newer, self.telegram)]),
                dict(wire_path='/fixture/rearchive-enable', status=200),
                self.write(self.newer), self.write(self.other, False),
            ],
        }
        for name, archived, chats in [
            ('telegram-only', False, [self.telegram]), ('telegram-empty', False, []),
            ('telegram-unarchived', False, [self.telegram]),
            ('telegram-bulk-empty', False, []), ('telegram-restart-empty', False, []),
            ('telegram-restart-archived', True, self.all_chats), ('plain-incoming-inbox', False, [self.newer]),
            ('plain-incoming-archived', True, [chat for chat in self.all_chats if chat != self.newer]),
            ('plain-rearchived-inbox', False, []),
            ('plain-rearchived-archived', True, self.all_chats),
        ]:
            self.data[f'{name}.state.json'] = dict(view='all', show_archived=archived, chat_count=len(chats), pending_archives=0,
                                                 selected=dict(id=self.telegram) if chats else None)
            self.data[f'{name}.chats.json'] = dict(total=len(chats), chats=[dict(id=chat, archived=archived,
                provider='telegram' if chat == self.telegram else 'whatsapp', account='telegram' if chat == self.telegram else 'personal') for chat in chats])
            (self.folder / f'{name}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + bytes(10000))
            (self.folder / f'{name}.uia.txt').write_text('MessagesZig | Combined inbox - Wazig v0.0.526')
        (self.folder / 'telegram-archive-state.txt').write_text(''.join(
            (f"telegram\ttelegram\t{chat}\n" if chat == self.telegram else
             f"{chat}\t1\t2026-10-10T14:00:00Z\n") for chat in (group, self.telegram)))
        (self.folder / 'actions.log').write_text('keys: %i\nkeys: ^a\nkeys: ^e\n')
        (self.folder / 'hub-proof.log').write_text('hub-archive telegram-single-bulk-restart-incoming PASS')

    def write(self, chat, archived=True, status=200):
        return dict(wire_path='/v1/wazig/archive', status=status, body=dict(chat=chat, archived=archived))

    def check(self):
        self.checker['check_telegram'](self.folder, self.data.__getitem__)

    def test_hub_unsupported_providers_use_local_archive_route(self):
        source = (ROOT / 'src/main.zig').read_text()
        archive = source.split('fn archiveChat(', 1)[1].split('fn archiveChatKey(', 1)[0]
        local_route = archive.split('state.setLocalArchived(key, !unarchive)', 1)[0]
        self.assertIn('unifiedHub(a)', local_route)
        self.assertIn('key.provider == .telegram', local_route)
        self.assertIn('key.provider == .signal', local_route)

    def test_complete_telegram_and_network_unarchive_proof_passes(self):
        self.check()

    def test_missing_initial_or_explicit_plain_archive_evidence_fails(self):
        original = copy.deepcopy(self.data['telegram.requests.json'])
        for index in (2, 7):
            with self.subTest(missing_archive=index):
                self.data['telegram.requests.json'] = copy.deepcopy(original)
                self.data['telegram.requests.json'].pop(index)
                with self.assertRaises(AssertionError):
                    self.check()

    def test_any_telegram_hub_write_or_duplicate_whatsapp_rearchive_fails(self):
        for status in (200, 502):
            self.data['telegram.requests.json'].append(self.write(self.telegram, status=status))
            with self.assertRaisesRegex(AssertionError, 'must stay local'):
                self.check()
            self.data['telegram.requests.json'].pop()
        self.data['telegram.requests.json'].append(self.write(self.newer))
        with self.assertRaises(AssertionError):
            self.check()
        self.data['telegram.requests.json'].pop()
        self.data['telegram.requests.json'][-2]['body']['chat'] = 'telegram:user:wrong'
        with self.assertRaises(AssertionError):
            self.check()

    def test_automatic_plain_rearchive_attempt_evidence_fails(self):
        self.data['telegram.requests.json'].insert(6, self.write(self.newer, status=409))
        with self.assertRaisesRegex(AssertionError, 'must not auto-rearchive'):
            self.check()

    def test_legacy_plain_entries_after_restart_evidence_fail(self):
        path = self.folder / 'telegram-archive-state.txt'
        original = path.read_text()
        for chat in (self.newer, self.other, self.checker['PLAIN_REACTED']):
            path.write_text(original + f'{chat}\t0\tbaseline\n')
            with self.assertRaisesRegex(AssertionError, 'must not persist an entry'):
                self.check()

    def test_hub_must_really_unarchive_both_with_newer_timestamps(self):
        original = copy.deepcopy(self.data['telegram.requests.json'])
        for index in (0, 1):
            for field, value in [('archived', True), ('last_message_ts', '2026-10-10T13:00:00Z')]:
                with self.subTest(index=index, field=field):
                    self.data['telegram.requests.json'] = copy.deepcopy(original)
                    self.data['telegram.requests.json'][5]['rows'][index][field] = value
                    with self.assertRaises(AssertionError):
                        self.check()

    def test_inbox_return_missing_restart_archive_or_wrong_provider_fails(self):
        for name in ('telegram-empty', 'telegram-bulk-empty', 'telegram-restart-empty', 'plain-incoming-inbox', 'plain-rearchived-inbox'):
            with self.subTest(name=name):
                self.data[f'{name}.chats.json']['chats'].append(dict(id=self.telegram, archived=False))
                with self.assertRaises(AssertionError):
                    self.check()
                self.data[f'{name}.chats.json']['chats'].pop()
        for name in ('telegram-restart-archived', 'plain-incoming-archived', 'plain-rearchived-archived'):
            rows = self.data[f'{name}.chats.json']['chats']
            row = next(row for row in rows if row['id'] == self.telegram)
            row['provider'] = 'whatsapp'
            with self.assertRaises(AssertionError):
                self.check()
            row['provider'] = 'telegram'
            rows.remove(row)
            with self.assertRaises(AssertionError):
                self.check()
            rows.append(row)

    def test_missing_explicit_unarchive_proof_fails(self):
        self.data['telegram-unarchived.chats.json']['chats'].clear()
        with self.assertRaises(AssertionError):
            self.check()

    def test_lost_plain_state_fails(self):
        path = self.folder / 'telegram-archive-state.txt'
        path.write_text(''.join(line for line in path.read_text().splitlines(keepends=True) if not line.startswith('telegram\ttelegram\t' + self.telegram)))
        with self.assertRaises(ValueError):
            self.check()


class HubLocalArchiveJourneyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def fixture(self, provider):
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
            gates += ['captcha']
        data = {
            'session.json': dict(feature=provider, sha256='fixture', commit='fixture'),
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
            data[f'{name}.state.json'] = dict(view=provider, current_view=dict(provider=provider, account=provider, label=title, inbox=False),
                                            chat_count=len(selected_rows), show_archived=name in ('archived', 'unarchived-archive'),
                                            pending_archives=0, pending_sends=0, theme='amoled', selected=dict(id=chat))
            data[f'{name}.chats.json'] = dict(total=len(selected_rows), chats=selected_rows)
            (self.folder / f'{name}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + bytes(10000))
            (self.folder / f'{name}.uia.txt').write_text(f'MessagesZig | {title} - Wazig v0.0.526')
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
        keys = ['%1' if provider == 'telegram' else '%2', '%k', 'Compose message', 'Attach photo or file',
                f'Synthetic {title} outgoing', f'Synthetic {title} file', 'Synthetic rejected send', 'Like', '{ENTER}',
                '^e', 'Show archived chats', '^e', 'Show inbox chats']
        if provider == 'telegram':
            keys += ['Reply to selected message', 'Synthetic Telegram reply']
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


if __name__ == '__main__':
    unittest.main()

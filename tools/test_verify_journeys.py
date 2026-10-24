import contextlib
import copy
import hashlib
import io
import json
import os
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


if __name__ == '__main__':
    unittest.main()

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools/verify-wazig'


class BaseReproCacheTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        self.steps = self.workflow['jobs']['base-fails']['steps']
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.evidence = Path(self.temp.name)
        self.result_file = self.evidence / 'classification.json'

    def classify(self, code):
        return subprocess.run([sys.executable, str(TOOLS / 'classify_red.py'), '--feature', 'search',
                               '--evidence', str(self.evidence), '--exit-code', str(code),
                               '--result-file', str(self.result_file)], capture_output=True, text=True)

    def test_reproduced_result_survives_cache_roundtrip(self):
        (self.evidence / 'journey-check-failed.txt').write_text('search: visible result missing')
        result = self.classify(1)
        self.assertEqual(result.returncode, 0, result.stderr)
        cached = self.result_file.read_bytes()
        self.result_file.unlink()
        self.result_file.write_bytes(cached)
        self.assertEqual(json.loads(self.result_file.read_text()), {
            'feature': 'search', 'classification': 'reproduced', 'check': 'search: visible result missing',
        })

    def test_pass_infrastructure_and_wrong_marker_do_not_cache_success(self):
        for code, marker in ((0, 'search: app check'), (1, None), (1, 'voice: app check'), (1, 'search: ')):
            with self.subTest(code=code, marker=marker):
                self.result_file.write_text('{"classification":"reproduced"}')
                failure = self.evidence / 'journey-check-failed.txt'
                failure.unlink(missing_ok=True)
                if marker is not None:
                    failure.write_text(marker)
                result = self.classify(code)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.result_file.exists())

    def test_cache_key_uses_base_feature_registered_script_and_shared_tools(self):
        cache_index = next(i for i, step in enumerate(self.steps) if step.get('id') == 'base-cache')
        cache = self.steps[cache_index]
        self.assertEqual(cache['uses'], 'actions/cache@v4')
        self.assertEqual(cache['with']['path'], 'base-evidence/classification.json')
        key = cache['with']['key']
        for part in ('github.event.pull_request.base.sha', 'needs.plan.outputs.repro',
                     "hashFiles(format('pr-head/tools/verify-wazig/{0}', steps.journey.outputs.script))",
                     "hashFiles('pr-head/tools/verify-wazig/**')", 'env.BASE_ZIG_VERSION', 'env.BASE_APP_VERSION'):
            self.assertIn(part, key)
        self.assertNotIn('restore-keys', cache['with'])
        checkouts = [step for step in self.steps[:cache_index] if step.get('uses') == 'actions/checkout@v4']
        self.assertEqual(len(checkouts), 2)
        self.assertEqual(checkouts[-1]['with']['path'], 'pr-head')

    def test_script_resolver_handles_shared_journey_filename(self):
        step = next(step for step in self.steps if step.get('id') == 'journey')
        root = self.evidence
        registry = root / 'pr-head/tools/verify-wazig/journeys.json'
        registry.parent.mkdir(parents=True)
        registry.write_bytes((TOOLS / 'journeys.json').read_bytes())
        output = root / 'output'
        result = subprocess.run([sys.executable, '-c', step['run']], cwd=root, capture_output=True, text=True,
                                env=dict(os.environ, FEATURE='hub-migration-before-rename', GITHUB_OUTPUT=str(output)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output.read_text(), 'script=journey-hub-migration-crash.ps1\n')

    def test_cache_hit_skips_all_build_and_run_setup(self):
        heavy = ('Build base desktop', 'Overlay PR journey tools', 'Install audio output', 'Install typing recorder',
                 'Build historical rollback input', 'Install Chrome screenshot driver', 'Run reproduction on base')
        for name in heavy:
            with self.subTest(name=name):
                step = next(step for step in self.steps if step.get('name') == name)
                self.assertIn("steps.base-cache.outputs.cache-hit != 'true'", step['if'])
        zig = next(step for step in self.steps if step.get('uses', '').startswith('mlugg/setup-zig@'))
        self.assertIn("steps.base-cache.outputs.cache-hit != 'true'", zig['if'])
        run = next(step for step in self.steps if step.get('name') == 'Run reproduction on base')
        self.assertIn('-ResultFile base-evidence/classification.json', run['run'])
        classification = next(step for step in self.steps if step.get('id') == 'classification')
        self.assertNotIn('cache-hit', classification['if'])
        self.assertIn('base-evidence/classification.json', classification['run'])
        summary = next(step for step in self.steps if step.get('name') == 'Summarize base cache')
        self.assertEqual(summary['if'], 'always()')
        self.assertIn('GITHUB_STEP_SUMMARY', summary['run'])
        artifact = next(step for step in self.steps if step.get('uses') == 'actions/upload-artifact@v4')
        self.assertEqual(artifact['with']['name'], 'repro-base')
        self.assertEqual(artifact['with']['path'], 'base-evidence/')


if __name__ == '__main__':
    unittest.main()

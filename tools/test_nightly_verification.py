import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


class NightlyVerificationTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())

    def plan_step(self, step_id):
        step = next(step for step in self.workflow['jobs']['plan']['steps'] if step.get('id') == step_id)
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'outputs'
            result = subprocess.run([sys.executable, '-c', step['run']], cwd=ROOT, capture_output=True,
                                    text=True, env=dict(os.environ, EVENT_NAME='schedule', FEATURE='search',
                                                       GITHUB_OUTPUT=str(output)))
            self.assertEqual(result.returncode, 0, result.stderr)
            return dict(line.split('=', 1) for line in output.read_text().splitlines())

    def test_schedule_runs_every_registered_journey(self):
        events = self.workflow.get('on', self.workflow.get(True))
        self.assertEqual(events['schedule'], [{'cron': '40 2 * * *'}])
        outputs = self.plan_step('matrix')
        journeys = json.loads((ROOT / 'tools/verify-wazig/journeys.json').read_text())['journeys']
        self.assertEqual(json.loads(outputs['matrix'])['include'],
                         [{'feature': row['name'], 'evidence': row['evidence']} for row in journeys])
        verify = self.workflow['jobs']['verify']
        self.assertEqual(verify['strategy']['matrix'], '${{ fromJSON(needs.plan.outputs.matrix) }}')
        self.assertIn("github.event_name != 'pull_request'", verify['if'])

    def test_planted_historical_journeys_have_the_same_build_input_as_verify(self):
        planted = self.workflow['jobs']['planted']['steps']
        verify = self.workflow['jobs']['verify']['steps']
        checkout = next(step for step in planted if step.get('uses') == 'actions/checkout@v4')
        self.assertEqual(checkout.get('with', {}).get('fetch-depth'), 0)
        historical = next(step for step in verify if 'build-historical-847.ps1' in step.get('run', ''))
        copied = next(step for step in planted if step.get('name') == historical['name'])
        self.assertEqual(copied, dict(historical, run=historical['run'].replace('verification-evidence/', 'planted-evidence/')))
        self.assertEqual(copied['if'], "matrix.feature == 'hub-rollback' || matrix.feature == 'hub-migration-crash' || matrix.feature == 'hub-migration-before-rename'")
        zig = next(step for step in planted if step.get('uses') == 'mlugg/setup-zig@v2')
        journey = next(step for step in planted if step.get('name') == 'Run planted journey')
        self.assertLess(planted.index(checkout), planted.index(copied))
        self.assertLess(planted.index(zig), planted.index(copied))
        self.assertLess(planted.index(copied), planted.index(journey))
        for feature in ('hub-rollback', 'hub-migration-crash', 'hub-migration-before-rename'):
            with self.subTest(feature=feature):
                patch = ROOT / 'tools/verify-wazig/planted' / (feature + '.patch')
                self.assertTrue(patch.is_file())
                self.assertTrue(patch.with_suffix('.txt').read_text().strip())

    def test_schedule_retains_every_planted_journey(self):
        outputs = self.plan_step('planted')
        patches = sorted(path.stem for path in (ROOT / 'tools/verify-wazig/planted').glob('*.patch'))
        self.assertTrue(patches)
        self.assertEqual(json.loads(outputs['planted']), {'include': [{'feature': name.split('--')[0], 'patch': name} for name in patches]})
        planted = self.workflow['jobs']['planted']
        self.assertEqual(planted['if'], "${{ github.event_name == 'schedule' || github.event_name == 'workflow_dispatch' }}")
        self.assertEqual(planted['strategy']['matrix'], '${{ fromJSON(needs.plan.outputs.planted) }}')
        self.assertEqual(planted['needs'], ['plan'])
        self.assertIn('planted', self.workflow['jobs']['planted-summary']['needs'])


if __name__ == '__main__':
    unittest.main()

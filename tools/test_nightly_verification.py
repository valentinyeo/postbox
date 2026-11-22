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
        self.planted = yaml.safe_load((ROOT / '.github/workflows/planted.yml').read_text())

    def events(self, workflow):
        return workflow.get('on', workflow.get(True))

    def plan_step(self, workflow, step_id):
        step = next(step for step in workflow['jobs']['plan']['steps'] if step.get('id') == step_id)
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'outputs'
            result = subprocess.run([sys.executable, '-c', step['run']], cwd=ROOT, capture_output=True,
                                    text=True, env=dict(os.environ, EVENT_NAME='schedule', FEATURE='search',
                                                       GITHUB_OUTPUT=str(output)))
            self.assertEqual(result.returncode, 0, result.stderr)
            return dict(line.split('=', 1) for line in output.read_text().splitlines())

    def test_schedule_runs_every_registered_journey(self):
        self.assertEqual(self.events(self.workflow)['schedule'], [{'cron': '40 2 * * *'}])
        outputs = self.plan_step(self.workflow, 'matrix')
        journeys = json.loads((ROOT / 'tools/verify-wazig/journeys.json').read_text())['journeys']
        self.assertEqual(json.loads(outputs['matrix'])['include'],
                         [{'feature': row['name'], 'evidence': row['evidence']} for row in journeys])
        verify = self.workflow['jobs']['verify']
        self.assertEqual(verify['strategy']['matrix'], '${{ fromJSON(needs.plan.outputs.matrix) }}')
        self.assertIn("github.event_name != 'pull_request'", verify['if'])

    def test_pr_workflow_carries_no_planted_jobs(self):
        self.assertNotIn('planted', self.workflow['jobs'])
        self.assertNotIn('planted-summary', self.workflow['jobs'])
        self.assertNotIn('planted', self.workflow['jobs']['plan']['outputs'])
        self.assertNotIn('plan.outputs.planted', (ROOT / '.github/workflows/verify.yml').read_text())

    def test_planted_workflow_runs_only_nightly_and_manually(self):
        events = self.events(self.planted)
        self.assertEqual(events, {'schedule': [{'cron': '40 2 * * *'}], 'workflow_dispatch': None})
        self.assertEqual(events['schedule'], self.events(self.workflow)['schedule'])
        self.assertEqual(self.planted['permissions'], {'contents': 'read'})
        self.assertEqual(self.planted['concurrency']['group'], 'planted-${{ github.ref }}')
        self.assertTrue(self.planted['concurrency']['cancel-in-progress'])

    def test_planted_historical_journeys_have_the_same_build_input_as_verify(self):
        planted = self.planted['jobs']['planted']['steps']
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

    def test_voice_download_red_skips_transcript_copy(self):
        step = next(step for step in self.workflow['jobs']['verify']['steps'] if step.get('name') == 'Queued-send voice download historical red control')
        self.assertEqual(step['env']['VOICE_DOWNLOAD_RED'], '1')
        self.assertIn('run.ps1 -Feature voice', step['run'])
        journey = (ROOT / 'tools/verify-wazig/journey-voice.ps1').read_text()
        red = journey.split('elseif ($env:VOICE_DOWNLOAD_RED)', 1)[1].split('} else {', 1)[0]
        clean = journey.split('} else {', 1)[1]
        self.assertNotIn('transcript-copy.ps1', red)
        self.assertIn('Invoke-VoiceDownloadJourney', red)
        self.assertIn('transcript-copy.ps1', clean)
        self.assertIn('Invoke-VoiceDownloadJourney', clean)

    def test_schedule_retains_every_planted_journey(self):
        outputs = self.plan_step(self.planted, 'planted')
        patches = sorted(path.stem for path in (ROOT / 'tools/verify-wazig/planted').glob('*.patch'))
        self.assertTrue(patches)
        self.assertEqual(json.loads(outputs['planted']), {'include': [{'feature': name.split('--')[0], 'patch': name} for name in patches]})
        planted = self.planted['jobs']['planted']
        self.assertEqual(planted['if'], "${{ github.event_name == 'schedule' || github.event_name == 'workflow_dispatch' }}")
        self.assertEqual(planted['strategy']['matrix'], '${{ fromJSON(needs.plan.outputs.planted) }}')
        self.assertEqual(planted['needs'], ['plan'])
        self.assertEqual(self.planted['jobs']['planted-summary']['needs'], ['plan', 'planted'])


if __name__ == '__main__':
    unittest.main()

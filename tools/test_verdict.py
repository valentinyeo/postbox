import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/verify-wazig/verdict.py'
SPEC = importlib.util.spec_from_file_location('verdict', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class VerdictTests(unittest.TestCase):
    def setUp(self):
        self.needs = {
            'plan': {'result': 'success', 'outputs': {'needed': 'true', 'repro': 'search', 'notes': '[]'}},
            'base-fails': {'result': 'success', 'outputs': {'classified': 'true'}},
            'verify': {'result': 'success', 'outputs': {}},
        }

    def test_all_pass(self):
        self.assertEqual(MODULE.verdict(self.needs), ('PASS', []))

    def test_failed_or_cancelled_dependency_overrides_notes(self):
        self.needs['plan']['outputs']['notes'] = '["No repro journey selected."]'
        for name in self.needs:
            for result in ('failure', 'cancelled'):
                with self.subTest(name=name, result=result):
                    needs = copy.deepcopy(self.needs)
                    needs[name]['result'] = result
                    self.assertEqual(MODULE.verdict(needs)[0], 'FAIL')

    def test_skipped_unneeded_verify_is_fine(self):
        self.needs['plan']['outputs'].update(needed='false', repro='')
        self.needs['verify']['result'] = 'skipped'
        self.assertEqual(MODULE.verdict(self.needs), ('PASS', []))

    def test_unexpected_skips_fail(self):
        for name in self.needs:
            with self.subTest(name=name):
                needs = copy.deepcopy(self.needs)
                needs[name]['result'] = 'skipped'
                self.assertEqual(MODULE.verdict(needs)[0], 'FAIL')

    def test_plan_notes(self):
        self.needs['plan']['outputs']['notes'] = '["No repro journey selected."]'
        self.assertEqual(MODULE.verdict(self.needs), ('PASS+NOTES', ['No repro journey selected.']))

    def test_unclassified_base_is_not_a_silent_pass(self):
        self.needs['base-fails']['outputs'] = {}
        self.assertEqual(MODULE.verdict(self.needs), ('PASS+NOTES', ['Base reproduction could not be classified.']))

    def test_cli_summary_and_exit_status(self):
        for expected in ('PASS', 'PASS+NOTES', 'FAIL'):
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as temp:
                needs = copy.deepcopy(self.needs)
                if expected == 'PASS+NOTES':
                    needs['plan']['outputs']['notes'] = '["Repro skipped."]'
                if expected == 'FAIL':
                    needs['verify']['result'] = 'failure'
                summary = Path(temp) / 'summary.md'
                result = subprocess.run([sys.executable, str(SCRIPT)], text=True, capture_output=True,
                                        env=dict(os.environ, NEEDS_JSON=json.dumps(needs), GITHUB_STEP_SUMMARY=str(summary)))
                self.assertEqual(result.returncode, int(expected == 'FAIL'), result.stderr)
                self.assertEqual(summary.read_text().splitlines()[0], expected)
                self.assertEqual(result.stdout.splitlines()[0], expected)

    def test_required_verdict_runs_for_every_pr(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        events = workflow.get('on', workflow.get(True))
        self.assertNotIn('paths', events['pull_request'])
        job = workflow['jobs']['verify-verdict']
        self.assertEqual(job['needs'], ['plan', 'base-fails', 'verify'])
        self.assertIn('always()', job['if'])
        self.assertIn("github.event_name == 'pull_request'", job['if'])
        self.assertIn('verify-verdict', (ROOT / 'tools/required-checks.txt').read_text().splitlines())

    def test_automerge_requires_successful_verdict(self):
        result = subprocess.run(['bash', str(ROOT / 'tools/test-automerge-admit.sh')],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('missing verifier verdict blocks', result.stdout)
        self.assertIn('pending verifier verdict blocks', result.stdout)


if __name__ == '__main__':
    unittest.main()

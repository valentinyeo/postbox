import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest


SCRIPT = Path(__file__).resolve().parent / 'verify-wazig/count_checks.py'
SPEC = importlib.util.spec_from_file_location('count_checks', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class JobCountTests(unittest.TestCase):
    def test_empty_run_does_not_invent_after_counts(self):
        self.assertEqual(MODULE.count_checks([]), {'entries': 0, 'not_skipped': 0})

    def test_skips_are_excluded_but_failed_and_pending_checks_are_not(self):
        checks = [{'state': state} for state in ('SUCCESS', 'FAILURE', 'CANCELLED', 'PENDING', 'SKIPPED')]
        self.assertEqual(MODULE.count_checks(checks), {'entries': 5, 'not_skipped': 4})

    def test_pr514_shape(self):
        checks = [{'state': 'SUCCESS'} for _ in range(22)] + [{'state': 'SKIPPED'} for _ in range(2)]
        self.assertEqual(MODULE.count_checks(checks), {'entries': 24, 'not_skipped': 22})

    def test_cli_accepts_gh_pr_checks_json(self):
        checks = [{'name': 'verify-verdict', 'state': 'SUCCESS', 'workflow': 'verify-wazig'},
                  {'name': 'nightly-summary', 'state': 'SKIPPED', 'workflow': 'planted-wazig'}]
        result = subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(checks),
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), {'entries': 2, 'not_skipped': 1})


if __name__ == '__main__':
    unittest.main()

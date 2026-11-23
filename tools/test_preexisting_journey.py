import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/verify-wazig/preexisting.py'
SPEC = importlib.util.spec_from_file_location('preexisting', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def run(url, created, jobs, event='schedule', branch='main'):
    return {'url': url, 'created_at': created, 'jobs': jobs, 'event': event, 'head_branch': branch}


def job(name, conclusion):
    return {'name': name, 'conclusion': conclusion}


class ClassifyTests(unittest.TestCase):
    def test_same_journey_red_on_the_newest_default_branch_run_is_preexisting(self):
        runs = [run('https://example.test/run/2', '2026-11-22T00:00:00Z', [job('verify (search, true)', 'failure'), job('verify (voice, true)', 'success')])]
        found = MODULE.classify('search', runs)
        self.assertTrue(found['preexisting'])
        self.assertIn('https://example.test/run/2', found['detail'])
        self.assertIn('verify (search, true)', found['detail'])

    def test_a_newer_pass_is_not_excused_by_an_older_failure(self):
        runs = [
            run('https://example.test/run/1', '2026-11-21T00:00:00Z', [job('verify (search, true)', 'failure')]),
            run('https://example.test/run/2', '2026-11-22T00:00:00Z', [job('verify (search, true)', 'success')]),
        ]
        found = MODULE.classify('search', runs)
        self.assertFalse(found['preexisting'])
        self.assertTrue(found['decisive'])
        self.assertIn('https://example.test/run/2', found['detail'])

    def test_a_newer_run_of_another_journey_does_not_hide_a_red_journey(self):
        runs = [
            run('https://example.test/run/9', '2026-11-22T03:00:00Z', [job('verify (voice, true)', 'success')]),
            run('https://example.test/run/8', '2026-11-22T02:00:00Z', [job('verify (search, true)', 'failure'), job('verify (voice, false)', 'success')]),
        ]
        found = MODULE.classify('search', runs)
        self.assertTrue(found['preexisting'])
        self.assertIn('https://example.test/run/8', found['detail'])

    def test_cancelled_or_skipped_results_fall_through_to_the_older_run(self):
        runs = [
            run('https://example.test/run/4', '2026-11-22T04:00:00Z', [job('verify (search, true)', 'cancelled'), job('verify (search, false)', 'skipped')]),
            run('https://example.test/run/3', '2026-11-22T03:00:00Z', [job('verify (search, true)', 'failure')]),
        ]
        self.assertTrue(MODULE.classify('search', runs)['preexisting'])

    def test_a_pass_beside_a_failure_in_the_same_run_is_not_preexisting(self):
        runs = [run('https://example.test/run/5', '2026-11-22T05:00:00Z', [job('verify (search, true)', 'failure'), job('verify (search, false)', 'success')])]
        self.assertFalse(MODULE.classify('search', runs)['preexisting'])

    def test_feature_names_match_exactly(self):
        runs = [run('https://example.test/run/6', '2026-11-22T06:00:00Z', [job('verify (archive-inbox, true)', 'failure'), job('planted (archive)', 'failure')])]
        found = MODULE.classify('archive', runs)
        self.assertFalse(found['preexisting'])
        self.assertFalse(found['decisive'])
        self.assertIsNone(MODULE.job_feature('planted (search)'))
        self.assertEqual(MODULE.job_feature('verify (archive-inbox, true)'), 'archive-inbox')

    def test_no_history_is_not_preexisting(self):
        found = MODULE.classify('search', [])
        self.assertFalse(found['preexisting'])
        self.assertIn('no completed run', found['detail'])

    def test_cli_exit_status_follows_the_classification(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'runs.json'
            path.write_text(json.dumps([run('https://example.test/run/7', '2026-11-22T07:00:00Z', [job('verify (reply, false)', 'failure')])]))
            red = subprocess.run([sys.executable, str(SCRIPT), '--feature', 'reply', '--runs', str(path)], capture_output=True, text=True)
            self.assertEqual(red.returncode, 0, red.stderr)
            self.assertIn('preexisting reply failed', red.stdout)
            path.write_text(json.dumps([run('https://example.test/run/7', '2026-11-22T07:00:00Z', [job('verify (reply, false)', 'success')])]))
            green = subprocess.run([sys.executable, str(SCRIPT), '--feature', 'reply', '--runs', str(path)], capture_output=True, text=True)
            self.assertEqual(green.returncode, 1)
            self.assertIn('passed in https://example.test/run/7', green.stdout)


class FetchTests(unittest.TestCase):
    def script(self, responses):
        calls = []

        def run(args, capture_output, text):
            self.assertTrue(capture_output and text)
            calls.append(list(args))
            stdout, code = responses(list(args))
            return type('Result', (), {'returncode': code, 'stdout': stdout, 'stderr': ''})()

        return calls, run

    def test_fetch_uses_the_newest_run_that_actually_ran_the_journey(self):
        def responses(args):
            if args[1] == 'run':
                return json.dumps([
                    {'databaseId': 2, 'url': 'https://example.test/run/2', 'createdAt': '2026-11-22T00:00:00Z', 'headBranch': 'main', 'event': 'workflow_dispatch'},
                    {'databaseId': 1, 'url': 'https://example.test/run/1', 'createdAt': '2026-11-21T00:00:00Z', 'headBranch': 'main', 'event': 'schedule'},
                ]), 0
            if args[3].endswith('/runs/2/jobs?per_page=100'):
                return '{"name":"verify (voice, true)","conclusion":"success"}\n', 0
            if args[3].endswith('/runs/1/jobs?per_page=100'):
                return '{"name":"verify (search, true)","conclusion":"failure"}\n', 0
            raise AssertionError(args)

        calls, run = self.script(responses)
        found = MODULE.evaluate('search', 'acme/postbox', 'main', 30, run)
        self.assertTrue(found['preexisting'])
        self.assertIn('https://example.test/run/1', found['detail'])
        self.assertEqual(len(calls), 3)

    def test_fetch_stops_when_the_newest_run_already_decided(self):
        def responses(args):
            if args[1] == 'run':
                return json.dumps([
                    {'databaseId': 4, 'url': 'https://example.test/run/4', 'createdAt': '2026-11-22T00:00:00Z', 'headBranch': 'main', 'event': 'schedule'},
                    {'databaseId': 3, 'url': 'https://example.test/run/3', 'createdAt': '2026-11-21T00:00:00Z', 'headBranch': 'main', 'event': 'schedule'},
                ]), 0
            if '/runs/4/' in args[3]:
                return '{"name":"verify (search, true)","conclusion":"success"}\n', 0
            raise AssertionError(args)

        calls, run = self.script(responses)
        found = MODULE.evaluate('search', 'acme/postbox', 'main', 30, run)
        self.assertFalse(found['preexisting'])
        self.assertEqual(len(calls), 2)

    def test_a_pull_request_run_never_counts_as_the_default_branch(self):
        def responses(args):
            if args[1] == 'run':
                return json.dumps([
                    {'databaseId': 6, 'url': 'https://example.test/run/6', 'createdAt': '2026-11-22T02:00:00Z', 'headBranch': 'main', 'event': 'pull_request'},
                    {'databaseId': 5, 'url': 'https://example.test/run/5', 'createdAt': '2026-11-22T01:00:00Z', 'headBranch': 'main', 'event': 'schedule'},
                ]), 0
            if '/runs/5/' in args[3]:
                return '{"name":"verify (search, true)","conclusion":"success"}\n', 0
            raise AssertionError(args)

        _, run = self.script(responses)
        found = MODULE.evaluate('search', 'acme/postbox', 'main', 30, run)
        self.assertFalse(found['preexisting'])
        self.assertIn('https://example.test/run/5', found['detail'])

    def test_an_older_listed_failure_does_not_outrank_a_newer_pass(self):
        def responses(args):
            if args[1] == 'run':
                return json.dumps([
                    {'databaseId': 1, 'url': 'https://example.test/run/1', 'createdAt': '2026-11-21T00:00:00Z', 'headBranch': 'main', 'event': 'schedule'},
                    {'databaseId': 2, 'url': 'https://example.test/run/2', 'createdAt': '2026-11-22T00:00:00Z', 'headBranch': 'main', 'event': 'schedule'},
                ]), 0
            if '/runs/2/' in args[3]:
                return '{"name":"verify (search, true)","conclusion":"success"}\n', 0
            raise AssertionError(args)

        calls, run = self.script(responses)
        found = MODULE.evaluate('search', 'acme/postbox', 'main', 30, run)
        self.assertFalse(found['preexisting'])
        self.assertIn('https://example.test/run/2', found['detail'])
        self.assertEqual(len(calls), 2)

    def test_unreadable_history_does_not_excuse_the_failure(self):
        def responses(args):
            return 'no', 1

        _, run = self.script(responses)
        found = MODULE.evaluate('search', 'acme/postbox', 'main', 30, run)
        self.assertFalse(found['preexisting'])
        self.assertIn('could not read runs', found['detail'])
        self.assertFalse(MODULE.evaluate('search', 'not a repo', 'main', 30, run)['preexisting'])


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        self.steps = self.workflow['jobs']['verify']['steps']
        self.drive = next(index for index, step in enumerate(self.steps) if step.get('id') == 'drive')

    def test_a_pull_request_failure_checks_the_default_branch_before_failing(self):
        self.assertEqual(self.workflow['permissions'], {'contents': 'read', 'actions': 'read'})
        drive = self.steps[self.drive]
        self.assertEqual(drive['name'], 'Launch, doctor and drive')
        self.assertIs(drive['continue-on-error'], True)
        gate = self.steps[self.drive + 1]
        self.assertEqual(gate['if'], "steps.drive.outcome == 'failure'")
        self.assertIn("EVENT_NAME -ne 'pull_request'", gate['run'])
        self.assertIn('throw \'One or more journey runs failed\'', gate['run'])
        self.assertIn('python tools/verify-wazig/preexisting.py', gate['run'])
        self.assertIn('github.event.repository.default_branch', gate['env']['DEFAULT_BRANCH'])
        self.assertNotIn('secrets', gate['env']['GH_TOKEN'])
        self.assertIn('github.token', gate['env']['GH_TOKEN'])
        self.assertIn('preexisting.txt', gate['run'])
        self.assertIn('PREEXISTING=true', gate['run'])
        record = next(step for step in self.steps if step.get('name') == 'Record clean result')
        self.assertIn('PREEXISTING', record['run'])
        self.assertIn("'preexisting'", record['run'])

    def test_later_evidence_steps_do_not_run_after_a_preexisting_failure(self):
        for step in self.steps[self.drive + 1:]:
            condition = str(step.get('if') or '')
            if 'always()' in condition:
                continue
            if "steps.drive.outcome == 'failure'" in condition:
                continue
            self.assertIn("steps.drive.outcome == 'success'", condition, step.get('name'))


if __name__ == '__main__':
    unittest.main()

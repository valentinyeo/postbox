import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import yaml


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/verify-wazig/judge_eval.py'
WORKFLOW = ROOT / '.github/workflows/judge-eval.yml'
SPEC = importlib.util.spec_from_file_location('judge_eval', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

FAILURE = 'search: Timed out: settled typed search'
PLANTED_RUN = '44536500173'
CLEAN_RUN = '44562234769'
OPENAI = 'openai/gpt-oss-120b'
KIMI = 'moonshotai/kimi-k2-instruct-0905'


def reply(verdict, notes=(), quote=''):
    return json.dumps({'verdict': verdict, 'notes': list(notes), 'quote': quote})


def http_error(code):
    return MODULE.verdict.urllib.error.HTTPError(MODULE.verdict.API_URL, code, 'error', {}, None)


class JudgeEvalTests(unittest.TestCase):
    def setUp(self):
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.root = Path(holder.name)
        self.evidence = self.root / 'evidence'
        self.summary = self.root / 'summary.md'

    def download(self, run, target):
        folder = Path(target) / 'verify-wazig-search'
        folder.mkdir(parents=True, exist_ok=True)
        if str(run) == PLANTED_RUN:
            (folder / 'failure.txt').write_text(FAILURE + '\n')
            (folder / 'clean-result.txt').write_text('failure\n')
        else:
            (folder / 'result.txt').write_text('JOURNEY PASSED: search\n')
            (folder / 'clean-result.txt').write_text('success\n')

    @staticmethod
    def gh(*args):
        if args[:2] == ('pr', 'view'):
            return json.dumps({'title': 'Search filter', 'body': 'Author model: anthropic/claude-opus'})
        return 'diff --git a/src/main.zig b/src/main.zig\n'

    def post(self, answers):
        seen = []
        queued = {model: list(items) for model, items in answers.items()}

        def call(body, key):
            seen.append(body['model'])
            answer = queued[body['model']].pop(0)
            if isinstance(answer, Exception):
                raise answer
            return answer

        return call, seen

    def run_eval(self, answers, families='openai,kimi'):
        post, seen = self.post(answers)
        argv = ['--planted-run', PLANTED_RUN, '--planted-pr', '546', '--clean-run', CLEAN_RUN,
                '--clean-pr', '551', '--families', families, '--evidence-dir', str(self.evidence)]
        out = io.StringIO()
        with mock.patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': str(self.summary)}), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = MODULE.main(argv, post=post, download=self.download, gh=self.gh, sleep=lambda seconds: None)
        records = [json.loads(line) for line in out.getvalue().splitlines() if line.startswith('{')]
        return code, records, seen

    def test_both_families_find_the_planted_bug_and_pass_the_clean_change(self):
        planted = reply('FAIL', ['Search never settled.'], FAILURE)
        answers = {OPENAI: [planted, reply('PASS')], KIMI: [planted, reply('PASS')]}
        code, records, seen = self.run_eval(answers)
        self.assertEqual(code, 0)
        self.assertEqual([r['case'] for r in records], ['planted', 'planted', 'clean', 'clean'])
        self.assertEqual([r['family'] for r in records], ['openai', 'kimi', 'openai', 'kimi'])
        self.assertEqual([r['verdict'] for r in records], ['FAIL', 'FAIL', 'PASS', 'PASS'])
        self.assertTrue(all(r['ok'] for r in records))
        self.assertEqual(records[0]['quote'], FAILURE)
        planted_models = [r['model'] for r in records[:2]]
        self.assertEqual(planted_models, [OPENAI, KIMI])
        self.assertEqual(seen, [OPENAI, KIMI, OPENAI, KIMI])
        self.assertIn('| planted | openai |', self.summary.read_text())
        self.assertIn('| clean | kimi |', self.summary.read_text())

    def test_a_planted_case_judged_pass_fails_the_eval(self):
        answers = {OPENAI: [reply('PASS'), reply('PASS')], KIMI: [reply('PASS'), reply('PASS')]}
        code, records, _ = self.run_eval(answers)
        self.assertEqual(code, 1)
        self.assertEqual([r['case'] for r in records if not r['ok']], ['planted', 'planted'])
        self.assertEqual({r['verdict'] for r in records[:2]}, {'PASS'})

    def test_a_fail_without_a_real_quote_fails_the_eval(self):
        answers = {OPENAI: [reply('FAIL', ['Trust me.'], 'invented evidence line'), reply('PASS')],
                   KIMI: [reply('PASS'), reply('PASS')]}
        code, records, _ = self.run_eval(answers)
        self.assertEqual(code, 1)
        self.assertEqual(records[0]['verdict'], 'PASS+NOTES')
        self.assertFalse(records[0]['ok'])
        self.assertTrue(records[2]['ok'])

    def test_an_unreachable_family_fails_the_eval_instead_of_skipping(self):
        answers = {OPENAI: [reply('FAIL', ['Search never settled.'], FAILURE), reply('PASS')],
                   KIMI: [http_error(500), reply('PASS')]}
        code, records, _ = self.run_eval(answers)
        self.assertEqual(code, 1)
        self.assertEqual([r['family'] for r in records if not r['ok']], ['kimi'])
        self.assertEqual({r['verdict'] for r in records if not r['ok']}, {'FAIL'})
        self.assertEqual({r['quote'] for r in records if not r['ok']}, {''})

    def test_a_clean_change_judged_fail_with_a_real_quote_fails_the_eval(self):
        answers = {OPENAI: [reply('FAIL', ['Search never settled.'], FAILURE),
                            reply('FAIL', ['Gap.'], 'clean-result.txt: success')],
                   KIMI: [reply('FAIL', ['Search never settled.'], FAILURE), reply('PASS')]}
        code, records, _ = self.run_eval(answers)
        self.assertEqual(code, 1)
        self.assertEqual((records[2]['verdict'], records[2]['ok']), ('FAIL', False))

    def test_unknown_family_fails_before_any_model_call(self):
        post, seen = self.post({})
        argv = ['--planted-run', PLANTED_RUN, '--planted-pr', '546', '--clean-run', CLEAN_RUN,
                '--clean-pr', '551', '--families', 'openai,acme', '--evidence-dir', str(self.evidence)]
        with contextlib.redirect_stderr(io.StringIO()):
            code = MODULE.main(argv, post=post, download=self.download, gh=self.gh, sleep=lambda seconds: None)
        self.assertEqual(code, 1)
        self.assertEqual(seen, [])

    def test_the_eval_never_runs_on_a_pull_request(self):
        workflow = yaml.safe_load(WORKFLOW.read_text())
        triggers = workflow.get('on', workflow.get(True))
        self.assertEqual(set(triggers), {'workflow_dispatch'})
        self.assertNotIn('pull_request', json.dumps(triggers))
        defaults = {name: spec['default'] for name, spec in triggers['workflow_dispatch']['inputs'].items()}
        self.assertEqual(defaults, {'planted_run': PLANTED_RUN, 'planted_pr': '546', 'clean_run': CLEAN_RUN,
                                    'clean_pr': '551', 'families': 'openai,kimi'})
        self.assertEqual(workflow['permissions'], {'contents': 'read', 'actions': 'read', 'pull-requests': 'read'})
        self.assertTrue(workflow['concurrency']['cancel-in-progress'])
        job = workflow['jobs']['judge']
        self.assertEqual(job['runs-on'], 'ubuntu-latest')
        step = job['steps'][-1]
        self.assertEqual(step['env']['VERDICT_API_KEY'], '${{ secrets.GROQ_API_KEY }}')
        self.assertEqual(step['env']['GH_TOKEN'], '${{ github.token }}')
        self.assertIn('tools/verify-wazig/judge_eval.py', step['run'])
        self.assertEqual(job['steps'][0]['uses'], 'actions/checkout@v4')


if __name__ == '__main__':
    unittest.main()

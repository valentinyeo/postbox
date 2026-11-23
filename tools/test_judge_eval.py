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
OPENAI_FALLBACK = 'openai/gpt-oss-20b'
QWEN_A = 'qwen/qwen3.6-27b'
QWEN_B = 'qwen/qwen3.8-27b'
LIVE_LIST = [
    OPENAI,
    OPENAI_FALLBACK,
    QWEN_A,
    QWEN_B,
    'whisper-large-v3',
    'openai/gpt-oss-safeguard-20b',
    'allam-2-7b',
]


def reply(verdict, notes=(), quote=''):
    return json.dumps({'verdict': verdict, 'notes': list(notes), 'quote': quote})


def http_error(code):
    return MODULE.verifier.urllib.error.HTTPError(MODULE.verifier.API_URL, code, 'error', {}, None)


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

    def run_eval(self, answers, families='', listed=LIVE_LIST, fetch_error=None, api_key='test-key'):
        post, seen = self.post(answers)
        fetches = []

        def fetch(key):
            fetches.append(key)
            if fetch_error:
                raise fetch_error
            return list(listed)

        argv = ['--planted-run', PLANTED_RUN, '--planted-pr', '546', '--clean-run', CLEAN_RUN,
                '--clean-pr', '551', '--families', families, '--evidence-dir', str(self.evidence)]
        out = io.StringIO()
        err = io.StringIO()
        env = {'GITHUB_STEP_SUMMARY': str(self.summary), 'VERDICT_API_KEY': api_key}
        with mock.patch.dict(os.environ, env), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = MODULE.main(argv, post=post, download=self.download, gh=self.gh,
                               sleep=lambda seconds: None, fetch=fetch)
        records = [json.loads(line) for line in out.getvalue().splitlines() if line.startswith('{')]
        return code, records, seen, fetches, err.getvalue()

    def test_picks_two_live_families_from_verifier_and_evaluates_both_cases(self):
        planted = reply('FAIL', ['Search never settled.'], FAILURE)
        answers = {OPENAI: [planted, reply('PASS')], QWEN_A: [planted, reply('PASS')]}
        code, records, seen, fetches, _ = self.run_eval(answers)
        self.assertEqual(code, 0)
        self.assertEqual(fetches, ['test-key'])
        self.assertEqual([r['case'] for r in records], ['planted', 'planted', 'clean', 'clean'])
        self.assertEqual([r['family'] for r in records], ['openai', 'qwen', 'openai', 'qwen'])
        self.assertEqual([r['verdict'] for r in records], ['FAIL', 'FAIL', 'PASS', 'PASS'])
        self.assertTrue(all(r['ok'] for r in records))
        self.assertEqual(records[0]['quote'], FAILURE)
        self.assertEqual([r['model'] for r in records[:2]], [OPENAI, QWEN_A])
        self.assertEqual(seen, [OPENAI, QWEN_A, OPENAI, QWEN_A])
        self.assertIn('| planted | openai |', self.summary.read_text())
        self.assertIn('| clean | qwen |', self.summary.read_text())

    def test_retired_model_404_moves_to_next_live_model_in_same_family(self):
        planted = reply('FAIL', ['Search never settled.'], FAILURE)
        answers = {
            OPENAI: [planted, reply('PASS')],
            QWEN_A: [http_error(404), reply('PASS')],
            QWEN_B: [planted],
        }
        code, records, seen, _, _ = self.run_eval(answers)
        self.assertEqual(code, 0)
        self.assertEqual(records[1]['family'], 'qwen')
        self.assertEqual(records[1]['model'], QWEN_B)
        self.assertEqual(seen, [OPENAI, QWEN_A, QWEN_B, OPENAI, QWEN_A])

    def test_live_list_failure_falls_back_to_verifier_preferences(self):
        planted = reply('FAIL', ['Search never settled.'], FAILURE)
        first_openai = MODULE.verifier.JUDGE_PREFERENCE['openai'][0]
        first_kimi = MODULE.verifier.JUDGE_PREFERENCE['kimi'][0]
        answers = {first_openai: [planted, reply('PASS')], first_kimi: [planted, reply('PASS')]}
        code, records, seen, _, _ = self.run_eval(answers, fetch_error=MODULE.verifier.urllib.error.URLError('down'))
        self.assertEqual(code, 0)
        self.assertEqual([r['family'] for r in records[:2]], ['openai', 'kimi'])
        self.assertEqual(seen, [first_openai, first_kimi, first_openai, first_kimi])

    def test_a_planted_case_judged_pass_fails_the_eval(self):
        answers = {OPENAI: [reply('PASS'), reply('PASS')], QWEN_A: [reply('PASS'), reply('PASS')]}
        code, records, _, _, _ = self.run_eval(answers)
        self.assertEqual(code, 1)
        self.assertEqual([r['case'] for r in records if not r['ok']], ['planted', 'planted'])
        self.assertEqual({r['verdict'] for r in records[:2]}, {'PASS'})

    def test_a_fail_without_a_real_quote_fails_the_eval(self):
        answers = {OPENAI: [reply('FAIL', ['Trust me.'], 'invented evidence line'), reply('PASS')],
                   QWEN_A: [reply('PASS'), reply('PASS')]}
        code, records, _, _, _ = self.run_eval(answers)
        self.assertEqual(code, 1)
        self.assertEqual(records[0]['verdict'], 'PASS+NOTES')
        self.assertFalse(records[0]['ok'])
        self.assertTrue(records[2]['ok'])

    def test_an_unreachable_family_fails_the_eval_instead_of_skipping(self):
        answers = {OPENAI: [reply('FAIL', ['Search never settled.'], FAILURE), reply('PASS')],
                   QWEN_A: [http_error(500), reply('PASS')],
                   QWEN_B: [http_error(500)]}
        code, records, _, _, _ = self.run_eval(answers)
        self.assertEqual(code, 1)
        self.assertEqual([r['family'] for r in records if not r['ok']], ['qwen'])
        self.assertEqual({r['verdict'] for r in records if not r['ok']}, {'FAIL'})
        self.assertEqual({r['quote'] for r in records if not r['ok']}, {''})

    def test_a_clean_change_judged_fail_with_a_real_quote_fails_the_eval(self):
        answers = {OPENAI: [reply('FAIL', ['Search never settled.'], FAILURE),
                            reply('FAIL', ['Gap.'], 'clean-result.txt: success')],
                   QWEN_A: [reply('FAIL', ['Search never settled.'], FAILURE), reply('PASS')]}
        code, records, _, _, _ = self.run_eval(answers)
        self.assertEqual(code, 1)
        self.assertEqual((records[2]['verdict'], records[2]['ok']), ('FAIL', False))

    def test_unknown_missing_or_single_family_fails_before_any_model_call(self):
        code, _, seen, fetches, _ = self.run_eval({}, families='openai,acme')
        self.assertEqual(code, 1)
        self.assertEqual(seen, [])
        self.assertEqual(fetches, [])

        code, _, seen, _, _ = self.run_eval({}, families='openai,kimi', listed=LIVE_LIST)
        self.assertEqual(code, 1)
        self.assertEqual(seen, [])

        code, _, seen, _, _ = self.run_eval({}, families='', listed=[OPENAI, 'whisper-large-v3'])
        self.assertEqual(code, 1)
        self.assertEqual(seen, [])

        code, _, seen, fetches, _ = self.run_eval({}, api_key='')
        self.assertEqual(code, 1)
        self.assertEqual(seen, [])
        self.assertEqual(fetches, [])

    def test_the_eval_runs_only_on_schedule_and_dispatch_never_pull_request(self):
        workflow = yaml.safe_load(WORKFLOW.read_text())
        triggers = workflow.get('on', workflow.get(True))
        self.assertEqual(set(triggers), {'schedule', 'workflow_dispatch'})
        self.assertNotIn('pull_request', json.dumps(triggers))
        self.assertEqual(len(triggers['schedule']), 1)
        cron_fields = triggers['schedule'][0]['cron'].split()
        self.assertEqual(len(cron_fields), 5)
        self.assertNotEqual(cron_fields[4], '*')
        defaults = {name: spec['default'] for name, spec in triggers['workflow_dispatch']['inputs'].items()}
        self.assertEqual(defaults, {'planted_run': PLANTED_RUN, 'planted_pr': '546', 'clean_run': CLEAN_RUN,
                                    'clean_pr': '551', 'families': ''})
        self.assertEqual(workflow['permissions'], {'contents': 'read', 'actions': 'read', 'pull-requests': 'read'})
        self.assertTrue(workflow['concurrency']['cancel-in-progress'])
        job = workflow['jobs']['judge']
        self.assertEqual(job['runs-on'], 'ubuntu-latest')
        step = job['steps'][-1]
        self.assertEqual(step['env']['VERDICT_API_KEY'], '${{ secrets.GROQ_API_KEY }}')
        self.assertEqual(step['env']['GH_TOKEN'], '${{ github.token }}')
        self.assertIn(PLANTED_RUN, step['env']['PLANTED_RUN'])
        self.assertIn(CLEAN_RUN, step['env']['CLEAN_RUN'])
        self.assertIn('tools/verify-wazig/judge_eval.py', step['run'])
        self.assertEqual(job['steps'][0]['uses'], 'actions/checkout@v4')


if __name__ == '__main__':
    unittest.main()

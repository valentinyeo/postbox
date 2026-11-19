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
        for expected, verify in (('FAIL', 'failure'), ('FAIL', 'success')):
            with self.subTest(verify=verify), tempfile.TemporaryDirectory() as temp:
                needs = copy.deepcopy(self.needs)
                needs['verify']['result'] = verify
                summary = Path(temp) / 'summary.md'
                event = Path(temp) / 'event.json'
                event.write_text(json.dumps({'pull_request': {'title': 't', 'body': 'Author model: anthropic/claude-opus-5-5'}}))
                env = {k: v for k, v in os.environ.items() if k not in ('VERDICT_API_KEY', 'GITHUB_REPOSITORY')}
                env.update(NEEDS_JSON=json.dumps(needs), GITHUB_STEP_SUMMARY=str(summary), GITHUB_EVENT_PATH=str(event),
                           EVIDENCE_DIR=str(Path(temp) / 'none'))
                result = subprocess.run([sys.executable, str(SCRIPT)], text=True, capture_output=True, env=env)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(summary.read_text().splitlines()[0], expected)
                self.assertEqual(result.stdout.splitlines()[0], expected)
                self.assertIn(MODULE.MARKER, result.stdout)

    def test_required_verdict_runs_for_every_pr(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        events = workflow.get('on', workflow.get(True))
        self.assertNotIn('paths', events['pull_request'])
        job = workflow['jobs']['verify-verdict']
        self.assertEqual(job['needs'], ['plan', 'base-fails', 'verify'])
        self.assertIn('always()', job['if'])
        self.assertIn("github.event_name == 'pull_request'", job['if'])
        self.assertIn('verify-verdict', (ROOT / 'tools/required-checks.txt').read_text().splitlines())

    def test_verdict_job_runs_main_judge_not_pr_code(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        job = workflow['jobs']['verify-verdict']
        checkout = job['steps'][0]
        self.assertEqual(checkout['uses'], 'actions/checkout@v4')
        self.assertEqual(checkout['with']['ref'], '${{ github.event.repository.default_branch }}')
        self.assertEqual(job['permissions']['pull-requests'], 'write')
        judge = job['steps'][-1]
        self.assertIn('secrets.GROQ_API_KEY', judge['env']['VERDICT_API_KEY'])
        self.assertIn('head.repo.full_name == github.repository', judge['env']['VERDICT_API_KEY'])
        for name, other in workflow['jobs'].items():
            if name != 'verify-verdict':
                self.assertNotIn('GROQ_API_KEY', json.dumps(other))

    def test_automerge_requires_successful_verdict(self):
        result = subprocess.run(['bash', str(ROOT / 'tools/test-automerge-admit.sh')],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('missing verifier verdict blocks', result.stdout)
        self.assertIn('pending verifier verdict blocks', result.stdout)


def reply(verdict, notes=(), quote=''):
    return json.dumps({'verdict': verdict, 'notes': list(notes), 'quote': quote})


class Model:
    def __init__(self, *answers):
        self.answers = list(answers)
        self.models = []

    def __call__(self, body, key):
        self.models.append(body['model'])
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return answer


def http_error(code):
    return MODULE.urllib.error.HTTPError(MODULE.API_URL, code, 'error', {}, None)


class JudgeTests(unittest.TestCase):
    def setUp(self):
        self.needs = {
            'plan': {'result': 'success', 'outputs': {'needed': 'true', 'repro': '', 'notes': '[]'}},
            'base-fails': {'result': 'success', 'outputs': {}},
            'verify': {'result': 'success', 'outputs': {}},
        }
        self.body = 'Fix search\n\nAuthor model: anthropic/claude-opus-5-5'
        self.evidence = '## verify-wazig-search\nresult.txt: JOURNEY PASSED: search\nside-effects.json: {"pendingSends": 2}'

    def run_judge(self, model, body=None, key='k', needs=None):
        return MODULE.judge(needs or self.needs, self.body if body is None else body, 'pr', ['search'],
                            self.evidence, 'diff', key, post=model, sleep=lambda seconds: None)

    def test_judge_comes_from_a_family_no_author_used(self):
        model = Model(reply('PASS'))
        self.assertEqual(self.run_judge(model)[:2], ('PASS', []))
        self.assertEqual(model.models, ['openai/gpt-oss-120b'])
        model = Model(reply('PASS'))
        self.run_judge(model, body='Author model: openai/gpt-6.1-sol\nAuthor model: anthropic/claude')
        self.assertEqual(model.models, ['moonshotai/kimi-k2-instruct-0905'])

    def test_missing_unknown_or_exhausted_authors_fail_without_asking(self):
        bodies = ('', 'no line', '```\nAuthor model: anthropic/claude\n```', 'Author model: acme/mystery',
                  'Author model: anthropic/claude trailing',
                  'Author model: openai/gpt\nAuthor model: kimi/k2\nAuthor model: qwen/qwen3\nAuthor model: meta/llama')
        for body in bodies:
            with self.subTest(body=body):
                model = Model()
                result, notes, used = self.run_judge(model, body=body)
                self.assertEqual(result, 'FAIL')
                self.assertEqual(model.models, [])
                self.assertIsNone(used)

    def test_red_jobs_stay_fail_and_skip_the_model(self):
        needs = copy.deepcopy(self.needs)
        needs['verify']['result'] = 'failure'
        self.evidence = '## verify-wazig-search\nfailure.txt: search: chats were not filtered'
        model = Model(reply('PASS'))
        result, notes, used = self.run_judge(model, needs=needs)
        self.assertEqual(result, 'FAIL')
        self.assertIn('failure.txt: search: chats were not filtered', notes)
        self.assertEqual(model.models, [])

    def test_fail_needs_a_real_evidence_quote(self):
        quote = 'side-effects.json: {"pendingSends": 2}'
        result, notes, _ = self.run_judge(Model(reply('FAIL', ['Sends were left pending.'], quote)))
        self.assertEqual(result, 'FAIL')
        self.assertIn('Evidence: ' + quote, notes)
        result, notes, _ = self.run_judge(Model(reply('FAIL', ['Looks wrong.'], 'pendingSends: 9 invented')))
        self.assertEqual(result, 'PASS+NOTES')
        result, _, _ = self.run_judge(Model(reply('FAIL', ['Too short.'], 'PASSED')))
        self.assertEqual(result, 'PASS+NOTES')

    def test_notes_are_kept(self):
        result, notes, _ = self.run_judge(Model(reply('PASS+NOTES', ['src/x.zig ran no journey.'])))
        self.assertEqual((result, notes), ('PASS+NOTES', ['src/x.zig ran no journey.']))
        needs = copy.deepcopy(self.needs)
        needs['plan']['outputs']['notes'] = '["No repro journey selected."]'
        result, notes, _ = self.run_judge(Model(reply('PASS')), needs=needs)
        self.assertEqual((result, notes), ('PASS+NOTES', ['No repro journey selected.']))

    def test_no_key_or_no_answer_fails_loudly(self):
        self.assertEqual(self.run_judge(Model(), key='')[0], 'FAIL')
        model = Model('no json here', http_error(500), http_error(404), MODULE.urllib.error.URLError('down'))
        result, notes, used = self.run_judge(model)
        self.assertEqual(result, 'FAIL')
        self.assertIn('No independent judge answered', notes[0])
        self.assertIsNone(used)

    def test_rate_limit_retries_then_moves_on(self):
        model = Model(http_error(429), http_error(429), http_error(429), '<think>x</think>' + reply('PASS'))
        result, _, used = self.run_judge(model)
        self.assertEqual((result, used), ('PASS', 'moonshotai/kimi-k2-instruct-0905'))
        self.assertEqual(model.models.count('openai/gpt-oss-120b'), 3)

    def test_digest_reads_text_evidence_and_caps_it(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / 'verify-wazig-search'
            folder.mkdir()
            (folder / 'result.txt').write_text('JOURNEY PASSED: search\n')
            (folder / 'actions.log').write_text('x' * 5000 + 'last action')
            (folder / 'after.png').write_bytes(b'\x89PNG')
            (Path(temp) / 'repro-base').mkdir()
            (Path(temp) / 'repro-base' / 'classification.json').write_text('{"classification": "reproduced"}')
            text = MODULE.digest(temp)
            self.assertIn('result.txt: JOURNEY PASSED: search', text)
            self.assertIn('classification.json: {"classification": "reproduced"}', text)
            self.assertTrue(text.split('actions.log tail: ')[1].split('\n')[0].endswith('last action'))
            self.assertNotIn('PNG', text)
            for index in range(30):
                extra = Path(temp) / f'verify-wazig-{index:02d}'
                extra.mkdir()
                (extra / 'failure.txt').write_text('y' * 2000)
            self.assertLessEqual(len(MODULE.digest(temp)), MODULE.MAX_EVIDENCE + 20)

    def test_comment_carries_marker_verdict_and_judge(self):
        text = MODULE.render('PASS+NOTES', ['A gap.'], 'openai/gpt-oss-120b', 'abc', 'https://run')
        lines = text.splitlines()
        self.assertEqual(lines[0], MODULE.MARKER)
        self.assertIn('PASS+NOTES', lines)
        self.assertIn('- A gap.', lines)
        self.assertIn('openai/gpt-oss-120b', text)


if __name__ == '__main__':
    unittest.main()

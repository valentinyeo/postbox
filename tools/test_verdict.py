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
SCRIPT = ROOT / 'tools/verify-wazig/verifier.py'
SPEC = importlib.util.spec_from_file_location('verifier', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class VerdictTests(unittest.TestCase):
    def setUp(self):
        self.needs = {
            'plan': {'result': 'success', 'outputs': {'needed': 'true'}},
            'verify': {'result': 'success', 'outputs': {}},
        }

    def test_missing_base_reproduction_is_fine(self):
        self.assertNotIn('base-fails', self.needs)
        self.assertEqual(MODULE.verdict(self.needs), ('PASS', []))

    def test_failed_or_cancelled_dependency_fails(self):
        for name in self.needs:
            for result in ('failure', 'cancelled'):
                with self.subTest(name=name, result=result):
                    needs = copy.deepcopy(self.needs)
                    needs[name]['result'] = result
                    self.assertEqual(MODULE.verdict(needs)[0], 'FAIL')

    def test_skipped_unneeded_verify_is_fine(self):
        self.needs['plan']['outputs'].update(needed='false')
        self.needs['verify']['result'] = 'skipped'
        self.assertEqual(MODULE.verdict(self.needs), ('PASS', []))

    def test_unexpected_skips_fail(self):
        for name in self.needs:
            with self.subTest(name=name):
                needs = copy.deepcopy(self.needs)
                needs[name]['result'] = 'skipped'
                self.assertEqual(MODULE.verdict(needs)[0], 'FAIL')

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
        self.assertEqual(job['needs'], ['plan', 'verify'])
        self.assertIn('always()', job['if'])
        self.assertIn("github.event_name == 'pull_request'", job['if'])
        self.assertIn('verify-verdict', (ROOT / 'tools/required-checks.txt').read_text().splitlines())

    def test_verdict_job_runs_main_judge_not_pr_code(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        job = workflow['jobs']['verify-verdict']
        downloads = [step for step in job['steps'] if step.get('uses') == 'actions/download-artifact@v4']
        self.assertEqual([step['with']['pattern'] for step in downloads], ['verify-wazig-*'])
        self.assertTrue(all(step['continue-on-error'] for step in downloads))
        checkout = job['steps'][0]
        self.assertEqual(checkout['uses'], 'actions/checkout@v4')
        self.assertEqual(checkout['with']['ref'], '${{ github.event.repository.default_branch }}')
        self.assertEqual(job['permissions']['pull-requests'], 'write')
        judge = job['steps'][-1]
        self.assertEqual(judge['run'], 'python3 tools/verify-wazig/verifier.py')
        self.assertIn('secrets.GROQ_API_KEY', judge['env']['VERDICT_API_KEY'])
        self.assertIn('head.repo.full_name == github.repository', judge['env']['VERDICT_API_KEY'])
        for name, other in workflow['jobs'].items():
            if name != 'verify-verdict':
                self.assertNotIn('GROQ_API_KEY', json.dumps(other))

    def test_verdict_command_preserves_script_exit_status(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        run = workflow['jobs']['verify-verdict']['steps'][-1]['run']
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            tools = root / 'tools' / 'verify-wazig'
            tools.mkdir(parents=True)
            (tools / 'verifier.py').write_text('import os\nraise SystemExit(int(os.environ["PY_EXIT"]))\n')
            for status in (0, 7):
                with self.subTest(status=status):
                    env = dict(os.environ, PY_EXIT=str(status), NEEDS_JSON=json.dumps(self.needs))
                    result = subprocess.run(['bash', '-e', '-c', run], cwd=root, env=env, text=True, capture_output=True)
                    self.assertEqual(result.returncode, status, result.stderr)

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
            'plan': {'result': 'success', 'outputs': {'needed': 'true'}},
            'verify': {'result': 'success', 'outputs': {}},
        }
        self.body = 'Fix search\n\nAuthor model: anthropic/claude-opus-5-5'
        self.evidence = '## verify-wazig-search\nresult.txt: JOURNEY PASSED: search\nside-effects.json: {"pendingSends": 2}'

    def run_judge(self, model, body=None, key='k', needs=None, evidence=None, listed=None, fetch=None, fetch_error=None):
        def fake_fetch(ignored):
            if fetch_error:
                raise fetch_error
            return listed
        return MODULE.judge(needs or self.needs, self.body if body is None else body, 'pr', ['search'],
                            self.evidence if evidence is None else evidence, 'diff', key, post=model,
                            sleep=lambda seconds: None, fetch=fetch or fake_fetch, say=lambda line: None)

    def test_judge_comes_from_a_family_no_author_used(self):
        model = Model(reply('PASS'))
        self.assertEqual(self.run_judge(model)[:2], ('PASS', []))
        self.assertEqual(model.models, ['openai/gpt-oss-120b'])
        model = Model(reply('PASS'))
        self.run_judge(model, body='Author model: openai/gpt-6.1-sol\nAuthor model: anthropic/claude')
        self.assertEqual(model.models, ['moonshotai/kimi-k2-instruct-0905'])

    def test_missing_base_reproduction_still_gets_an_independent_verdict(self):
        for needed, verify in (('true', 'success'), ('false', 'skipped')):
            with self.subTest(needed=needed):
                self.needs['plan']['outputs']['needed'] = needed
                self.needs['verify']['result'] = verify
                model = Model(reply('PASS'))
                self.assertEqual(self.run_judge(model)[:2], ('PASS', []))
                self.assertEqual(model.models, ['openai/gpt-oss-120b'])
                self.assertNotIn('base-fails', self.needs)

    def test_cursor_author_is_a_known_family(self):
        for declared in ('cursor/composer-2.5', 'composer/composer-2.5'):
            self.assertEqual(MODULE.family_of(declared), {'cursor'}, declared)
        model = Model(reply('PASS'))
        self.assertEqual(self.run_judge(model, body='Author model: cursor/composer-2.5')[:2], ('PASS', []))
        self.assertEqual(model.models, ['openai/gpt-oss-120b'])

    def test_judges_come_from_the_live_model_list(self):
        listed = ['openai/gpt-oss-120b', 'moonshotai/kimi-k2-instruct', 'qwen/qwen3-32b',
                  'llama-3.3-70b-versatile', 'whisper-large-v3', 'groq/compound']
        model = Model(reply('PASS'))
        result, _, used = self.run_judge(model, body='Author model: openai/gpt-6.1-sol', listed=listed)
        self.assertEqual((result, used), ('PASS', 'moonshotai/kimi-k2-instruct'))
        self.assertEqual(model.models, ['moonshotai/kimi-k2-instruct'])

    def test_retired_model_404_moves_to_the_next_listed_judge(self):
        listed = ['moonshotai/kimi-k2-instruct', 'qwen/qwen3-32b']
        model = Model(http_error(404), reply('PASS'))
        result, notes, used = self.run_judge(model, listed=listed)
        self.assertEqual((result, used), ('PASS', 'qwen/qwen3-32b'))
        self.assertEqual(model.models, ['moonshotai/kimi-k2-instruct', 'qwen/qwen3-32b'])
        self.assertEqual(notes, [])

    def test_live_list_keeps_the_author_family_exclusion(self):
        listed = ['openai/gpt-oss-120b', 'moonshotai/kimi-k2-instruct', 'qwen/qwen3-32b',
                  'meta-llama/llama-4-scout-17b-16e-instruct', 'llama-3.3-70b-versatile']
        model = Model(reply('PASS'))
        result, _, used = self.run_judge(model, body='Author model: openai/gpt-6.1-sol\nAuthor model: kimi/k2',
                                         listed=listed)
        self.assertEqual((result, used), ('PASS', 'qwen/qwen3-32b'))
        self.assertEqual(model.models, ['qwen/qwen3-32b'])

    def test_non_chat_and_unknown_models_are_never_judges(self):
        listed = ['whisper-large-v3', 'playai-tts', 'meta-llama/llama-guard-4-12b',
                  'nomic-embed-text-v1.5', 'groq/compound']
        model = Model()
        result, notes, used = self.run_judge(model, listed=listed)
        self.assertEqual(result, 'FAIL')
        self.assertIsNone(used)
        self.assertEqual(model.models, [])
        self.assertIn('no model from a family this PR did not author with', notes[0])

    def test_listed_endpoint_failure_falls_back_to_the_static_list(self):
        for fetch_error in (MODULE.urllib.error.URLError('down'), MODULE.urllib.error.HTTPError(
                MODULE.MODELS_URL, 401, 'unauthorized', {}, None), ValueError('bad json')):
            with self.subTest(error=type(fetch_error).__name__):
                model = Model(reply('PASS'))
                result, _, used = self.run_judge(model, fetch_error=fetch_error)
                self.assertEqual((result, used), ('PASS', 'openai/gpt-oss-120b'))

    def test_empty_list_also_falls_back_to_the_static_list(self):
        model = Model(reply('PASS'))
        self.assertEqual(self.run_judge(model, listed=[])[0], 'PASS')
        self.assertEqual(model.models, ['openai/gpt-oss-120b'])

    def test_retired_static_judge_404_moves_to_the_next_preference(self):
        model = Model(http_error(404), http_error(404), http_error(404), reply('PASS'))
        result, _, used = self.run_judge(model, fetch_error=MODULE.urllib.error.URLError('down'))
        self.assertEqual((result, used), ('PASS', 'moonshotai/kimi-k2-instruct'))
        self.assertEqual(model.models, ['openai/gpt-oss-120b', 'openai/gpt-oss-20b',
                                       'moonshotai/kimi-k2-instruct-0905', 'moonshotai/kimi-k2-instruct'])

    def test_the_run_prints_every_model_tried_and_skipped(self):
        lines = []
        MODULE.judge(self.needs, 'Author model: openai/gpt-6.1-sol', 'pr', ['search'], self.evidence, 'diff', 'k',
                     post=Model(reply('PASS')),
                     sleep=lambda seconds: None,
                     fetch=lambda key: ['moonshotai/kimi-k2-instruct', 'whisper-large-v3', 'groq/compound'],
                     say=lines.append)
        printed = '\n'.join(lines)
        self.assertIn('Groq lists 3 models', printed)
        self.assertIn('skipped openai family: named by an `Author model:` line', printed)
        self.assertIn('skipped whisper-large-v3: not a chat model', printed)
        self.assertIn('skipped groq/compound: no known model family', printed)
        self.assertIn('judges to try, in order: moonshotai/kimi-k2-instruct', printed)
        self.assertIn('moonshotai/kimi-k2-instruct: answered', printed)

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
        self.assertIn('verify-wazig-search failure.txt: search: chats were not filtered', notes)
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

    def test_a_failure_already_red_on_the_default_branch_does_not_fail_the_pull_request(self):
        evidence = (
            '## verify-wazig-search\n'
            'preexisting.txt: preexisting search failed in https://example.test/run/9 as verify (search, true)\n'
            'failure.txt: search: chats were not filtered\n'
            'clean-result.txt: preexisting\n\n'
            '## verify-wazig-voice\n'
            'result.txt: JOURNEY PASSED: voice\n'
            'side-effects.json: {"pendingSends": 2}'
        )
        quote = 'failure.txt: search: chats were not filtered'
        result, notes, _ = self.run_judge(Model(reply('FAIL', ['Search failed.'], quote)), evidence=evidence)
        self.assertEqual(result, 'PASS+NOTES')
        self.assertIn('The quoted failure was already red on the default branch.', notes)
        other = 'side-effects.json: {"pendingSends": 2}'
        result, notes, _ = self.run_judge(Model(reply('FAIL', ['Sends were left pending.'], other)), evidence=evidence)
        self.assertEqual(result, 'FAIL')
        self.assertIn('Evidence: ' + other, notes)

    def test_notes_are_kept(self):
        result, notes, _ = self.run_judge(Model(reply('PASS+NOTES', ['src/x.zig ran no journey.'])))
        self.assertEqual((result, notes), ('PASS+NOTES', ['src/x.zig ran no journey.']))

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
        self.assertEqual((result, used), ('PASS', 'openai/gpt-oss-20b'))
        self.assertEqual(model.models.count('openai/gpt-oss-120b'), 3)

    def test_digest_reads_text_evidence_and_caps_it(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / 'verify-wazig-search'
            folder.mkdir()
            (folder / 'result.txt').write_text('JOURNEY PASSED: search\n')
            (folder / 'preexisting.txt').write_text('preexisting search failed in https://example.test/run/9\n')
            (folder / 'actions.log').write_text('x' * 5000 + 'last action')
            (folder / 'after.png').write_bytes(b'\x89PNG')
            (folder / 'classification.json').write_text('{"classification": "reproduced"}')
            text = MODULE.digest(temp)
            self.assertIn('result.txt: JOURNEY PASSED: search', text)
            self.assertIn('preexisting.txt: preexisting search failed in https://example.test/run/9', text)
            self.assertIn('classification.json: {"classification": "reproduced"}', text)
            self.assertTrue(text.split('actions.log tail: ')[1].split('\n')[0].endswith('last action'))
            self.assertNotIn('PNG', text)
            control = folder / 'red-control'
            control.mkdir()
            (control / 'failure.txt').write_text('reply: Timed out: Reply preview missing')
            self.assertNotIn('Reply preview missing', MODULE.digest(temp))
            for index in range(30):
                extra = Path(temp) / f'verify-wazig-{index:02d}'
                extra.mkdir()
                (extra / 'failure.txt').write_text('y' * 2000)
            text = MODULE.digest(temp)
            self.assertLessEqual(len(text), MODULE.MAX_EVIDENCE + 400)
            self.assertIn('## verify-wazig-29', text)
            self.assertIn('## verify-wazig-search', text)

    def test_red_job_names_the_failing_journey(self):
        evidence = ('## verify-wazig-voice\nfailure.txt: voice: playback stalled\n\n'
                    '## verify-wazig-search\nfailure.txt: search: chats were not filtered')
        self.assertEqual(MODULE.failure_lines(evidence),
                         ['verify-wazig-voice failure.txt: voice: playback stalled',
                          'verify-wazig-search failure.txt: search: chats were not filtered'])

    def test_reply_parsing_takes_the_first_object(self):
        self.assertEqual(MODULE.parse_reply(reply('PASS') + ' then ' + reply('FAIL')), ('PASS', [], ''))
        self.assertIsNone(MODULE.parse_reply('{"verdict": "MAYBE"}'))
        self.assertIsNone(MODULE.parse_reply('no json'))

    def test_failed_comment_post_keeps_the_verdict(self):
        with tempfile.TemporaryDirectory() as temp:
            needs = copy.deepcopy(self.needs)
            needs['verify']['result'] = 'failure'
            fake = Path(temp) / 'gh'
            fake.write_text('#!/bin/sh\nexit 1\n')
            fake.chmod(0o755)
            event = Path(temp) / 'event.json'
            event.write_text(json.dumps({'pull_request': {'number': 5, 'title': 't', 'body': '', 'head': {'sha': 'abc'}}}))
            env = dict(os.environ, NEEDS_JSON=json.dumps(needs), GITHUB_EVENT_PATH=str(event), GITHUB_REPOSITORY='o/r',
                       VERDICT_POST='1', EVIDENCE_DIR=str(Path(temp) / 'none'), PATH=temp + os.pathsep + os.environ['PATH'])
            env.pop('GITHUB_STEP_SUMMARY', None)
            result = subprocess.run([sys.executable, str(SCRIPT)], text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertEqual(result.stdout.splitlines()[0], 'FAIL')
            self.assertIn('could not post the PR comment', result.stdout)

    def test_comment_carries_marker_verdict_and_judge(self):
        text = MODULE.render('PASS+NOTES', ['A gap.'], 'openai/gpt-oss-120b', 'abc', 'https://run')
        lines = text.splitlines()
        self.assertEqual(lines[0], MODULE.MARKER)
        self.assertIn('PASS+NOTES', lines)
        self.assertIn('- A gap.', lines)
        self.assertIn('openai/gpt-oss-120b', text)


if __name__ == '__main__':
    unittest.main()

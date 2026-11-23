import contextlib
import copy
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

import check_release_proof as proof


ROOT = Path(__file__).resolve().parents[1]


class FakeRunner:
    def __init__(self):
        self.tags = 'v1.9.0\nv1.10.0\nv1.11.0\nv2.0.0\nv1.10.1-beta\n'
        self.commits = ['abc123']
        self.files = ['src/media.zig']
        self.pr_files = [{'filename': 'src/media.zig'}]
        self.pulls = [{'number': 42, 'merged_at': '2026-01-01T00:00:00Z',
                       'head': {'sha': 'pr-head'}, 'title': 'Add media', 'body': ''}]
        self.runs = [{'id': 100, 'head_sha': 'pr-head', 'event': 'pull_request',
                      'status': 'completed', 'conclusion': 'success'}]
        self.artifacts = [{'name': f'verify-wazig-{name}', 'expired': False, 'size_in_bytes': 100}
                          for name in ['search', 'voice', 'reply', 'media-fit', 'caret']]
        self.content = {'run.log': b'journey passed', 'screenshots/final.png': b'image'}
        self.calls = []
        self.pages = {}

    def __call__(self, command):
        self.calls.append(command)
        if command[:3] == ['git', 'tag', '--list']:
            return self.tags
        if command[:3] == ['git', 'log', '--first-parent']:
            return '\n'.join(self.commits)
        if command[:2] == ['git', 'diff-tree']:
            return '\0'.join(self.files) + '\0'
        if command[:2] == ['gh', 'api']:
            url = urlsplit(command[2])
            page = int(parse_qs(url.query).get('page', ['1'])[0])
            if (url.path, page) in self.pages:
                return json.dumps(self.pages[url.path, page])
            if page > 1:
                data = []
                if '/runs' in url.path:
                    data = {'workflow_runs': []} if url.path.endswith('/runs') else {'artifacts': []}
            elif url.path.endswith('/pulls'):
                data = self.pulls
            elif url.path.endswith('/files'):
                data = self.pr_files
            elif url.path.endswith('/runs'):
                data = {'workflow_runs': self.runs}
            elif url.path.endswith('/artifacts'):
                data = {'artifacts': self.artifacts}
            else:
                raise AssertionError(command)
            return json.dumps(data)
        if command[:3] == ['gh', 'run', 'download']:
            dest = Path(command[command.index('-D') + 1])
            for name, content in self.content.items():
                path = dest / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            return ''
        raise AssertionError(command)


class ReleaseProofTests(unittest.TestCase):
    def setUp(self):
        self.runner = FakeRunner()

    def check(self, previous=None):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = proof.check_release_proof('owner/repo', 'v1.11.0', previous, runner=self.runner)
        return code, output.getvalue()

    def assert_missing(self, item):
        code, output = self.check()
        self.assertEqual(code, 1, output)
        for text in ['MISSING:', 'abc123', 'PR #42', item]:
            self.assertIn(text, output)
        return output

    def test_complete_proof_passes_and_selects_numeric_previous_tag(self):
        code, output = self.check()
        self.assertEqual(code, 0, output)
        for name in ['search', 'voice', 'reply', 'media-fit']:
            self.assertIn(f'journey {name}: ok', output)
        self.assertTrue(any('refs/tags/v1.10.0..refs/tags/v1.11.0' in call for call in self.runner.calls))

    def test_explicit_previous_tag(self):
        self.assertEqual(self.check('v1.9.0')[0], 0)
        self.assertTrue(any('refs/tags/v1.9.0..refs/tags/v1.11.0' in call for call in self.runner.calls))

    def test_first_release_checks_nothing(self):
        self.runner.tags = 'v1.11.0\nv2.0.0\n'
        code, output = self.check()
        self.assertEqual(code, 0)
        self.assertIn('first release', output)
        self.assertFalse(any(call[0] == 'gh' for call in self.runner.calls))

    def test_missing_artifact_names_journey(self):
        self.runner.artifacts = [row for row in self.runner.artifacts if row['name'] != 'verify-wazig-media-fit']
        self.assert_missing('journey media-fit: missing artifact verify-wazig-media-fit')

    def test_log_without_recording_fails(self):
        self.runner.content = {'run.log': b'passed'}
        self.assert_missing('non-empty .png screenshot or .mp4 recording')

    def test_empty_recording_fails(self):
        self.runner.content['screenshots/final.png'] = b''
        self.assert_missing('non-empty .png screenshot or .mp4 recording')

    def test_mp4_without_png_passes(self):
        self.runner.content = {'run.log': b'passed', 'capture.mp4': b'video'}
        self.assertEqual(self.check()[0], 0)

    def test_missing_or_empty_log_fails(self):
        for content in [None, b'']:
            with self.subTest(content=content):
                self.runner.content.pop('run.log', None)
                if content is not None:
                    self.runner.content['run.log'] = content
                self.assert_missing('non-empty run.log')

    def test_expired_artifact_fails(self):
        self.runner.artifacts[0]['expired'] = True
        self.assert_missing('journey search: expired artifact')

    def test_empty_artifact_fails(self):
        self.runner.artifacts[0]['size_in_bytes'] = 0
        self.assert_missing('journey search: empty artifact')

    def test_no_pr_fails(self):
        self.runner.pulls = []
        code, output = self.check()
        self.assertEqual(code, 1)
        self.assertIn('abc123: no PR, no recorded proof', output)

    def test_unmerged_pr_does_not_count(self):
        self.runner.pulls[0]['merged_at'] = None
        self.runner.pulls[0]['state'] = 'closed'
        self.assertEqual(self.check()[0], 1)

    def test_no_app_changes_passes_without_gh(self):
        self.runner.files = ['README.md', 'tools/test_release_proof.py']
        code, output = self.check()
        self.assertEqual(code, 0)
        self.assertIn('no changed app features', output)
        self.assertFalse(any(call[0] == 'gh' for call in self.runner.calls))

    def test_build_and_mapped_tool_changes_need_proof(self):
        for path in ['build.zig', 'tools/verify-wazig/caret.ps1']:
            with self.subTest(path=path):
                self.runner.files = [path]
                self.runner.pulls = []
                self.assertEqual(self.check()[0], 1)

    def test_no_successful_pr_head_run_fails(self):
        for change in [{'conclusion': 'failure'}, {'status': 'in_progress'},
                       {'head_sha': 'wrong'}, {'event': 'workflow_dispatch'}]:
            with self.subTest(change=change):
                self.runner.runs = [dict(FakeRunner().runs[0], **change)]
                self.assert_missing('no successful verify-wazig PR run on head pr-head')

    def test_latest_successful_run_is_required(self):
        self.runner.runs.append(dict(self.runner.runs[0], id=101))
        self.assertEqual(self.check()[0], 0)
        downloads = [call for call in self.runner.calls if call[:3] == ['gh', 'run', 'download']]
        self.assertTrue(downloads)
        self.assertTrue(all(call[3] == '101' for call in downloads))

    def test_download_failure_fails_closed(self):
        def runner(command):
            if command[:3] == ['gh', 'run', 'download']:
                raise subprocess.CalledProcessError(1, command)
            return self.runner(command)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = proof.check_release_proof('owner/repo', 'v1.11.0', runner=runner)
        self.assertEqual(code, 1)
        self.assertIn('MISSING:', output.getvalue())
        self.assertIn('PR #42', output.getvalue())

    def test_repeated_commits_for_pr_check_journeys_once(self):
        self.runner.commits.append('def456')
        code, output = self.check()
        self.assertEqual(code, 0)
        self.assertEqual(output.count('journey search: ok'), 1)

    def test_pr_files_not_just_commit_files_select_journeys(self):
        self.runner.files = ['src/main.zig']
        self.runner.pr_files.append({'filename': 'tools/verify-wazig/caret.ps1'})
        self.runner.artifacts = [row for row in self.runner.artifacts if row['name'] != 'verify-wazig-caret']
        self.assert_missing('journey caret: missing artifact')

    def test_renamed_old_path_is_included(self):
        self.runner.pr_files = [{'filename': 'docs/moved.md', 'previous_filename': 'src/media.zig'}]
        self.runner.artifacts = [row for row in self.runner.artifacts if row['name'] != 'verify-wazig-media-fit']
        self.assert_missing('journey media-fit: missing artifact')

    def test_real_git_first_parent_merge_range_requires_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], text=True, stderr=subprocess.PIPE).strip()

            git('init', '-q')
            git('config', 'user.email', 'fixture@example.invalid')
            git('config', 'user.name', 'Fixture')
            path = Path(directory) / 'build.zig'
            path.write_text('before')
            git('add', '.')
            git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD')
            git('tag', 'v1.0.0')
            path.write_text('after')
            git('add', '.')
            git('commit', '-qm', 'feature')
            feature = git('rev-parse', 'HEAD')
            tree = git('rev-parse', 'HEAD^{tree}')
            merge = git('commit-tree', tree, '-p', base, '-p', feature, '-m', 'merge')
            git('tag', 'v1.1.0', merge)

            def runner(command):
                if command[0] == 'git':
                    return subprocess.check_output(['git', '-C', directory, *command[1:]], text=True)
                return self.runner(command)

            for pulls, expected in [(self.runner.pulls, 0), ([], 1)]:
                with self.subTest(pr_present=bool(pulls)):
                    self.runner.pulls = pulls
                    output = io.StringIO()
                    with contextlib.redirect_stdout(output):
                        code = proof.check_release_proof('owner/repo', 'v1.1.0', runner=runner)
                    self.assertEqual(code, expected, output.getvalue())
                    self.assertIn(merge, output.getvalue())
                    self.assertNotIn(feature, output.getvalue())

    def test_github_file_limit_fails_closed(self):
        path = 'repos/owner/repo/pulls/42/files'
        self.runner.pages = {(path, page): [{'filename': 'README.md'}] * 100 for page in range(1, 31)}
        self.assert_missing('PR file list reached the GitHub limit')

    def test_files_runs_and_artifacts_paginate(self):
        for endpoint, first, second in [
            ('pulls/42/files', [{'filename': 'README.md'}] * 100, self.runner.pr_files),
            ('actions/workflows/verify.yml/runs', {'workflow_runs': [dict(self.runner.runs[0], conclusion='failure')] * 100}, {'workflow_runs': self.runner.runs}),
            ('actions/runs/100/artifacts', {'artifacts': [{'name': 'unrelated'}] * 100}, {'artifacts': self.runner.artifacts}),
        ]:
            with self.subTest(endpoint=endpoint):
                path = f'repos/owner/repo/{endpoint}'
                self.runner.pages = {(path, 1): first, (path, 2): second}
                code, output = self.check()
                self.assertEqual(code, 0, output)
                self.assertIn('journey media-fit: ok', output)


class JourneyPlanningTests(unittest.TestCase):
    def setUp(self):
        self.mapping = json.loads((ROOT / 'tools/verify-wazig/pr-journeys.json').read_text())
        self.journeys = json.loads((ROOT / 'tools/verify-wazig/journeys.json').read_text())['journeys']

    def test_old_inline_expected_sets(self):
        cases = [
            ([], set()),
            (['README.md'], set()),
            (['src/main.zig'], {'search', 'voice', 'reply'}),
            (['build.zig'], {'search', 'voice', 'reply'}),
            (['.github/workflows/verify.yml'], {'search', 'voice', 'reply'}),
            (['tools/verify-wazig/run.ps1'], {'search', 'voice', 'reply'}),
            (['src/audio.zig', 'src/reply.zig'], {'search', 'voice', 'reply'}),
            (['src/media.zig', 'src/slack.zig'], {'search', 'voice', 'reply', 'media-fit', 'slack-threads'}),
            (['src/paste_image.zig', 'tools/verify-wazig/caret.ps1'], {'search', 'voice', 'reply', 'paste-image', 'caret'}),
            (['src/theme.zig', 'src/dictation.zig'], {'search', 'voice', 'reply', 'sidebar-surface', 'dictation-shortcuts'}),
        ]
        for files, expected in cases:
            with self.subTest(files=files):
                self.assertEqual(proof.plan_journeys(files, self.mapping, self.journeys), expected)

    def test_limits_and_unknown_names_fail(self):
        mapping = copy.deepcopy(self.mapping)
        mapping['max_journeys'] = 2
        with self.assertRaisesRegex(ValueError, 'PR journey limit exceeded'):
            proof.plan_journeys(['src/main.zig'], mapping, self.journeys)
        mapping = copy.deepcopy(self.mapping)
        mapping['paths']['docs/'] = ['unknown']
        with self.assertRaisesRegex(ValueError, 'PR journey map contains unknown journeys'):
            proof.plan_journeys(['docs/file.md'], mapping, self.journeys)


if __name__ == '__main__':
    unittest.main()

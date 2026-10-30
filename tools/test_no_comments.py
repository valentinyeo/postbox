import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCANNER = ROOT / "tools/strip-comments.mjs"


class CommentPolicyTests(unittest.TestCase):
    def test_repository_file_types_and_generated_sources(self):
        fixtures = {
            ".github/workflows/javascript.yml": "jobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/github-script@v7\n        with:\n          script: |\n            const a = 1; // remove\n",
            ".github/workflows/shell.yml": "jobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n          echo ok # remove\n",
            ".github/workflows/powershell.yml": "jobs:\n  check:\n    runs-on: windows-latest\n    steps:\n      - shell: pwsh\n        run: |\n          Write-Output 'ok' <# remove #>\n",
            "src/generated/table.zig": "// remove\nconst a = 1;\n",
            "docs/example.zig": "// remove\nconst a = 1;\n",
            "build.zig.zon": ".{ .name = .example } // remove\n",
            "tools/extensionless": "#!/bin/sh\n# remove\necho ok\n",
            "src/generated.zig": "//! Automatically generated\nconst a = 1;\n",
            "assets/installer.wxs": '<Wix><!-- remove --></Wix>\n',
            ".gitattributes": "# remove\n*.zig text eol=lf\n",
            ".gitignore": "# remove\ncache/\n",
            "tools/systemd/review.service": "# remove\n[Unit]\nDescription=Review\n",
            "tools/systemd/review.timer": "# remove\n[Timer]\nOnBootSec=1m\n",
        }
        for name, source in fixtures.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                subprocess.run(["git", "init", "-q", directory], check=True)
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(source)
                subprocess.run(["git", "-C", directory, "add", "."], check=True)
                failed = subprocess.run(["node", str(SCANNER), "--check", directory], capture_output=True, text=True)
                self.assertEqual(failed.returncode, 1, failed.stderr)
                self.assertIn(name + ":", failed.stderr)
                self.assertEqual(target.read_text(), source)
                subprocess.run(["node", str(SCANNER), directory], check=True, capture_output=True)
                clean = subprocess.run(["node", str(SCANNER), "--check", directory], check=True, capture_output=True, text=True)
                self.assertIn("No code comments found.", clean.stdout)

    def test_zig_format_directives_survive(self):
        program = "import { strip } from './tools/strip-comments.mjs'; const s = '// zig fmt: off\\nconst a=1;\\n// zig fmt: on\\n'; if (strip(s, 'zig').output !== s) process.exit(1);"
        subprocess.run(["node", "--input-type=module", "-e", program], cwd=ROOT, check=True)

    def test_generators_do_not_emit_comments(self):
        for name in ("gen_emoji_data.py", "gen_shortcodes.py"):
            source = (ROOT / "tools" / name).read_text()
            self.assertNotIn('out.write("//', source)
            self.assertNotIn('print("//', source)


class AutomergeCommentCheckTests(unittest.TestCase):
    def run_workflow(self, mode):
        workflow = (ROOT / '.github/workflows/automerge.yml').read_text()
        script = textwrap.dedent(workflow.split('        run: |\n', 1)[1])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gh = root / 'gh'
            gh.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ['FAKE_DIR'])
mode = os.environ['FAKE_MODE']
with (root / 'calls').open('a') as log:
    log.write(json.dumps(args) + '\\n')
sha = 'a' * 40
if args[:2] == ['pr', 'list']:
    print('' if mode == 'self-heal' else '1')
elif args[:2] == ['pr', 'view']:
    if 'mergeCommit' in args:
        print(sha)
    else:
        checks = ['ci', 'tdlib', 'windows-smoke', 'no-comments', 'unfurl-verification',
                  'private-markers', 'secret-scan', 'pr-title', 'notify-release', 'tdlib-cache / cache']
        if mode == 'missing-check': checks.remove('no-comments')
        if mode == 'read-failure': sys.exit(1)
        if mode == 'invalid-json': print('{'); sys.exit(0)
        if mode == 'invalid-head': sha = 'not-a-commit'
        rollup = [dict(name=n, status='COMPLETED', conclusion='SUCCESS') for n in checks]
        if ':' in mode:
            action, name = mode.split(':', 1)
            if action == 'missing': rollup = [c for c in rollup if c['name'] != name]
            elif action == 'pending':
                if name not in checks: rollup.append(dict(name=name))
                rollup = [dict(c, status='IN_PROGRESS', conclusion='') if c['name'] == name else c for c in rollup]
            elif action == 'stale-success':
                rollup = [dict(c, status='IN_PROGRESS') if c['name'] == name else c for c in rollup]
            elif action == 'invalid-rollup': rollup = None
            elif action == 'status': rollup.append(dict(__typename='StatusContext', context='external', state=name))
            else: rollup.append(dict(name=name, status='COMPLETED', conclusion=action))
        print(json.dumps(dict(isDraft=False, labels=[], mergeable='MERGEABLE', headRefOid=sha,
            statusCheckRollup=rollup, isCrossRepository=(mode == 'cross-repository'),
            author=dict(login='contributor' if mode == 'non-owner' else 'fixture'))))
elif args[:2] == ['pr', 'merge']:
    pass
elif args[0] == 'api':
    print('src/main.zig' if '/files?' in args[1] else '0' if '/compare/' in args[1] else sha)
elif args[:2] == ['workflow', 'run']:
    if mode == 'dispatch-failure' and args[2] == 'no-comments.yml': sys.exit(1)
    (root / args[2]).touch()
elif args[:2] == ['run', 'list']:
    name = args[args.index('-w') + 1]
    print(int((root / name).exists()) if mode != 'missing-check' else 1)
else:
    sys.exit('unexpected gh call: ' + str(args))
''')
            gh.chmod(0o755)
            (root / 'sleep').write_text('#!/bin/sh\nexit 0\n')
            (root / 'sleep').chmod(0o755)
            env = dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH'],
                       FAKE_DIR=directory, FAKE_MODE=mode, REPO='fixture/repository', REPO_OWNER='fixture', RUNNER_TEMP=directory)
            result = subprocess.run(['bash', '-c', script], env=env, cwd=ROOT, capture_output=True, text=True)
            calls = [json.loads(line) for line in (root / 'calls').read_text().splitlines()]
            return result, calls

    def test_merge_dispatches_both_checks(self):
        result, calls = self.run_workflow('merge')
        self.assertEqual(result.returncode, 0, result.stderr)
        dispatched = [args[2] for args in calls if args[:2] == ['workflow', 'run']]
        self.assertEqual(dispatched, ['ci.yml', 'no-comments.yml'])

    def test_IGSH_635_cross_repository_pr_is_skipped(self):
        result, calls = self.run_workflow('cross-repository')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('#1: skip (not a same-repo PR by the owner)', result.stdout)
        self.assertFalse(any(args[:2] == ['pr', 'merge'] for args in calls))

    def test_IGSH_635_non_owner_pr_is_skipped(self):
        result, calls = self.run_workflow('non-owner')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('#1: skip (not a same-repo PR by the owner)', result.stdout)
        self.assertFalse(any(args[:2] == ['pr', 'merge'] for args in calls))

    def test_self_heal_dispatches_both_checks(self):
        result, calls = self.run_workflow('self-heal')
        self.assertEqual(result.returncode, 0, result.stderr)
        dispatched = [args[2] for args in calls if args[:2] == ['workflow', 'run']]
        self.assertEqual(dispatched, ['ci.yml', 'no-comments.yml'])

    def test_missing_comment_check_blocks_merge(self):
        result, calls = self.run_workflow('missing-check')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('required checks not green: no-comments', result.stdout)
        self.assertFalse(any(args[:2] == ['pr', 'merge'] for args in calls))

    def test_failed_comment_dispatch_fails_closed(self):
        result, calls = self.run_workflow('dispatch-failure')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(sum(args[:3] == ['workflow', 'run', 'no-comments.yml'] for args in calls), 3)
        self.assertIn('could not start no-comments.yml', result.stderr)

    def test_IGSH_504_every_head_check_must_be_green(self):
        checks = ('ci', 'tdlib', 'windows-smoke', 'no-comments', 'unfurl-verification',
                  'private-markers', 'secret-scan', 'pr-title', 'notify-release', 'tdlib-cache / cache')
        modes = [f'{state}:{name}' for name in checks
                 for state in ('missing', 'pending', 'FAILURE', 'SKIPPED', 'CANCELLED', 'stale-success')]
        modes += ['FAILURE:future-check', 'FAILURE:tdlib-cache / cache', 'pending:future-check', 'status:PENDING', 'status:FAILURE']
        for mode in modes:
            with self.subTest(mode=mode):
                result, calls = self.run_workflow(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('required checks not green:', result.stdout)
                self.assertFalse(any(args[:2] == ['pr', 'merge'] for args in calls), result.stdout)

    def test_IGSH_504_ai_review_never_blocks_and_head_is_pinned(self):
        for mode in ('merge', 'SUCCESS:future-check', 'FAILURE:code-review', 'SKIPPED:code-review', 'pending:code-review', 'status:SUCCESS'):
            with self.subTest(mode=mode):
                result, calls = self.run_workflow(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                merges = [args for args in calls if args[:2] == ['pr', 'merge']]
                self.assertEqual(len(merges), 1, result.stdout)
                self.assertEqual(merges[0][merges[0].index('--match-head-commit') + 1], 'a' * 40)

    def test_IGSH_504_unreadable_head_checks_fail_closed(self):
        for mode in ('read-failure', 'invalid-json', 'invalid-head', 'invalid-rollup:all'):
            with self.subTest(mode=mode):
                result, calls = self.run_workflow(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(any(args[:2] == ['pr', 'merge'] for args in calls), result.stdout)
                self.assertTrue('could not' in result.stdout or 'invalid PR head' in result.stdout, result.stdout)

    def test_IGSH_504_notification_is_a_successful_noop_on_prs(self):
        historical = subprocess.run(['git', 'show', 'e383ae2^:.github/workflows/ci.yml'],
                                    cwd=ROOT, capture_output=True, text=True, check=True).stdout
        job = historical.split('  notify-release:', 1)[1]
        before_steps, steps = job.split('    steps:', 1)
        self.assertNotIn('    if:', before_steps)
        self.assertIn("github.event_name == 'workflow_dispatch'", steps)
        self.assertIn("github.ref == 'refs/heads/main'", steps)
        self.assertIn('        if: >-', steps)

    def test_IGSH_504_lint_rejects_historical_automerge(self):
        workflow = subprocess.run(['git', 'show', '4064743:.github/workflows/automerge.yml'],
                                  cwd=ROOT, capture_output=True, text=True, check=True).stdout
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'src').mkdir()
            (root / 'src/main.zig').write_text('')
            (root / '.github/workflows').mkdir(parents=True)
            (root / '.github/workflows/automerge.yml').write_text(workflow)
            result = subprocess.run(['bash', str(ROOT / 'tools/lint-repeats.sh'), directory],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('[B8]', result.stdout)

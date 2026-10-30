import copy
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / '.github/workflows'
REPORTS = ('ci', 'verify', 'release-proof', 'postbox-upgrade', 'voice-language',
           'no-comments', 'gitleaks', 'private-markers', 'run-log-markers')


def load(name):
    return yaml.safe_load((WORKFLOWS / (name + '.yml')).read_text())


def check_reports(workflows):
    for name, workflow in workflows.items():
        triggers = workflow[True]
        assert set(triggers) == {'schedule', 'workflow_dispatch'}, name
        assert triggers['schedule'] and all(row.get('cron') for row in triggers['schedule']), name
        assert workflow['permissions']['contents'] == 'read', name
        assert all(value == 'read' for value in workflow['permissions'].values()), name


def check_release(auto, release):
    assert set(auto[True]) == {'push', 'workflow_dispatch'}
    assert auto[True]['push']['branches'] == ['main']
    assert auto['concurrency']['cancel-in-progress'] is False
    steps = auto['jobs']['tag']['steps']
    by_name = {step.get('name'): step for step in steps}
    guard = by_name['Require main ref']['run']
    assert '"$GITHUB_REF" != "refs/heads/main"' in guard and 'exit 1' in guard
    assert steps.index(by_name['Require main ref']) < steps.index(by_name['Select pushed commit'])
    assert 'target_sha=${GITHUB_SHA}' in by_name['Select pushed commit']['run']
    retry = by_name['Skip or retry an existing tag']['run']
    for fragment in ('--points-at "${target_sha}"', 'gh release view', 'gh workflow run release.yml', 'echo "skip=true"'):
        assert fragment in retry
    version = by_name['Work out the next version']['run']
    for fragment in ('sort -V | tail -1', 'refs/tags/${next}', 'refusing to move it', 'minor)'):
        assert fragment in version
    tag = by_name['Tag it']['run']
    for fragment in ('sha="${target_sha}"', 'ref=refs/tags/${next_tag}', 'sha=${sha}', 'gh workflow run release.yml', '--ref "${next_tag}"'):
        assert fragment in tag
    assert 'auto-release-pick.sh' not in str(steps) and 'ci-green.sh' not in str(steps)
    assert set(release[True]) == {'push', 'workflow_dispatch'}
    assert release[True]['push']['tags'] == ['v*']
    jobs = release['jobs']
    assert jobs['build']['if'] == "github.ref_type == 'tag'"
    assert jobs['launch']['needs'] == 'build'
    assert jobs['launch']['runs-on'] == 'windows-latest'
    assert jobs['release']['needs'] == ['build', 'launch', 'gitleaks']
    for job in ('build', 'launch', 'gitleaks', 'release'):
        assert 'if' not in jobs[job] or job == 'build'
    build = str(jobs['build']['steps'])
    for fragment in ('x86_64-windows-gnu', 'aarch64-windows-gnu', '--release=small', 'release-bundle', 'SHA256SUMS.txt', 'Postbox-', 'Messages-', '.msi'):
        assert fragment in build
    launch = str(jobs['launch']['steps'])
    for fragment in ('release-bundle', 'Start-Process', 'MainWindowHandle', 'HasExited'):
        assert fragment in launch
    scan = str(jobs['gitleaks']['steps'])
    for fragment in ('fetch-depth', 'gitleaks detect', '--redact', '$GITHUB_SHA'):
        assert fragment in scan
    publish = str(jobs['release']['steps'])
    for fragment in ('release-bundle', 'gh release create', '--verify-tag', 'gh release upload', 'SHA256SUMS.txt'):
        assert fragment in publish
    assert jobs['release']['permissions']['contents'] == 'write'


class WorkflowContractTests(unittest.TestCase):
    def test_report_workflows(self):
        check_reports({name: load(name) for name in REPORTS})

    def test_report_trigger_and_permissions_mutations_fail(self):
        for name in REPORTS:
            for mutation in ('push', 'schedule', 'permissions'):
                with self.subTest(name=name, mutation=mutation):
                    workflow = copy.deepcopy(load(name))
                    if mutation == 'push':
                        workflow[True]['push'] = None
                    elif mutation == 'schedule':
                        del workflow[True]['schedule']
                    else:
                        workflow['permissions']['contents'] = 'write'
                    with self.assertRaises(AssertionError):
                        check_reports({name: workflow})

    def test_fast_release_contract(self):
        check_release(load('auto-release'), load('release'))

    def test_fast_release_regressions_fail(self):
        for mutation in ('branch', 'guard', 'sha', 'retry', 'tag', 'build', 'launch', 'scan', 'publish', 'needs'):
            with self.subTest(mutation=mutation):
                auto, release = copy.deepcopy(load('auto-release')), copy.deepcopy(load('release'))
                steps = {step.get('name'): step for step in auto['jobs']['tag']['steps']}
                if mutation == 'branch': auto[True]['push']['branches'] = ['*']
                elif mutation == 'guard': steps['Require main ref']['run'] = 'true'
                elif mutation == 'sha': steps['Select pushed commit']['run'] = 'echo target_sha=origin/main'
                elif mutation == 'retry': steps['Skip or retry an existing tag']['run'] = 'true'
                elif mutation == 'tag': steps['Tag it']['run'] = 'true'
                elif mutation == 'build': release['jobs']['build']['steps'] = []
                elif mutation == 'launch': release['jobs']['launch']['steps'] = []
                elif mutation == 'scan': release['jobs']['gitleaks']['steps'] = []
                elif mutation == 'publish': release['jobs']['release']['steps'] = []
                else: release['jobs']['release']['needs'] = ['build']
                with self.assertRaises(AssertionError):
                    check_release(auto, release)

    def test_main_guard_and_pushed_sha_steps(self):
        steps = {step.get('name'): step for step in load('auto-release')['jobs']['tag']['steps']}
        guard = steps['Require main ref']['run']
        for ref, expected in [('refs/heads/main', 0), ('refs/heads/feature', 1), ('refs/tags/v1.0.0', 1)]:
            result = subprocess.run(['bash', '-e', '-c', guard], env=dict(os.environ, GITHUB_REF=ref), capture_output=True)
            self.assertEqual(result.returncode, expected, ref)
        with tempfile.TemporaryDirectory() as directory:
            envfile = Path(directory) / 'env'
            subprocess.run(['bash', '-e', '-c', steps['Select pushed commit']['run']], check=True,
                           env=dict(os.environ, GITHUB_SHA='a' * 40, GITHUB_ENV=str(envfile)))
            self.assertEqual(envfile.read_text(), 'target_sha=' + 'a' * 40 + '\n')


if __name__ == '__main__':
    unittest.main()

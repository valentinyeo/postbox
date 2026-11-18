import copy
import hashlib
import json
import runpy
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools/verify-wazig'


def check_version_pins(workflow):
    pins = workflow['env']
    for name in ('BASE_ZIG_VERSION', 'BASE_APP_VERSION'):
        assert re.fullmatch(r'\d+\.\d+\.\d+', pins[name]), name
    for job_name, job in workflow['jobs'].items():
        assert not {'BASE_ZIG_VERSION', 'BASE_APP_VERSION'} & job.get('env', {}).keys(), job_name
        for step in job.get('steps', []):
            assert not {'BASE_ZIG_VERSION', 'BASE_APP_VERSION'} & step.get('env', {}).keys(), job_name
            if step.get('uses', '').startswith('mlugg/setup-zig@'):
                assert step['with']['version'] == '${{ env.BASE_ZIG_VERSION }}', job_name
            for value in re.findall(r'-Dversion=(\$\{\{.*?\}\}|[^\s\'\"]+)', step.get('run', '')):
                assert value == '${{ env.BASE_APP_VERSION }}', (job_name, value)
            for line in step.get('run', '').splitlines():
                if '-ExpectedVersion' in line and '-FontBaseline' not in line:
                    assert re.search(r'-ExpectedVersion (?:\$env:VERIFY_VERSION|\$\{\{ env.BASE_APP_VERSION \}\})(?:\s|$)', line), job_name
                if 'VERIFY_VERSION=' in line and 'RELEASE_TAG' not in line:
                    assert 'VERIFY_VERSION=${{ env.BASE_APP_VERSION }}' in line, job_name


class FailureMarkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.evidence = Path(self.temp.name)

    def classify(self, code, feature='search'):
        return subprocess.run([sys.executable, str(TOOLS / 'classify_red.py'), '--feature', feature,
                               '--evidence', str(self.evidence), '--exit-code', str(code)],
                              capture_output=True, text=True)

    def test_nonzero_with_own_check_marker_counts_for_every_planted_journey(self):
        for patch in (TOOLS / 'planted').glob('*.patch'):
            with self.subTest(feature=patch.stem):
                (self.evidence / 'journey-check-failed.txt').write_text(f'{patch.stem}: app behaviour check\n')
                result = self.classify(1, patch.stem)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('app behaviour check', result.stdout)

    def test_unlisted_harness_error_never_counts_without_marker(self):
        (self.evidence / 'journey-started.txt').write_text('JOURNEY STARTED')
        (self.evidence / 'failure.txt').write_text('search: cosmic widget transport imploded 8675309')
        result = self.classify(1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no journey check failure marker', result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def test_zero_never_counts_even_with_marker(self):
        for marker in (False, True):
            with self.subTest(marker=marker):
                if marker:
                    (self.evidence / 'journey-check-failed.txt').write_text('search: app check')
                result = self.classify(0)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('repro passed on base', result.stderr)

    def test_empty_or_other_journey_marker_is_rejected(self):
        for contents in ('', 'voice: playback advances'):
            with self.subTest(contents=contents):
                (self.evidence / 'journey-check-failed.txt').write_text(contents)
                self.assertNotEqual(self.classify(1).returncode, 0)

    def test_both_ci_red_jobs_use_the_same_classifier(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        for job in ('base-fails', 'planted'):
            steps = workflow['jobs'][job]['steps']
            self.assertTrue(any('tools/verify-wazig/classify-red.ps1' in step.get('run', '') for step in steps))
        wrapper = (TOOLS / 'classify-red.ps1').read_text()
        self.assertIn('classify_red.py', wrapper)
        self.assertIn('$LASTEXITCODE -ne 0', wrapper)

    def test_planted_text_comparison_installs_the_same_chrome_driver(self):
        jobs = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())['jobs']
        name = 'Install Chrome screenshot driver'
        clean = next(step for step in jobs['verify']['steps'] if step.get('name') == name)
        steps = jobs['planted']['steps']
        planted = next(step for step in steps if step.get('name') == name)
        self.assertEqual(planted, clean)
        self.assertEqual(planted['if'], "matrix.feature == 'text-comparison'")
        journey = next(step for step in steps if step.get('name') == 'Run planted journey')
        self.assertLess(steps.index(planted), steps.index(journey))

    @unittest.skipUnless(shutil.which('pwsh'), 'Journey marker PowerShell runtime requires hosted CI')
    def test_text_comparison_marks_native_text_mismatch(self):
        source = (TOOLS / 'harness.ps1').read_text()
        assertion = re.search(r'^function Assert-That\([^\n]*\) \{[\s\S]*?^\}', source, re.M).group()
        journey = (TOOLS / 'journey-text-comparison.ps1').read_text()
        check = journey.split("Copy-Item $metrics (Join-Path $Evidence 'text-metrics.json')\n", 1)[1].split('Save-Screen', 1)[0]
        check = check.replace('$PSScriptRoot', TOOLS.as_posix())
        expected = json.loads((ROOT / 'src/verify_text.json').read_text())['data']['messages'][0]['Text']
        for text, failed in ((expected, False), ('Wrong paragraph text', True), (expected.lower(), True)):
            with self.subTest(text=text):
                marker = self.evidence / 'journey-check-failed.txt'
                marker.unlink(missing_ok=True)
                (self.evidence / 'text-metrics.json').write_text(json.dumps(dict(text=text)))
                session = json.dumps(dict(evidence=str(self.evidence), feature='text-comparison'))
                script = assertion + '\nfunction Get-App($Session) { return @{ HasExited = $false } }\n'
                script += f"$Evidence = '{self.evidence}'; $script:JourneyCheckSession = '{session}' | ConvertFrom-Json\n"
                script += "$ErrorActionPreference = 'Stop'\ntry {\n" + check + '\n} catch {\n'
                script += 'if (-not [object]::ReferenceEquals($_.Exception, $script:JourneyCheckFailure)) { exit 2 }; exit 1\n}\n'
                result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, int(failed), result.stdout + result.stderr)
                self.assertEqual(marker.exists(), failed)
                classified = self.classify(result.returncode, 'text-comparison')
                self.assertEqual(classified.returncode == 0, failed, classified.stderr)
                if failed:
                    self.assertEqual(marker.read_text(encoding='utf-8-sig').strip(),
                                     'text-comparison: native paragraph matches fixture text')

    @unittest.skipUnless(shutil.which('pwsh'), 'Journey marker PowerShell runtime requires hosted CI')
    def test_only_failed_app_checks_write_marker(self):
        source = (TOOLS / 'harness.ps1').read_text()
        helpers = '\n'.join(re.search(rf'^function {name}\([^\n]*\) \{{[\s\S]*?^\}}', source, re.M).group()
                            for name in ('Assert-That', 'Wait-Until'))
        helpers = helpers.replace('"$PSScriptRoot/wait_message.py"', f"'{TOOLS / 'wait_message.py'}'")
        runner = (TOOLS / 'run.ps1').read_text()
        reset = runner.split("$ErrorActionPreference = 'Stop'", 1)[1].split('. "$PSScriptRoot/harness.ps1"', 1)[0]
        drive = runner.split('    try {\n        if ($FontBaseline)', 1)[1].split('    $final = Read-Control', 1)[0]
        drive = '    try {\n        if ($FontBaseline)' + drive
        drive = drive.replace('$PSScriptRoot', f"'{self.evidence}'")
        reject = runner.split('    if (-not [object]::ReferenceEquals', 1)[1].split('    "${Feature}:', 1)[0]
        reject = '    if (-not [object]::ReferenceEquals' + reject
        fixture = r'''
$ErrorActionPreference = 'Stop'
function Get-App($Session) {
    if ($env:DEAD_APP -eq 'true') { throw 'App disappeared' }
    return @{ HasExited = $false }
}
'''
        for case, command, expected in [
            ('assertion', "Assert-That $false 'Search order differs'", True),
            ('passed', "Assert-That $true 'Search order differs'", False),
            ('setup', "$script:JourneyCheckSession = $null; Assert-That $false 'setup failed'", False),
            ('harness', "Assert-That $false 'control tool failed' -Harness", False),
            ('exception', "throw 'new missing tool error'", False),
            ('check-exception', "Wait-Until { throw 'new tool crash' } 'app check' -Seconds 0", False),
            ('check-wait', "Wait-Until { $false } 'playback advances' -Seconds 0", True),
            ('harness-wait', "Wait-Until { $false } 'tool listening' -Seconds 0 -Harness", False),
            ('crashed-app', "$env:DEAD_APP = 'true'; Assert-That $false 'app check'", False),
            ('caught-then-error', "try { Assert-That $false 'app check' } catch { }; throw 'unrelated crash'", False),
            ('caught-then-pass', "try { Assert-That $false 'app check' } catch { }", False),
        ]:
            with self.subTest(case=case):
                marker = self.evidence / 'journey-check-failed.txt'
                marker.write_text('search: stale check from earlier run')
                (self.evidence / 'case.ps1').write_text(command)
                session = json.dumps(dict(evidence=str(self.evidence), feature='search'))
                script = fixture + helpers + f"\n$session = '{session}' | ConvertFrom-Json\n"
                script += f"$Evidence = '{self.evidence}'; $journey = @{{ script = 'case.ps1' }}; $FontBaseline = $false\n"
                script += reset + '\ntry {\n' + drive + '\n} catch {\n' + reject + 'Write-Output $_.Exception.Message\n}\n'
                result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(marker.exists(), expected, result.stdout + result.stderr)
                if case == 'crashed-app':
                    self.assertIn('app check; app lookup failed: App disappeared', result.stdout)
                if expected:
                    name = 'playback advances' if case == 'check-wait' else 'Search order differs'
                    self.assertEqual(marker.read_text(encoding='utf-8-sig').strip(), f'search: {name}')


class SidebarPlantedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.evidence = Path(self.temp.name)
        self.oracle = runpy.run_path(str(TOOLS / 'check-sidebar-surface.py'))

    def fixture(self, width):
        for folder, commit, sidebar in [(self.evidence, 'candidate', 24),
                                        (self.evidence / 'baseline', 'historical', 0)]:
            folder.mkdir(exist_ok=True)
            image = [[(16, 16, 16)] * 900 for _ in range(320)]
            for row in image:
                row[:width] = [(sidebar,) * 3] * width
                row[width] = (46,) * 3
            for y in range(64, 74):
                image[y][70:140] = [(242,) * 3] * 70
            for y, shade in [(98, 36), (99, 36), (172, 32), (173, 32)]:
                image[y][width + 209:width + 213] = [(shade,) * 3] * 4
            self.oracle['PNG']['write_png'](folder / 'sidebar-amoled.png', image)
            files = {
                'session.json': dict(feature='sidebar-surface', commit=commit, sha256=commit),
                'sidebar-layout.json': [dict(theme='amoled', dpi=96, client=[0, 0, 900, 320],
                                             edge=width, canvas=[width + 1, 0, 899 - width, 320])],
                'sidebar-amoled.messages.json': dict(messages=[dict(id='ISSUE-462-PARAGRAPH', bubble=[10, 90, 410, 180])]),
                'side-effects.json': dict(sync='stopped', pending_sends=0, pending_archives=0,
                                          production_preferences_absent=True, whatsapp_store_absent=True,
                                          telegram_store_absent=True),
            }
            for name, data in files.items():
                (folder / name).write_text(json.dumps(data))
            (folder / 'result.txt').write_text('JOURNEY PASSED: sidebar-surface\n')
            (folder / 'cleanup.txt').write_text('CLEANUP PASSED:\n')
        provenance = dict(candidate_commit='candidate', baseline_commit='historical', assertion_parent='historical',
                          candidate_sha256='candidate', baseline_sha256='historical',
                          fixture_sha256=hashlib.sha256((ROOT / 'src/verify_text.json').read_bytes().replace(b'\r\n', b'\n')).hexdigest().upper())
        (self.evidence / 'sidebar-builds.json').write_text(json.dumps(provenance))

    def validate(self):
        return subprocess.run([sys.executable, str(TOOLS / 'check-evidence.py'), str(self.evidence)],
                              capture_output=True, text=True)

    def classify(self, code):
        return subprocess.run([sys.executable, str(TOOLS / 'classify_red.py'), '--feature', 'sidebar-surface',
                               '--evidence', str(self.evidence), '--exit-code', str(code)],
                              capture_output=True, text=True)

    def test_clean_width_passes_without_failure_marker(self):
        self.fixture(300)
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.evidence / 'journey-check-failed.txt').exists())
        self.assertNotEqual(self.classify(result.returncode).returncode, 0)

    def test_wrong_width_is_an_expected_journey_red(self):
        self.fixture(390)
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        classified = self.classify(result.returncode)
        self.assertEqual(classified.returncode, 0, classified.stderr)
        self.assertIn('sidebar-surface: ', classified.stdout)

    def test_missing_baseline_is_not_an_expected_red(self):
        self.fixture(300)
        (self.evidence / 'baseline/session.json').unlink()
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        classified = self.classify(result.returncode)
        self.assertNotEqual(classified.returncode, 0)
        self.assertIn('no journey check failure marker', classified.stderr)

    def test_bad_provenance_is_not_an_expected_red(self):
        self.fixture(390)
        (self.evidence / 'sidebar-builds.json').write_text('{}')
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(self.classify(result.returncode).returncode, 0)
        self.assertFalse((self.evidence / 'journey-check-failed.txt').exists())

    def test_failed_cleanup_is_not_an_expected_red(self):
        self.fixture(390)
        (self.evidence / 'cleanup.txt').write_text('CLEANUP FAILED:\n')
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(self.classify(result.returncode).returncode, 0)
        self.assertFalse((self.evidence / 'journey-check-failed.txt').exists())

    def test_planted_job_has_sidebar_baseline_and_validation(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())
        planted = workflow['jobs']['planted']['steps']
        checkout = next(step for step in planted if step.get('uses', '').startswith('actions/checkout@'))
        self.assertEqual(checkout.get('with', {}).get('fetch-depth'), 0)
        name = 'Build and capture the pre-change sidebar baseline'
        baseline = next(step for step in planted if step.get('name') == name)
        clean = next(step for step in workflow['jobs']['verify']['steps'] if step.get('name') == name)
        self.assertEqual(baseline['if'], clean['if'])
        self.assertEqual(baseline['run'].replace('planted-evidence', 'verification-evidence'), clean['run'])
        drive = next(step for step in planted if step.get('id') == 'journey')['run']
        self.assertIn("if ($code -eq 0 -and $env:FEATURE -eq 'sidebar-surface')", drive)
        self.assertIn('python tools/verify-wazig/check-evidence.py planted-evidence', drive)
        self.assertIn('"code=$code" >> $env:GITHUB_OUTPUT', drive)


class VersionPinTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT / '.github/workflows/verify.yml').read_text())

    def test_jobs_read_shared_pins(self):
        check_version_pins(self.workflow)

    def test_different_hardcoded_zig_version_in_any_job_fails(self):
        for name, job in self.workflow['jobs'].items():
            for index, step in enumerate(job.get('steps', [])):
                if step.get('uses', '').startswith('mlugg/setup-zig@'):
                    with self.subTest(job=name):
                        changed = copy.deepcopy(self.workflow)
                        changed['jobs'][name]['steps'][index]['with']['version'] = '0.99.1'
                        with self.assertRaises(AssertionError):
                            check_version_pins(changed)

    def test_hardcoded_app_version_and_shadowed_pins_fail(self):
        for mutation in ('build', 'expected', 'export', 'shadow'):
            with self.subTest(mutation=mutation):
                changed = copy.deepcopy(self.workflow)
                job = changed['jobs']['candidate']
                if mutation == 'shadow':
                    job['env'] = dict(BASE_ZIG_VERSION='0.99.1')
                else:
                    job['steps'].append({'run': {'build': 'zig build -Dversion=0.99.1',
                                                'expected': 'pwsh run.ps1 -ExpectedVersion 0.99.1',
                                                'export': "'VERIFY_VERSION=0.99.1' >> $env:GITHUB_ENV"}[mutation]})
                with self.assertRaises(AssertionError):
                    check_version_pins(changed)


if __name__ == '__main__':
    unittest.main()

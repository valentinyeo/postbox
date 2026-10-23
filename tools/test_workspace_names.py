import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('views_evidence', ROOT / 'tools/verify-wazig/check-views-evidence.py')
EVIDENCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EVIDENCE)


class WorkspaceNamesEvidenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        names = ['Alpha Workspace', 'Beta Workspace']
        screenshots = {
            'view-label': ['view-3.png', 'view-4.png'],
            'sort-views': ['sort-before.png'],
            'palette': ['workspace-palette.png'],
            'inbox-tooltip': ['inbox-tooltip-T0ABC123.png', 'inbox-tooltip-T0DEF456.png'],
        }
        self.checks = {}
        for check_id, images in screenshots.items():
            prefix = 'Show Slack ' if check_id == 'palette' else 'Slack '
            self.checks[check_id] = dict(status='passed', names=names, labels=[prefix + name for name in names], screenshots=images)
            for image in images:
                (self.folder / image).write_bytes(b'fixture screenshot')
        self.write_checks()
        (self.folder / 'hub-proof.log').write_text('\n'.join(f'views {check_id} PASS' for check_id in screenshots))
        (self.folder / 'actions.log').write_text('hover: T0ABC123\nhover: T0DEF456\n')
        (self.folder / 'final-data').mkdir()
        self.write('final-data/hub-fixture-workspace-names.json', dict(T0ABC123=names[0], T0DEF456=names[1]))

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value), encoding='utf-8')

    def write_checks(self):
        self.write('workspace-names.json', self.checks)
        self.write('result.json', dict(feature='views', status='passed', checks=self.checks))

    def validate(self):
        def capture(name):
            self.assertTrue((self.folder / f'{name}.png').is_file())
            return dict(current_view=dict(inbox=True))

        EVIDENCE.check_workspace_names(self.folder, capture)

    def test_both_names_on_all_surfaces_pass(self):
        self.validate()

    def test_each_surface_rejects_either_old_team_id_label(self):
        for check_id, check in self.checks.items():
            for index, team in enumerate(['T0ABC123', 'T0DEF456']):
                with self.subTest(check_id=check_id, team=team):
                    old = check['labels'][index]
                    check['labels'][index] = ('Show ' if check_id == 'palette' else '') + 'Slack ' + team
                    self.write_checks()
                    with self.assertRaises(AssertionError):
                        self.validate()
                    check['labels'][index] = old
        self.write_checks()
        self.validate()

    def test_each_surface_rejects_bare_workspace_labels(self):
        for check_id, check in self.checks.items():
            for index, name in enumerate(check['names']):
                with self.subTest(check_id=check_id, name=name):
                    old = check['labels'][index]
                    check['labels'][index] = ('Show ' if check_id == 'palette' else '') + name
                    self.write_checks()
                    with self.assertRaises(AssertionError):
                        self.validate()
                    check['labels'][index] = old
        self.write_checks()
        self.validate()

    def test_each_surface_rejects_extra_team_id_labels(self):
        for check_id, check in self.checks.items():
            for team in ['T0ABC123', 'T0DEF456']:
                with self.subTest(check_id=check_id, team=team):
                    check['labels'].append(('Show ' if check_id == 'palette' else '') + 'Slack ' + team)
                    self.write_checks()
                    with self.assertRaises(AssertionError):
                        self.validate()
                    check['labels'].pop()
        self.write_checks()
        self.validate()

    def test_missing_check_screenshot_proof_or_cache_is_rejected(self):
        originals = json.loads(json.dumps(self.checks))
        for check_id in originals:
            self.checks = json.loads(json.dumps(originals))
            del self.checks[check_id]
            self.write_checks()
            with self.assertRaises(AssertionError):
                self.validate()
        self.checks = originals
        self.write_checks()
        for name in ['workspace-palette.png', 'hub-proof.log', 'final-data/hub-fixture-workspace-names.json']:
            path = self.folder / name
            data = path.read_bytes()
            path.unlink()
            with self.assertRaises((AssertionError, FileNotFoundError)):
                self.validate()
            path.write_bytes(data)
        self.validate()

    def test_result_must_preserve_observed_checks(self):
        self.write('result.json', dict(feature='views', status='passed'))
        with self.assertRaises(AssertionError):
            self.validate()


class WorkspaceNamesSourceTests(unittest.TestCase):
    def test_shared_label_formatter_and_duplicate_precedence_are_wired(self):
        subprocess.run([sys.executable, str(ROOT / 'tools/verify-wazig/check-views-source.py'), 'workspace-names'], cwd=ROOT, check=True)

    def test_all_source_check_modes_work_without_git_history(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['src', 'tools/verify-wazig']:
                shutil.copytree(ROOT / name, root / name)
            for name in ['build.zig', 'CHANGELOG.md', '.github/workflows/verify.yml',
                         '.claude/skills/verify-wazig/features/views.md']:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            self.assertFalse((root / '.git').exists())
            for mode in ['model', 'integration', 'journey', 'fixture', 'workspace-names']:
                with self.subTest(mode=mode):
                    result = subprocess.run(
                        [sys.executable, str(root / 'tools/verify-wazig/check-views-source.py'), mode],
                        cwd=root, env=dict(os.environ, PATH=''), capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn(f'views {mode} static PASS', result.stdout)

    def test_inbox_hover_sends_absolute_moves_with_dispatch_time(self):
        source = (ROOT / 'tools/verify-wazig/menus.cs').read_text()
        hover = source.split('public static void Hover(', 1)[1].split('public static void Click(', 1)[0]
        for fragment in [
            'WindowFromPoint(new Point { X = x, Y = y })', 'if (owner != pid) throw',
            'GetSystemMetrics(76)', 'GetSystemMetrics(77)', 'GetSystemMetrics(78)', 'GetSystemMetrics(79)',
            'x = absoluteX, y = absoluteY, flags = 0xE001',
            'if (SendInput(1, input, Marshal.SizeOf(typeof(Input))) != 1) throw',
            'System.Threading.Thread.Sleep(100)',
        ]:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, hover)
        self.assertNotIn('Mouse(pid, x, y, 1)', hover)

    def test_inbox_tooltip_timeout_records_native_state_and_rethrows(self):
        source = (ROOT / 'tools/verify-wazig/views.ps1').read_text()
        hover = source.split('function Read-InboxWorkspaceTooltips(', 1)[1].split('function Assert-AccountView(', 1)[0]
        self.assertIn('DescribeWindow([VerifyWindow]::GetForegroundWindow())', hover)
        self.assertLess(hover.index('"hover-foreground:'), hover.index('[VerifyMenus]::Hover'))
        failure = hover.split('} catch {', 1)[1]
        for fragment in [
            "'inbox-tooltip-failure.txt'", 'row_index=$index', 'error=$tooltipFailure', '$tooltipFailure = $_',
            '[VerifyInboxTooltip]::Capture($handle, $origin.X + 24, $origin.Y + $offset)',
            "Save-Screen $Session 'inbox-tooltip-failure'", 'Native diagnostics failed:',
            'Failure screenshot failed:', '\n            throw $tooltipFailure\n',
        ]:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, failure)
        self.assertLess(failure.index('::Capture('), failure.index('\n            throw $tooltipFailure\n'))
        self.assertLess(failure.index('Save-Screen'), failure.index('\n            throw $tooltipFailure\n'))

    def test_inbox_tooltip_diagnostics_read_remote_tools_including_hidden_foreign_windows(self):
        source = (ROOT / 'tools/verify-wazig/inbox-tooltip.cs').read_text()
        required = [
            'GetCursorPos(out cursor)', '"list: " + DescribeWindow(list)', 'GetWindowRect(window, out rect)',
            '"WindowFromPoint: " + DescribeWindow(WindowFromPoint(hover))',
            '"foreground: " + DescribeWindow(GetForegroundWindow())', 'ScreenToClient(list, ref hover)',
            'SendMessageTimeout(list, 0x01A9', 'LB_ITEMFROMPOINT ok=', 'outside={3}',
            'owner_pid={2} visible={3}', 'GetWindowThreadProcessId(window, out pid)',
            'GetClassName(window, name, name.Capacity)', 'GetWindowText(window, text, text.Capacity)',
            'EnumWindows((window, data) =>', 'ClassName(window) != "tooltips_class32"',
            '"tooltip: " + DescribeWindow(window)', 'TooltipText(output, window)',
            'OpenProcess(0x1038, false, pid)', 'VirtualAllocEx(process,', 'WriteProcessMemory(process,',
            'ReadProcessMemory(process,', 'Environment.Is64BitOperatingSystem && !wow64 ? 72 : 48',
            'size == 72 ? 48 : 36', '0x043B', '0x043A', 'Message(window, 0x0438, 32768, memory',
            'TTM_GETTEXT={3}', '0x23, 500, out result)', 'safeToFree = false;',
            'memory != IntPtr.Zero && safeToFree', 'CloseHandle(process)',
        ]
        def validate(text):
            for fragment in required:
                self.assertIn(fragment, text)
            enumeration = text.split('bool enumerated = EnumWindows(', 1)[1]
            self.assertNotIn('IsWindowVisible', enumeration)
            self.assertNotIn('pid ==', enumeration)
        validate(source)
        for fragment in required:
            with self.subTest(missing=fragment):
                with self.assertRaises(AssertionError):
                    validate(source.replace(fragment, 'removed'))
        for filter_text in ['if (!IsWindowVisible(window)) return true;', 'if (pid == 1) return true;']:
            with self.subTest(filter=filter_text):
                with self.assertRaises(AssertionError):
                    validate(source.replace('count++;', filter_text + 'count++;', 1))

    def test_inbox_tooltip_native_fallback_requires_visible_exact_text(self):
        source = (ROOT / 'tools/verify-wazig/views.ps1').read_text()
        hover = source.split('function Read-InboxWorkspaceTooltips(', 1)[1].split('function Assert-AccountView(', 1)[0]
        for fragment in [
            '0x01A1', '0x018E', '$Rows[$index].view_account -ne $team',
            '($index - [int]$top.ToUInt64()) * [int]$height.ToUInt64()',
            'Hover($Session.pid, $origin.X + 20, $origin.Y + $offset - 5)',
            'Hover($Session.pid, $origin.X + 24, $origin.Y + $offset)',
            "'Slack Alpha Workspace'", "'Slack Beta Workspace'",
            '-not $tip.Current.IsOffscreen -and $tip.Current.Name -ceq $expectedName',
            "[VerifyMenus]::Find($Session.pid, 'tooltips_class32')",
            '$nativeTip -ne [IntPtr]::Zero', '[VerifyMenus]::Bounds($nativeTip)',
            '$bounds.Right -gt $screen.Left -and $bounds.Left -lt $screen.Right',
            '$bounds.Bottom -gt $screen.Top -and $bounds.Top -lt $screen.Bottom',
            '$text = Read-EditText $nativeTip', 'if ($text -ceq $expectedName) { return $text }',
            '"tooltip: $team = $tooltip"', '$labels += $tooltip',
            'Save-Screen $Session "inbox-tooltip-$team"', "Save-WorkspaceNameCheck $Session 'inbox-tooltip'",
        ]:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, hover)
        menus = (ROOT / 'tools/verify-wazig/menus.cs').read_text()
        find = menus.split('public static IntPtr Find(', 1)[1].split('public static Rect Bounds(', 1)[0]
        self.assertIn('owner == pid && IsWindowVisible(window) && text.ToString() == name', find)
        harness = (ROOT / 'tools/verify-wazig/harness.ps1').read_text()
        self.assertIn('ReadText($Handle, 13,', harness)


if __name__ == '__main__':
    unittest.main()

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).with_name('verify-wazig') / 'check-search-center.py'
spec = importlib.util.spec_from_file_location('search_center', CHECKER)
search_center = importlib.util.module_from_spec(spec)
spec.loader.exec_module(search_center)


def fixture(folder, dx=0, dy=0, caret=True):
    layout = {}
    for state, text_width in (('placeholder', 100), ('typed', 28)):
        rows = [[(42, 48, 46)] * 240 for _ in range(34)]
        for y in (0, 33):
            rows[y] = [(110, 120, 115)] * 240
        left = int((240 - text_width) / 2 + dx)
        top = int(12 + dy)
        for y in range(top, top + 10):
            for x in range(left, left + text_width):
                if (x - left) % 7 < 4 or y in (top, top + 9):
                    rows[y][x] = (180, 190, 185)
        if state == 'typed' and caret:
            for y in range(8, 26):
                rows[y][left + text_width + 1] = (240, 240, 240)
        search_center.workspace_icons.write_png(folder / f'search-center-{state}.png', rows)
        layout[state] = {'pill': [0, 0, 240, 34], 'edit': [17, 1, 223, 33],
                         'focused': state == 'typed', 'text': 'Beta' if state == 'typed' else ''}
    (folder / 'search-center-layout.json').write_text(json.dumps(layout))


class SearchCenterTest(unittest.TestCase):
    def run_check(self, dx=0, dy=0, source=None):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            fixture(folder, dx, dy)
            script = CHECKER
            if source is not None:
                script = folder / 'mutated.py'
                source = source.replace("Path(__file__).with_name('check-workspace-icons.py')",
                                        repr(str(CHECKER.with_name('check-workspace-icons.py'))))
                script.write_text(source)
            process = subprocess.run([sys.executable, str(script), str(folder)], capture_output=True, text=True)
            result = json.loads((folder / 'search-center.json').read_text())
            return process, result

    def test_centered_and_exact_tolerance_edges_pass(self):
        for dx, dy in ((0, 0), (2, 1), (-2, -1)):
            with self.subTest(dx=dx, dy=dy):
                process, result = self.run_check(dx, dy)
                self.assertEqual(process.returncode, 0, process.stderr)
                self.assertIn('search-center PASS', process.stdout)
                self.assertEqual(result, {state: {'dx': dx, 'dy': dy} for state in ('placeholder', 'typed')})

    def test_top_left_and_each_axis_beyond_tolerance_fail(self):
        for dx, dy in ((-70, -9), (3, 0), (-3, 0), (0, 2), (0, -2)):
            with self.subTest(dx=dx, dy=dy):
                process, result = self.run_check(dx, dy)
                self.assertNotEqual(process.returncode, 0)
                self.assertIn('search-center FAIL', process.stderr)
                self.assertEqual(result['typed'], {'dx': dx, 'dy': dy})

    def test_each_state_is_required(self):
        for state in ('placeholder', 'typed'):
            with tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                fixture(folder)
                bad = folder / 'bad'
                bad.mkdir()
                fixture(bad, 3)
                (folder / f'search-center-{state}.png').write_bytes((bad / f'search-center-{state}.png').read_bytes())
                with self.assertRaisesRegex(ValueError, state):
                    search_center.check(folder)

    def test_missing_ink_fails(self):
        with self.assertRaisesRegex(AssertionError, 'missing text ink'):
            search_center.offsets([[(42, 48, 46)] * 240 for _ in range(34)], [0, 0, 240, 34], [17, 1, 223, 33])

    def test_negative_controls_detect_loosened_and_broken_tolerances(self):
        source = CHECKER.read_text()
        for old, new, dx, dy in (("> 2", "> 3", 3, 0), ("> 1", "> 2", 0, 2),
                                 ("abs(value['dx'])", "value['dx']", -3, 0),
                                 ("abs(value['dy'])", "value['dy']", 0, -2)):
            with self.subTest(mutation=new):
                self.assertIn(old, source)
                good, _ = self.run_check(dx, dy)
                broken, _ = self.run_check(dx, dy, source.replace(old, new))
                self.assertNotEqual(good.returncode, 0)
                self.assertEqual(broken.returncode, 0, broken.stderr)


if __name__ == '__main__':
    unittest.main()

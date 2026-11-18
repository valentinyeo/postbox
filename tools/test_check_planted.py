import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('check_planted', Path(__file__).with_name('check-planted.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PlantedChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / 'tools/verify-wazig'
        (self.folder / 'planted').mkdir(parents=True)
        (self.folder / 'journeys.json').write_text(json.dumps({'journeys': [{'name': 'search'}, {'name': 'voice'}]}))
        (self.folder / 'planted-limits.txt').write_text('1\n')
        (self.folder / 'planted/search.patch').write_text('diff --git a/src/main.zig b/src/main.zig\n')
        (self.folder / 'planted/search.txt').write_text('Search is broken.\n')
        (self.folder / 'planted/search.check').write_text('typed query reaches the filter\n')

    def test_valid(self):
        self.assertEqual(module.check(self.root), [])

    def test_unknown_journey(self):
        (self.folder / 'planted/unknown.patch').write_text('diff --git a/src/main.zig b/src/main.zig\n')
        self.assertTrue(any('unknown journey' in e for e in module.check(self.root)))

    def test_description_required(self):
        (self.folder / 'planted/search.txt').unlink()
        self.assertTrue(any('missing description' in e for e in module.check(self.root)))

    def test_expected_check_required(self):
        (self.folder / 'planted/search.check').unlink()
        self.assertTrue(any('missing expected check' in e for e in module.check(self.root)))

    def test_patch_shape(self):
        (self.folder / 'planted/search.patch').write_text('diff --git a/tools/file b/tools/file\n')
        self.assertTrue(any('expected a src patch' in e for e in module.check(self.root)))

    def test_limit(self):
        (self.folder / 'planted-limits.txt').write_text('0\n')
        self.assertTrue(any('limit is 0' in e for e in module.check(self.root)))


if __name__ == '__main__':
    unittest.main()

import importlib.util
import json
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
            prefix = 'Show ' if check_id == 'palette' else ''
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


if __name__ == '__main__':
    unittest.main()

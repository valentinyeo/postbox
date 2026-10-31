from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
HISTORICAL = {'check-hub-rollback-evidence.py'}
PINNED_TITLE = r'Postbox v0\.0\.526'


class EvidenceVersionTests(unittest.TestCase):
    def test_checks_use_the_version_the_run_built(self):
        for path in sorted((ROOT / 'tools/verify-wazig').glob('*.py')):
            if path.name in HISTORICAL:
                continue
            text = path.read_text()
            self.assertNotIn(PINNED_TITLE, text, f'{path.name} pins the product version')
            for number, line in enumerate(text.splitlines(), 1):
                if '0.0.526' not in line:
                    continue
                self.assertTrue('expected_version' in line or 'expected_product_version' in line,
                                f'{path.name}:{number} pins the product version')


if __name__ == '__main__':
    unittest.main()

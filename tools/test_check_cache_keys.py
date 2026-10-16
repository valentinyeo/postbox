import pathlib
import unittest

import check_cache_keys

ROOT = pathlib.Path(__file__).resolve().parent.parent


class CacheKeyTest(unittest.TestCase):
    def test_wazi_126_key_hashing_ci_yml_fails(self):
        line = "          key: tdlib-${{ env.TDLIB_COMMIT }}-${{ hashFiles('.github/workflows/ci.yml') }}"
        self.assertEqual(len(check_cache_keys.problems("ci.yml", line)), 1)

    def test_key_hashing_build_script_passes(self):
        line = "          key: tdlib-${{ env.TDLIB_COMMIT }}-${{ hashFiles('tools/build-tdlib.sh') }}"
        self.assertEqual(check_cache_keys.problems("ci.yml", line), [])

    def test_repo_workflows_pass(self):
        self.assertEqual(check_cache_keys.main(str(ROOT)), 0)


if __name__ == "__main__":
    unittest.main()

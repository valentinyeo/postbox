import pathlib
import re
import unittest
from check_hub_only import negative_controls, verify as verify_desktop

ROOT = pathlib.Path(__file__).resolve().parent.parent


def verify(workflows):
    for name, text in workflows.items():
        assert '-Dtdlib' not in text and 'Build TDLib' not in text and 'TELEGRAM_API_' not in text, name
    release = workflows['release']
    assert 'zig build -Dtarget=x86_64-windows-gnu --release=small -Dversion=' in release
    assert 'zig build -Dtarget=aarch64-windows-gnu --release=small -Dversion=' in release
    proof = workflows['release-proof']
    assert 'python3 tools/check_hub_only.py --binary zig-out/bin/Messages.exe' in proof
    smoke = proof.split('      - name: Headless Telegram smoke\n', 1)[1].split('      - name:', 1)[0]
    assert 'if:' not in smoke
    assert 'tools/verify-wazig/run.ps1 -Feature telegram -Bin ' in smoke
    assert 'python tools/verify-wazig/check-evidence.py verification-evidence' in proof
    for context in ('tdlib', 'windows-smoke', 'tdlib-cache / cache'):
        assert re.search(r'^    name: ' + re.escape(context) + r'$', workflows['ci'], re.M), context
    assert 'python3 tools/check_hub_only.py' in workflows['ci']
    assert 'uses: ./.github/workflows/tdlib-cache.yml' not in workflows['ci']


class TdlibReleaseTest(unittest.TestCase):
    def setUp(self):
        self.workflows = {name: (ROOT / '.github/workflows' / (name + '.yml')).read_text() for name in ('release', 'release-proof', 'ci')}

    def test_release_contract(self):
        verify(self.workflows)
        verify_desktop()
        negative_controls()

    def test_reintroduced_link_rejected(self):
        self.workflows['release'] += '\n-Dtdlib=/tmp/tdlib-install\n'
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_reintroduced_build_rejected(self):
        self.workflows['release'] += '\nBuild TDLib\n'
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_missing_binary_guard_rejected(self):
        self.workflows['release-proof'] = self.workflows['release-proof'].replace('python3 tools/check_hub_only.py --binary zig-out/bin/Messages.exe', 'true')
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_disabled_smoke_rejected(self):
        self.workflows['release-proof'] = self.workflows['release-proof'].replace('      - name: Headless Telegram smoke\n', '      - name: Headless Telegram smoke\n        if: false\n')
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_missing_required_context_rejected(self):
        for context in ('tdlib', 'windows-smoke', 'tdlib-cache / cache'):
            original = self.workflows['ci']
            self.workflows['ci'] = original.replace('    name: ' + context + '\n', '    name: other\n')
            with self.assertRaises(AssertionError):
                verify(self.workflows)
            self.workflows['ci'] = original

    def test_source_layout(self):
        self.assertFalse((ROOT / '.github/workflows/tdlib-cache.yml').exists())
        self.assertFalse((ROOT / 'tools/build-tdlib.sh').exists())
        self.assertFalse((ROOT / 'tools/TDLIB_COMMIT').exists())
        self.assertNotIn('tdlib', (ROOT / 'build.zig').read_text())


if __name__ == '__main__':
    unittest.main()

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def verify(workflows):
    keys = []
    for name, text in workflows.items():
        restore = text.split('      - name: Restore TDLib\n', 1)[1].split('      - name:', 1)[0]
        assert 'if:' not in restore, name
        assert re.search(r'uses: actions/cache@[a-f0-9]{40}\n', restore), name
        assert 'path: /tmp/tdlib-install\n' in restore, name
        key = re.search(r'key: (.+)', restore)[1]
        assert "${{ steps.tdlib.outputs.commit }}" in key, name
        assert "${{ hashFiles('tools/build-tdlib.sh') }}" in key, name
        assert 'cat tools/TDLIB_COMMIT' in text, name
        keys.append(key)
        build = text.split('      - name: Build TDLib\n', 1)[1].split('      - name:', 1)[0]
        assert "if: steps.tdcache.outputs.cache-hit != 'true'" in build, name
        assert 'run: bash tools/build-tdlib.sh' in build, name
    assert len(set(keys)) == 1
    release = workflows['release']
    build = release.split('      - name: Build\n', 1)[1].split('      - name:', 1)[0]
    assert '-Dtdlib=/tmp/tdlib-install' in build
    assert '-Dtelegram-api-id="$TELEGRAM_API_ID"' in build
    assert '-Dtelegram-api-hash="$TELEGRAM_API_HASH"' in build
    assert 'b"setTdlibParameters" in Path("zig-out/bin/Messages.exe").read_bytes()' in release
    smoke = release.split('      - name: Headless Telegram smoke\n', 1)[1].split('      - name:', 1)[0]
    assert 'if:' not in smoke
    assert "-ArgumentList '--tdlib-smoke' -Wait -PassThru" in smoke
    assert '$code -ne 0' in smoke
    arm = release.split('      - name: Build and package ARM64\n', 1)[1].split('      - name:', 1)[0]
    assert '-Dtarget=aarch64-windows-gnu' in arm
    assert '-Dtdlib' not in arm
    cache = workflows['tdlib-cache']
    for trigger in ('branches: [main]', '- tools/build-tdlib.sh', '- tools/TDLIB_COMMIT', 'workflow_dispatch:', 'workflow_call:', 'schedule:', 'cron:'):
        assert trigger in cache
    assert 'uses: ./.github/workflows/tdlib-cache.yml' in workflows['ci']
    assert 'needs: tdlib-cache' in workflows['ci']


class TdlibReleaseTest(unittest.TestCase):
    def setUp(self):
        self.workflows = {name: (ROOT / '.github/workflows' / (name + '.yml')).read_text() for name in ('release', 'ci', 'tdlib-cache')}

    def test_release_contract(self):
        verify(self.workflows)

    def test_disabled_restore_rejected(self):
        self.workflows['release'] = self.workflows['release'].replace('        id: tdcache', '        if: false\n        id: tdcache')
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_disabled_build_rejected(self):
        self.workflows['release'] = self.workflows['release'].replace("if: steps.tdcache.outputs.cache-hit != 'true'", 'if: false')
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_missing_link_rejected(self):
        self.workflows['release'] = self.workflows['release'].replace(' -Dtdlib=/tmp/tdlib-install', '')
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_disabled_smoke_rejected(self):
        self.workflows['release'] = self.workflows['release'].replace('      - name: Headless Telegram smoke\n', '      - name: Headless Telegram smoke\n        if: false\n')
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_cache_drift_rejected(self):
        self.workflows['ci'] = self.workflows['ci'].replace('key: tdlib-', 'key: other-')
        with self.assertRaises(AssertionError):
            verify(self.workflows)

    def test_source_layout(self):
        script = (ROOT / 'tools/build-tdlib.sh').read_text()
        self.assertIn('sha256sum -c /tmp/openssl.sha256', script)
        self.assertIn('git checkout "$TDLIB_COMMIT"', script)
        self.assertIn('git checkout 51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf', script)
        self.assertIn('-print-file-name="$lib"', script)
        self.assertRegex((ROOT / 'tools/TDLIB_COMMIT').read_text(), r'^[a-f0-9]{40}\n$')
        self.assertNotIn('/usr/lib/gcc/', (ROOT / 'build.zig').read_text())


if __name__ == '__main__':
    result = unittest.main(exit=False).result
    if not result.wasSuccessful():
        raise SystemExit(1)
    print('TDLib release checks passed')

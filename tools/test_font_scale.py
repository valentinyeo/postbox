from pathlib import Path
import hashlib
import json
import runpy
import tempfile
import zipfile
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def verify_defaults(main, config):
    assert re.search(r'pub const default_scale: i32 = 100;', config)
    assert 'font_scale: i32 = @import("font_config.zig").default_scale,' in main
    load = main.split('fn loadFontScale() i32 {', 1)[1].split('\n}', 1)[0]
    assert 'if (result != win.ERROR_SUCCESS) return @import("font_config.zig").default_scale;' in load
    assert 'return @import("font_config.zig").savedScale(value);' in load
    assert 'command_font_reset, command_font_default => setFontScale(a, @import("font_config.zig").default_scale)' in main
    setter = main.split('fn setFontScale(a: *App, scale: i32) void {', 1)[1].split('\n}', 1)[0]
    assert 'a.font_scale = next;' in setter
    assert 'saveFontScale(next);' in setter


class FontScaleTests(unittest.TestCase):
    def test_approved_default_and_reset_share_scale(self):
        verify_defaults((ROOT / 'src/main.zig').read_text(), (ROOT / 'src/font_config.zig').read_text())

    def test_rejects_historical_undersized_default(self):
        historical = lambda path: subprocess.check_output(['git', 'show', f'b41ee91:{path}'], cwd=ROOT, text=True)
        with self.assertRaises(AssertionError):
            verify_defaults(historical('src/main.zig'), historical('src/font_config.zig'))


class PublishedFontBaselineTests(unittest.TestCase):
    def fixture(self, root):
        old = root / 'old'
        new = root / 'new'
        old.mkdir()
        new.mkdir()
        archive = old / 'Postbox-v0.9.224.zip'
        binary = b'published executable'
        with zipfile.ZipFile(archive, 'w') as package:
            package.writestr('Messages.exe', binary)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        exe = hashlib.sha256(binary).hexdigest()
        def put(folder, name, value):
            (folder / name).write_text(json.dumps(value))
        put(old, 'published-font-package.json', dict(tag='v0.9.224', asset_name=archive.name,
                                                     asset_digest='sha256:' + digest, package_sha256=digest))
        put(old, 'published-font-release.json', dict(tag_name='v0.9.224', assets=[dict(name=archive.name, digest='sha256:' + digest)]))
        (old / 'SHA256SUMS.txt').write_text(f'{digest}  {archive.name}\n')
        put(old, 'session.json', dict(feature='appearance', expected_version='0.9.224', expected_product='Postbox',
                                      sha256=exe.upper(), id='old', root='old-root', pid=10, startTicks='old-start'))
        put(old, 'font-baseline.state.json', dict(version='0.9.224'))
        put(old, 'font-baseline.json', dict(runtime_version='0.9.224', exe_sha256=exe.upper(), id='old', root='old-root',
                                            pid=10, start_ticks='old-start', initial_saved=False, scale=82,
                                            points=9.0, dpi=96, width=1920, height=1032))
        put(old, 'side-effects.json', dict(production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True, pending_sends=0, pending_archives=0, sync='stopped'))
        put(old, 'result.json', dict(feature='appearance', status='baseline-captured'))
        (old / 'result.txt').write_text('FONT BASELINE CAPTURED: v0.9.224')
        put(new, 'session.json', dict(feature='appearance', expected_version='0.0.526', sha256='a' * 64,
                                      commit='candidate', id='new', root='new-root'))
        put(new, 'result.json', dict(feature='appearance', status='passed'))
        put(new, 'text-fresh-default.state.json', dict(version='0.0.526', font_layout=dict(scale=100)))
        put(new, 'text-scale.json', dict(initial_saved=False, baseline_points=11.25))
        put(new, 'text-presets.json', [dict(scale=80, points=9), dict(scale=100, points=11.25), dict(scale=125, points=14), dict(scale=150, points=17)])
        put(new, 'font-viewport.json', dict(width=1920, height=1032, dpi=96, hosted_only=True))
        for folder, name in ((old, 'font-baseline'), (new, 'text-fresh-default')):
            (folder / (name + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n' + b'x' * 11000)
            version = '0.9.224' if folder == old else '0.0.526'
            (folder / (name + '.uia.txt')).write_text(f'MessagesZig | Combined inbox - Postbox v{version}\n')
            (folder / 'cleanup.txt').write_text('CLEANUP PASSED: fixture')
        return old, new

    def test_rejects_wrong_release_sha_default_and_status(self):
        check = runpy.run_path(str(ROOT / 'tools/verify-wazig/check-font-baseline.py'))['check']
        cases = [
            ('old', 'published-font-package.json', 'tag', 'v0.9.223'),
            ('old', 'session.json', 'sha256', '0' * 64),
            ('new', 'text-fresh-default.state.json', 'font_layout', {'scale': 82}),
            ('old', 'result.json', 'status', 'passed'),
            ('old', 'font-baseline.json', 'initial_saved', True),
            ('old', 'font-baseline.json', 'runtime_version', '0.9.223'),
            ('old', 'published-font-release.json', 'tag_name', 'v0.9.223'),
            ('new', 'text-scale.json', 'initial_saved', True),
            ('new', 'font-viewport.json', 'dpi', 144),
        ]
        with tempfile.TemporaryDirectory() as directory:
            old, new = self.fixture(Path(directory))
            check(old, new)
            for folder, filename, key, value in cases:
                path = (old if folder == 'old' else new) / filename
                original = path.read_text()
                changed = json.loads(original)
                changed[key] = value
                path.write_text(json.dumps(changed))
                with self.subTest(case=filename, key=key), self.assertRaises(AssertionError):
                    check(old, new)
                path.write_text(original)


if __name__ == '__main__':
    unittest.main()

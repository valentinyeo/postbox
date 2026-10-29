import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from check_shared_design import validate

ROOT = Path(__file__).resolve().parents[1]


class SharedDesignTests(unittest.TestCase):
    def test_current_application_consumes_the_pinned_shared_module(self):
        validate(ROOT)
        main = (ROOT / 'src/main.zig').read_text()
        for painter in ('micPill', 'roundButton', 'field', 'bubble', 'row', 'wave'):
            self.assertIn(f'design.{painter}(', main)
        self.assertIn('session.elapsedMs()', main)
        self.assertIn('session.level()', main)
        self.assertIn('session.fixture = .{ .pcm = pcm, .response = response };', main)
        self.assertIn('if (verification_fixture)', main[main.index('fn ensureDictation('):main.index('fn toggleDictation(')])
        capture = (ROOT / 'src/dictation.zig').read_text()
        self.assertIn('if (self.fixture) |fixture| parseResponse(self.allocator, fixture.response)', capture)
        self.assertIn('captureMicrophone(self)', capture)

    def test_hash_and_literal_checks_reject_real_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(ROOT / 'src', root / 'src')
            shutil.copyfile(ROOT / 'shared-design.json', root / 'shared-design.json')
            module = root / 'src/design_tokens.zig'
            original = module.read_text()
            module.write_text(original.replace('ReaderForeground: u32 = 0xF2F2F2', 'ReaderForeground: u32 = 0x5096FF'))
            with self.assertRaisesRegex(AssertionError, 'hash mismatch'):
                validate(root)
            module.write_text(original)
            main = root / 'src/main.zig'
            main.write_text(main.read_text() + '\npub const drift = 0x5096FF;\n')
            with self.assertRaisesRegex(AssertionError, 'UI colour literal'):
                validate(root)

    def test_manifest_hash_is_calculated_from_the_vendored_bytes(self):
        manifest = json.loads((ROOT / 'shared-design.json').read_text())
        self.assertEqual(manifest['sha256'], hashlib.sha256((ROOT / manifest['path']).read_bytes()).hexdigest())


if __name__ == '__main__':
    unittest.main()

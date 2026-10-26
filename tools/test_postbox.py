from contextlib import redirect_stdout
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import threading
import unittest

from check_postbox import check

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('github_fixture', ROOT / 'tools/verify-wazig/fake-github-updates.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class ProductContractTests(unittest.TestCase):
    def test_current_product(self):
        check(ROOT)

    def test_product_contract_rejects_boundary_regressions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ['src/main.zig', 'src/messenger_view.zig', 'src/wazigctl.zig', 'src/control.zig', 'src/update.zig', 'assets/installer.wxs', '.github/workflows/release.yml']:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            for name, old, new in [
                ('src/messenger_view.zig', 'Postbox v', 'Wazig v'),
                ('src/main.zig', '/repos/valentinyeo/postbox/releases', '/repos/valentinyeo/wazig/releases'),
                ('src/main.zig', 'Software\\\\Messages', 'Software\\\\Postbox'),
                ('src/main.zig', 'migrateProductName(init);', ''),
                ('assets/installer.wxs', 'Name="Postbox"', 'Name="Wazig"'),
                ('assets/installer.wxs', 'E2C53374-5665-593B-94F8-38573F3164D2', '00000000-0000-0000-0000-000000000000'),
                ('assets/installer.wxs', 'Target="[INSTALLDIR]Messages.exe"', 'Target="[INSTALLDIR]Postbox.exe"'),
                ('.github/workflows/release.yml', 'cp "Messages-${GITHUB_REF_NAME}.zip"', 'cp "wrong.zip"'),
                ('src/update.zig', 'if (branded and !std.mem.startsWith(u8, name.string, zip_asset_prefix)) continue;', ''),
            ]:
                with self.subTest(name=name, change=new):
                    path = root / name
                    original = path.read_text()
                    self.assertIn(old, original)
                    path.write_text(original.replace(old, new))
                    with self.assertRaises(AssertionError), redirect_stdout(io.StringIO()):
                        check(root)
                    path.write_text(original)


class UpdateFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'offer.json').write_text(json.dumps({'tag': 'v0.9.999'}))
        (self.root / 'update.zip').write_bytes(b'original updater payload')
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), fixture.UpdateHandler)
        self.server.root = self.root
        self.worker = threading.Thread(target=self.server.serve_forever)
        self.worker.start()
        self.addCleanup(self.close)

    def close(self):
        self.server.shutdown()
        self.worker.join()
        self.server.server_close()

    def get(self, path):
        connection = HTTPConnection(*self.server.server_address)
        try:
            connection.request('GET', path)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_old_api_redirects_without_weakening_https(self):
        code, headers, _ = self.get('/repos/valentinyeo/wazig/releases/latest')
        self.assertEqual(code, 301)
        self.assertEqual(headers['Location'], 'https://api.github.com/repos/valentinyeo/postbox/releases/latest')

    def test_both_names_share_verified_payload_and_history_terminates(self):
        code, _, body = self.get('/repos/valentinyeo/postbox/releases/latest')
        self.assertEqual(code, 200)
        release = json.loads(body)
        self.assertEqual(release['tag_name'], 'v0.9.999')
        self.assertEqual([asset['name'] for asset in release['assets']], ['Messages-v0.9.999.zip', 'Postbox-v0.9.999.zip'])
        _, _, payload = self.get('/update.zip')
        self.assertEqual(payload, b'original updater payload')
        for asset in release['assets']:
            self.assertEqual(asset['digest'], 'sha256:' + hashlib.sha256(payload).hexdigest())
            self.assertEqual(asset['size'], len(payload))
        self.assertEqual(json.loads(self.get('/repos/valentinyeo/postbox/releases?page=1')[2]), [release])
        self.assertEqual(json.loads(self.get('/repos/valentinyeo/postbox/releases?page=2')[2]), [])
        (self.root / 'offer.json').write_text(json.dumps({'tag': 'v0.10.0'}))
        self.assertEqual(json.loads(self.get('/repos/valentinyeo/postbox/releases/latest')[2])['tag_name'], 'v0.10.0')
        self.assertEqual(self.get('/unsupported')[0], 404)


if __name__ == '__main__':
    unittest.main()

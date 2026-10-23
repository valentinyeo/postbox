import json
from pathlib import Path
import random
import runpy
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools/verify-wazig'
CHECK = runpy.run_path(str(TOOLS / 'check-link-previews-evidence.py'))['check_link_previews']
PNG = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))['write_png']
FIXTURE = runpy.run_path(str(TOOLS / 'fake-hub.py'))
PROVIDERS = ['slack', 'whatsapp', 'telegram', 'signal']


class LinkPreviewsTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.folder = Path(temp.name)
        self.write('session.json', dict(sha256='fixture-hash', commit='fixture-commit', pid=7))
        self.write('result.json', dict(feature='link-previews', status='passed'))
        self.write('viewer.json', dict(handle=1, pid=7, **{'class': 'MessagesImageViewer'}))
        self.write('cache-requests.json', dict(before=5, after=5))
        self.write('side-effects.json', dict(pending_sends=0, pending_archives=0, sync='stopped',
                                           production_preferences_absent=True, whatsapp_store_absent=True, telegram_store_absent=True))
        pixels = []
        rng = random.Random(704)
        image = [[tuple(rng.randrange(256) for _ in range(3)) for _ in range(400)] for _ in range(250)]
        for y in range(20, 100):
            for x in range(20, 100):
                image[y][x] = (240, 160, 32)
            for x in range(120, 240):
                image[y][x] = (48, 112, 240)
        for provider in PROVIDERS:
            rows = []
            for kind in ['IMAGE', 'PAGE', 'QUERY', 'PLAIN']:
                url = 'http://127.0.0.1:7004/' + dict(IMAGE='pic.png', PAGE='page', QUERY='query?a=1&b=2', PLAIN='plain')[kind]
                rows.append(dict(id='LINK-' + kind, text={'PAGE': 'Synthetic page label', 'PLAIN': 'Clean page label'}.get(kind, url),
                                 links=[url], quote='Quoted & label' if kind == 'QUERY' else '',
                                 local=kind == 'IMAGE', media_type='image' if kind == 'IMAGE' else '',
                                 media=[20, 20, 100, 100] if kind == 'IMAGE' else [0, 0, 0, 0],
                                 card=[120, 20, 240, 100] if kind == 'PAGE' else [0, 0, 0, 0],
                                 preview=dict(ready=kind == 'PAGE', image=kind == 'PAGE', title='Synthetic preview',
                                              site='127.0.0.1', description='Synthetic description')))
            self.write(provider + '.messages.json', dict(chat=dict(provider=provider), messages=rows))
            self.write(provider + '.state.json', dict(selected=dict(provider=provider)))
            (self.folder / (provider + '.uia.txt')).write_text('MessagesZig | Wazig Messages v0.0.526')
            PNG(self.folder / (provider + '.png'), image)
            for colour, rect in [('amber', [20, 20, 100, 100]), ('cobalt', [120, 20, 240, 100])]:
                samples = len(range(rect[0] + 8, rect[2] - 8, 3)) * len(range(rect[1] + 8, rect[3] - 8, 3))
                pixels.append(dict(screenshot=provider + '.png', colour=colour, rect=rect, canvas=[0, 0], hits=samples, samples=samples))
        self.write('image-pixels.json', pixels)
        PNG(self.folder / 'viewer.png', image)
        requests = [dict(wire_path=path, status=200, authorized=False) for path in ['/pic.png', '/card.png', '/page', '/plain', '/query?a=1&b=2']]
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(row) for row in requests))
        (self.folder / 'actions.log').write_text('SendInput: inline image\nkeys: {ESC}\n' + '\n'.join('keys: Verification Links ' + p for p in PROVIDERS))
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: synthetic fixture')
        (self.folder / 'final-data').mkdir()
        for team in ['fixture-amber', 'fixture-cobalt']:
            (self.folder / 'final-data' / (team + '.image')).write_bytes(FIXTURE['workspace_png'](team))

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value), encoding='utf-8')

    def test_complete_evidence(self):
        CHECK(self.folder)

    def test_raw_markup_and_missing_rendering_are_rejected(self):
        for field, value in [('text', '<http://example.com|label>'), ('text', 'a&amp;b'), ('local', False), ('links', [])]:
            with self.subTest(field=field, value=value):
                path = self.folder / 'slack.messages.json'
                original = path.read_text()
                shown = json.loads(original)
                shown['messages'][0][field] = value
                self.write(path.name, shown)
                with self.assertRaises(AssertionError):
                    CHECK(self.folder)
                path.write_text(original)

    def test_fabricated_pixel_metrics_are_rejected(self):
        image = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))['read_png'](self.folder / 'slack.png')[2]
        for y in range(20, 100):
            for x in range(20, 100):
                image[y][x] = (0, 0, 0)
        PNG(self.folder / 'slack.png', image)
        with self.assertRaises(AssertionError):
            CHECK(self.folder)

    def test_missing_card_image_or_quoted_markup_is_rejected(self):
        path = self.folder / 'slack.messages.json'
        original = path.read_text()
        for index, key, value in [(1, 'preview', dict(ready=True, image=False)), (2, 'quote', '<raw>'), (3, 'card', [1, 2, 3, 4])]:
            shown = json.loads(original)
            shown['messages'][index][key] = value
            self.write(path.name, shown)
            with self.assertRaises(AssertionError):
                CHECK(self.folder)
        path.write_text(original)

    def test_missing_cached_image_is_rejected(self):
        (self.folder / 'final-data/fixture-amber.image').unlink()
        with self.assertRaises(AssertionError):
            CHECK(self.folder)


if __name__ == '__main__':
    unittest.main()

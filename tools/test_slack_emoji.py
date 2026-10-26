import copy
import hashlib
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import runpy
import socket
import struct
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.parse import quote


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools/verify-wazig'
FIXTURE = runpy.run_path(str(TOOLS / 'fake-hub.py'))
CHECK = runpy.run_path(str(TOOLS / 'check-slack-emoji-evidence.py'))['check_slack_emoji']
PIXELS = runpy.run_path(str(TOOLS / 'check-workspace-icons.py'))
TABLE_HASH = '0df5b13a416662c7d84266ed31b3499c7ae4ef99ba191854aa2fc9537b38f70a'


def check_table(raw):
    assert hashlib.sha256(raw).hexdigest() == TABLE_HASH
    lines = raw.decode().splitlines()
    names = [line.split('\t')[0] for line in lines]
    assert names == sorted(set(names))
    table = dict(line.split('\t') for line in lines)
    for name, emoji in [('broken_heart', '💔'), ('timer_clock', '⏲️'), ('billed_cap', '🧢'),
                        ('crossed_fingers', '🤞'), ('smiling_face_with_tear', '🥲'), ('tea', '🍵'),
                        ('+1', '👍'), ('thumbsup', '👍'), ('thumbsup::skin-tone-2', '👍🏻')]:
        assert table[name] == emoji
    assert 'cat_alone' not in table and 'crycat' not in table
    for name, emoji in table.items():
        lo, hi = 0, len(raw)
        while lo < hi:
            mid = lo + (hi - lo) // 2
            start = raw.rfind(b'\n', lo, mid) + 1 if b'\n' in raw[lo:mid] else lo
            end = raw.index(b'\n', start)
            code, value = raw[start:end].decode().split('\t')
            if name == code:
                assert value == emoji
                break
            if name < code:
                hi = start
            else:
                lo = end + 1
        else:
            raise AssertionError(name)
    return table


class EmojiDataChecks(unittest.TestCase):
    def test_generated_table_and_negative_controls(self):
        raw = (ROOT / 'src/slack_emoji.tsv').read_bytes()
        table = check_table(raw)
        self.assertGreater(len(table), 4000)
        self.assertGreater(sum('::skin-tone-' in name for name in table), 2000)
        for changed in [raw.replace(b'broken_heart', b'broken_wrong'), raw[:raw.rfind(b'\n', 0, -1) + 1]]:
            with self.assertRaises(AssertionError):
                check_table(changed)

    def test_generator_keeps_every_alias_and_skin_variation(self):
        generate = runpy.run_path(str(ROOT / 'tools/generate-slack-emoji.py'))['generate']
        raw = json.dumps([dict(short_names=['fixture_hand', 'fixture_alias'], unified='1F44D',
                               skin_variations={'1F3FB': dict(unified='1F44D-1F3FB'),
                                                '1F3FB-1F3FF': dict(unified='1F44D-1F3FB-1F3FF')})]).encode()
        table = dict(line.split('\t') for line in generate(raw).splitlines())
        self.assertEqual(len(table), 6)
        for name in ['fixture_hand', 'fixture_alias']:
            self.assertEqual(table[name], '👍')
            self.assertEqual(table[name + '::skin-tone-2'], '👍🏻')
            self.assertEqual(table[name + '::skin-tone-2::skin-tone-6'], '👍🏻🏿')

    def test_zig_parser_tests_and_renderer_are_wired(self):
        parser = (ROOT / 'src/slack_emoji.zig').read_text()
        for text in ['IGSH-670 standard aliases skin tones adjacent pairs and unknown',
                     'IGSH-670 custom resolver preserves unknown', ':timer_clock::billed_cap:',
                     ':thumbsup::skin-tone-2:', ':unknown_fixture:', ':thumbsup_extra:']:
            self.assertIn(text, parser)
        self.assertIn('"src/slack_emoji.zig"', (ROOT / 'build.zig').read_text())
        source = (ROOT / 'src/main.zig').read_text()
        self.assertIn('var paths: std.json.ObjectMap = .empty;', source)
        self.assertNotIn('std.json.ObjectMap.init(', source)
        for text in ['slack_emoji.replace', 'resolveCustomEmoji', 'importCustomEmoji', 'cacheSlackEmoji',
                     'entry.scope.slice(), scope', 'loadAvatarBitmap(a, entry.path.ptr())',
                     'win.AlphaBlend(hdc, cursor, y, em, em', 'message.gif_frame_index + 1',
                     'gif_frames', 'entry.name.slice()']:
            self.assertIn(text, source)
        self.assertNotIn('client.call', source.split('fn drawEmojiRun(', 1)[1].split('fn drawMixedLine(', 1)[0])
        self.assertIn('slack_emoji.zig', (ROOT / 'src/slack.zig').read_text())
        reaction_slice = source.split('        message.reaction_to.set(reaction_to);', 1)[1].split('        message.timestamp.set(getString(object, "Timestamp"));', 1)[0]
        self.assertNotIn('chat.provider', reaction_slice)
        self.assertNotIn('slack_emoji', reaction_slice)

    def test_hub_cache_completion_regression_uses_real_handler(self):
        source = (ROOT / 'src/main.zig').read_text()
        handler = source.split('        .hub_media => {\n            for (&a.media_downloads)', 1)[1].split('        .hub_avatar => {', 1)[0]
        success = handler.split('                if (ok) {', 1)[1].split('                } else {', 1)[0]
        self.assertIn('markMediaAttempted(a, slot.jid.slice(), slot.id.slice());', success)
        self.assertLess(success.index('markMediaAttempted('), success.index('clearMediaFailure('))
        queue = source.split('    if (batch.phase == .downloading) {', 1)[1].split('fn ensureAvatarSession(', 1)[0]
        self.assertIn('hubMediaPath(a, a.allocator, chat_key.of(batch), id.slice())', queue)
        self.assertIn('.has_local_path = if (path) |cached| fileExistsUtf8(cached) else false,', queue)
        build = (ROOT / 'build.zig').read_text()
        self.assertIn('sourceSection("        .hub_media => {\\n            for (&a.media_downloads)"', build)
        tests = (ROOT / 'src/background_media_test.zig').read_text()
        finish = tests.split('fn finish(a: *App) void {', 1)[1].split('\n}', 1)[0]
        self.assertIn('finishHubMedia(a, &result);', finish)
        self.assertNotIn('markMediaAttempted(', finish)
        self.assertIn('IGSH-670 hub Giphy completion advances the cached batch without refetching on reopen', tests)
        self.assertIn('IGSH-670 pending and failed hub media do not suppress a later download', tests)


class EmojiContractChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), FIXTURE['SlackEmojiHandler'])
        self.server.daemon_threads = True
        self.server.state = FIXTURE['bridge'].State(Path(self.temp.name) / 'requests.jsonl')
        self.addCleanup(self.server.server_close)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(self.server.shutdown)

    def get(self, path, authorized=True):
        connection = HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        try:
            headers = {'Authorization': 'Bearer ' + FIXTURE['bridge'].KEY} if authorized else {}
            connection.request('GET', path, headers=headers)
            response = connection.getresponse()
            return response.status, response.read(), response.getheader('Content-Type')
        finally:
            connection.close()

    def test_account_scoping_authorization_and_alias_contract(self):
        path = '/v1/wazig/slack/emoji?account=fixture-emoji'
        self.assertEqual(self.get(path, False)[0], 401)
        self.assertEqual(self.get('/v1/wazig/slack/emoji?account=fixture-other')[0], 404)
        status, raw, mime = self.get(path)
        self.assertEqual(status, 200)
        emoji = json.loads(raw)['emoji']
        self.assertEqual(emoji['crycat'], 'alias:cat_alone')
        self.assertEqual(emoji['fixture_cat'], 'alias:crycat')
        self.assertEqual(emoji['fixture_standard'], 'alias:tea')
        self.assertEqual(mime, 'application/json')
        media = '/v1/wazig/slack/emoji/media?account=fixture-emoji&name=cat_alone'
        self.assertEqual(self.get(media, False)[0], 401)
        self.assertEqual(self.get(media.replace('fixture-emoji', 'fixture-other'))[0], 404)
        self.assertEqual(self.get(media)[1:], (FIXTURE['workspace_png']('fixture-amber'), 'image/png'))
        hub = (ROOT / 'src/hub.zig').read_text()
        self.assertIn('/v1/wazig/slack/emoji/media?account={s}&name={s}', hub)
        self.assertIn('swapRemove("SlackEmojiPaths")', hub)

    def test_keep_alive_client_reset_is_not_a_handler_error(self):
        finished = threading.Event()
        errors = []
        finish_request = self.server.finish_request

        def finish(*args):
            try:
                finish_request(*args)
            except Exception as error:
                errors.append(error)
            finally:
                finished.set()

        with patch.object(self.server, 'finish_request', side_effect=finish):
            connection = HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
            try:
                connection.request('GET', '/v1/wazig/chats', headers={'Authorization': 'Bearer ' + FIXTURE['bridge'].KEY})
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                response.read()
                linger = struct.pack('HH' if os.name == 'nt' else 'ii', 1, 0)
                connection.sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, linger)
            finally:
                connection.close()
            self.assertTrue(finished.wait(5), 'Reset connection handler did not finish')
        self.assertEqual(errors, [])
        self.assertEqual(self.get('/v1/wazig/chats')[0], 200)

    def test_optional_avatar_and_workspace_icon_are_json_not_handler_errors(self):
        for path in ['/v1/wazig/avatar/' + quote(FIXTURE['SLACK_EMOJI_CHAT'], safe=''),
                     '/v1/wazig/workspace-icon/fixture-emoji']:
            with self.subTest(path=path):
                self.assertEqual(self.get(path, False)[0], 401)
                status, raw, mime = self.get(path)
                self.assertEqual((status, mime), (404, 'application/json'))
                self.assertEqual(json.loads(raw), {'error': 'unavailable'})

    def test_history_reactions_giphy_and_two_frame_bytes(self):
        chat = FIXTURE['SLACK_EMOJI_CHAT']
        status, raw, _ = self.get('/v1/wazig/messages?chat=' + quote(chat, safe=''))
        self.assertEqual(status, 200)
        rows = {row['MsgID']: row for row in json.loads(raw)}
        self.assertEqual(set(rows), {'EMOJI-STANDARD', 'EMOJI-CUSTOM', 'GIPHY'})
        self.assertIn(':timer_clock::billed_cap:', rows['EMOJI-STANDARD']['Text'])
        self.assertEqual(rows['EMOJI-STANDARD']['reactions'][0], dict(name='crycat', count=2))
        attachment = rows['GIPHY']['attachments'][0]
        self.assertEqual(attachment['image_mimetype'], 'image/gif')
        route = '/v1/wazig/media/' + quote(chat, safe='') + '/GIPHY'
        self.assertEqual(self.get(route, False)[0], 401)
        status, data, mime = self.get(route)
        self.assertEqual((status, mime), (200, 'image/gif'))
        self.assertEqual(data, FIXTURE['emoji_gif']())
        self.assertEqual(data[:6], b'GIF89a')
        self.assertEqual(data.count(b'!\xf9\x04'), 2)
        self.assertTrue(data.endswith(b';'))
        self.assertEqual(self.get('/v1/wazig/media/' + quote(chat, safe='') + '/UNKNOWN')[0], 404)


class EmojiJourneyChecks(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.folder = Path(temp.name)
        self.write('session.json', dict(feature='slack-emoji', sha256='fixture-hash', commit='fixture-revision', pid=7))
        self.write('result.json', dict(feature='slack-emoji', status='passed'))
        self.shown = dict(chat=dict(provider='slack'), messages=[
            dict(id='EMOJI-STANDARD', text='💔 ⏲️🧢 🤞 👍🏻 :unknown_fixture:', reaction='\ue000 2  🥲 1  🍵 1', reaction_chip=[20, 65, 180, 90]),
            dict(id='EMOJI-CUSTOM', text='Custom \ue001 alias \ue002 🍵 :cycle_a:', bubble=[20, 100, 300, 150]),
            dict(id='GIPHY', local=True, media_type='image', gif_frames=2, media=[20, 175, 116, 223])])
        self.write('emoji.messages.json', self.shown)
        image = [[(0, 0, 0) for _ in range(400)] for _ in range(300)]
        self.proof = {}
        for key, rect in [('custom', [20, 100, 300, 150]), ('reaction', [20, 65, 180, 90])]:
            for y in range(rect[1], rect[3]):
                for x in range(rect[0], rect[2]):
                    image[y][x] = (240, 160, 32)
            self.proof[key] = dict(screenshot='emoji.png', rect=rect, canvas=[0, 0], amber=(rect[2] - rect[0]) * (rect[3] - rect[1]), cobalt=0)
        PIXELS['write_png'](self.folder / 'emoji.png', image)
        self.proof['frames'] = []
        for name, colour, amber, cobalt in [('frame-a', (240, 160, 32), 96 * 48, 0), ('frame-b', (48, 112, 240), 0, 96 * 48)]:
            for y in range(175, 223):
                for x in range(20, 116):
                    image[y][x] = colour
            PIXELS['write_png'](self.folder / (name + '.png'), image)
            self.proof['frames'].append(dict(screenshot=name + '.png', rect=[20, 175, 116, 223], canvas=[0, 0], amber=amber, cobalt=cobalt))
        self.write('emoji-pixels.json', self.proof)
        for name in ['emoji', 'frame-a', 'frame-b', 'reopened']:
            (self.folder / (name + '.uia.txt')).write_text('MessagesZig | Postbox v0.0.526')
            self.write(name + '.state.json', dict(selected=dict(provider='slack')))
        paths = ['/v1/wazig/slack/emoji?account=fixture-emoji', '/v1/wazig/slack/emoji/media?account=fixture-emoji&name=cat_alone',
                 '/v1/wazig/media/slack%3Afixture-emoji%3Achannel/GIPHY']
        (self.folder / 'bridge-requests.jsonl').write_text('\n'.join(json.dumps(dict(wire_path=path, status=200, authorized=True)) for path in paths))
        self.write('emoji-cache.json', dict(before=3, after=3))
        (self.folder / 'final-data').mkdir()
        (self.folder / 'final-data/custom.img').write_bytes(FIXTURE['workspace_png']('fixture-amber'))
        (self.folder / 'final-data/animation.img').write_bytes(FIXTURE['emoji_gif']())
        (self.folder / 'actions.log').write_text('keys: ^f\nkeys: Verification Emoji\nkeys: Verification Other\nkeys: Verification Emoji')
        self.write('side-effects.json', dict(pending_sends=0, pending_archives=0, sync='stopped', production_preferences_absent=True,
                                           whatsapp_store_absent=True, telegram_store_absent=True))
        (self.folder / 'cleanup.txt').write_text('CLEANUP PASSED: fixture')

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value), encoding='utf-8')

    def test_complete_evidence(self):
        CHECK(self.folder)

    def test_baseline_shortcodes_unknown_changes_and_missing_custom_are_rejected(self):
        for index, field, value in [(0, 'text', ':broken_heart: :timer_clock::billed_cap: :crossed_fingers:'),
                                    (0, 'text', '💔 ⏲️🧢 🤞 👍🏻'), (0, 'reaction', ':crycat: 2  🥲 1  🍵 1'),
                                    (1, 'text', 'Custom :cat_alone: alias :fixture_cat:'), (2, 'gif_frames', 1), (2, 'local', False)]:
            with self.subTest(index=index, field=field):
                shown = copy.deepcopy(self.shown)
                shown['messages'][index][field] = value
                self.write('emoji.messages.json', shown)
                with self.assertRaises(AssertionError):
                    CHECK(self.folder)
        self.write('emoji.messages.json', self.shown)

    def test_forged_custom_pixels_are_rejected(self):
        width, height, image = PIXELS['read_png'](self.folder / 'emoji.png')
        self.assertEqual((width, height), (400, 300))
        for y in range(100, 150):
            for x in range(20, 300):
                image[y][x] = (0, 0, 0)
        PIXELS['write_png'](self.folder / 'emoji.png', image)
        with self.assertRaises(AssertionError):
            CHECK(self.folder)

    def test_static_gif_even_with_forged_metrics_is_rejected(self):
        (self.folder / 'frame-b.png').write_bytes((self.folder / 'frame-a.png').read_bytes())
        self.proof['frames'][1].update(amber=96 * 48, cobalt=0)
        self.write('emoji-pixels.json', self.proof)
        with self.assertRaises(AssertionError):
            CHECK(self.folder)

    def test_missing_cache_or_wrong_account_is_rejected(self):
        path = self.folder / 'bridge-requests.jsonl'
        original = path.read_text()
        path.write_text(original.replace('fixture-emoji&name', 'fixture-other&name'))
        with self.assertRaises(AssertionError):
            CHECK(self.folder)
        path.write_text(original)
        (self.folder / 'final-data/animation.img').unlink()
        with self.assertRaises(AssertionError):
            CHECK(self.folder)

    def test_journey_loads_click_helper_like_existing_slack_journeys(self):
        journey = (TOOLS / 'slack-emoji.ps1').read_text()
        for name in ['slack-emoji', 'link-previews', 'reactions']:
            self.assertTrue((TOOLS / (name + '.ps1')).read_text().startswith('. "$PSScriptRoot/menus.ps1"\n'))
        self.assertIn('function Click-Control(', (TOOLS / 'menus.ps1').read_text())
        for description in ['Slack emoji history', 'other chat opened', 'emoji chat reopened']:
            self.assertIn("} '" + description + "'\n    Click-Control $Session '1032'", journey)
        self.assertIn("$shown.chat.id -eq 'slack:fixture-emoji:channel' -and $shown.chat.provider -eq 'slack'", journey)
        self.assertIn("$shown.chat.id -eq 'slack:fixture-emoji:other' -and $shown.chat.provider -eq 'slack'", journey)

    def test_journey_registration(self):
        workflow = (ROOT / '.github/workflows/verify.yml').read_text()
        runner = (TOOLS / 'run.ps1').read_text()
        registry = json.loads((TOOLS / 'journeys.json').read_text())
        entry, = [row for row in registry['journeys'] if row['name'] == 'slack-emoji']
        self.assertTrue(entry['pr'] and entry['evidence'] and entry['maximize'])
        self.assertEqual((entry['hub'], entry['chats']), ('slack-emoji', 2))
        self.assertEqual(entry['hub_handler'], dict(file='fake-hub.py', **{'class': 'SlackEmojiHandler'}))
        self.assertEqual(entry['validator'], dict(file='check-slack-emoji-evidence.py', function='check_slack_emoji'))
        self.assertIn('src/slack_emoji.*', workflow)
        self.assertIn('fromJSON(needs.plan.outputs.matrix)', workflow)
        self.assertIn('if: matrix.evidence', workflow)
        self.assertIn('-Mode $journey.hub', runner)
        self.assertIn('. (Join-Path $PSScriptRoot $journey.script)', runner)
        script = (TOOLS / entry['script']).read_text()
        self.assertIn('. "$PSScriptRoot/slack-emoji.ps1"', script)
        self.assertIn('Invoke-SlackEmojiJourney $session', script)
        parser, journeys = FIXTURE['journey_parser']()
        args = parser.parse_args(['--slack-emoji', '--port-file', 'port', '--log', 'log'])
        self.assertEqual(journeys[args.mode], entry)
        self.assertIn("journey['validator']", (TOOLS / 'check-evidence.py').read_text())
        self.assertTrue((ROOT / '.claude/skills/verify-wazig/features/slack-emoji.md').is_file())


if __name__ == '__main__':
    unittest.main()

import hashlib
import json
from pathlib import Path
import re
import runpy
from urllib.parse import parse_qs, unquote, urlsplit


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))


STANDARD = '💔 ⏲️🧢 🤞 👍🏻 :unknown_fixture:'


def check_slack_emoji(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit'] and session['pid']
    assert session['feature'] == 'slack-emoji'
    assert read('result.json') == dict(feature='slack-emoji', status='passed')
    assert not (folder / 'failure.txt').exists()
    shown = read('emoji.messages.json')
    assert shown['chat']['provider'] == 'slack'
    rows = {row['id']: row for row in shown['messages']}
    assert set(rows) == {'EMOJI-STANDARD', 'EMOJI-CUSTOM', 'GIPHY'}
    assert rows['EMOJI-STANDARD']['text'] == STANDARD
    assert rows['EMOJI-STANDARD']['reaction'].endswith(' 2  🥲 1  🍵 1')
    assert re.fullmatch('[\ue000-\uf8ff] 2  🥲 1  🍵 1', rows['EMOJI-STANDARD']['reaction'])
    assert re.fullmatch('Custom [\ue000-\uf8ff] alias [\ue000-\uf8ff] 🍵 :cycle_a:', rows['EMOJI-CUSTOM']['text'])
    gif = rows['GIPHY']
    assert gif['local'] and gif['media_type'] == 'image' and gif['gif_frames'] == 2
    read_png = runpy.run_path(str(Path(__file__).with_name('check-workspace-icons.py')))['read_png']
    proof = read('emoji-pixels.json')
    crops = []
    for key, row, target in [('custom', proof['custom'], rows['EMOJI-CUSTOM']['bubble']),
                             ('reaction', proof['reaction'], rows['EMOJI-STANDARD']['reaction_chip'])] + [
                             ('frame', frame, gif['media']) for frame in proof['frames']]:
        assert row['rect'] == target
        assert row['screenshot'] in (['emoji.png'] if key != 'frame' else ['frame-a.png', 'frame-b.png'])
        width, height, image = read_png(folder / row['screenshot'])
        left, top, right, bottom = target
        cx, cy = row['canvas']
        assert 0 <= left + cx < right + cx <= width and 0 <= top + cy < bottom + cy <= height
        pixels = [image[y + cy][x + cx] for y in range(top, bottom) for x in range(left, right)]
        amber = sum(r > 210 and 130 < g < 190 and b < 65 for r, g, b in pixels)
        cobalt = sum(b > 210 and r < 75 and 85 < g < 145 for r, g, b in pixels)
        assert row['amber'] == amber and row['cobalt'] == cobalt
        if key != 'frame':
            assert amber > 75, key
        else:
            assert max(amber, cobalt) > 500 and max(amber, cobalt) / len(pixels) > 0.7
            crops.append(pixels)
    assert len(proof['frames']) == 2 and [row['screenshot'] for row in proof['frames']] == ['frame-a.png', 'frame-b.png']
    assert len(crops[0]) == len(crops[1])
    assert sum(a != b for a, b in zip(*crops)) / len(crops[0]) > 0.7
    assert (proof['frames'][0]['amber'] > 500 and proof['frames'][1]['cobalt'] > 500) or (proof['frames'][1]['amber'] > 500 and proof['frames'][0]['cobalt'] > 500)
    for name in ['emoji', 'frame-a', 'frame-b', 'reopened']:
        title = (folder / (name + '.uia.txt')).read_text(encoding='utf-8-sig').splitlines()[0]
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), title)
        assert read(name + '.state.json')['selected']['provider'] == 'slack'
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    api = [row for row in requests if row['wire_path'].startswith('/v1/wazig/')]
    assert api and all(row['authorized'] for row in api if row.get('method') != 'SSE')
    for route, query in [('/v1/wazig/slack/emoji', dict(account=['fixture-emoji'])),
                         ('/v1/wazig/slack/emoji/media', dict(account=['fixture-emoji'], name=['cat_alone']))]:
        fetched = [row for row in api if urlsplit(row['wire_path']).path == route]
        assert len(fetched) == 1 and fetched[0]['status'] == 200
        assert parse_qs(urlsplit(fetched[0]['wire_path']).query) == query
    media = [row for row in api if unquote(urlsplit(row['wire_path']).path) == '/v1/wazig/media/slack:fixture-emoji:channel/GIPHY']
    assert len(media) == 1 and media[0]['status'] == 200
    assert not any('/fixture/animation.gif' in row['wire_path'] for row in requests)
    cache = read('emoji-cache.json')
    assert cache['before'] == cache['after'] == 3
    fixture = runpy.run_path(str(Path(__file__).with_name('fake-hub.py')))
    digests = {hashlib.sha256(path.read_bytes()).digest() for path in (folder / 'final-data').rglob('*') if path.is_file()}
    for data in [fixture['emoji_gif'](), fixture['workspace_png']('fixture-amber')]:
        assert hashlib.sha256(data).digest() in digests
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert actions.count('keys: Verification Emoji') == 2 and 'keys: Verification Other' in actions and 'keys: ^f' in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: Slack Unicode, custom message/reaction pixels, animated GIF frames and hub caches')

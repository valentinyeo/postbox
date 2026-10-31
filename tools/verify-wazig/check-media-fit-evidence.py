import json
import re
from pathlib import Path
import runpy
from urllib.parse import unquote


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))

read_png = runpy.run_path(str(Path(__file__).with_name('check-workspace-icons.py')))['read_png']


def check_media_fit(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'media-fit' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='media-fit', status='passed')
    assert not (folder / 'failure.txt').exists()
    fixture = read('media-fit-fixture.json')
    assert fixture['landscape'] == [1600, 1000] and fixture['portrait'] == [700, 1400]
    assert fixture['video'], 'captioned video fixture required'
    ids = ['fit-own', 'landscape', 'portrait', 'video']
    checks = read('media-fit-checks.json')
    assert [(row['size'], row['id']) for row in checks] == [(size, key) for size in ['wide', 'narrow'] for key in ids]
    def word_text(message, word):
        raw = message['text'].encode('utf-16-le')
        return raw[2 * word['start']:2 * (word['start'] + word['len'])].decode('utf-16-le')

    def formatted_caption(message, caption, bubble):
        assert message['text'] == caption and message['forwarded']
        words = message['words']
        assert words
        for word in words:
            left, top, right, bottom = word['rect']
            assert bubble[0] <= left < right <= bubble[2]
            assert bubble[1] <= top < bottom <= bubble[3]
        assert any(word['bold'] and 'Synthetic' in word_text(message, word) for word in words)
        assert any(word['italic'] and ('Second' in word_text(message, word) or 'formatted' in word_text(message, word)) for word in words)
        assert sum('•' in word_text(message, word) for word in words) == caption.count('•')
        assert any('ü' in word_text(message, word) for word in words)
        covered = [0] * (len(caption.encode('utf-16-le')) // 2)
        for word in words:
            for i in range(word['start'], word['start'] + word['len']):
                covered[i] += 1
        for i, unit in enumerate(caption):
            if not unit.isspace() and unit not in '*_':
                assert covered[i] == 1, 'caption character missing or rendered twice'

    def label_pixels(image, canvas, bubble, top, bottom):
        ox, oy, _, _ = canvas
        return [(x, y) for y in range(top, bottom)
                for x in range(bubble[0] + 1, bubble[2] - 1)
                if all(115 <= channel <= 160 for channel in image[oy + y][ox + x])]

    widths = {}
    for row in checks:
        key, size, dpi = row['id'], row['size'], row['dpi']
        px = lambda n: (n * dpi + 48) // 96
        name = f'{size}-{key}'
        shown = read(f'{name}.messages.json')
        assert shown['chat']['id'] == 'fixture-media@g.us' and shown['chat']['provider'] == 'whatsapp'
        message, = [m for m in shown['messages'] if m['id'] == key]
        b, m = row['bubble'], row['media']
        assert message['bubble'] == b and message['media'] == m
        assert b[2] > b[0] and b[3] > b[1] and row['result']['problems'] == []
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
        assert read(f'{name}.state.json')['selected']['id'] == shown['chat']['id']
        width, height, image = read_png(folder / row['screenshot'])
        ox, oy, cw, ch = row['canvas']
        assert 0 <= ox < ox + cw <= width and 0 <= oy < oy + ch <= height
        assert b[1] >= 0 and b[3] <= ch
        if key == 'fit-own':
            widths[size] = b[2] - b[0]
            assert message['from_me'] and set(message['text']) == {'M', ' '}
            ink = lambda x, y: min(image[oy + y][ox + x]) > 110
            text = [(x, y) for y in range(b[1] + px(6), b[3] - px(5))
                    for x in range(b[0] + px(12), b[2] - px(12)) if ink(x, y)]
            t = message['time_header']
            time = [(x, y) for y in range(max(0, t[1]), min(ch, t[3]))
                    for x in range(max(0, t[0]), min(cw, t[2])) if ink(x, y)]
            assert text and time
            assert t[3] <= b[1], 'media-fit: time header overlaps bubble'
            assert max(x for x, y in text) >= b[2] - px(52), 'media-fit: text does not exercise former time box'
            assert max(y for x, y in text) == row['result']['textBottom']
            assert t[1] == row['result']['timeTop']
        else:
            assert message['local'] and not message['from_me']
            assert b[0] + px(12) <= m[0] < m[2] <= b[2] - px(12)
            assert b[1] <= m[1] < m[3] <= b[3]
            assert m[2] - m[0] <= b[2] - b[0] and m[3] - m[1] <= px(250)
            colour = {'landscape': (32, 176, 208), 'portrait': (176, 64, 208)}.get(key)
            pixels = [(x, y) for y in range(ch) for x in range(cw)
                      if (max(abs(a - c) for a, c in zip(image[oy + y][ox + x], colour)) <= 8 if colour else
                          image[oy + y][ox + x][0] > 230 and 120 < image[oy + y][ox + x][1] < 190 and image[oy + y][ox + x][2] < 25)]
            assert pixels and len(pixels) == row['result']['pixels']
            assert all(m[0] <= x < m[2] and m[1] <= y < m[3] and b[0] <= x < b[2] and b[1] <= y < b[3] for x, y in pixels)
            if key in ('landscape', 'video'):
                formatted_caption(message, '*Synthetic heading*\n• Grüner Punkt\n• _Second line_', b)
                label_top = m[3] + px(4)
                assert label_pixels(image, row['canvas'], b, label_top, label_top + px(10)), 'forwarding label ink missing'
                ink_rows = [y for y in range(m[3], b[3] - px(5))
                            if any(min(image[oy + y][ox + x]) > 110
                                   for x in range(b[0] + px(14), b[2] - px(14)))]
                assert ink_rows and max(ink_rows) - min(ink_rows) > px(25), 'caption and forwarding ink missing'
    for size in ('wide', 'narrow'):
        evidence = read(f'{size}-forwarded-short.json')
        message, dpi, canvas = evidence['message'], evidence['dpi'], evidence['canvas']
        bubble = message['bubble']
        px = lambda n: (n * dpi + 48) // 96
        assert message['text'] == 'Hi' and message['forwarded']
        assert bubble[2] - bubble[0] >= px(80), 'short forwarding label bubble too narrow'
        _, _, image = read_png(folder / f'{size}-forwarded-short.png')
        body_top = min(word['rect'][1] for word in message['words'])
        pixels = label_pixels(image, canvas, bubble, bubble[1] + px(10), body_top - px(4))
        assert pixels and max(x for x, _ in pixels) - min(x for x, _ in pixels) >= px(55), 'short forwarding label clipped or missing'

    document = read('wide-document.json')
    message, dpi, canvas = document['message'], document['dpi'], document['canvas']
    bubble = message['bubble']
    assert message['id'] == 'document' and message['local']
    assert 650 <= len(fixture['long_caption']) <= 800
    formatted_caption(message, fixture['long_caption'], bubble)
    width, height, image = read_png(folder / 'wide-document.png')
    ox, oy, cw, ch = canvas
    assert 0 <= ox < ox + cw <= width and 0 <= oy < oy + ch <= height
    assert 0 <= bubble[1] < bubble[3] <= ch
    px = lambda n: (n * dpi + 48) // 96
    body_top = min(word['rect'][1] for word in message['words'])
    assert label_pixels(image, canvas, bubble, message['media'][3] + px(8), body_top - px(4)), 'document forwarding label missing'

    live = read('caption-live.json')
    message, dpi, canvas = live['message'], live['dpi'], live['canvas']
    assert 0 <= live['elapsed_seconds'] < 10
    assert message['id'] == 'fit-live' and message['text'] == '*Live* caption • Grüße' and message['forwarded'] and message['local']
    bubble, media = message['bubble'], message['media']
    width, height, image = read_png(folder / 'caption-live.png')
    ox, oy, cw, ch = canvas
    assert 0 <= ox < ox + cw <= width and 0 <= oy < oy + ch <= height
    assert 0 <= bubble[1] < media[1] < media[3] < bubble[3] <= ch
    px = lambda n: (n * dpi + 48) // 96
    assert label_pixels(image, canvas, bubble, media[3] + px(4), media[3] + px(14)), 'live forwarding label missing'
    assert message['words'] and all(bubble[1] <= word['rect'][1] < word['rect'][3] <= bubble[3] for word in message['words'])
    assert any(min(image[oy + y][ox + x]) > 110
               for word in message['words'] for y in range(word['rect'][1], word['rect'][3])
               for x in range(word['rect'][0], word['rect'][2])), 'live caption ink missing'
    resize = read('media-fit-resize.json')
    assert resize['target'] == 320 and 300 <= resize['canvas'] <= 340
    assert all(row['canvas'][2] == resize['canvas'] for row in checks if row['size'] == 'narrow')
    assert len(resize['steps']) <= 8
    for index, step in enumerate(resize['steps']):
        assert step['requested_window'] == step['window_before'] + step['gain'] * (resize['target'] - step['canvas_before'])
        assert step['requested_window'] > 0 and step['canvas_after'] > 0
        if index:
            assert step['canvas_before'] == resize['steps'][index - 1]['canvas_after']
    if resize['steps']:
        assert resize['steps'][-1]['canvas_after'] == resize['canvas']
    assert resize['sidebar_limit'] == (300 * resize['dpi'] + 48) // 96
    assert all(step['gain'] == (2 if step['canvas_before'] < resize['sidebar_limit'] else 1) for step in resize['steps'])
    assert widths['wide'] > widths['narrow']
    wide, = [row for row in checks if row['size'] == 'wide' and row['id'] == 'landscape']
    narrow, = [row for row in checks if row['size'] == 'narrow' and row['id'] == 'landscape']
    padding = (24 * narrow['dpi'] + 48) // 96
    assert narrow['bubble'][2] - narrow['bubble'][0] - padding < wide['media'][2] - wide['media'][0], 'media-fit: narrow content must exercise downscaling'
    requests = read('media-fit.requests.json')
    for key in ids[1:] + ['document']:
        assert any(row.get('status') == 200 and row['method'] == 'GET' and unquote(row['wire_path']).endswith('/v1/wazig/media/fixture-media@g.us/' + key) for row in requests)
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'Verification Media' in actions and f"resize: media-fit canvas={resize['canvas']} target=320" in actions
    assert '{LEFT 4}' not in actions and '{LEFT 40}' not in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('MEDIA FIT EVIDENCE VERIFIED: wide/narrow media containment, screenshot pixels and separate timestamp line')

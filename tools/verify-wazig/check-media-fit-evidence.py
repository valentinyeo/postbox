import json
import re
from pathlib import Path
import runpy
from urllib.parse import unquote

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
    ids = ['fit-own', 'landscape', 'portrait'] + (['video'] if fixture['video'] else [])
    checks = read('media-fit-checks.json')
    assert [(row['size'], row['id']) for row in checks] == [(size, key) for size in ['wide', 'narrow'] for key in ids]
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
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
        assert read(f'{name}.state.json')['selected']['id'] == shown['chat']['id']
        width, height, image = read_png(folder / row['screenshot'])
        ox, oy, cw, ch = row['canvas']
        assert 0 <= ox < ox + cw <= width and 0 <= oy < oy + ch <= height
        assert b[1] >= 0 and b[3] <= ch
        if key == 'fit-own':
            widths[size] = b[2] - b[0]
            assert message['from_me'] and set(message['text']) == {'M', ' '}
            time_left = b[2] - px(52)
            ink = lambda x, y: min(image[oy + y][ox + x]) > 110
            text = [(x, y) for y in range(b[1] + px(6), b[3] - px(5))
                    for x in range(b[0] + px(12), time_left - px(4)) if ink(x, y)]
            text_bottom = max(y for x, y in text)
            text_rows = {y for x, y in text}
            text_top = text_bottom
            while text_top - 1 in text_rows:
                text_top -= 1
            time = [(x, y) for y in range(text_top, b[3] - px(5))
                    for x in range(time_left, b[2] - px(10)) if ink(x, y)]
            assert text and time
            text_bottom = max(y for x, y in text)
            time_rows = {y for x, y in time}
            time_top = max(time_rows)
            while time_top - 1 in time_rows:
                time_top -= 1
            assert text_bottom < time_top, 'media-fit: time overlaps text pixels'
            assert any(min(image[oy + y][ox + x]) > 230 for y in range(text_top, text_bottom + 1)
                       for x in range(time_left, b[2] - px(12))), 'media-fit: text does not exercise the time box'
            assert text_bottom == row['result']['textBottom'] and time_top == row['result']['timeTop']
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
    for key in ids[1:]:
        assert any(row.get('status') == 200 and row['method'] == 'GET' and unquote(row['wire_path']).endswith('/v1/wazig/media/fixture-media@g.us/' + key) for row in requests)
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'Verification Media' in actions and f"resize: media-fit canvas={resize['canvas']} target=320" in actions
    assert '{LEFT 4}' not in actions and '{LEFT 40}' not in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('MEDIA FIT EVIDENCE VERIFIED: wide/narrow media containment, screenshot pixels and separate timestamp line')

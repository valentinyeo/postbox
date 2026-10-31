import json
import re
import runpy
from pathlib import Path


png_rows = runpy.run_path(str(Path(__file__).with_name('check-inline-links-evidence.py')))['png_rows']


def check_emoji_picker_glyphs(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    measurements = []
    for stage in ('empty', 'heart-search', 'wink-grid', 'wink-hover', 'gap-grid', 'gap-before', 'gap-after'):
        picker = read(f'emoji-{stage}.status.json')['emoji_picker']
        screen = read(f'emoji-{stage}.screen.json')
        rows = list(png_rows(folder / f'emoji-{stage}.png'))
        width, height, channels, _ = rows[0]
        assert [width, height] == screen['size']
        ox, oy = screen['origin']
        for cell in picker['cells']:
            left, top, right, bottom = cell['rect']
            left -= ox
            right -= ox
            top -= oy
            bottom -= oy
            assert 0 <= left < right <= width and 0 <= top < bottom <= height
            em = picker['em']
            x0 = left + (right - left - em) // 2
            y0 = top + (bottom - top - em) // 2
            assert left < x0 < x0 + em < right and top < y0 < y0 + em < bottom
            def pixel(x, y):
                row = rows[y][3]
                return row[x * channels:x * channels + 3]
            background = pixel(left + 2, top + 2)
            foreground = []
            for y in range(y0, y0 + em):
                for x in range(x0, x0 + em):
                    colour = pixel(x, y)
                    if max(abs(int(colour[i]) - int(background[i])) for i in range(3)) >= 40:
                        foreground.append((x, y))
            record = {'stage': stage, 'match': cell['match'], 'index': cell['index'], 'rect': cell['rect'],
                      'region': [x0, y0, x0 + em, y0 + em], 'background': list(background),
                      'foreground_pixels': len(foreground), 'background_pixels': em * em - len(foreground),
                      'foreground_width': max((x for x, _ in foreground), default=0) - min((x for x, _ in foreground), default=0) + bool(foreground),
                      'foreground_height': max((y for _, y in foreground), default=0) - min((y for _, y in foreground), default=0) + bool(foreground)}
            measurements.append(record)
        (folder / 'emoji-pixels.json').write_text(json.dumps(measurements, indent=2), encoding='utf-8')
    assert all(row['foreground_pixels'] >= 5 and row['background_pixels'] >= 5 and row['foreground_width'] >= 2 and row['foreground_height'] >= 2 for row in measurements), 'Visible emoji has no meaningful foreground pixels'

    session = read('session.json')
    environment = read('emoji-environment.json')
    empty = read('emoji-empty.status.json')['emoji_picker']
    cells = empty['cells']
    assert session['feature'] == 'emoji-picker-glyphs'
    assert environment['commit'] == session['commit'] and environment['sha256'] == session['sha256']
    assert environment['os'] and environment['dpi'] > 0
    assert environment['font_file'].lower() == 'seguiemj.ttf'
    assert re.fullmatch(r'[0-9a-fA-F]{64}', environment['font_sha256'])
    assert 'font_version' in environment and (environment['font_version'] is None or
                                               isinstance(environment['font_version'], str) and bool(environment['font_version'].strip()))
    assert len(cells) == 48 and [cell['match'] for cell in cells] == list(range(48))
    assert sum(row['stage'] == 'empty' for row in measurements) == 48
    assert all(cell['coverage'] != 'missing' and cell['text'] and cell['name'] for cell in cells)
    left, top, right, bottom = empty['bounds']
    for cell in cells:
        x1, y1, x2, y2 = cell['rect']
        assert left <= x1 < x2 <= right and top <= y1 < y2 <= bottom
    seed = empty['seed']
    assert seed is not None and empty['recents'][0] == seed
    missing = [row for row in empty['journal'] if row['index'] == seed and row['coverage'] == 'missing' and row['missing']]
    assert missing and all(cell['index'] != seed for cell in cells)
    target = next(row for row in empty['journal'] if row['index'] == 11)
    assert target['text'] == '\U0001faeb'
    if target['coverage'] == 'missing':
        assert all(cell['index'] != 11 for cell in cells)
    order = [cell['index'] for cell in cells[8:]]
    assert order == sorted(order)
    for row in empty['journal']:
        if 9 <= row['index'] <= 13 and row['coverage'] == 'supported':
            assert row['index'] in order
    search = read('emoji-missing-search.status.json')['emoji_picker']
    assert all(cell['index'] != seed for cell in search['cells'])
    if seed == 11:
        assert search['match_count'] == 0
        assert read('emoji-missing-enter.status.json')['emoji_picker']['match_count'] == 0
    assert read('emoji-unmatched.status.json')['emoji_picker']['match_count'] == 0
    assert read('emoji-unmatched-enter.status.json')['emoji_picker']['match_count'] == 0
    heart = '\u2764\ufe0f'
    wink = '\U0001f609'
    heart_cells = read('emoji-heart-search.status.json')['emoji_picker']['cells']
    wink_cells = read('emoji-wink-grid.status.json')['emoji_picker']['cells']
    assert any(cell['text'] == heart and cell['coverage'] == 'supported' for cell in heart_cells)
    wink_cell = next(cell for cell in wink_cells if cell['match'] >= 8 and cell['text'] == wink)
    assert wink_cell['coverage'] == 'supported'
    hover = read('emoji-wink-hover.json')
    click = read('emoji-wink-click.json')
    assert hover['cell'] == click['cell'] == wink_cell and hover['point'] == click['point']
    x, y = hover['point']
    left, top, right, bottom = wink_cell['rect']
    assert left <= x < right and top <= y < bottom
    assert abs(hover['cursor'][2] - x) <= 1 and abs(hover['cursor'][3] - y) <= 1
    assert read('emoji-heart-insert.json')['text'] == heart
    assert read('emoji-wink-insert.json')['text'] == heart + wink
    before = read('emoji-gap-before.status.json')['emoji_picker']
    after = read('emoji-gap-after.status.json')['emoji_picker']
    assert after['selected_match'] == before['selected_match'] + 1
    assert after['selected_index'] == wink_cell['index']
    assert before['selected_index'] < after['selected_index']
    if target['coverage'] == 'missing':
        assert before['selected_index'] < 11 < after['selected_index']
    gap = read('emoji-gap-insert.json')
    assert gap['before'] == before['selected_index'] and gap['after'] == after['selected_index']
    assert gap['text'] == heart + wink + wink
    recent = read('emoji-recent.status.json')['emoji_picker']
    assert [cell['text'] for cell in recent['cells'][:2]] == [wink, heart]
    assert seed in recent['recents'] and all(cell['index'] != seed for cell in recent['cells'])
    reaction = read('emoji-reaction-cancel.status.json')
    assert reaction['emoji_picker']['react'] and reaction['pending_reaction_count'] == 0
    assert read('emoji-reaction-closed.status.json')['pending_reaction_count'] == 0
    final = read('emoji-final.json')
    assert final['draft'] == heart + wink + wink and final['status']['emoji_picker'] is None
    assert final['status']['pending_reaction_count'] == 0
    assert not [row for row in final['requests'] if row['method'] in ('POST', 'PUT', 'PATCH', 'DELETE')]
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines() if line.strip()]
    assert requests and all(row['method'] in ('GET', 'HEAD', 'OPTIONS', 'SSE') for row in requests)
    assert (folder / 'cleanup.txt').read_text(encoding='utf-8-sig').strip().startswith('CLEANUP PASSED:')
    side_effects = read('side-effects.json')
    assert side_effects['pending_reaction_count'] == side_effects['pending_sends'] == side_effects['pending_archives'] == 0
    assert side_effects['production_preferences_absent'] and side_effects['whatsapp_store_absent'] and side_effects['telegram_store_absent']
    assert read('result.json') == {'feature': 'emoji-picker-glyphs', 'status': 'passed'}

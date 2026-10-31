import json


def check_emoji_picker_glyphs(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    environment = read('emoji-environment.json')
    empty = read('emoji-empty.status.json')['emoji_picker']
    cells = empty['cells']
    assert session['feature'] == 'emoji-picker-glyphs'
    assert environment['commit'] == session['commit'] and environment['sha256'] == session['sha256']
    assert environment['os'] and environment['font_version'] and environment['font_sha256'] and environment['dpi']
    assert len(cells) == 48 and [cell['match'] for cell in cells] == list(range(48))
    assert all(cell['coverage'] != 'missing' and cell['text'] and cell['name'] for cell in cells)
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
    left, top, right, bottom = empty['bounds']
    for cell in cells:
        x1, y1, x2, y2 = cell['rect']
        assert left <= x1 < x2 <= right and top <= y1 < y2 <= bottom
    search = read('emoji-missing-search.status.json')['emoji_picker']
    assert all(cell['index'] != seed for cell in search['cells'])
    if seed == 11:
        assert search['match_count'] == 0
    heart = '\u2764\ufe0f'
    wink = '\U0001f609'
    heart_cells = read('emoji-heart-search.status.json')['emoji_picker']['cells']
    wink_cells = read('emoji-wink-search.status.json')['emoji_picker']['cells']
    assert any(cell['text'] == heart and cell['coverage'] == 'supported' for cell in heart_cells)
    assert wink_cells[0]['text'] == wink and wink_cells[0]['coverage'] == 'supported'
    assert read('emoji-heart-insert.json')['text'] == heart
    assert read('emoji-wink-insert.json')['text'] == heart + wink
    recent = read('emoji-recent.status.json')['emoji_picker']
    assert [cell['text'] for cell in recent['cells'][:2]] == [wink, heart]
    assert seed in recent['recents'] and all(cell['index'] != seed for cell in recent['cells'])
    assert read('emoji-reaction-cancel.status.json')['emoji_picker']['react']
    final = read('emoji-final.json')
    assert final['draft'] == heart + wink and final['status']['emoji_picker'] is None
    assert not [row for row in final['requests'] if row['method'] in ('POST', 'PUT', 'PATCH', 'DELETE')]
    for stage in ('empty', 'missing-search', 'heart-search', 'wink-search', 'recent', 'reaction-cancel'):
        assert (folder / f'emoji-{stage}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert read('result.json') == {'feature': 'emoji-picker-glyphs', 'status': 'passed'}

import json


def check_emoji_picker_glyphs(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    owner = read('emoji-empty.owner.json')
    state = read('emoji-empty.status.json')
    requests = read('emoji-empty.requests.json')
    assert session['feature'] == 'emoji-picker-glyphs'
    assert session['sha256'] and session['commit']
    assert owner['session'] == session['id'] and owner['app_pid'] == session['pid']
    assert owner['popup'] and owner['query'] == ''
    cells = state['emoji_picker']['cells']
    assert len(cells) == 48
    assert [cell['match'] for cell in cells] == list(range(48))
    assert cells[19]['index'] == 11 and cells[19]['text'] == '\U0001faeb'
    assert any(cell['text'] == '\U0001f44d' and cell['available'] for cell in cells)
    assert all(cell['available'] and cell['text'] and cell['name'] for cell in cells)
    left, top, right, bottom = state['emoji_picker']['bounds']
    for cell in cells:
        x1, y1, x2, y2 = cell['rect']
        assert left <= x1 < x2 <= right and top <= y1 < y2 <= bottom
    assert not [row for row in requests if row['method'] in ('POST', 'PUT', 'PATCH', 'DELETE') and row['wire_path'] != '/v1/wazig/mark-read']
    assert (folder / 'emoji-empty.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert read('result.json') == {'feature': 'emoji-picker-glyphs', 'status': 'passed'}

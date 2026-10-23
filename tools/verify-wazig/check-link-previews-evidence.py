import hashlib
import json
from pathlib import Path
import runpy


def check_link_previews(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='link-previews', status='passed')
    assert not (folder / 'failure.txt').exists()
    for provider in ['slack', 'whatsapp', 'telegram', 'signal']:
        shown = read(f'{provider}.messages.json')
        assert shown['chat']['provider'] == provider
        rows = {row['id']: row for row in shown['messages']}
        assert set(rows) == {'LINK-IMAGE', 'LINK-PAGE', 'LINK-QUERY', 'LINK-PLAIN'}
        for row in rows.values():
            assert all(marker not in row['text'] for marker in ['<', '|>', '&amp;'])
            assert row['links'] and all('&amp;' not in link for link in row['links'])
        image, page, query, plain = [rows['LINK-' + kind] for kind in ['IMAGE', 'PAGE', 'QUERY', 'PLAIN']]
        assert image['local'] and image['media_type'] == 'image' and image['media'][2] > image['media'][0]
        assert page['preview']['ready'] and page['preview']['image']
        assert page['preview']['title'] == 'Synthetic preview' and page['preview']['site'] == '127.0.0.1'
        assert page['preview']['description'] == 'Synthetic description'
        assert page['card'][2] > page['card'][0]
        assert '?a=1&b=2' in query['links'][0]
        assert not plain['preview']['image'] and plain['card'] == [0, 0, 0, 0]
        if provider == 'slack':
            assert plain['text'] == 'Clean page label' and page['text'] == 'Synthetic page label'
            assert query['quote'] == 'Quoted & label'
        image_bytes = (folder / f'{provider}.png').read_bytes()
        assert image_bytes.startswith(b'\x89PNG\r\n\x1a\n') and len(image_bytes) > 10000
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{provider}.uia.txt').read_text(encoding='utf-8-sig')
        assert read(f'{provider}.state.json')['selected']['provider'] == provider
    read_png = runpy.run_path(str(Path(__file__).with_name('check-workspace-icons.py')))['read_png']
    screenshots = {provider + '.png': read_png(folder / (provider + '.png')) for provider in ['slack', 'whatsapp', 'telegram', 'signal']}
    pixels = read('image-pixels.json')
    assert len(pixels) == 8
    assert {(row['screenshot'], row['colour']) for row in pixels} == {(name + '.png', colour) for name in ['slack', 'whatsapp', 'telegram', 'signal'] for colour in ['amber', 'cobalt']}
    for row in pixels:
        assert row['colour'] in ['amber', 'cobalt'] and row['samples'] > 0 and row['hits'] / row['samples'] > 0.1
        width, height, image = screenshots[row['screenshot']]
        rows = {message['id']: message for message in read(row['screenshot'].replace('.png', '.messages.json'))['messages']}
        target = rows['LINK-IMAGE']['media'] if row['colour'] == 'amber' else rows['LINK-PAGE']['card']
        assert row['rect'] == target
        left, top, right, bottom = target
        cx, cy = row['canvas']
        assert 0 <= left + cx < right + cx <= width and 0 <= top + cy < bottom + cy <= height
        hits = samples = 0
        for y in range(top + 8, bottom - 8, 3):
            for x in range(left + 8, right - 8, 3):
                red, green, blue = image[y + cy][x + cx]
                match = red > 210 and 130 < green < 190 and blue < 65 if row['colour'] == 'amber' else blue > 210 and red < 75 and 85 < green < 145
                hits += bool(match)
                samples += 1
        assert hits == row['hits'] and samples == row['samples'] and hits / samples > 0.1
    viewer = read('viewer.json')
    assert viewer['handle'] and viewer['class'] == 'MessagesImageViewer' and viewer['pid'] == session['pid']
    assert (folder / 'viewer.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    cache = read('cache-requests.json')
    assert cache['before'] == cache['after'] and cache['before'] > 0
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    for path in ['/pic.png', '/card.png', '/page', '/plain', '/query?a=1&b=2']:
        fetched = [row for row in requests if row['wire_path'] == path]
        assert fetched and all(row['status'] == 200 for row in fetched), path
        assert len(fetched) == 1, (path, 'URL cache did not suppress repeated fetches across providers')
    assert not any(row['wire_path'] == '/missing.png' for row in requests)
    assert all(row['authorized'] for row in requests if row.get('method') != 'SSE' and row['wire_path'].startswith('/v1/wazig/'))
    files = list((folder / 'final-data').rglob('*'))
    digests = {hashlib.sha256(path.read_bytes()).hexdigest() for path in files if path.is_file()}
    fixture = runpy.run_path(str(Path(__file__).with_name('fake-hub.py')))
    for team in ['fixture-amber', 'fixture-cobalt']:
        assert hashlib.sha256(fixture['workspace_png'](team)).hexdigest() in digests
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'SendInput: inline image' in actions and 'keys: {ESC}' in actions
    for provider in ['slack', 'whatsapp', 'telegram', 'signal']:
        assert 'keys: Verification Links ' + provider in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: clean Slack labels, inline image and viewer, Open Graph cards, four providers and URL caches')

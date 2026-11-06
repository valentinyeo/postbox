import hashlib
import json
import re
import struct
from pathlib import Path


def check_gif_picker(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'gif-picker' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='gif-picker', status='passed')
    assert not (folder / 'failure.txt').exists()
    summary = read('gif-picker.json')
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    giphy = [row for row in requests if row.get('kind') == 'giphy']
    hub = [row for row in requests if row.get('kind') != 'giphy']
    assert re.fullmatch(r'[0-9a-f]{64}', summary['key_sha256']) and summary['key_kind'] == 'Binary'
    assert summary['key_plain_in_registry'] is False
    api = [row for row in giphy if row['path'].startswith('/v1/gifs/')]
    media = [row for row in giphy if row['path'].startswith('/media/')]
    assert api and media and len(api) + len(media) == len(giphy)
    assert all(row['key_sha256'] == summary['key_sha256'] for row in api)
    assert all(row['key_sha256'] == '' for row in media)
    assert not any('api_key' in row['path'] or 'api_key' in row['wire_path'] for row in giphy)
    assert all(row['authorized'] for row in hub if row.get('method') != 'SSE' and row.get('wire_path', '').startswith('/v1/wazig/'))

    def calls(path, **match):
        return [row for row in giphy if row['path'].split('?')[0] == path and all(row.get(key) == value for key, value in match.items())]

    trending = calls('/v1/gifs/trending')
    assert trending and all(row['status'] == 200 and row['count'] == 3 for row in trending)
    boom = [row for row in calls('/v1/gifs/search') if row.get('query') == 'boom']
    assert [row['status'] for row in boom][:2] == [500, 200] and boom[1]['count'] == 2
    cats = [row for row in calls('/v1/gifs/search') if row.get('query') == 'cats']
    assert cats and cats[-1]['status'] == 200 and cats[-1]['count'] == 2
    previews = [row for row in giphy if row.get('rendition') == '200']
    assert {row['id'] for row in previews} >= {'catwave1', 'catwave2', 'catwave3'} and all(row['status'] == 200 for row in previews)
    originals = [row for row in giphy if row.get('rendition') == 'giphy']
    assert {row['id'] for row in originals} == {'catwave3'}
    assert [row['status'] for row in originals] == [500, 200]

    sends = [row for row in hub if row.get('path') == '/v1/wazig/send']
    assert len(sends) == 1
    send = sends[0]
    assert send['accepted'] and send['status'] == 200 and send['multipart']
    assert send['body']['chat'] == 'paste:whatsapp' and send['body']['text'] == 'gif draft'
    assert send['body']['reply_to'] == 'GIF-ORIGINAL' and send['body']['file'].endswith('.gif')
    assert send['body']['client_id'].isalnum() and send['body']['client_id'] == summary['client_id']
    assert send['upload'] == summary['upload'] == 'paste-uploads/' + send['body']['client_id'] + '.gif'
    raw = (folder / send['upload']).read_bytes()
    assert raw.startswith(b'GIF89a') and struct.unpack('<HH', raw[6:10]) == (64, 48)
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == summary['upload_sha256'] == send['file_sha256'] == originals[-1]['file_sha256']
    assert summary['picked'] == 'catwave3' and summary['dimensions'] == [64, 48]
    assert summary['pixels'] == [32, 180, 220, 250, 250, 250]
    assert (summary['trending_count'], summary['boom_count'], summary['cats_count']) == (3, 2, 2)

    sent = read('sent.messages.json')
    assert sent['chat']['id'] == 'paste:whatsapp'
    row, = [item for item in sent['messages'] if item['id'] == send['message_id']]
    assert row['from_me'] and row['media_type'] == 'image' and row['quoted_msg_id'] == 'GIF-ORIGINAL'

    for name in ('no-key', 'trending', 'escaped', 'search-failed', 'cats', 'download-failed', 'staged', 'sent', 'after'):
        assert (folder / f'{name}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), name
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + re.escape(session['expected_version']),
                            (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]), name
    assert read('no-key.state.json')['gif_picker'] is None
    assert read('no-key.state.json')['update_card']['error'] == 'GIF search needs a GIPHY key'
    trending_state = read('trending.state.json')
    assert trending_state['gif_picker']['status'] == 'ready' and trending_state['reply']['id'] == 'GIF-ORIGINAL'
    escaped = read('escaped.state.json')
    assert escaped['gif_picker'] is None and escaped['staged_attachment_count'] == 0 and escaped['reply']['id'] == 'GIF-ORIGINAL'
    assert read('search-failed.state.json')['update_card']['error'] == 'GIF search failed. Press Enter to retry'
    assert read('download-failed.state.json')['update_card']['error'] == 'GIF download failed. Press Enter to retry'
    staged = read('staged.state.json')
    assert staged['staged_attachment_count'] == 1 and staged['gif_picker'] is None and staged['reply']['id'] == 'GIF-ORIGINAL'
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    for gate in ('no-key-notice', 'trending', 'escape-keeps-draft', 'search-retry', 'staged', 'sent-with-reply', 'chat-isolated', 'key-protected'):
        assert f'gif-picker {gate} PASS' in proof, gate

    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: gif-picker' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    print('GIF PICKER EVIDENCE VERIFIED: key storage, search retry, staged original, reply, one send and no key in evidence')

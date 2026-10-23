import json
from pathlib import Path


def check_telegram(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def capture(name):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig'), name
        state = read(f'{name}.state.json')
        assert state['view'] == 'telegram', name
        assert state['current_view'] == dict(provider='telegram', account='telegram', label='Telegram', inbox=False)
        return state

    session = read('session.json')
    assert session['feature'] == 'telegram' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='telegram', status='passed')
    assert not (folder / 'failure.txt').exists()
    linked = capture('linked')
    assert read('marks.json')['brand_blue_pixels'] > 20
    assert linked['chat_count'] == 5
    assert {(row['provider'], row['view_account']) for row in read('linked.chats.json')['chats']} == {('telegram', 'telegram')}
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
    assert all(row['path'].startswith('/v1/wazig/') or row['path'] == '/fixture/live' for row in requests)
    palette = read('palette.json')
    assert 'Show Telegram' in palette
    assert not any(label in palette for label in ['Connect Telegram account', 'Log out of Telegram', 'Remove Telegram account...'])
    rows = read('linked.chats.json')['chats']
    assert {row['id'] for row in rows} == {'telegram:user:1001', 'telegram:user:1002', 'telegram:user:9001', 'telegram:chat:2001', 'telegram:channel:3001'}
    assert [row['id'] for row in rows if row['saved']] == ['telegram:user:9001']
    history = read('history.messages.json')
    assert history['chat']['id'] == 'telegram:user:1001'
    assert any(row['id'] == '1000' and row['text'] == 'Synthetic Telegram history' for row in history['messages'])
    reads = [row for row in requests if row['path'] == '/v1/wazig/mark-read']
    assert any(row['body']['chat'] == 'telegram:user:1001' and row['body']['message_id'] in ('1000', '1001') and row['status'] == 200 for row in reads)
    assert not next(row for row in read('read.chats.json')['chats'] if row['id'] == 'telegram:user:1001')['unread']
    assert any(row['path'].startswith('/v1/wazig/media/') and row['status'] == 200 for row in requests)
    reactions = [row for row in requests if row['path'] == '/v1/wazig/react']
    assert len(reactions) == 1
    assert reactions[0]['status'] == 200 and reactions[0]['body']['chat'] == 'telegram:user:1001'
    assert reactions[0]['body']['msg'] == '1001' and reactions[0]['body']['emoji'] == '\U0001f44d'
    assert set(reactions[0]['body']) == {'chat', 'msg', 'emoji', 'client_id'}
    assert any(row['id'] == '1001' and row['reaction'] == '\U0001f44d' for row in read('reacted.messages.json')['messages'])
    sends = [row for row in requests if row['path'] == '/v1/wazig/send']
    accepted = [row for row in sends if row['status'] == 200]
    assert len(accepted) == 3 and all(row['accepted'] and row['body']['chat'] == 'telegram:user:1001' for row in accepted)
    text = next(row for row in accepted if row['body']['text'] == 'Synthetic Telegram outgoing')
    assert text['body']['text'] == 'Synthetic Telegram outgoing'
    assert set(text['body']) == {'chat', 'text', 'reply_to', 'client_id'}
    reply = next(row for row in accepted if row['body']['text'] == 'Synthetic Telegram reply')
    assert reply['body']['reply_to'] == '1001' and not reply['multipart']
    assert any(row['text'] == 'Synthetic Telegram reply' and row['from_me'] for row in read('reply.messages.json')['messages'])
    file = next(row for row in accepted if row['multipart'])
    assert file['body']['text'] == 'Synthetic Telegram file' and file['body']['file'].endswith('.png')
    assert file['file_sha256'] == read('file.json')['sha256'] and file['file_size'] == read('file.json')['size'] > 0
    assert any(row['text'] == 'Synthetic Telegram outgoing' and row['from_me'] for row in read('text.messages.json')['messages'])
    assert any(row['text'] == 'Synthetic Telegram file' and row['media_type'] == 'image' for row in read('file.messages.json')['messages'])
    assert any(row['method'] == 'SSE' and row['kind'] == 'message' and row['chat'] == 'telegram:user:1001' for row in requests)
    assert any(row['id'] == '1002' and row['text'] == 'Synthetic Telegram live' for row in read('live.messages.json')['messages'])
    for name, code, reason in [('limited', 429, 'telegram rate limited')]:
        rejected = [row for row in sends if row['body']['chat'] == 'telegram:user:1002']
        assert len(rejected) == 1 and rejected[0]['status'] == code, 'rejection was retried or missing'
        shown = read(f'{name}.messages.json')
        assert shown['chat']['id'] == 'telegram:user:1002'
        assert sum(row['send_state'] == 'failed' and reason in row['text'] for row in shown['messages']) == 1
        assert capture(name)['pending_sends'] == 0
    archives = [row for row in requests if row['path'] == '/v1/wazig/archive']
    assert len(archives) == 1 and archives[0]['status'] == 502 and archives[0]['body']['chat'] == 'telegram:user:1001'
    for name in ['history', 'read', 'reacted', 'reply', 'text', 'file', 'live', 'after']:
        capture(name)
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    for gate in ['linked-chats', 'history', 'mark-read', 'media', 'react', 'reply', 'send-text', 'send-file', 'live-events', 'limited', 'archive-unsupported']:
        assert f'telegram {gate} PASS' in proof, gate
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped' and not final['slack_connected']
    assert all(final[key] for key in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for keys in ['%1', 'Reply to selected message', 'Synthetic Telegram reply', '%k', 'Compose message', 'Attach photo or file', 'Synthetic Telegram outgoing', 'Synthetic Telegram file', 'Synthetic rejected send', 'Like', '{ENTER}']:
        assert f'keys: {keys}' in actions, keys
    assert 'JOURNEY PASSED: telegram' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('TELEGRAM EVIDENCE VERIFIED: prelinked hub, account view, history, writes, receipts, media, events and terminal rejections')

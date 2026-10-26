import re
import json
from pathlib import Path


def check_signal(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def capture(name):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]), name
        state = read(f'{name}.state.json')
        assert state['view'] == 'signal', name
        assert state['current_view'] == dict(provider='signal', account='signal', label='Signal', inbox=False)
        return state

    session = read('session.json')
    assert session['feature'] == 'signal' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='signal', status='passed')
    assert not (folder / 'failure.txt').exists()
    linked = capture('linked')
    assert read('marks.json')['brand_blue_pixels'] > 20
    assert linked['chat_count'] == 4
    assert {(row['provider'], row['view_account']) for row in read('linked.chats.json')['chats']} == {('signal', 'signal')}
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
    assert all(row['path'].startswith('/v1/wazig/') or row['path'] == '/fixture/live' for row in requests)
    history = read('history.messages.json')
    assert history['chat']['id'] == 'signal:fixture-contact'
    assert any(row['id'] == 'fixture-sender:1000' and row['text'] == 'Synthetic Signal history' for row in history['messages'])
    reads = [row for row in requests if row['path'] == '/v1/wazig/mark-read']
    assert any(row['body']['chat'] == 'signal:fixture-contact' and row['body']['message_id'] in ('fixture-sender:1000', 'fixture-sender:1001') and row['status'] == 200 for row in reads)
    assert not next(row for row in read('read.chats.json')['chats'] if row['id'] == 'signal:fixture-contact')['unread']
    assert any(row['path'].startswith('/v1/wazig/media/') and row['status'] == 200 for row in requests)
    reactions = [row for row in requests if row['path'] == '/v1/wazig/react']
    assert len(reactions) == 1
    assert reactions[0]['status'] == 200 and reactions[0]['body']['chat'] == 'signal:fixture-contact'
    assert reactions[0]['body']['msg'] == 'fixture-sender:1001' and reactions[0]['body']['emoji'] == '\U0001f44d'
    assert set(reactions[0]['body']) == {'chat', 'msg', 'emoji', 'client_id'}
    assert any(row['id'] == 'fixture-sender:1001' and row['reaction'] == '\U0001f44d' for row in read('reacted.messages.json')['messages'])
    sends = [row for row in requests if row['path'] == '/v1/wazig/send']
    accepted = [row for row in sends if row['status'] == 200]
    assert len(accepted) == 2 and all(row['accepted'] and row['body']['chat'] == 'signal:fixture-contact' for row in accepted)
    text = next(row for row in accepted if not row['multipart'])
    assert text['body']['text'] == 'Synthetic Signal outgoing'
    assert set(text['body']) == {'chat', 'text', 'reply_to', 'client_id'}
    file = next(row for row in accepted if row['multipart'])
    assert file['body']['text'] == 'Synthetic Signal file' and file['body']['file'].endswith('.png')
    assert file['file_sha256'] == read('file.json')['sha256'] and file['file_size'] == read('file.json')['size'] > 0
    assert any(row['text'] == 'Synthetic Signal outgoing' and row['from_me'] for row in read('text.messages.json')['messages'])
    assert any(row['text'] == 'Synthetic Signal file' and row['media_type'] == 'image' for row in read('file.messages.json')['messages'])
    assert any(row['method'] == 'SSE' and row['kind'] == 'msg' and row['chat'] == 'signal:fixture-contact' for row in requests)
    assert any(row['id'] == 'fixture-sender:1002' and row['text'] == 'Synthetic Signal live' for row in read('live.messages.json')['messages'])
    for name, code, reason in [('limited', 429, 'signal rate limited'), ('captcha', 403, 'signal captcha required')]:
        rejected = [row for row in sends if row['body']['chat'] == f'signal:fixture-{name}']
        assert len(rejected) == 1 and rejected[0]['status'] == code, 'rejection was retried or missing'
        shown = read(f'{name}.messages.json')
        assert shown['chat']['id'] == f'signal:fixture-{name}'
        assert sum(row['send_state'] == 'failed' and reason in row['text'] for row in shown['messages']) == 1
        assert capture(name)['pending_sends'] == 0
    archives = [row for row in requests if row['method'] == 'POST' and row['path'] == '/v1/wazig/archive' and row['body']['chat'] == 'signal:fixture-contact']
    assert not archives, 'Signal archive must stay local'
    for name, archived, count in [('archived-inbox', False, 3), ('archived', True, 1), ('unarchived-archive', True, 0), ('after', False, 4)]:
        state = capture(name)
        assert state['show_archived'] == archived and state['pending_archives'] == 0 and state['chat_count'] == count, name
        chats = read(f'{name}.chats.json')
        assert chats['total'] == len(chats['chats']) == count, name
        target = [row for row in chats['chats'] if row['id'] == 'signal:fixture-contact']
        if name in ('archived', 'after'):
            assert len(target) == 1 and target[0]['provider'] == 'signal' and target[0]['archived'] == archived, name
        else:
            assert not target, name
        if name == 'archived':
            assert state['selected']['id'] == 'signal:fixture-contact'
    for name in ['history', 'read', 'reacted', 'text', 'file', 'live', 'after']:
        capture(name)
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    for gate in ['linked-chats', 'history', 'mark-read', 'media', 'react', 'send-text', 'send-file', 'live-events', 'limited', 'captcha', 'local-archive-unarchive']:
        assert f'signal {gate} PASS' in proof, gate
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped' and not final['slack_connected']
    assert all(final[key] for key in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for keys in ['^3', '%k', 'Compose message', 'Attach photo or file', 'Synthetic Signal outgoing', 'Synthetic Signal file', 'Synthetic rejected send', 'Like', '^e', 'Show archived chats', 'Show inbox chats', '{ENTER}']:
        assert f'keys: {keys}' in actions, keys
    assert actions.count('keys: ^e\n') == 2
    assert 'JOURNEY PASSED: signal' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('SIGNAL EVIDENCE VERIFIED: prelinked hub, account view, history, writes, receipts, media, events, local archive/unarchive and terminal rejections')

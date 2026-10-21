from pathlib import Path
import hashlib
import json
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
if session['feature'] == 'whatsapp-hub':
    assert session['sha256'] and session['commit']
    assert not (folder / 'failure.txt').exists()
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    gates = ['chats', 'history', 'mark-read', 'live-sse-replay', 'send-client-id-dedupe', 'media-202-ready-cache', 'archive', 'auth-dpapi-backend']
    for gate in gates:
        assert f'whatsapp-hub {gate} PASS' in proof, gate
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
    sends = [row for row in requests if row['path'] == '/v1/send']
    assert len(sends) >= 2 and len({row['body']['client_id'] for row in sends}) == 1
    assert sum(row['accepted'] for row in sends) == 1
    assert any(row.get('duplicate') and row['status'] == 200 for row in sends)
    assert all(row['body']['account'] == 'personal' and row['body']['chat'] == '15550000001@s.whatsapp.net' for row in sends)
    for path in ['/v1/accounts', '/v1/chats?', '/v1/messages?', '/v1/mark-read', '/v1/archive']:
        assert any(row['path'].startswith(path) and row.get('status') == 200 for row in requests), path
    assert any(row['path'] == '/v1/archive' and row['body']['archived'] for row in requests)
    assert any(row['method'] == 'SSE' and row['kind'] == 'msg' for row in requests)
    for event_id in ['1', '2']:
        assert any(row['path'] == '/v1/events' and row.get('last_event_id') == event_id for row in requests)
    media = [row for row in requests if row['path'].startswith('/v1/media/')]
    assert any(row['status'] == 202 for row in media)
    ready = [row for row in media if row['status'] == 200]
    assert ready and any(row['status'] == 202 and row['path'] == ready[0]['path'] for row in media)
    cached = list((folder / 'final-data/hub-media').glob('*.bin'))
    assert any(hashlib.sha256(path.read_bytes()).hexdigest() == ready[0]['sha256'] for path in cached)
    history = json.loads((folder / 'history.messages.json').read_text(encoding='utf-8-sig'))
    live = json.loads((folder / 'live.messages.json').read_text(encoding='utf-8-sig'))
    assert any(row['id'] == 'BASELINE' for row in history['messages'])
    assert not any(row['id'] == 'LIVE' for row in history['messages'])
    assert any(row['id'] == 'LIVE' for row in live['messages'])
    images = []
    for name in ['before', 'history', 'live', 'sent', 'after']:
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig')
        images.append(hashlib.sha256(image).hexdigest())
    assert len(set(images)) >= 4
    before = json.loads((folder / 'before.state.json').read_text(encoding='utf-8-sig'))
    final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
    assert before['chat_count'] == 2 and final['chat_count'] == 1
    assert final['pending_sends'] == 0 and final['pending_archives'] == 0
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
    assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for keys in ['^{TAB}', '^+{TAB}', 'Compose message', 'Fixture outgoing', 'Archive selected chat', '{ENTER}']:
        assert f'keys: {keys}' in actions
    launch = (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8')
    assert launch.count('whatsapp backend:') == 1 and 'whatsapp backend: hub' in launch
    assert 'fixture-key-not-a-secret' not in launch and session['bridge_url'] not in launch
    assert 'JOURNEY PASSED: whatsapp-hub' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: whatsapp-hub chats, history, live replay, send dedupe, reads, archive, media cache and isolation')
    raise SystemExit(0)
assert session['feature'] == 'search'
assert session['sha256'] and session['commit']
for name in ['doctor.json', 'before.state.json', 'after.state.json', 'empty.state.json', 'side-effects.json']:
    data = json.loads((folder / name).read_text(encoding='utf-8-sig'))
    assert data['version'] == '0.0.526', name
    assert data['pending_sends'] == 0 and data['pending_archives'] == 0, name
    assert data['sync'] == 'stopped' and not data['slack_connected'], name
before = json.loads((folder / 'before.state.json').read_text(encoding='utf-8-sig'))
after = json.loads((folder / 'after.state.json').read_text(encoding='utf-8-sig'))
empty = json.loads((folder / 'empty.state.json').read_text(encoding='utf-8-sig'))
final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
assert before['chat_count'] == 2 and before['search'] == ''
assert after['chat_count'] == 1 and after['search'] == 'Beta'
assert after['selected']['name'] == 'Verification Beta'
assert empty['chat_count'] == 0 and empty['search'] == 'NoSuchFixture'
assert final['chat_count'] == 2 and final['search'] == ''
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
assert 'JOURNEY PASSED: search' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
assert not (folder / 'failure.txt').exists()
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
for keys in ['^f', 'Beta', '{ESC}', 'NoSuchFixture']:
    assert f'keys: {keys}' in actions
images = []
for name in ['before', 'after', 'empty']:
    image = (folder / f'{name}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig')
    images.append(hashlib.sha256(image).hexdigest())
assert len(set(images)) == 3
cached = json.loads((folder / 'final-data/chats-0000000000000526.json').read_text(encoding='utf-8-sig'))
assert sorted(row['name'] for row in cached['data']) == ['Verification Alpha', 'Verification Beta']
assert not (folder / 'final-data/telegram').exists()
print('EVIDENCE VERIFIED: search action, match, empty state, restoration, isolation, surviving screenshots and cleanup')

from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
unified = session['feature'] == 'hub'
assert session['sha256'] and session['commit']
assert not (folder / 'failure.txt').exists()
proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
gates = ['chats', 'chat-switch', 'history', 'mark-read', 'live-sse-replay', 'send-client-id-dedupe', 'media-202-ready-cache', 'archive', 'auth-dpapi-backend']
for gate in gates:
    assert f"{session['feature']} {gate} PASS" in proof, gate
requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
sends = [row for row in requests if row['path'] == '/v1/send']
if not unified:
    assert f"{session['feature']} foreign-outbox-startup PASS" in proof
    adopted = [row for row in sends if row['body']['client_id'] == '53200000000000000000000000000001']
    assert len(adopted) == 1 and adopted[0]['status'] == 200 and adopted[0]['accepted']
    assert adopted[0]['body']['account'] == 'personal'
    assert adopted[0]['body']['chat'] == '15550000001@s.whatsapp.net'
    assert adopted[0]['body']['reply_to'] == 'BASELINE'
    assert not (folder / 'final-data/hub-1111111111111111-outbox.jsonl').read_bytes()
    sends = [row for row in sends if row not in adopted]
assert len(sends) >= 2 and len({row['body']['client_id'] for row in sends}) == 1
assert sum(row['accepted'] for row in sends) == 1
assert any(row.get('duplicate') and row['status'] == 200 for row in sends)
if unified:
    assert all('account' not in row['body'] and row['body']['chat'] == 'fixture-alpha' for row in sends)
else:
    assert all(row['body']['account'] == 'personal' and row['body']['chat'] == '15550000001@s.whatsapp.net' for row in sends)
paths = ['/v1/chats?', '/v1/messages?', '/v1/mark-read']
if not unified:
    paths.extend(['/v1/accounts', '/v1/archive'])
for path in paths:
    assert any(row['path'].startswith(path) and row.get('status') == 200 for row in requests), path
if unified:
    assert not any(row['path'] == '/v1/archive' for row in requests)
else:
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
before_beta = json.loads((folder / 'before-beta.requests.json').read_text(encoding='utf-8-sig'))
assert not any('history_request' in row for row in before_beta)
delayed = [row for row in requests if row.get('history_request') == 1 and row['status'] == 200]
assert len(delayed) == 1 and delayed[0]['history_delay_ms'] >= 3000
assert any(row.get('history_request') == 1 and row.get('history_phase') == 'requested' for row in requests)
switch = json.loads((folder / 'beta-switch.json').read_text(encoding='utf-8-sig'))
empty = json.loads((folder / 'beta-empty.messages.json').read_text(encoding='utf-8-sig'))
empty_state = json.loads((folder / 'beta-empty.state.json').read_text(encoding='utf-8-sig'))
assert 0 <= switch['elapsed_ms'] <= 1000
assert switch['selected']['name'] == empty_state['selected']['name'] == 'Verification Beta'
assert switch['selected']['last_message_time'] and empty['chat']['last_message_time']
assert empty['messages'] == []
for selected in [switch['selected'], empty_state['selected']]:
    assert all(empty['chat'][field] == selected[field] for field in ['id', 'provider', 'account'])
history = json.loads((folder / 'history.messages.json').read_text(encoding='utf-8-sig'))
beta = json.loads((folder / 'beta.messages.json').read_text(encoding='utf-8-sig'))
beta_state = json.loads((folder / 'beta.state.json').read_text(encoding='utf-8-sig'))
alpha_state = json.loads((folder / 'history.state.json').read_text(encoding='utf-8-sig'))
assert beta_state['selected']['name'] == 'Verification Beta'
assert alpha_state['selected']['name'] == 'Verification Alpha'
for shown, selected in [(beta, beta_state['selected']), (history, alpha_state['selected'])]:
    assert all(shown['chat'][field] == selected[field] for field in ['id', 'provider', 'account'])
assert len(beta['messages']) == 1 and beta['messages'][0]['id'] == 'BASELINE_BETA'
assert beta['messages'][0]['text'] == 'Fixture Beta history'
assert not any(row['id'] == 'BASELINE_BETA' for row in history['messages'])
live = json.loads((folder / 'live.messages.json').read_text(encoding='utf-8-sig'))
assert any(row['id'] == 'BASELINE' for row in history['messages'])
assert not any(row['id'] == 'LIVE' for row in history['messages'])
assert any(row['id'] == 'LIVE' for row in live['messages'])
images = []
for name in ['before', 'beta-empty', 'beta', 'history', 'live', 'sent', 'after']:
    image = (folder / f'{name}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
    if name != 'beta-empty':
        images.append(hashlib.sha256(image).hexdigest())
assert len(set(images)) >= 4
before = json.loads((folder / 'before.state.json').read_text(encoding='utf-8-sig'))
final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
assert before['chat_count'] == (3 if unified else 2) and final['chat_count'] == 1
assert final['pending_sends'] == 0 and final['pending_archives'] == 0
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
for keys in ['^{TAB}', '^+{TAB}', 'Compose message', 'Fixture outgoing', 'Archive selected chat', '{ENTER}']:
    assert f'keys: {keys}' in actions
launch = (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8')
backend = 'message backend:' if unified else 'whatsapp backend:'
assert launch.count(backend) == 1 and backend + ' hub' in launch
if unified:
    assert before['selected']['provider'] == 'slack' and final['selected']['provider'] == 'slack'
    assert 'hub provider-views PASS' in proof and 'hub mixed-lid-page PASS' in proof and 'hub mixed-older-pages PASS' in proof
    mixed = json.loads((folder / 'mixed-lid.messages.json').read_text(encoding='utf-8-sig'))
    assert len(mixed['messages']) == 80
    assert set(['Mixed phone first', 'Mixed lid first', 'Mixed phone second', 'Mixed lid second']) <= set(row['text'] for row in mixed['messages'])
    assert mixed['chat']['id'] == '15550000005@s.whatsapp.net' and 'WrongChat' not in launch
    paged = json.loads((folder / 'mixed-paged.messages.json').read_text(encoding='utf-8-sig'))
    paged_ids = [row['id'] for row in paged['messages']]
    assert paged['chat']['id'] == mixed['chat']['id']
    assert len(paged_ids) == 250 and set(paged_ids) == {f'MIXED-{number}' for number in range(1, 251)}
    assert paged['messages'] == sorted(paged['messages'], key=lambda row: (row['time'], row['id']))
    assert len({row['time'] for row in paged['messages']}) == 249
    mixed_reads = [row for row in requests if row.get('wire_path', '').startswith('/v1/wazig/messages?') and 'mixed_count' in row and row['status'] == 200]
    assert mixed_reads[0]['mixed_before'] == '' and mixed_reads[0]['mixed_count'] == 80
    older = [row for row in mixed_reads if row['mixed_before']]
    assert len(older) >= 4 and older[-1]['mixed_count'] == 0 and all(row['mixed_count'] > 0 for row in older[:-1])
    assert all(re.fullmatch(r'MIXED-\d+:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', row['mixed_before']) for row in older)
    assert len({row['mixed_before'] for row in older}) == len(older)
    assert all('limit=80' in row['wire_path'] for row in mixed_reads)
    assert (folder / 'mixed-paged.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert 'keys: {PGUP}' in actions
    assert not any(row['path'] == '/v1/archive' for row in requests)
    for keys in ['%1', '%2', '%0']:
        assert f'keys: {keys}' in actions
    subprocess.run([sys.executable, str(Path(__file__).with_name('check-hub-views.py')), str(folder)], check=True)
    assert all(row['wire_path'].startswith('/v1/wazig/') or row['wire_path'] == '/fixture/live' for row in requests)
    assert not any('account=' in row['wire_path'] for row in requests)
assert 'fixture-key-not-a-secret' not in launch and session['bridge_url'] not in launch
assert 'JOURNEY PASSED: ' + session['feature'] in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: ' + session['feature'] + ' chats, history, live replay, send dedupe, reads, archive, media cache and isolation')
raise SystemExit(0)

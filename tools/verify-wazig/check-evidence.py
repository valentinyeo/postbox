from pathlib import Path
import hashlib
import json
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
if session['feature'] in ('whatsapp-hub', 'hub'):
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
    assert len(sends) >= 2 and len({row['body']['client_id'] for row in sends}) == 1
    assert sum(row['accepted'] for row in sends) == 1
    assert any(row.get('duplicate') and row['status'] == 200 for row in sends)
    if unified:
        assert all('account' not in row['body'] and row['body']['chat'] == 'fixture-alpha' for row in sends)
    else:
        assert all(row['body']['account'] == 'personal' and row['body']['chat'] == '15550000001@s.whatsapp.net' for row in sends)
    paths = ['/v1/chats?', '/v1/messages?', '/v1/mark-read', '/v1/archive']
    if not unified:
        paths.append('/v1/accounts')
    for path in paths:
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
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig')
        if name != 'beta-empty':
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
    backend = 'message backend:' if unified else 'whatsapp backend:'
    assert launch.count(backend) == 1 and backend + ' hub' in launch
    if unified:
        assert before['selected']['provider'] == 'slack' and final['selected']['provider'] == 'telegram'
        assert all(row['wire_path'].startswith('/v1/wazig/') or row['wire_path'] == '/fixture/live' for row in requests)
        assert not any('account=' in row['wire_path'] for row in requests)
    assert 'fixture-key-not-a-secret' not in launch and session['bridge_url'] not in launch
    assert 'JOURNEY PASSED: ' + session['feature'] in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: ' + session['feature'] + ' chats, history, live replay, send dedupe, reads, archive, media cache and isolation')
    raise SystemExit(0)
if session['feature'] == 'menus':
    assert session['sha256'] and session['commit']
    assert 'JOURNEY PASSED: menus' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert 'PIXEL ORACLE PASSED:' in (folder / 'pixel-oracle-controls.txt').read_text(encoding='utf-8-sig')
    assert not (folder / 'failure.txt').exists()
    measurements = json.loads((folder / 'menu-luminances.json').read_text(encoding='utf-8-sig'))
    popups = ['amoled-' + name for name in ['chat', 'composer', 'search', 'message', 'selection', 'palette', 'accounts', 'emoji', 'shortcuts', 'slack-setup', 'shortcode']] + ['green-chat']
    popup_records = [row for row in measurements if row['expected'] != 'dark-edit']
    assert sorted(row['screenshot'] for row in popup_records) == sorted(name + '-after.png' for name in popups)
    for row in measurements:
        metric = row['measurement']
        assert metric['pixels'] > 0
        assert metric['rect']['Right'] > metric['rect']['Left']
        assert metric['rect']['Bottom'] > metric['rect']['Top']
        if row['expected'] == 'light':
            assert metric['background'] >= 0.7
        else:
            assert metric['background'] <= 0.05126945837404324
            assert metric['lightTileFraction'] <= 0.02
        if row['expected'] != 'dark-edit':
            assert metric['contrast'] >= 4.5 and metric['textPixels'] >= 24
    for name in popups:
        images = []
        for phase in ['before', 'after']:
            path = folder / f'{name}-{phase}.png'
            data = path.read_bytes()
            assert data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) > 10000
            images.append(hashlib.sha256(data).hexdigest())
            assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}-{phase}.uia.txt').read_text(encoding='utf-8-sig')
        assert images[0] != images[1], name
    state = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
    assert state['theme'] == 'green' and state['chat_count'] == 2
    assert state['sync'] == 'stopped' and state['pending_sends'] == 0 and state['pending_archives'] == 0
    assert state['production_preferences_absent'] and state['whatsapp_store_absent'] and state['telegram_store_absent']
    cached = json.loads((folder / 'final-data/chats-0000000000000526.json').read_text(encoding='utf-8-sig'))
    assert sorted(row['name'] for row in cached['data']) == ['Verification Alpha', 'Verification Beta']
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'drag-select synthetic message text and right-click' in actions and 'keys: Theme: Green' in actions
    print('EVIDENCE VERIFIED: menus popup pairs, fixed pixel thresholds, negative controls, isolated state and cleanup')
    sys.exit(0)
assert session['feature'] in ('search', 'archive')
feature = session['feature']
assert session['sha256'] and session['commit']
snapshots = ['doctor', 'before', 'after', 'side-effects']
if feature == 'search':
    assert 'hub no-url-direct-fallback PASS' in (folder / 'fallback-proof.log').read_text(encoding='utf-8-sig')
    launch = (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8-sig')
    assert 'whatsapp backend: wacli (URL not configured)' in launch and 'message backend: hub' not in launch
    snapshots += ['empty']
else:
    snapshots += ['action', 'kept', 'inbox']
for name in [f'{stage}.json' if stage in ('doctor', 'side-effects') else f'{stage}.state.json' for stage in snapshots]:
    data = json.loads((folder / name).read_text(encoding='utf-8-sig'))
    assert data['version'] == '0.0.526', name
    assert data['pending_sends'] == 0 and data['pending_archives'] == 0, name
    assert data['sync'] == 'stopped' and not data['slack_connected'], name
before = json.loads((folder / 'before.state.json').read_text(encoding='utf-8-sig'))
after = json.loads((folder / 'after.state.json').read_text(encoding='utf-8-sig'))
final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
assert before['chat_count'] == 2 and before['search'] == ''
if feature == 'search':
    empty = json.loads((folder / 'empty.state.json').read_text(encoding='utf-8-sig'))
    assert after['chat_count'] == 1 and after['search'] == 'Beta'
    assert after['selected']['name'] == 'Verification Beta'
    assert empty['chat_count'] == 0 and empty['search'] == 'NoSuchFixture'
    assert final['chat_count'] == 2 and final['search'] == ''
else:
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def alpha(provider):
        rows = [row for row in provider['data'] if row['jid'] == 'verify-alpha@s.whatsapp.net']
        assert len(rows) == 1
        return rows[0]

    action = read('action.state.json')
    kept = read('kept.state.json')
    inbox = read('inbox.state.json')
    assert before['selected']['name'] == 'Verification Alpha' and not before['show_archived']
    assert before['selected']['unread_count'] == 0
    assert action['show_archived'] and action['selected']['archived']
    assert action['selected']['name'] == 'Verification Alpha' and action['selected']['unread_count'] == 0
    assert kept['show_archived'] and kept['selected']['unread_count'] == 0
    assert not inbox['show_archived'] and inbox['chat_count'] == 1
    assert inbox['selected']['name'] == 'Verification Beta'
    for state in (after, final):
        assert state['show_archived'] and state['chat_count'] == 1 and state['search'] == ''
        row = state['selected']
        assert row['name'] == 'Verification Alpha' and row['archived'] and row['unread']
        assert row['unread_count'] == 1 and row['last_message_time'] == '2026-10-10T11:00:00Z'
    for stage, names in [('before', ['Verification Alpha', 'Verification Beta']), ('action', ['Verification Alpha']), ('kept', ['Verification Alpha']), ('inbox', ['Verification Beta']), ('after', ['Verification Alpha'])]:
        chats = read(f'{stage}.chats.json')
        assert chats['total'] == len(names) and sorted(row['name'] for row in chats['chats']) == names
    incoming = read('incoming-provider.json')
    assert not alpha(incoming)['archived'] and alpha(incoming)['unread_count'] == 1
    messages = incoming['messages']['verify-alpha@s.whatsapp.net']['data']['messages']
    assert len(messages) == 1 and messages[0]['MsgID'] == 'verify-incoming-1' and not messages[0]['FromMe']
    assert messages[0]['Timestamp'] == alpha(incoming)['last_message_ts'] == '2026-10-10T11:00:00Z'
    provider = read('final-data/verification-provider.json')
    assert sorted(row['name'] for row in provider['data']) == ['Verification Alpha', 'Verification Beta']
    assert alpha(provider)['archived'] and alpha(provider)['unread_count'] == 1
    assert provider['messages'] == incoming['messages']
    assert 'archive: jid=verify-alpha@s.whatsapp.net archived=true source=kept' in (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8-sig')
    for name in ('kept-archive-state.txt', 'final-data/archive-state.txt'):
        assert 'verify-alpha@s.whatsapp.net\t1\t' in (folder / name).read_text(encoding='utf-8-sig')
    assert 'Archive and keep archived' in (folder / 'action.palette.uia.txt').read_text(encoding='utf-8-sig')
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
assert f'JOURNEY PASSED: {feature}' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
assert not (folder / 'failure.txt').exists()
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
keys_required = ['^f', 'Beta', '{ESC}', 'NoSuchFixture'] if feature == 'search' else ['^e', '^k', 'Archive and keep archived', 'Show inbox chats', 'Show archived chats', '{ENTER}']
for keys in keys_required:
    assert f'keys: {keys}' in actions
images = []
stages = ['before', 'after', 'empty'] if feature == 'search' else ['before', 'action', 'kept', 'inbox', 'after']
for name in stages:
    image = (folder / f'{name}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig')
    images.append(hashlib.sha256(image).hexdigest())
assert len(set(images)) == len(stages)
if feature == 'search':
    cached = json.loads((folder / 'final-data/chats-0000000000000526.json').read_text(encoding='utf-8-sig'))
    assert sorted(row['name'] for row in cached['data']) == ['Verification Alpha', 'Verification Beta']
else:
    ordered_actions = ['keys: ^e', 'keys: Show archived chats', 'keys: Archive and keep archived', 'keys: Show inbox chats', 'provider: incoming verify-incoming-1; archived=false; unread_count=1', 'keys: Show archived chats']
    position = 0
    for action in ordered_actions:
        position = actions.index(action, position) + len(action)
assert not (folder / 'final-data/telegram').exists()
print(f'EVIDENCE VERIFIED: {feature} action, state transitions, isolation, surviving screenshots and cleanup')

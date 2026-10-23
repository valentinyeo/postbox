from pathlib import Path
import hashlib
import json
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
if session['feature'] == 'slack-threads':
    runpy.run_path(str(Path(__file__).with_name('check-slack-threads-evidence.py')))['check_threads'](folder)
    raise SystemExit(0)
if session['feature'] == 'window':
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='window', status='passed')
    assert not (folder / 'failure.txt').exists()
    steps = read('window.json')
    assert [row['step'] for row in steps] == ['start-1', 'restored', 'start-2', 'start-3', 'start-4', 'start-5']
    assert [row['zoomed'] for row in steps] == [True, False, True, True, True, True], 'Unexpected zoomed sequence'
    assert [row['update_relaunch'] for row in steps] == [False, False, False, True, False, True]
    assert all(row['root'] == session['root'] and row['id'] == session['id'] for row in steps)
    assert len({(row['pid'], row['start_ticks']) for row in steps}) == 5
    assert steps[0]['pid'] == steps[1]['pid'] and steps[0]['start_ticks'] == steps[1]['start_ticks']
    assert steps[-1]['pid'] == session['pid'] and steps[-1]['start_ticks'] == session['startTicks']
    starts = [row for row in steps if row['step'] != 'restored']
    assert [row['start_method'] for row in starts] == ['process-start'] * 3 + ['createprocess-shownormal', 'createprocess-update-relaunch']
    for row in starts:
        assert row['launch_zoomed_after'] > row['launch_zoomed_before'] >= 0, (row['step'], 'launch log lacks a new startup: window zoomed=true line')
    assert [row['launch_zoomed_after'] for row in starts] == sorted(row['launch_zoomed_after'] for row in starts)
    launch_log = (folder / 'final-data' / 'launch-log.txt').read_text(encoding='utf-8-sig')
    assert sum(line.endswith(' startup: window zoomed=true') for line in launch_log.splitlines()) >= 5
    assert not any(line.endswith(' startup: window zoomed=false') for line in launch_log.splitlines())
    assert read('doctor.json')['version'] == '0.0.526'
    assert len({row['monitor_handle'] for row in steps}) == 1
    for row in steps:
        assert row['hwnd'] and row['monitor_handle'] and row['start_ticks']
        for field in ['monitor_rect', 'work_rect', 'normal_rect']:
            rect = row[field]
            assert rect['Right'] > rect['Left'] and rect['Bottom'] > rect['Top'], (row['step'], field)
        image = (folder / (row['step'] + '.png')).read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / (row['step'] + '.uia.txt')).read_text(encoding='utf-8-sig')
        state = read(row['step'] + '.state.json')
        assert state['sync'] == 'stopped' and state['pending_sends'] == state['pending_archives'] == 0
    normal = steps[1]['normal_rect']
    assert normal == steps[2]['normal_rect'] == steps[3]['normal_rect'] == steps[4]['normal_rect'] == steps[5]['normal_rect']
    initial = steps[0]['normal_rect']
    assert normal['Right'] - normal['Left'] < initial['Right'] - initial['Left']
    assert normal['Bottom'] - normal['Top'] < initial['Bottom'] - initial['Top']
    preferences = (folder / 'preferences.txt').read_text(encoding='utf-8-sig')
    for name in ['WindowLeft', 'WindowTop', 'WindowRight', 'WindowBottom']:
        assert name in preferences, name
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert actions.count('keys: %{F4}') == 4 and 'keys: r' in actions and 'keys: s' in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: window' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: zoomed startups, keyboard restore and Alt+F4, same-profile update relaunch, Start-menu style and updater CreateProcessW launches and retained monitor')
    raise SystemExit(0)
if session['feature'] == 'repaint':
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='repaint', status='passed')
    assert not (folder / 'failure.txt').exists()
    paints = read('paints.json')
    assert 60 <= paints['elapsed_seconds'] < 70
    fields = {'window', 'window_full', 'canvas', 'canvas_full', 'list', 'list_full'}
    assert set(paints['before']) == set(paints['after']) == set(paints['delta']) == fields
    for field in fields:
        assert paints['delta'][field] == paints['after'][field] - paints['before'][field] >= 0
    full = sum(paints['delta'][field] for field in fields if field.endswith('_full'))
    assert full == paints['full'] and full <= 3, f'repaint: {full} full repaints in 60 s, limit 3'
    assert paints['provider']['ticks'] >= 29 and paints['provider']['incoming'] >= 5
    assert paints['selected_before'] == paints['selected_after'] == 'fixture-alpha'
    before = read('before.chats.json')['chats']
    after = read('after.chats.json')['chats']
    beta_before, = [row for row in before if row['id'] == 'fixture-beta']
    beta_after, = [row for row in after if row['id'] == 'fixture-beta']
    assert beta_after['unread_count'] - beta_before['unread_count'] >= 5
    assert beta_after['last_message_time'] > beta_before['last_message_time']
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    updates = [row for row in requests if row['method'] == 'SSE']
    assert sum(row['kind'] == 'reset' for row in updates) >= 30
    assert sum(row['kind'] == 'msg' for row in updates) >= 5
    assert len([row for row in requests if row['method'] == 'GET' and row['wire_path'].startswith('/v1/wazig/chats?') and row.get('incoming') is not None]) >= 25
    for phase in ['before', 'after']:
        image = (folder / f'{phase}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        tree = (folder / f'{phase}.uia.txt').read_text(encoding='utf-8-sig')
        assert 'MessagesZig | Wazig Messages v0.0.526' in tree
        assert read(f'{phase}.state.json')['selected']['id'] == 'fixture-alpha'
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: repaint' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: no-input repaint workload, incoming chat updates, surface deltas and isolation')
    raise SystemExit(0)
if session['feature'] == 'reactions':
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='reactions', status='passed')
    assert not (folder / 'failure.txt').exists()
    bodies = [json.loads(line) for line in (folder / 'react-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    clicks = read('reaction-clicks.json')
    assert len(clicks) == 2 and {row['provider'] for row in clicks} == {'whatsapp', 'slack'}
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    expected = chr(0x1f602)
    for provider, chat, message in [('whatsapp', 'fixture-beta', 'BASELINE_BETA'), ('slack', 'fixture-alpha', 'BASELINE')]:
        observed = [row for row in bodies if row['chat'] == chat]
        assert observed and all(row['msg'] == message and row['emoji'] == expected for row in observed), (provider, observed)
        assert all(set(row) == {'chat', 'msg', 'emoji', 'client_id'} and row['client_id'] for row in observed)
        accepted = [row for row in requests if row['wire_path'] == '/v1/wazig/react' and row.get('body', {}).get('chat') == chat]
        assert accepted and all(row['authorized'] and row['status'] == 200 and row['body'] in observed for row in accepted)
        click, = [row for row in clicks if row['provider'] == provider]
        assert click['chat'] == chat and click['message'] == message and click['expected'] == expected
        assert click['menu_class'] == '#32768' and click['menu_pid'] == session['pid']
        assert click['index'] == 2 and click['cell_width'] > 0
        assert click['x'] == click['row_left'] + click['index'] * click['cell_width'] + click['cell_width'] // 2
        assert click['y'] == click['row_top'] + click['cell_width'] // 2
        rect = click['menu']
        assert rect['Left'] < click['x'] < rect['Right'] and rect['Top'] < click['y'] < rect['Bottom']
        shown = read(f'{provider}-after.messages.json')
        assert shown['chat']['id'] == chat and shown['chat']['provider'] == provider
        incoming, = [row for row in shown['messages'] if row['id'] == message]
        assert not incoming['from_me'] and incoming['reaction'] == expected
        images = []
        for phase in ['before', 'after']:
            name = f'{provider}-{phase}'
            image = (folder / f'{name}.png').read_bytes()
            assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
            images.append(hashlib.sha256(image).hexdigest())
            assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig')
            selected = read(f'{name}.state.json')['selected']
            assert selected['id'] == chat and selected['provider'] == provider
        assert images[0] != images[1]
        assert f'SendInput: right-click {provider} message={message}' in actions
        assert f'SendInput: left-click {provider} laughing-face cell=2' in actions
        assert f'reactions {provider}-laughing-face PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert {row['chat'] for row in bodies} == {'fixture-alpha', 'fixture-beta'}
    assert not any(row['wire_path'] in ('/v1/wazig/send', '/v1/wazig/archive') for row in requests)
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: reactions' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: real mouse laughing-face reactions on WhatsApp and Slack, exact hub bodies, visible chips and isolation')
    raise SystemExit(0)
if session['feature'] == 'workspace-icons':
    from importlib.util import module_from_spec, spec_from_file_location

    spec = spec_from_file_location('workspace_icons', Path(__file__).with_name('check-workspace-icons.py'))
    icons = module_from_spec(spec)
    spec.loader.exec_module(icons)

    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='workspace-icons', status='passed')
    assert not (folder / 'failure.txt').exists()
    icons.check_pixels(folder)
    rows = read('workspace-icons-list.chats.json')
    layout = read('workspace-icons-layout.json')
    ids = [row['id'] for row in rows['chats']]
    assert rows['total'] == 5
    assert ids == layout['ids']
    assert sorted(ids) == sorted(icons.IDS)
    assert all(row['provider'] == ('signal' if row['id'] == 'signal:fixture-contact' else 'whatsapp' if row['id'] == 'whatsapp:fixture:contact-delta' else 'slack') for row in rows['chats'])
    state = read('workspace-icons-list.state.json')
    assert state['view'] == 'all' and state['theme'] == 'amoled'
    assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / 'workspace-icons-list.uia.txt').read_text(encoding='utf-8-sig')
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert all(row['wire_path'].startswith('/v1/wazig/') for row in requests)
    for team, status in [('fixture-amber', 200), ('fixture-cobalt', 200), ('fixture-empty', 404)]:
        route = '/v1/wazig/workspace-icon/' + team
        fetched = [row for row in requests if row['wire_path'] == route and row['authorized']]
        assert len(fetched) == 1 and fetched[0]['status'] == status, team
        assert any(row['wire_path'] == route and not row['authorized'] and row['status'] == 401 for row in requests), team
        if status == 200:
            cached = list((folder / 'final-data/avatars').glob('*.img'))
            assert any(hashlib.sha256(path.read_bytes()).hexdigest() == fetched[0]['sha256'] for path in cached), team
    assert all(row['authorized'] or row['status'] == 401 for row in requests if row['method'] != 'SSE')
    assert not any(row['wire_path'] in ('/v1/wazig/send', '/v1/wazig/archive') for row in requests)
    assert len(list((folder / 'final-data/avatars').glob('*.none'))) >= 2
    final = read('side-effects.json')
    assert final['chat_count'] == 5 and final['pending_sends'] == final['pending_archives'] == 0
    assert final['sync'] == 'stopped' and not final['slack_connected']
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'workspace-icons workspace-icons-pixels PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert 'keys: %0' in (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: workspace-icons' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: workspace icon badge pixels, authenticated team cache, fallback, WhatsApp green, Signal blue and isolation')
    raise SystemExit(0)
if session['feature'] == 'hub-archive':
    runpy.run_path(str(Path(__file__).with_name('check-hub-archive-evidence.py')))['check_hub_archive'](folder)
    raise SystemExit(0)

if session['feature'] == 'notrap':
    runpy.run_path(str(Path(__file__).with_name('check-notrap-evidence.py')))['check_notrap'](folder)
    raise SystemExit(0)

if session['feature'] == 'telegram':
    runpy.run_path(str(Path(__file__).with_name('check-telegram-evidence.py')))['check_telegram'](folder)
    raise SystemExit(0)

if session['feature'] == 'signal':
    runpy.run_path(str(Path(__file__).with_name('check-signal-evidence.py')))['check_signal'](folder)
    raise SystemExit(0)
if session['feature'] == 'slack-archive':
    runpy.run_path(str(Path(__file__).with_name('check-slack-archive-evidence.py')))['check_slack_archive'](folder)
    raise SystemExit(0)

if session['feature'] == 'slack-sort':
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='slack-sort', status='passed')
    assert not (folder / 'failure.txt').exists()
    orders = {
        'before': ['fixture-beta', 'fixture-gamma', 'fixture-alpha', 'fixture-unknown'],
        'after': ['fixture-alpha', 'fixture-beta', 'fixture-gamma', 'fixture-unknown'],
        'sent': ['fixture-gamma', 'fixture-alpha', 'fixture-beta', 'fixture-unknown'],
    }
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    for stage, expected in orders.items():
        rows = read(f'{stage}.chats.json')
        assert rows['total'] == 4 and [row['id'] for row in rows['chats']] == expected
        assert all(row['provider'] == 'slack' for row in rows['chats'])
        times = [row['last_message_time'] for row in rows['chats']]
        assert times[-1] == '' and all(times[:3]) and times[:3] == sorted(times[:3], reverse=True)
        walk = read(f'{stage}.navigation.json')
        offset = expected.index(walk[0])
        assert walk == expected[offset:] + expected[:offset]
        assert f'slack-sort {stage}-last-message-order PASS' in proof
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig')
        assert read(f'{stage}.state.json')['view'] == 'slack'
    initial_times = {row['id']: row['last_message_time'] for row in read('before.chats.json')['chats']}
    assert initial_times['fixture-alpha'] < read('after.chats.json')['chats'][0]['last_message_time']
    assert initial_times['fixture-gamma'] < read('sent.chats.json')['chats'][0]['last_message_time']
    assert read('after.state.json')['selected']['id'] == 'fixture-gamma'
    assert read('sent.state.json')['selected']['id'] == 'fixture-gamma'
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
    assert any(row['method'] == 'SSE' and row['kind'] == 'msg' for row in requests)
    assert any(row['wire_path'] == '/fixture/live' and row['status'] == 200 for row in requests)
    sends = [row for row in requests if row['wire_path'] == '/v1/wazig/send']
    assert sends and all(row['status'] == 200 and row['body']['chat'] == 'fixture-gamma' and row['body']['text'] == 'Synthetic Slack outgoing' for row in sends)
    final = read('side-effects.json')
    assert final['chat_count'] == 4 and final['pending_sends'] == final['pending_archives'] == 0
    assert final['sync'] == 'stopped' and not final['slack_connected']
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for keys in ['%1', '^{TAB}', '^+{TAB}', 'Compose message', 'Synthetic Slack outgoing', '{ENTER}']:
        assert f'keys: {keys}' in actions
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: slack-sort' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: Slack last message ordering, unknown last, incoming and sent promotion with keyboard order and isolation')
    raise SystemExit(0)
if session['feature'] == 'views':
    runpy.run_path(str(Path(__file__).with_name('check-views-evidence.py')))['check_views'](folder)
    raise SystemExit(0)
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
    paths = ['/v1/chats?', '/v1/messages?', '/v1/mark-read', '/v1/archive']
    if not unified:
        paths.append('/v1/accounts')
    for path in paths:
        assert any(row['path'].startswith(path) and row.get('status') == 200 for row in requests), path
    assert any(row['path'] == '/v1/archive' and row['body']['archived'] and (not unified or row['body']['chat'] == 'fixture-beta') for row in requests)
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
        assert before['selected']['provider'] == 'slack' and final['selected']['provider'] == 'slack'
        assert 'hub provider-views PASS' in proof
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
if session['feature'] in ('palette', 'appearance'):
    feature = session['feature']
    assert session['sha256'] and session['commit']
    assert not (folder / 'failure.txt').exists()
    assert f'JOURNEY PASSED: {feature}' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    if feature == 'palette':
        removed = json.loads((folder / 'removed-status.json').read_text(encoding='utf-8-sig'))
        assert removed['positive_query'] == 'Keyboard shortcuts' and removed['positive_matches'] == 1
        assert removed['query'] == 'Status' and removed['status_rows'] == 0
        assert removed['sidebar_status_controls'] == 0
        stages = ['before', 'removed-status', 'action', 'after']
        keys = ['^k', 'Keyboard shortcuts', '^a', 'Status', '{ENTER}', '{ESC}']
    else:
        scale = json.loads((folder / 'text-scale.json').read_text(encoding='utf-8-sig'))
        assert scale['initial_saved'] is False and scale['larger'] == 92 and scale['reset'] == 82
        assert 0 < scale['baseline_points'] < scale['larger_points']
        assert scale['reset_points'] == scale['baseline_points']
        stages = ['before', 'action', 'text-larger', 'after']
        keys = ['^k', 'Theme: Green', 'Make text larger', '{ENTER}', '^0']
        preferences = (folder / 'preferences.txt').read_text(encoding='utf-8-sig')
        assert 'FontScale' in preferences and '82' in preferences
    for keys_sent in keys:
        assert f'keys: {keys_sent}' in actions
    images = []
    for name in stages:
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        images.append(hashlib.sha256(image).hexdigest())
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig')
        state = json.loads((folder / f'{name}.state.json').read_text(encoding='utf-8-sig'))
        assert state['version'] == '0.0.526' and state['chat_count'] == 2
        assert state['pending_sends'] == state['pending_archives'] == 0 and state['sync'] == 'stopped'
    assert images[0] != images[1] and images[2] != images[3]
    final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['chat_count'] == 2 and final['search'] == ''
    assert final['theme'] == ('green' if feature == 'appearance' else 'amoled')
    print(f'EVIDENCE VERIFIED: {feature} input, new assertions, surviving screenshots and isolation')
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
    for popup, count in [('palette', 1), ('accounts', 1), ('emoji', 1), ('slack-setup', 2)]:
        edits = [row for row in measurements if row['expected'] == 'dark-edit' and row['screenshot'] == f'amoled-{popup}-after.png']
        assert len(edits) == count, popup
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

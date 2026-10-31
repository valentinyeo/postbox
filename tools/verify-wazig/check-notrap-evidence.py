import re
import json
import struct
from datetime import datetime
from urllib.parse import urlsplit


def check_notrap(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def capture(name):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + re.escape(session['expected_version']), (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]), name
        state = read(f'{name}.state.json')
        rows = read(f'{name}.chats.json')['chats']
        assert state['chat_count'] == len(rows), name
        return state, rows

    session = read('session.json')
    assert session['feature'] == 'notrap' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='notrap', status='passed')
    assert not (folder / 'failure.txt').exists()
    assert read('startup-seed.json') == dict(view=4, account='signal', providers_without_rows=['signal', 'telegram'])
    startup, rows = capture('startup')
    assert startup['view'] not in ('signal', 'telegram') and startup['current_view']['inbox']
    assert startup['chat_count'] == 8 and {row['provider'] for row in rows} == {'whatsapp', 'slack'}
    order = startup['view_order']
    assert [(view['provider'], view['account']) for view in order] == [
        ('whatsapp', 'personal'), ('whatsapp', 'business'), ('slack', 'T0ABC123'),
        ('slack', 'T0DEF456'), ('telegram', 'telegram'), ('signal', 'signal')]

    def identity(view):
        return dict(provider=view['provider'], account=view['account'], label=view['label'], inbox=False)

    for number, view in enumerate(order, 1):
        state, rows = capture(f'view-{number}')
        assert state['current_view'] == identity(view)
        empty = view['provider'] in ('signal', 'telegram')
        assert state['chat_count'] == (0 if empty else 2)
        assert all(row['provider'] == view['provider'] and row['view_account'] == view['account'] for row in rows)
        escaped = read(f'esc-{number}.state.json')
        assert escaped['search'] == '' and escaped['chat_count'] > 0
        assert escaped['current_view'] == (startup['current_view'] if empty else identity(view))
        assert read(f'escape-to-first-{number}.state.json')['current_view'] == identity(order[0])
    transitions = read('transitions.json')
    expected = {(source, target) for source in range(1, len(order) + 1) for target in [*range(1, len(order) + 1), '%1', '%i', 'gi']}
    assert len(transitions) == len(expected)
    assert {(row['source'], row['target']) for row in transitions} == expected
    for row in transitions:
        wanted = identity(order[row['target'] - 1]) if isinstance(row['target'], int) else startup['current_view']
        assert row['current_view'] == wanted, row
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for key in [*(f'%{number + 1}' for number in range(1, len(order) + 1)), '%1', '%i', 'gi', '^1', 'g', 'x', 'i', '^f', 'no-trap-search', '{ESC}']:
        assert f'keys: {key}' in actions, key
    for name in ('ctrl-one', 'typed-gi', 'cancelled-gi', 'focus-cancelled-gi', 'composer-gi'):
        state, _ = capture(name)
        assert state['current_view'] == identity(order[0]), name
        if name == 'typed-gi':
            assert state['search'] == 'gi'
    for name, wanted in [('shortcut-alt-2', identity(order[0])), ('shortcut-alt-3', identity(order[1])),
                         ('shortcut-alt-1', startup['current_view']), ('shortcut-alt-i', startup['current_view']),
                         ('shortcut-g-i', startup['current_view'])]:
        state, _ = capture(name)
        assert state['current_view'] == wanted, name
    jump = read('ctrl-chat-jump.json')
    assert jump['first'] != jump['third'] and jump['selected'] == jump['first'] and jump['view'] == identity(order[0])
    jumped, _ = capture('ctrl-number-jump')
    assert jumped['selected']['id'] == jump['first'] and jumped['current_view'] == identity(order[0])
    menu_open, _ = capture('prefix-menu-open')
    menu_closed, _ = capture('prefix-menu-closed')
    menu = read('prefix-menu.json')
    assert menu['menu_class'] == '#32768' and menu['menu_pid'] == session['pid'] and menu['menu_handle'] != 0 and menu['closed']
    assert menu['after_count'] == menu['before_count'] + 1 and 0 <= menu['prefix_age_ms'] <= 900 and not menu['prefix_pending']
    assert menu_open['menu_entry_count'] == menu_closed['menu_entry_count'] == menu['after_count']
    assert menu_open['menu_prefix_age_ms'] == menu['prefix_age_ms'] and not menu_open['menu_prefix_pending']
    assert menu['current_view'] == menu_open['current_view'] == menu_closed['current_view'] == identity(order[0])
    assert 'SendInput: right-click synthetic message for prefix cancellation' in actions
    composer = read('composer-gi.json')
    assert composer == dict(text='gi', focus_id='1032', focus_pid=session['pid'], current_view=identity(order[0]))
    assert read('focus-cancelled-gi.json') == dict(text='i', focus_id='1032', focus_pid=session['pid'], current_view=identity(order[0]))
    assert read('composer-restored.json') == dict(text='')
    assert 'keys: ^a{BACKSPACE}' in actions
    ledger = read('ticketProof.json')
    assert [row['key'] for row in ledger] == ['%2', '%3', '%1', '%i', 'gi']
    assert [row['current_view'] for row in ledger] == [identity(order[0]), identity(order[1]), *[startup['current_view']] * 3]
    times = [datetime.fromisoformat(row['utc'].replace('Z', '+00:00')) for row in ledger]
    assert times == sorted(times)
    recording = read('ticketProof-capture.json')
    width, height = recording['width'], recording['height']
    assert width > 0 and height > 0 and recording['fps'] == 5
    if recording['mode'] == 'video':
        video = (folder / 'ticketProof.mp4').read_bytes()
        assert len(video) > 10000 and video[4:8] == b'ftyp'
        log = (folder / 'ticketProof-ffmpeg.log').read_text(encoding='utf-8-sig')
        counts = [int(count) for count in re.findall(r'frame=\s*(\d+)', log)]
        assert counts and max(counts) >= 90
        assert f'{width}x{height}' in log
        started = datetime.fromisoformat(recording['started'].replace('Z', '+00:00'))
        finished = datetime.fromisoformat(recording['finished'].replace('Z', '+00:00'))
        assert started <= times[0] <= times[-1] <= finished
    else:
        assert recording['mode'] == 'frames'
        frames = recording['frames']
        assert len(frames) == 100
        frame_dir = folder / 'ticketProof-frames'
        assert len(list(frame_dir.glob('frame-*.png'))) == 100
        for index, frame in enumerate(frames):
            assert frame['file'] == f'frame-{index:03}.png'
            data = (frame_dir / frame['file']).read_bytes()
            assert len(data) > 1000 and data[:8] == b'\x89PNG\r\n\x1a\n'
            assert struct.unpack('>II', data[16:24]) == (width, height)
        elapsed = [frame['elapsed_ms'] for frame in frames]
        assert 19500 <= elapsed[-1] - elapsed[0] <= 25000
        assert all(0 < later - earlier <= 1000 for earlier, later in zip(elapsed, elapsed[1:]))
        frame_times = [datetime.fromisoformat(frame['utc'].replace('Z', '+00:00')) for frame in frames]
        assert frame_times == sorted(frame_times)
        assert frame_times[0] <= times[0] <= times[-1] <= frame_times[-1]
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert any(row['path'].startswith('/v1/wazig/chats') and row['status'] == 200 for row in requests)
    for row in requests:
        if row['method'] == 'SSE':
            continue
        assert row['authorized']
        path = urlsplit(row['path']).path
        assert path in ('/v1/wazig/chats', '/v1/wazig/messages', '/v1/wazig/events', '/v1/wazig/mark-read') or path.startswith(('/v1/wazig/avatar/', '/v1/wazig/workspace-icon/')), path
        assert row['method'] != 'POST' or path == '/v1/wazig/mark-read'
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    for gate in ['startup-fallback', 'every-view-escape-alt']:
        assert f'notrap {gate} PASS' in proof
    final = read('side-effects.json')
    assert final['current_view']['inbox'] and final['chat_count'] == 8
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped' and not final['slack_connected']
    assert all(final[key] for key in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    assert 'JOURNEY PASSED: notrap' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('NOTRAP EVIDENCE VERIFIED: saved empty startup fallback, every view Escape, full Alt-key matrix and screenshots')

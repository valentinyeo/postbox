import re
import json
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
    for name in ('ctrl-one', 'typed-gi', 'cancelled-gi'):
        state, _ = capture(name)
        assert state['current_view'] == identity(order[0]), name
        if name == 'typed-gi':
            assert state['search'] == 'gi'
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

import re
import json
from urllib.parse import unquote, urlsplit


ARCHIVED = {
    'whatsapp': ('personal:15550000031@s.whatsapp.net', 'Archived Person Alpha'),
    'telegram': ('telegram:user:7001001', 'Archived Telegram Beta'),
    'slack': ('slack:T0PALETTE:C0000000002', 'Archived Slack Gamma'),
}
INBOX = {
    'epsilon': 'Inbox WhatsApp Epsilon',
    'zeta': 'Inbox WhatsApp Zeta',
    'delta': 'Inbox Slack Delta',
}
DOT = '·'
ROW_LIMIT = 10


def label(name):
    return f'{name}  {DOT}  Archived'


def check_palette_archived(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def capture(name):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]), name
        return read(f'{name}.state.json')

    session = read('session.json')
    assert session['feature'] == 'palette-archived' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='palette-archived', status='passed')
    assert not (folder / 'failure.txt').exists()
    journey = read('palette-archived.json')
    assert journey['failures'] == [] and journey['row_limit'] == ROW_LIMIT
    views = journey['views']
    assert read('view-order.json') == views
    providers = [view['provider'] for view in views]
    assert 'whatsapp' in providers and 'slack' in providers and len(views) >= 2
    matrix = {row['step']: row for row in journey['matrix']}
    control = matrix['a0-inbox-control']
    assert control['found'] and control['matches'] == 1 and control['expected'] == INBOX['delta']
    capture('a0-inbox-control')
    for key, (chat, name) in ARCHIVED.items():
        row = matrix[f'a-all-{key}']
        assert row['found'] and row['matches'] == 1 and row['expected'] == label(name), key
        assert 0 <= row['index'] < ROW_LIMIT and row['view'] == 'combined inbox', key
        assert row['labels'][row['index']] == label(name)
        palette = read(f'a-all-{key}.palette.json')
        assert label(name) in palette['labels'] and palette['index'] == row['index']
        capture(f'a-all-{key}')
    assert matrix['a-all-crowded']['informational']
    capture('a-all-crowded')
    for position, view in enumerate(views[:9], 1):
        capture(f'b-view-{position}')
        for key, (chat, name) in ARCHIVED.items():
            row = matrix[f'b-{position}-{key}']
            assert row['found'] and row['matches'] == 1 and 0 <= row['index'] < ROW_LIMIT, (position, key)
            assert row['expected'] == label(name) and row['view'] == view['label'], (position, key)
            capture(f'b-{position}-{key}')
        for slug, name in INBOX.items():
            row = matrix[f'b-{position}-inbox-{slug}']
            assert row['found'] and row['matches'] == 1 and 0 <= row['index'] < ROW_LIMIT, (position, slug)
            assert row['expected'] == name and row['view'] == view['label'], (position, slug)
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    kept = read('palette-archived.requests.json')
    assert len([row for row in kept if row['method'] != 'SSE']) <= len([row for row in requests if row['method'] != 'SSE'])
    assert any(row['method'] == 'GET' and row['status'] == 200 and row['wire_path'].startswith('/v1/wazig/chats') and
               'archived=true' in row['wire_path'] for row in requests)
    for scope in ['all', 'own']:
        for key, (chat, name) in ARCHIVED.items():
            state = capture(f'c-{scope}-{key}')
            assert state['selected']['id'] == chat and state['selected']['archived'], (scope, key)
            assert capture(f'c-{scope}-{key}-palette') is not None
            if scope == 'all':
                assert any(row['method'] == 'GET' and unquote(row['wire_path']).startswith('/v1/wazig/messages') and
                           f'chat={chat}' in unquote(row['wire_path']) and row['status'] == 200 for row in requests), key
    for row in requests:
        if row['method'] == 'SSE':
            continue
        assert row['authorized'] or row['status'] == 401
        path = urlsplit(row['wire_path']).path
        assert path.startswith('/v1/wazig/')
        if row['method'] == 'POST':
            assert path == '/v1/wazig/mark-read', path
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert 'palette-archived palette-archived-all PASS' in proof and 'palette-archived archived-scan-request PASS' in proof
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert not final['show_archived'] and final['current_view']['inbox']
    assert all(final[key] for key in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'keys: %i' in actions and 'keys: %1' in actions and 'keys: {ENTER}' in actions and 'keys: ^k' in actions
    assert 'JOURNEY PASSED: palette-archived' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('PALETTE ARCHIVED EVIDENCE VERIFIED: archived and inbox chats found from every view, Enter opens without unarchiving')

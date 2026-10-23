import json
from urllib.parse import urlsplit


GROUP = 'personal:120363000000000001@g.us'
OTHER = 'personal:15550000003@s.whatsapp.net'
LEGACY = '120363000000000001@g.us\t1\t2026-10-10T10:00:00Z'


def check_hub_archive(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def capture(name, archived):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig'), name
        state = read(f'{name}.state.json')
        rows = read(f'{name}.chats.json')
        assert state['show_archived'] == archived and state['chat_count'] == rows['total'] == 1
        row, = rows['chats']
        assert row['id'] == (GROUP if archived else OTHER) and row['provider'] == 'whatsapp'
        assert row['archived'] == archived

    session = read('session.json')
    assert session['feature'] == 'hub-archive' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='hub-archive', status='passed')
    assert not (folder / 'failure.txt').exists()
    assert (folder / 'legacy-archive-state.txt').read_text(encoding='utf-8-sig').strip() == LEGACY
    legacy_bytes = (folder / 'legacy-archive-state.txt').read_bytes()
    assert (folder / 'final-data/archive-state.txt').read_bytes() == legacy_bytes
    restart = read('restart.json')
    assert (restart['old_pid'], restart['old_start']) != (restart['new_pid'], restart['new_start'])
    assert restart['new_pid'] == session['pid'] and restart['new_start'] == session['startTicks']
    assert restart['root'] == session['root'] and restart['id'] == session['id'] and restart['sha256'] == session['sha256']
    assert read('restart-incoming.json') == dict(archived=False, last_message_ts='2026-10-10T13:00:00Z', unread_count=1)
    first_requests = read('first.requests.json')
    restart_requests = read('restart.requests.json')
    for phase, requests, stamp in [('first', first_requests, '2026-10-10T11:00:00Z'),
                                   ('restart', restart_requests[len(first_requests):], '2026-10-10T13:00:00Z')]:
        capture(f'{phase}-inbox', False)
        capture(f'{phase}-archived', True)
        lines = (folder / f'{phase}-archive-state.txt').read_text(encoding='utf-8-sig').splitlines()
        kept, = [line.split('\t') for line in lines if line.startswith(GROUP + '\t')]
        assert kept[1] == '1' and kept[2] >= '2026-10-10T11:00:00Z'
        assert (folder / f'{phase}-archive-legacy-done.txt').read_bytes()
        incoming = [index for index, row in enumerate(requests) if row.get('group_archived') is False and
                    row.get('group_last_message_ts') == stamp and row.get('group_unread_count') == 1]
        writes = [index for index, row in enumerate(requests) if row['wire_path'] == '/v1/wazig/archive' and
                  row['status'] == 200 and row['body'] == dict(chat=GROUP, archived=True)]
        assert incoming and writes and min(incoming) < min(writes), phase
        assert f'hub-archive {phase} PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    for row in requests:
        if row['method'] == 'SSE':
            continue
        assert row['authorized']
        path = urlsplit(row['wire_path']).path
        assert path.startswith('/v1/wazig/') or path == '/fixture/archive-incoming'
        if row['method'] == 'POST':
            assert path in ('/v1/wazig/archive', '/v1/wazig/mark-read', '/fixture/archive-incoming')
    state_files = list((folder / 'final-data').glob('hub-*-archive-state.txt'))
    marker_files = list((folder / 'final-data').glob('hub-*-archive-legacy-done.txt'))
    assert len(state_files) == len(marker_files) == 1
    assert state_files[0].name.replace('archive-state', 'archive-legacy-done') == marker_files[0].name
    assert marker_files[0].read_bytes() == (folder / 'first-archive-legacy-done.txt').read_bytes() == (folder / 'restart-archive-legacy-done.txt').read_bytes()
    assert any(line.startswith(GROUP + '\t1\t') for line in state_files[0].read_text(encoding='utf-8-sig').splitlines())
    final = read('side-effects.json')
    assert not final['show_archived'] and final['chat_count'] == 1
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    assert 'Show archived chats' in (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: hub-archive' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('HUB ARCHIVE EVIDENCE VERIFIED: legacy keep migration, hub re-archive, same-profile restart, scoped marker and unchanged legacy file')

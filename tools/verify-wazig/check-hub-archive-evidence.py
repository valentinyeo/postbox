import re
import json
from urllib.parse import urlsplit


GROUP = 'personal:120363000000000001@g.us'
OTHER = 'personal:15550000003@s.whatsapp.net'
PLAIN_REACTED = 'personal:15550000005@s.whatsapp.net'
PLAIN_NEWER = 'personal:15550000006@s.whatsapp.net'
TELEGRAM = 'telegram:user:7001'
LEGACY = '120363000000000001@g.us\t1\t2026-10-10T10:00:00Z'


def check_plain(folder, read, before):
    assert read('plain-dms.json') == dict(chats=[PLAIN_REACTED, PLAIN_NEWER], last_message_ts={PLAIN_REACTED: '2026-10-10T11:30:00Z', PLAIN_NEWER: '2026-10-10T11:00:00Z'})
    requests = read('plain.requests.json')[before:]

    def writes(chat, archived):
        return [index for index, row in enumerate(requests) if row['wire_path'] == '/v1/wazig/archive' and
                row['status'] == 200 and row['body'] == dict(chat=chat, archived=archived)]

    reacted, newer = writes(PLAIN_REACTED, True), writes(PLAIN_NEWER, True)
    assert len(reacted) == len(newer) == 1 and reacted[0] < newer[0]
    scan = read('plain-scan.json')
    assert scan['elapsed_ms'] >= 360000
    assert scan['requests_before'] > before + newer[0]
    assert any(row['method'] == 'GET' and row['wire_path'].startswith('/v1/wazig/chats?archived=true&')
               for row in requests[scan['requests_before'] - before:]), 'archived scan never ran after both archives'
    for chat in (PLAIN_REACTED, PLAIN_NEWER):
        assert not writes(chat, False), 'plain archived chat was unarchived without a user action'
    lines = (folder / 'plain-archive-state.txt').read_text(encoding='utf-8-sig').splitlines()
    for chat in (PLAIN_REACTED, PLAIN_NEWER):
        entry, = [line.split('\t') for line in lines if line.startswith(chat + '\t')]
        assert entry[1] == '0', chat
    for name, archived, expected in [('plain-inbox', False, [OTHER]),
                                     ('plain-archived', True, [GROUP, PLAIN_REACTED, PLAIN_NEWER])]:
        state = read(f'{name}.state.json')
        rows = read(f'{name}.chats.json')
        assert state['show_archived'] == archived and state['chat_count'] == rows['total'] == len(expected)
        assert sorted(row['id'] for row in rows['chats']) == sorted(expected)
        assert all(row['archived'] == archived for row in rows['chats'])
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    assert 'hub-archive plain PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')


def check_telegram(folder, read):
    assert read('telegram-dm.json') == dict(chat=TELEGRAM, provider='telegram', account='telegram')
    requests = read('telegram.requests.json')

    def writes(chat):
        return [(index, row['body']['archived']) for index, row in enumerate(requests)
                if row['wire_path'] == '/v1/wazig/archive' and row['status'] == 200 and row['body']['chat'] == chat]

    assert not any(row['wire_path'] == '/v1/wazig/archive' and row.get('body', {}).get('chat') == TELEGRAM
                   for row in requests), 'Telegram archive and unarchive must stay local, even when hub rejects writes'
    assert [archived for _, archived in writes(PLAIN_NEWER)] == [True, True], 'plain WhatsApp must re-archive once for incoming'
    assert [archived for _, archived in writes(PLAIN_REACTED)] == [True], 'own reaction must not unarchive'
    assert [archived for _, archived in writes(OTHER)] == [True, False], 'original inbox must be restored explicitly'
    incoming, = [index for index, row in enumerate(requests) if row['wire_path'] == '/fixture/plain-incoming']
    enabled, = [index for index, row in enumerate(requests) if row['wire_path'] == '/fixture/rearchive-enable']
    assert writes(PLAIN_NEWER)[0][0] < incoming < enabled < writes(PLAIN_NEWER)[1][0]
    assert any(row['wire_path'] == '/v1/wazig/archive' and row['status'] == 409 and
               row['body'] == dict(chat=PLAIN_NEWER, archived=True) for row in requests[incoming:enabled])
    event = read('plain-incoming.json')
    assert event['chats'] == [PLAIN_NEWER, TELEGRAM] and event['archived'] is False
    for chat in event['chats']:
        before = [item for row in requests[:incoming] for item in row.get('rows', []) if item['jid'] == chat]
        assert before and event['last_message_ts'] > max(item['last_message_ts'] for item in before)
        assert any(item['jid'] == chat and item['archived'] is False and item['last_message_ts'] == event['last_message_ts']
                   for row in requests[incoming:enabled] for item in row.get('rows', [])), 'hub must actually return archived=false'
    all_chats = [GROUP, OTHER, PLAIN_REACTED, PLAIN_NEWER, TELEGRAM]
    for name, archived, expected in [
        ('telegram-only', False, [TELEGRAM]), ('telegram-empty', False, []),
        ('telegram-unarchived', False, [TELEGRAM]),
        ('telegram-bulk-empty', False, []), ('telegram-restart-empty', False, []),
        ('telegram-restart-archived', True, all_chats), ('plain-incoming-inbox', False, []),
        ('plain-incoming-archived', True, all_chats), ('plain-rearchived-inbox', False, []),
        ('plain-rearchived-archived', True, all_chats),
    ]:
        state = read(f'{name}.state.json')
        rows = read(f'{name}.chats.json')
        assert state['view'] == 'all' and state['show_archived'] == archived
        assert state['chat_count'] == rows['total'] == len(expected), name
        assert sorted(row['id'] for row in rows['chats']) == sorted(expected), name
        assert all(row['archived'] == archived for row in rows['chats']), name
        if TELEGRAM in expected:
            row, = [row for row in rows['chats'] if row['id'] == TELEGRAM]
            assert row['provider'] == 'telegram' and row['account'] == 'telegram', name
        if not expected:
            assert state['selected'] is None, name
            if name != 'plain-incoming-inbox':
                assert state['pending_archives'] == 0, name
        if name == 'telegram-only':
            assert state['selected']['id'] == TELEGRAM
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]), name
    lines = (folder / 'telegram-archive-state.txt').read_text(encoding='utf-8-sig').splitlines()
    for chat in all_chats:
        entry, = [line.split('\t') for line in lines if line.startswith(('telegram\ttelegram\t' + chat) if chat == TELEGRAM else chat + '\t')]
        assert entry[1] == ('telegram' if chat == TELEGRAM else '1' if chat == GROUP else '0'), chat
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'keys: %i' in actions and 'keys: ^a' in actions and 'keys: ^e' in actions
    assert 'hub-archive telegram-single-bulk-restart-incoming PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')


def check_hub_archive(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def capture(name, archived):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]), name
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
    telegram_restart = read('telegram-restart.json')
    assert restart['new_pid'] == telegram_restart['old_pid'] and restart['new_start'] == telegram_restart['old_start']
    assert (telegram_restart['old_pid'], telegram_restart['old_start']) != (telegram_restart['new_pid'], telegram_restart['new_start'])
    assert telegram_restart['new_pid'] == session['pid'] and telegram_restart['new_start'] == session['startTicks']
    assert all(telegram_restart[key] == session[key] for key in ('root', 'id', 'sha256'))
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
    check_plain(folder, read, len(restart_requests))
    check_telegram(folder, read)
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    for row in requests:
        if row['method'] == 'SSE':
            continue
        assert row['authorized']
        path = urlsplit(row['wire_path']).path
        assert path.startswith('/v1/wazig/') or path in ('/fixture/archive-incoming', '/fixture/plain-dms', '/fixture/telegram-dm', '/fixture/plain-incoming', '/fixture/rearchive-enable')
        if row['method'] == 'POST':
            assert path in ('/v1/wazig/archive', '/v1/wazig/mark-read', '/fixture/archive-incoming', '/fixture/plain-dms', '/fixture/telegram-dm', '/fixture/plain-incoming', '/fixture/rearchive-enable')
    state_files = list((folder / 'final-data').glob('hub-*-archive-state.txt'))
    marker_files = list((folder / 'final-data').glob('hub-*-archive-legacy-done.txt'))
    assert len(state_files) == len(marker_files) == 1
    assert state_files[0].name.replace('archive-state', 'archive-legacy-done') == marker_files[0].name
    assert marker_files[0].read_bytes() == (folder / 'first-archive-legacy-done.txt').read_bytes() == (folder / 'restart-archive-legacy-done.txt').read_bytes()
    final_lines = state_files[0].read_text(encoding='utf-8-sig').splitlines()
    assert any(line.startswith(GROUP + '\t1\t') for line in final_lines)
    assert any(line == 'telegram\ttelegram\t' + TELEGRAM for line in final_lines)
    for chat in (PLAIN_REACTED, PLAIN_NEWER):
        assert any(line.startswith(chat + '\t0\t') for line in final_lines), chat
    assert not any(line.startswith(OTHER + '\t') for line in final_lines)
    final = read('side-effects.json')
    assert not final['show_archived'] and final['chat_count'] == 1
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    assert 'Show archived chats' in (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: hub-archive' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('HUB ARCHIVE EVIDENCE VERIFIED: legacy keep migration, hub re-archive, same-profile restart, scoped marker and unchanged legacy file')

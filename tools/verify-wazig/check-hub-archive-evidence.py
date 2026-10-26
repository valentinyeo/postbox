import re
import json
from urllib.parse import parse_qs, urlsplit


GROUP = 'personal:120363000000000001@g.us'
OTHER = 'personal:15550000003@s.whatsapp.net'
PLAIN_REACTED = 'personal:15550000005@s.whatsapp.net'
PLAIN_NEWER = 'personal:15550000006@s.whatsapp.net'
TELEGRAM = 'telegram:user:7001'
LEGACY = '120363000000000001@g.us\t1\t2026-10-10T10:00:00Z'
ARCHIVE_PATHS = ('/v1/wazig/archive', '/v1/wazig/archive-batch')
FIXTURE_PATHS = ('/fixture/archive-incoming', '/fixture/plain-dms', '/fixture/plain-activity', '/fixture/telegram-dm', '/fixture/plain-incoming')


def archive_writes(requests):
    return [row for row in requests if row['method'] == 'POST' and urlsplit(row['wire_path']).path in ARCHIVE_PATHS]


def assert_no_whatsapp_archive_writes(requests, where):
    assert not archive_writes(requests), 'NO_WHATSAPP_ARCHIVE_WRITES: ' + where


def read_messages(requests, chat):
    return [index for index, row in enumerate(requests) if row['method'] == 'GET' and
            urlsplit(row['wire_path']).path == '/v1/wazig/messages' and parse_qs(urlsplit(row['wire_path']).query).get('chat') == [chat]]


def check_plain(folder, read, before):
    assert read('plain-dms.json') == dict(chats=[PLAIN_REACTED, PLAIN_NEWER], last_message_ts={PLAIN_REACTED: '2026-10-10T11:30:00Z', PLAIN_NEWER: '2026-10-10T11:00:00Z'})
    requests = read('plain.requests.json')[before:]
    assert_no_whatsapp_archive_writes(requests, 'a plain WhatsApp archive must stay in Wazig')
    activity, = [index for index, row in enumerate(requests) if row['wire_path'] == '/fixture/plain-activity']
    event = read('plain-activity.json')
    assert event['chats'] == [PLAIN_REACTED, PLAIN_NEWER] and event['archived'] is False
    for chat in (PLAIN_REACTED, PLAIN_NEWER):
        assert any(item['jid'] == chat and item['archived'] is False and item['last_message_ts'] == event['last_message_ts']
                   for row in requests[activity:] for item in row.get('rows', [])), 'the hub row time never moved'
        assert [index for index in read_messages(requests, chat) if index > activity], 'the app never read the new activity of ' + chat
    lines = (folder / 'plain-archive-state.txt').read_text(encoding='utf-8-sig').splitlines()
    for chat in (PLAIN_REACTED, PLAIN_NEWER):
        entries = [line.split('\t') for line in lines if line.startswith(chat + '\t')]
        assert len(entries) == 1, 'plain archive must persist intent'
        entry, = entries
        assert entry[1] == '0', 'plain archive must persist intent without enabling keep'
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
    assert_no_whatsapp_archive_writes(requests, 'WhatsApp, Telegram and Signal archives must stay in Wazig')
    incoming, = [index for index, row in enumerate(requests) if row['wire_path'] == '/fixture/plain-incoming']
    event = read('plain-incoming.json')
    assert event['chats'] == [PLAIN_NEWER, TELEGRAM] and event['archived'] is False
    for chat in event['chats']:
        before = [item for row in requests[:incoming] for item in row.get('rows', []) if item['jid'] == chat]
        assert before and event['last_message_ts'] > max(item['last_message_ts'] for item in before)
        assert any(item['jid'] == chat and item['archived'] is False and item['last_message_ts'] == event['last_message_ts']
                   for row in requests[incoming:] for item in row.get('rows', [])), 'the hub row time never moved'
    assert [index for index in read_messages(requests, PLAIN_NEWER) if index > incoming], 'the app never read the new message of the archived chat'
    all_chats = [GROUP, OTHER, PLAIN_REACTED, PLAIN_NEWER, TELEGRAM]
    for name, archived, expected in [
        ('telegram-only', False, [TELEGRAM]), ('telegram-empty', False, []),
        ('telegram-unarchived', False, [TELEGRAM]),
        ('telegram-bulk-empty', False, []), ('telegram-restart-empty', False, []),
        ('telegram-restart-archived', True, all_chats), ('plain-incoming-inbox', False, [PLAIN_NEWER, TELEGRAM]),
        ('plain-incoming-archived', True, [GROUP, OTHER, PLAIN_REACTED]),
        ('plain-rearchived-inbox', False, []),
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
        assert state['pending_archives'] == 0, name
        if name == 'telegram-only':
            assert state['selected']['id'] == TELEGRAM
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]), name
    lines = (folder / 'telegram-archive-state.txt').read_text(encoding='utf-8-sig').splitlines()
    for chat in all_chats:
        entries = [line.split('\t') for line in lines if line.startswith(('telegram\ttelegram\t' + chat) if chat == TELEGRAM else chat + '\t')]
        if chat in (TELEGRAM, GROUP):
            entry, = entries
            assert entry[1] == ('telegram' if chat == TELEGRAM else '1'), chat
        else:
            assert len(entries) == 1, 'plain archive must retain durable non-kept intent'
            entry, = entries
            assert entry[1] == '0', 'plain archive must retain durable non-kept intent'
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
        assert incoming, phase
        assert_no_whatsapp_archive_writes(requests, 'the kept group stays archived in Wazig only (' + phase + ')')
        assert f'hub-archive {phase} PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    check_plain(folder, read, len(restart_requests))
    check_telegram(folder, read)
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    for row in requests:
        if row['method'] == 'SSE':
            continue
        assert row['authorized']
        path = urlsplit(row['wire_path']).path
        assert path.startswith('/v1/wazig/') or path in FIXTURE_PATHS
        if row['method'] == 'POST':
            assert path == '/v1/wazig/mark-read' or path in FIXTURE_PATHS
    assert_no_whatsapp_archive_writes(requests, 'no archive request may reach the hub in the whole journey')
    state_files = list((folder / 'final-data').glob('hub-*-archive-state.txt'))
    marker_files = list((folder / 'final-data').glob('hub-*-archive-legacy-done.txt'))
    assert len(state_files) == len(marker_files) == 1
    assert state_files[0].name.replace('archive-state', 'archive-legacy-done') == marker_files[0].name
    assert marker_files[0].read_bytes() == (folder / 'first-archive-legacy-done.txt').read_bytes() == (folder / 'restart-archive-legacy-done.txt').read_bytes()
    final_lines = state_files[0].read_text(encoding='utf-8-sig').splitlines()
    assert any(line.startswith(GROUP + '\t1\t') for line in final_lines)
    telegram_final, = [line.split('\t') for line in final_lines if line.split('\t')[:3] == ['telegram', 'telegram', TELEGRAM]]
    assert len(telegram_final) == 5 and telegram_final[3] == '0' and telegram_final[4], telegram_final
    for chat in (PLAIN_REACTED, PLAIN_NEWER):
        entry, = [line.split('\t') for line in final_lines if line.startswith(chat + '\t')]
        assert entry[1] == '0', 'plain archive intent lost in final data'
    for line in final_lines:
        if line.startswith(OTHER + '\t'):
            entry = line.split('\t')
            assert entry[1] == '0' and entry[2] == '' and entry[3:] == ['returned'], 'unarchived chat must keep only the returned marker'
    final = read('side-effects.json')
    assert not final['show_archived'] and final['chat_count'] == 1
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    assert 'Show archived chats' in (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: hub-archive' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('HUB ARCHIVE EVIDENCE VERIFIED: legacy keep migration, no WhatsApp archive request, return on a new message, same-profile restart, scoped marker and unchanged legacy file')

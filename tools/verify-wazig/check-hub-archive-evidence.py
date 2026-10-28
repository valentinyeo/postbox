import json
from urllib.parse import urlsplit


GROUP = 'personal:120363000000000001@g.us'
OTHER = 'personal:15550000003@s.whatsapp.net'
PLAIN_REACTED = 'personal:15550000005@s.whatsapp.net'
PLAIN_NEWER = 'personal:15550000006@s.whatsapp.net'
TELEGRAM = 'telegram:user:7001'
ARCHIVE_PATHS = ('/v1/wazig/archive', '/v1/wazig/archive-batch')


def archive_writes(requests):
    return [row for row in requests if row['method'] == 'POST' and urlsplit(row['wire_path']).path in ARCHIVE_PATHS]


def check_provider_requests(requests):
    writes = archive_writes(requests)
    actions = []
    for row in writes:
        assert row['status'] == 200, 'ARCHIVE_ACK_REQUIRED'
        chats = [row['body']['chat']] if 'chat' in row['body'] else [chat['chat'] for chat in row['body']['chats']]
        for chat in chats:
            assert chat not in (GROUP, TELEGRAM) and '@' in chat, 'KEPT_AND_OTHER_PROVIDERS_STAY_LOCAL'
            actions.append((chat, row['body']['archived']))
    assert actions.count((PLAIN_REACTED, True)) == 4, 'ARCHIVE_AND_MIGRATION_REQUIRED'
    assert actions.count((PLAIN_REACTED, False)) == 2, 'PROVIDER_UNARCHIVE_REQUIRED'
    assert actions.count((PLAIN_NEWER, True)) == 2, 'INCOMING_ARCHIVE_REQUIRED'
    assert actions.count((OTHER, True)) == 1
    incoming = next(index for index, row in enumerate(requests) if row['wire_path'] == '/fixture/plain-incoming')
    phone = next(index for index, row in enumerate(requests) if row['wire_path'] == '/fixture/phone-unarchive')
    assert phone < incoming
    assert any(item['jid'] == PLAIN_REACTED and item['archived'] is False for row in requests[phone:incoming] for item in row.get('rows', [])), 'PHONE_UNARCHIVE_REQUIRED'
    assert any(item['jid'] == PLAIN_NEWER and item['archived'] is False for row in requests[incoming:] for item in row.get('rows', [])), 'PROVIDER_INCOMING_REQUIRED'
    return actions


def check_hub_archive(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'hub-archive' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='hub-archive', status='passed')
    assert not (folder / 'failure.txt').exists()
    requests = read('provider.requests.json')
    check_provider_requests(requests)
    for name, archived, ids in [
        ('provider-archived', True, [GROUP, PLAIN_REACTED]),
        ('phone-unarchived', False, [OTHER, PLAIN_REACTED, PLAIN_NEWER]),
        ('provider-incoming', False, [OTHER, PLAIN_REACTED, PLAIN_NEWER, TELEGRAM]),
        ('kept-incoming', True, [GROUP]),
        ('migrated-archived', True, [GROUP, OTHER, PLAIN_REACTED, PLAIN_NEWER, TELEGRAM]),
    ]:
        state, rows = read(f'{name}.state.json'), read(f'{name}.chats.json')
        assert state['show_archived'] == archived and state['pending_archives'] == 0, name
        assert state['chat_count'] == rows['total'] == len(ids), name
        assert sorted(row['id'] for row in rows['chats']) == sorted(ids), name
        assert all(row['archived'] == archived for row in rows['chats']), name
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
    before = (folder / 'migration-before.txt').read_text(encoding='utf-8-sig')
    after = (folder / 'migration-after.txt').read_text(encoding='utf-8-sig')
    assert PLAIN_REACTED + '\t0\t' in before
    assert PLAIN_REACTED not in after, 'MIGRATION_ACK_REMOVES_LOCAL_ENTRY'
    assert GROUP + '\t1\t' in after and 'telegram\ttelegram\t' + TELEGRAM in after
    assert (folder / 'legacy-archive-state.txt').read_bytes() == (folder / 'final-data/archive-state.txt').read_bytes()
    state_files = list((folder / 'final-data').glob('hub-*-archive-state.txt'))
    assert len(state_files) == 1 and state_files[0].read_text(encoding='utf-8-sig') == after
    restart = read('restart.json')
    assert (restart['old_pid'], restart['old_start']) != (restart['new_pid'], restart['new_start'])
    assert restart['new_pid'] == session['pid'] and restart['new_start'] == session['startTicks']
    for key in ('root', 'id', 'sha256'):
        assert restart[key] == session[key]
    unknown = (folder / 'unknown-ids-archive-state.txt').read_text(encoding='utf-8-sig')
    assert all(chat not in unknown for chat in ('telegram:user:99999', 'signal:ghost', '99999\t'))
    notifications = read('notifications.json')
    assert [row['phase'] for row in notifications] == ['archived', 'inbox']
    launch = (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8-sig')
    for row in notifications:
        phase, message = row['phase'], row['id']
        assert 0 <= row['elapsed_seconds'] <= 10
        assert launch.count(f'notification: accepted chat=business:notification-{phase}@s.whatsapp.net message={message}') == 1
        image = (folder / f'notification-{phase}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        chats = read(f'notification-{phase}.chats.json')['chats']
        assert any(chat['id'] == f'business:notification-{phase}@s.whatsapp.net' and chat['archived'] is False for chat in chats)
    notification_requests = read('notification.requests.json')
    assert any(row.get('body') == dict(chat='business:notification-archived@s.whatsapp.net', archived=False)
               and row['status'] == 200 for row in notification_requests)
    final = read('side-effects.json')
    assert final['chat_count'] == final['pending_sends'] == final['pending_archives'] == 0
    assert not final['show_archived'] and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert 'JOURNEY PASSED: hub-archive' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('HUB ARCHIVE EVIDENCE VERIFIED: provider archive/unarchive, phone unarchive, incoming, kept, migration and restart')

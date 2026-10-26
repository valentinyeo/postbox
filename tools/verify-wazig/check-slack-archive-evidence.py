import re
import json
from datetime import datetime
from urllib.parse import urlsplit


def check_slack_archive(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='slack-archive', status='passed')
    assert not (folder / 'failure.txt').exists()
    baseline = read('before.state.json')['selected']
    key = tuple(baseline[field] for field in ['provider', 'account', 'id'])
    assert key[0] == 'slack' and key[2] == 'fixture-alpha'
    stages = dict(before=(False, 2, 0), archived=(True, 1, 0), rearchived=(True, 1, 0),
                  restart=(True, 1, 0), unarchived=(False, 2, None),
                  **{'incoming-inbox': (False, 2, 1), 'incoming-archive-empty': (True, 0, None),
                     'unarchived-archive': (True, 0, None)})
    for stage in ['archived-inbox', 'before-incoming', 'rearchived-inbox', 'restart-inbox']:
        stages[stage] = (False, 1, None)
    for stage, (archived, count, unread) in stages.items():
        state = read(f'{stage}.state.json')
        rows = read(f'{stage}.chats.json')
        assert state['show_archived'] == rows['archived'] == archived, stage
        assert state['chat_count'] == rows['total'] == len(rows['chats']) == count, stage
        assert state['pending_archives'] == state['pending_sends'] == 0, stage
        assert all(row['provider'] == 'slack' for row in rows['chats']), stage
        target = [row for row in rows['chats'] if tuple(row[field] for field in ['provider', 'account', 'id']) == key]
        present = stage in ['before', 'archived', 'incoming-inbox', 'rearchived', 'restart', 'unarchived']
        assert len(target) == int(present), stage
        if present:
            assert target[0]['archived'] == archived, stage
            assert target[0]['archive_label'] == ('Archived' if archived else ''), stage
            if unread is not None:
                assert target[0]['unread_count'] == unread, stage
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, stage
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]), stage
    restart = read('restart.json')
    assert restart['old_pid'] != restart['new_pid'] == session['pid']
    assert restart['old_start'] != restart['new_start'] == session['startTicks']
    assert all(restart[field] == session[field] for field in ['root', 'id', 'sha256'])
    archive_stamps = []
    for name, stage in [('slack-archive-state.txt', 'archived'), ('slack-rearchive-state.txt', 'rearchived')]:
        entries = [line.split('\t') for line in (folder / name).read_text(encoding='utf-8-sig').splitlines()]
        assert entries and all(len(entry) == 5 for entry in entries), name
        target = [entry for entry in entries if tuple(entry[:3]) == key]
        assert len(target) == 1 and target[0][3] == '0' and target[0][4], name
        stamp = target[0][4]
        rows = read(f'{stage}.chats.json')['chats']
        assert stamp == next(row['last_message_time'] for row in rows if tuple(row[field] for field in ['provider', 'account', 'id']) == key), name
        archive_stamps.append(datetime.fromisoformat(stamp.replace('Z', '+00:00')))
    assert archive_stamps[1] > archive_stamps[0]
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert requests and all(row['method'] and row['path'] and row['wire_path'] for row in requests)
    assert not any('archive' in urlsplit(row['wire_path']).path or 'archive' in urlsplit(row['path']).path for row in requests)
    assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
    deliveries = [row for row in requests if row['method'] == 'POST' and row['path'] == '/fixture/live']
    assert [row['incoming'] for row in deliveries] == [1]
    assert any(row['method'] == 'SSE' and row.get('kind') == 'msg' and row.get('incoming') == 1 and
               row.get('chat') == key[2] and datetime.fromisoformat(row['ts'].replace('Z', '+00:00')) > archive_stamps[0]
               for row in requests)
    refreshes = [row for row in requests if row['method'] == 'GET' and urlsplit(row['path']).path == '/v1/wazig/chats' and
                 row.get('incoming') == 1 and not row.get('archived', True)]
    assert refreshes
    assert any(any(chat['jid'] == key[2] and chat['archived'] is False and chat['unread_count'] == 1 and
                   datetime.fromisoformat(chat['last_message_ts'].replace('Z', '+00:00')) > archive_stamps[0]
                   for chat in row['rows']) for row in refreshes)
    final = read('side-effects.json')
    assert final['chat_count'] == 2 and not final['show_archived']
    assert final['pending_sends'] == final['pending_archives'] == 0
    assert final['sync'] == 'stopped' and not final['slack_connected']
    assert all(final[field] for field in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert actions.count('keys: ^e\n') == 3
    for keys in ['^2', '^+{HOME}', 'Show archived chats', 'Show inbox chats', 'Refresh']:
        assert f'keys: {keys}' in actions
    assert 'slack-archive local-archive-incoming-restart-unarchive PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: slack-archive' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: local Slack archive, automatic inbox return on one newer delivery, ordinary rearchive, same-profile restart, unarchive and no hub archive requests')

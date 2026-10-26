import json
import re
import runpy
from pathlib import Path
from urllib.parse import urlsplit


def check_show_archived(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def capture(name, enabled, count, archived, view=None):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        tree = (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig')
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v0\.0\.526', tree.splitlines()[0]), name
        assert '1146 |' not in tree and 'Show archived:' not in tree, name
        state = read(f'{name}.state.json')
        rows = read(f'{name}.chats.json')['chats']
        assert state['include_archived'] == enabled and not state['show_archived'], name
        assert state['chat_count'] == len(rows) == count and sum(row['archived'] for row in rows) == archived, name
        assert len({(row['provider'], row['account'], row['id']) for row in rows}) == count, name
        assert all(row['archive_label'] in ('Archived', 'Kept archived') for row in rows if row['archived']), name
        if view is None:
            assert state['current_view']['inbox'] and all(row['unread'] for row in rows), name
            assert {row['provider'] for row in rows} == {'whatsapp', 'slack', 'signal', 'telegram'}, name
        else:
            assert not state['current_view']['inbox'] and state['current_view']['account'] == view['account'], name
            assert all(row['provider'] == view['provider'] and row['view_account'] == view['account'] for row in rows), name
        stamps = [row['last_message_time'] for row in rows]
        assert stamps == sorted(stamps, reverse=True), name
        return state, rows

    session = read('session.json')
    assert session['feature'] == 'show-archived' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='show-archived', status='passed')
    assert not (folder / 'failure.txt').exists()
    views = read('show-archived-views.json')
    assert len(views) == 5 and [view['provider'] for view in views].count('whatsapp') == 2
    assert {view['provider'] for view in views} == {'whatsapp', 'slack', 'telegram', 'signal'}
    assert len({(view['provider'], view['account']) for view in views}) == 5
    off, _ = capture('inbox-off', False, 5, 0)
    on, _ = capture('inbox-on', True, 10, 5)
    assert off['unread_only'] and on['unread_only']
    capture('inbox-warm-off', False, 5, 0)
    capture('inbox-warm-on', True, 10, 5)
    launch = (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8-sig')
    toggle_lines = [line for line in launch.splitlines() if ' archive-toggle:' in line]
    timing_names = [('inbox-on', True), ('inbox-warm-off', False), ('inbox-warm-on', True)]
    for position in range(1, 6):
        timing_names.append((f'view-{position}-on', True))
        if position == 1:
            timing_names.extend([('palette-off', False), ('palette-on', True)])
        else:
            timing_names.append((f'view-{position}-disabled', False))
    previous_index = -1
    for name, enabled in timing_names:
        timing = read(f'{name}.toggle.json')
        assert timing['name'] == name and previous_index < timing['index'] < len(toggle_lines), name
        previous_index = timing['index']
        assert timing['line'] == toggle_lines[timing['index']], name
        match = re.fullmatch(r'\d+ archive-toggle: include=(true|false) rebuilds=(\d+) rebuild_ms=(\d+) fetches=(\d+) fetch_ms=(\d+) first_paint_ms=(\d+) paints=(\d+)', timing['line'])
        assert match and (match[1] == 'true') == enabled, name
        rebuilds, rebuild_ms, fetches, fetch_ms, first_paint_ms, paints = map(int, match.groups()[1:])
        assert first_paint_ms >= rebuild_ms and paints >= 1, name
        if fetches > 0:
            assert 1 <= rebuilds <= 2, name
        else:
            assert rebuilds == 1 and fetch_ms == 0 and paints == 1, name
    runpy.run_path(str(Path(__file__).with_name('check-archive-presentation.py')))['check_presentation'](folder)
    for position, view in enumerate(views, 1):
        capture(f'view-{position}-off', False, 2, 0, view)
        capture(f'view-{position}-on', True, 4, 2, view)
        archived_state, archived_rows = capture(f'view-{position}-archived', True, 4, 3, view)
        restored, restored_rows = capture(f'view-{position}-unarchived', True, 4, 2, view)
        assert archived_state['selected']['id'] == restored['selected']['id']
        assert archived_state['selected']['archived'] and not restored['selected']['archived']
        changed = [row['id'] for row in archived_rows if row['archived'] and not next(other['archived'] for other in restored_rows if other['id'] == row['id'])]
        assert changed == [restored['selected']['id']]
        if position != 1:
            capture(f'view-{position}-disabled', False, 2, 0, view)
    capture('palette-off', False, 2, 0, views[0])
    capture('palette-on', True, 4, 2, views[0])
    capture('account-one-kept', True, 4, 2, views[0])
    capture('account-two-off', False, 2, 0, views[1])
    for name in ('inbox-kept', 'inbox-return', 'restart-inbox', 'after'):
        capture(name, True, 10, 5)
    capture('restart-one', True, 4, 2, views[0])
    capture('restart-two', False, 2, 0, views[1])
    only = read('archived-only.state.json')
    only_rows = read('archived-only.chats.json')['chats']
    assert only['show_archived'] and only['chat_count'] == len(only_rows) == 10
    assert all(row['archived'] for row in only_rows)
    restart = read('show-archived-restart.json')
    assert (restart['old_pid'], restart['old_start']) != (restart['new_pid'], restart['new_start'])
    assert restart['new_pid'] == session['pid'] and restart['new_start'] == session['startTicks']
    assert all(restart[key] == session[key] for key in ('root', 'id', 'sha256'))
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert any(row['method'] == 'GET' and 'archived=true' in row['wire_path'] and row['status'] == 200 for row in requests)
    writes = [row for row in requests if row['method'] == 'POST' and urlsplit(row['wire_path']).path == '/v1/wazig/archive']
    expected = {row['id'] for number in (1, 2) for row in read(f'view-{number}-off.chats.json')['chats'] if row['name'].endswith('row 0')}
    assert len(writes) == 4 and {row['body']['chat'] for row in writes} == expected
    assert sum(row['body']['archived'] for row in writes) == 2
    assert all(row['status'] == 200 for row in writes)
    assert not [row for row in requests if row['method'] == 'POST' and urlsplit(row['wire_path']).path == '/v1/wazig/archive-batch']
    for row in requests:
        if row['method'] != 'SSE':
            assert row['authorized'] and row['status'] in (200, 404)
            if row['method'] == 'POST':
                assert urlsplit(row['wire_path']).path in ('/v1/wazig/mark-read', '/v1/wazig/archive')
    preferences = (folder / 'preferences.txt').read_text(encoding='utf-8-sig')
    assert 'ShowArchived' in preferences
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for key in ('%i', '^2', '^3', '^4', '^5', '^6', '%a', '^e', '^k', '{ENTER}'):
        assert 'keys: ' + key in actions, key
    assert 'show-archived show-archived-all PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['include_archived'] and not final['show_archived'] and final['current_view']['inbox']
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert 'JOURNEY PASSED: show-archived' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('SHOW ARCHIVED EVIDENCE VERIFIED: marked unread inbox, independent accounts, mixed actions, archive presentation and restart')

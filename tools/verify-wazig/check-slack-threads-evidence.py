import re
import json


def check_threads(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    parent = '1740000000.000100'
    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='slack-threads', status='passed')
    assert not (folder / 'failure.txt').exists()
    on = read('threads-on.json')
    panel = read('thread-panel.json')
    off = read('threads-off.json')
    restarted = read('threads-restart.json')
    assert on['parent_id'] == parent and on['parent_reply_line'] == '30 replies' and on['inline_replies'] == 0
    assert on['threads_option'] == 'on' and not on['open']
    assert panel['parent_id'] == parent and panel['open'] and panel['replies'] == 30
    assert off['inline_replies'] == 30 and off['parent_reply_line'] == '' and off['threads_option'] == 'off' and not off['open']
    assert restarted['restarted'] and restarted['threads_option'] == 'off' and restarted['inline_replies'] == 30
    restart = read('restart.json')
    assert restart['old_start'] != restart['new_start'] and restart['new_pid'] == session['pid']
    assert restart['root'] == session['root'] and restart['id'] == session['id'] and restart['sha256'] == session['sha256']
    for stage in ['threads-on', 'thread-panel', 'thread-reply', 'threads-off', 'threads-restart']:
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
        state = read(f'{stage}.state.json')
        assert state['selected']['provider'] == 'slack' and state['selected']['id'] == 'slack:fixture-threads:channel'
        if stage != 'thread-reply':
            measured = read(f'{stage}.json')
            assert all(state['slack_threads'][key] == value for key, value in measured.items() if key != 'restarted')
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    sends = [row for row in requests if row['method'] == 'POST' and row['wire_path'].endswith('/send')]
    assert sends and all(row['authorized'] and row['status'] == 200 and row['body']['chat'] == 'slack:fixture-threads:channel'
                         and row['body']['text'] == 'Synthetic thread reply'
                         and (row['body'].get('reply_to') == parent or row['body'].get('thread_ts') == parent) for row in sends)
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for key in ['^2', '^{UP}', '{ENTER}', 'Synthetic thread reply', '{ESC}', '^k', 'Slack threads like Slack for this account', 'Quit Messages']:
        assert f'keys: {key}' in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: slack-threads' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: Slack threads grouping, panel, scoped send, account option and restart')

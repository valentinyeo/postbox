import re
import json


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))


def check_thread_broadcast(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    parent = '1740000000.000100'
    chat = 'slack:fixture-threads:channel'
    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='slack-thread-broadcast', status='passed')
    assert not (folder / 'failure.txt').exists()
    unticked = read('broadcast-unticked.json')
    ticked = read('broadcast-ticked.json')
    reset = read('broadcast-reset.json')
    for state in (unticked, ticked, reset):
        assert state['parent_id'] == parent and state['open'] and state['replies'] >= 30
        assert state['broadcast_shown'] is True and state['broadcast_label'] == 'Also send to Verification Threads'
    assert unticked['replies'] == 30
    assert unticked['broadcast_checked'] is False
    assert ticked['broadcast_checked'] is True
    assert reset['broadcast_checked'] is False
    for stage in ['broadcast-unticked', 'broadcast-ticked', 'broadcast-reset', 'broadcast-thread-result', 'broadcast-chat-result']:
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
        state = read(f'{stage}.state.json')
        assert state['selected']['provider'] == 'slack' and state['selected']['id'] == chat
        threads = state['slack_threads']
        assert threads['broadcast_shown'] is (stage != 'broadcast-chat-result')
        if stage in ('broadcast-unticked', 'broadcast-ticked', 'broadcast-reset'):
            measured = read(f'{stage}.json')
            assert all(threads[key] == value for key, value in measured.items())
    assert (folder / 'broadcast-unticked.png').read_bytes() != (folder / 'broadcast-ticked.png').read_bytes()
    messages = read('broadcast-messages.json')
    messages = messages if isinstance(messages, list) else [messages]
    assert messages and all(row['text'] == 'Synthetic broadcast reply' for row in messages)
    quotes = [row['quoted_msg_id'] for row in messages]
    assert parent in quotes and '' in quotes and set(quotes) <= {'', parent}
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    sends = [row for row in requests if row['method'] == 'POST' and row['wire_path'].endswith('/send')]
    assert len(sends) == 2 and all(row['authorized'] and row['status'] == 200 and row['body']['chat'] == chat and row['body']['reply_to'] == parent for row in sends)
    plain = [row for row in sends if row['body']['text'] == 'Synthetic plain thread reply']
    broadcast = [row for row in sends if row['body']['text'] == 'Synthetic broadcast reply']
    assert len(plain) == len(broadcast) == 1
    assert 'reply_broadcast' not in plain[0]['body']
    assert broadcast[0]['body']['reply_broadcast'] is True
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for key in ['%2', '^{UP}', '{ENTER}', '{TAB}', 'Synthetic plain thread reply', 'Synthetic broadcast reply', '{ESC}', '^k', 'Refresh']:
        assert f'keys: {key}' in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: slack-thread-broadcast' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: Slack thread broadcast checkbox, reset, hub flag and chat result')

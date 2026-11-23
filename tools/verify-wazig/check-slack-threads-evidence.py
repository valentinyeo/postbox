import re
import json


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))


def check_threads(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    parent = '1740000000.000100'
    fresh_parent = '1750000000.000100'
    stage_chats = {
        'threads-on': 'slack:fixture-threads:channel',
        'thread-panel': 'slack:fixture-threads:channel',
        'thread-reply': 'slack:fixture-threads:channel',
        'threads-off': 'slack:fixture-threads:channel',
        'threads-restart': 'slack:fixture-threads:channel',
        'chat-whatsapp-style': 'slack:fixture-threads:channel',
        'chat-slack-style': 'slack:fixture-threads:channel',
        'fresh-slack-default': 'fixture-fresh',
        'whatsapp-default': 'fixture-whatsapp',
    }
    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='slack-threads', status='passed')
    assert not (folder / 'failure.txt').exists()
    on = read('threads-on.json')
    panel = read('thread-panel.json')
    off = read('threads-off.json')
    restarted = read('threads-restart.json')
    chat_whatsapp = read('chat-whatsapp-style.json')
    chat_slack = read('chat-slack-style.json')
    fresh = read('fresh-slack-default.json')
    legacy = read('legacy-account-threads.json')
    assert on['parent_id'] == parent and on['parent_reply_line'] == '30 replies' and on['inline_replies'] == 0 and on['loose_replies'] == 0
    assert on['threads_option'] == 'on' and not on['open']
    assert panel['parent_id'] == parent and panel['open'] and panel['replies'] == 30
    assert off['inline_replies'] == 32 and off['loose_replies'] == 32 and off['parent_reply_line'] == '' and off['threads_option'] == 'off' and not off['open']
    assert restarted['restarted'] and restarted['threads_option'] == 'off' and restarted['inline_replies'] == 32
    assert chat_whatsapp['replies_style'] == 'whatsapp' and chat_whatsapp['threads_option'] == 'off'
    assert chat_whatsapp['inline_replies'] == 32 and chat_whatsapp['loose_replies'] == 32 and chat_whatsapp['parent_reply_line'] == ''
    assert chat_slack['replies_style'] == 'slack' and chat_slack['threads_option'] == 'on'
    assert chat_slack['inline_replies'] == 0 and chat_slack['loose_replies'] == 0 and chat_slack['parent_reply_line'] == '30 replies'
    assert legacy == dict(account='fixture-fresh', key='SlackThreads-fixture-fresh', value='off')
    assert fresh['replies_style'] == 'slack' and fresh['threads_option'] == 'on' and not fresh['open']
    assert fresh['parent_id'] == fresh_parent and fresh['parent_reply_line'] == '2 replies'
    assert fresh['inline_replies'] == 0 and fresh['loose_replies'] == 0
    restart = read('restart.json')
    assert restart['old_start'] != restart['new_start'] and restart['new_pid'] == session['pid']
    assert restart['root'] == session['root'] and restart['id'] == session['id'] and restart['sha256'] == session['sha256']
    whatsapp = read('whatsapp-default.state.json')
    assert whatsapp['selected']['provider'] == 'whatsapp' and whatsapp['selected']['id'] == 'fixture-whatsapp'
    assert 'slack_threads' not in whatsapp
    replies = [row for row in read('whatsapp-default.messages.json')['messages'] if row['id'] == 'WA-REPLY']
    assert len(replies) == 1 and replies[0]['quoted_msg_id'] == 'WA-ORIGINAL'
    assert replies[0]['quote_line'][2] > replies[0]['quote_line'][0]
    for stage, chat in stage_chats.items():
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
        state = read(f'{stage}.state.json')
        assert state['selected']['id'] == chat
        if stage == 'whatsapp-default':
            assert state['selected']['provider'] == 'whatsapp' and 'slack_threads' not in state
        else:
            assert state['selected']['provider'] == 'slack'
            if stage != 'thread-reply':
                measured = read(f'{stage}.json')
                assert all(state['slack_threads'][key] == value for key, value in measured.items() if key != 'restarted')
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    sends = [row for row in requests if row['method'] == 'POST' and row['wire_path'].endswith('/send')]
    assert sends and all(row['authorized'] and row['status'] == 200 and row['body']['chat'] == 'slack:fixture-threads:channel'
                         and row['body']['text'] == 'Synthetic thread reply'
                         and (row['body'].get('reply_to') == parent or row['body'].get('thread_ts') == parent) for row in sends)
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for key in ['^f', 'Verification Threads', 'Verification Fresh', 'Verification WhatsApp', '^{UP}', '{ENTER}', 'Synthetic thread reply', '{ESC}', '^k', 'Slack threads like Slack for this account', 'Replies: WhatsApp style', 'Replies: Slack style', 'Quit Postbox']:
        assert f'keys: {key}' in actions
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: slack-threads' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: Slack threads grouping, panel, scoped send, account option, per-chat replies style, a default-on fresh Slack chat, a WhatsApp chat left in WhatsApp style and a restart')

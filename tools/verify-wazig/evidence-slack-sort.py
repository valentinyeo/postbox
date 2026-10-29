from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
def read(name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))

assert session['sha256'] and session['commit']
assert read('result.json') == dict(feature='slack-sort', status='passed')
assert not (folder / 'failure.txt').exists()
orders = {
    'before': ['fixture-beta', 'fixture-gamma', 'fixture-alpha', 'fixture-unknown'],
    'after': ['fixture-alpha', 'fixture-beta', 'fixture-gamma', 'fixture-unknown'],
    'sent': ['fixture-gamma', 'fixture-alpha', 'fixture-beta', 'fixture-unknown'],
}
proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
for stage, expected in orders.items():
    rows = read(f'{stage}.chats.json')
    assert rows['total'] == 4 and [row['id'] for row in rows['chats']] == expected
    assert all(row['provider'] == 'slack' for row in rows['chats'])
    times = [row['last_message_time'] for row in rows['chats']]
    assert times[-1] == '' and all(times[:3]) and times[:3] == sorted(times[:3], reverse=True)
    walk = read(f'{stage}.navigation.json')
    offset = expected.index(walk[0])
    assert walk == expected[offset:] + expected[:offset]
    assert f'slack-sort {stage}-last-message-order PASS' in proof
    image = (folder / f'{stage}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + re.escape(session.get('expected_version', '0.0.526')), (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
    assert read(f'{stage}.state.json')['view'] == 'slack'
initial_times = {row['id']: row['last_message_time'] for row in read('before.chats.json')['chats']}
assert initial_times['fixture-alpha'] < read('after.chats.json')['chats'][0]['last_message_time']
assert initial_times['fixture-gamma'] < read('sent.chats.json')['chats'][0]['last_message_time']
assert read('after.state.json')['selected']['id'] == 'fixture-gamma'
assert read('sent.state.json')['selected']['id'] == 'fixture-gamma'
requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
assert any(row['method'] == 'SSE' and row['kind'] == 'msg' for row in requests)
assert any(row['wire_path'] == '/fixture/live' and row['status'] == 200 for row in requests)
sends = [row for row in requests if row['wire_path'] == '/v1/wazig/send']
slack_sends = [row for row in sends if row['body']['chat'] == 'fixture-gamma']
assert slack_sends and all(row['status'] == 200 and row['body']['chat'] == 'fixture-gamma' and row['body']['text'] == 'Synthetic Slack outgoing' for row in slack_sends)
final = read('side-effects.json')
assert final['chat_count'] == 4 and final['pending_sends'] == final['pending_archives'] == 0
assert final['sync'] == 'stopped' and not final['slack_connected']
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
for keys in ['^2', '^{TAB}', '^+{TAB}', 'Compose message', 'Synthetic Slack outgoing', '{ENTER}']:
    assert f'keys: {keys}' in actions
assert 'keys: ^3' in actions
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
assert 'JOURNEY PASSED: slack-sort' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: Slack last message ordering, unknown last, incoming and sent promotion with keyboard order and isolation')
wa_orders = {
    'wa-before': ['wa-beta', 'wa-gamma', 'wa-alpha', 'wa-unknown'],
    'wa-sent': ['wa-gamma', 'wa-beta', 'wa-alpha', 'wa-unknown'],
    'wa-stale': ['wa-gamma', 'wa-beta', 'wa-alpha', 'wa-unknown'],
    'wa-phone': ['wa-alpha', 'wa-gamma', 'wa-beta', 'wa-unknown'],
}
for stage, expected in wa_orders.items():
    rows = read(f'{stage}.chats.json')['chats']
    assert [row['id'] for row in rows] == expected
    assert all(row['provider'] == 'whatsapp' for row in rows)
    assert f'slack-sort {stage}-last-message-order PASS' in proof
    image = (folder / f'{stage}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
assert read('wa-sent.chats.json')['chats'][0]['last_message_time'] == read('wa-stale.chats.json')['chats'][0]['last_message_time']
assert read('stale-provider.json')['wa-gamma'] < read('wa-stale.chats.json')['chats'][0]['last_message_time']
assert any(row['status'] == 200 and row['body']['chat'] == 'wa-gamma' and row['body']['text'] == 'https://example.com/sent-order' for row in sends)
assert any(row['wire_path'] == '/fixture/phone' and row['status'] == 200 for row in requests)
print('SENT_ORDER_VERIFIED: WhatsApp sends survive stale refresh and yield only to newer phone activity')
raise SystemExit(0)

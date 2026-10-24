from pathlib import Path
import json
import re
import sys
from urllib.parse import parse_qs, urlsplit

folder = Path(sys.argv[1])


def read(name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))


def ids(shown):
    return [row['id'] for row in shown['messages']]


session = read('session.json')
feature = 'whatsapp-history-backfill'
assert session['feature'] == feature and session['sha256'] and session['commit']
assert not (folder / 'failure.txt').exists()
assert read('result.json') == dict(feature=feature, status='passed')
requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
chat = 'personal:15550000681@s.whatsapp.net'
current = [f'HB-{index:03}' for index in range(1, 66)]
older = [f'HB-OLD-{index:03}' for index in range(1, 69)]
initial = read('initial.messages.json')
assert initial['chat']['id'] == chat and ids(initial) == current
assert not any(row['method'] == 'POST' and row['wire_path'] == '/v1/wazig/history-backfill' for row in read('initial.requests.json'))
notices = {
    'in-progress': (409, 'Older history fetch in progress; try again later'),
    'timeout': (504, 'Older history timed out; not completed, retry Fetch older history'),
    'unavailable': (503, 'Older history unavailable; not completed, retry Fetch older history'),
}
for stage, (status, notice) in notices.items():
    assert (folder / f'{stage}.status.txt').read_text(encoding='utf-8-sig').strip() == notice
    assert ids(read(f'{stage}.messages.json')) == current
    snapshot = read(f'{stage}.requests.json')
    posts = [row for row in snapshot if row['wire_path'] == '/v1/wazig/history-backfill']
    assert posts[-1]['status'] == status and posts[-1]['body'] == {'chat': chat}
    pages = [row for row in snapshot if row.get('history_before') and row.get('history_chat') == chat]
    assert pages and len(pages) == len([row for row in read('initial.requests.json') if row.get('history_before') and row.get('history_chat') == chat])
recovered = read('recovered.messages.json')
expected = older + current + ['HB-LIVE']
assert recovered['chat'] == initial['chat']
assert ids(recovered) == expected and len(set(ids(recovered))) == len(expected)
assert len([row for row in recovered['messages'] if row['id'] != 'HB-LIVE']) == 133
assert all(row['text'] and row['text'] != '(message)' for row in recovered['messages'])
posts = [row for row in requests if row['method'] == 'POST' and row['wire_path'] == '/v1/wazig/history-backfill']
assert all(row['body'] == {'chat': chat} for row in posts)
assert [row['status'] for row in posts] == [409, 504, 503, 0, 200]
assert posts[-2]['history_phase'] == 'waiting-for-live'
start = requests.index(posts[-2])
finish = requests.index(posts[-1])
arrivals = [index for index, row in enumerate(requests) if row.get('during_recovery')]
assert len(arrivals) == 1 and start < arrivals[0] < finish
assert any(row['method'] == 'SSE' and row['kind'] == 'msg' and row['chat'] == chat for row in requests)
reads = [row for row in requests if row.get('history_chat') == chat]
assert reads and reads[0]['history_count'] == 75 and not reads[0]['history_before']
assert all(parse_qs(urlsplit(row['wire_path']).query)['limit'] == ['80'] for row in reads)
assert any(row['history_before'] and row['history_count'] == 0 and not row['history_released'] for row in reads)
assert not any(row['history_released'] for row in requests[:finish] if 'history_released' in row)
released = [row for row in requests[finish + 1:] if row.get('history_chat') == chat and row.get('history_released')]
assert any(row['history_before'] and row['history_count'] > 0 for row in released)
assert any(row['history_before'] and row['history_count'] == 0 for row in released)
assert {message_id for row in released for message_id in row['history_ids'] if message_id.startswith('HB-OLD-')} == set(older)
for row in reads:
    if row['history_before']:
        assert re.fullmatch(r'HB-(?:OLD-)?\d{3}:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', row['history_before'])
for name, key, message_id in [('Verification Other', 'personal:15550000682@s.whatsapp.net', 'OTHER'),
                              ('Verification Business', 'business:15550000681@s.whatsapp.net', 'BUSINESS')]:
    before = read(f'{name}-before.messages.json')
    after = read(f'{name}-after.messages.json')
    assert before['chat']['id'] == after['chat']['id'] == key
    assert before['messages'] == after['messages'] and ids(after) == [message_id]
    foreign_reads = [row for row in requests if row.get('history_chat') == key]
    assert foreign_reads and all(row['history_ids'] == [message_id] for row in foreign_reads)
assert all(row['wire_path'] in ('/v1/wazig/history-backfill', '/v1/wazig/mark-read', '/fixture/live') for row in requests if row['method'] == 'POST')
assert all('account=' not in row['wire_path'] for row in requests)
proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
for gate in ['stored-boundary', 'in-progress-retryable', 'timeout-retryable', 'unavailable-retryable',
             'scoped-recovery-live-merge', 'chat-account-isolation']:
    assert f'{feature} {gate} PASS' in proof
for stage in ['initial', *notices, 'backfill-command', 'recovering', 'recovered',
              'Verification Other-after', 'Verification Business-after']:
    assert (folder / f'{stage}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert read(f'{stage}.state.json')['pending_sends'] == 0
    assert (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').startswith('MessagesZig | ')
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
assert 'keys: Fetch older history' in actions and 'keys: {PGUP}' in actions
final = read('side-effects.json')
assert final['chat_count'] == 3 and final['pending_sends'] == final['pending_archives'] == 0
assert final['sync'] == 'stopped'
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert f'JOURNEY PASSED: {feature}' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: 65 stored + 68 recovered = 133 history IDs, live arrival, retry notices and chat/account isolation')

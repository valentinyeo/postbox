import json
from pathlib import Path
import re

from real_size_seed import ARCHIVED, BUSY, CHATS, COUNTS, GROUP, INBOX, MANIFEST, MESSAGES, SEARCH, VOICE


STEPS = ('inbox', 'list-scroll', 'busy', 'busy-top', 'search', 'voice', 'group', 'archived', 'inbox-return')
MINIMUMS = dict(chats=300, messages=6000, voice=50, images=100, groups=30)


def check_size(folder):
    log = (folder / 'run.log').read_text(encoding='utf-8-sig')
    for key, minimum in MINIMUMS.items():
        assert COUNTS[key] >= minimum, f'Real-size seed shrank: {key}={COUNTS[key]}, minimum={minimum}'
        values = re.findall(rf'\bseeded_{key}=(\d+)\b', log)
        assert values == [str(COUNTS[key])], f'Real-size seeded_{key}: logged {values}, expected {COUNTS[key]}'
    assert len(MESSAGES[BUSY]) >= 1500, 'Real-size busiest chat shrank below 1500 messages'
    assert re.findall(r'\bstep=([a-z-]+) finished=true\b', log) == list(STEPS), 'Real-size journey steps missing or out of order'
    assert re.findall(r'\bapp_inbox_chats=(\d+)\b', log) == [str(len(INBOX))]
    assert re.findall(r'\bapp_archived_chats=(\d+)\b', log) == [str(len(ARCHIVED))]


def check_evidence(folder):
    folder = Path(folder)
    check_size(folder)

    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'real-size' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='real-size', status='passed')
    assert not (folder / 'failure.txt').exists()
    assert read('seed.json') == MANIFEST, 'Real-size served seed differs from generated seed'
    for phase, expected in [('inbox', INBOX), ('archived', ARCHIVED), ('after', INBOX)]:
        rows = read(f'{phase}.chats.json')
        assert rows['total'] == len(rows['chats']) == len(expected), phase
        assert {row['id'] for row in rows['chats']} == {row['jid'] for row in expected}, phase
        assert all(row['archived'] is (phase == 'archived') for row in rows['chats']), phase
    scroll = read('list-scroll.json')
    assert scroll['native_count'] == len(INBOX) and scroll['top_index'] > 0
    assert scroll['state']['selected']['id'] == INBOX[-1]['jid']
    for phase, count in [('busy', 80), ('busy-top', 1000)]:
        shown = read(f'{phase}.messages.json')
        assert shown['chat']['id'] == BUSY
        assert [row['id'] for row in shown['messages']] == [row['MsgID'] for row in MESSAGES[BUSY][-count:]], phase
    first = read('busy-top.messages.json')['messages'][0]
    assert first['bubble'][2] > first['bubble'][0] and first['bubble'][3] > first['bubble'][1], 'Loaded history top was not painted'
    search = read('search.json')
    assert search['query'] == MANIFEST['search'] and search['focused'] and search['palette']
    assert search['native_count'] == len(search['labels']) >= len(SEARCH) >= 50
    assert {row['id'] for row in search['rows']} == {row['jid'] for row in SEARCH}
    assert {row['name'] for row in SEARCH}.issubset(search['labels']), 'Search omitted visible chat labels'
    voice = read('voice.messages.json')
    assert voice['chat']['id'] == VOICE and len(voice['messages']) == len(MESSAGES[VOICE])
    for kind, minimum in [('audio', 1), ('image', 2)]:
        assert sum(row['media_type'] == kind and row['local'] for row in voice['messages']) >= minimum, kind
    group = read('group.messages.json')
    assert group['chat']['id'] == GROUP
    assert [row['id'] for row in group['messages']] == [row['MsgID'] for row in MESSAGES[GROUP]]
    assert all(row['sender'].startswith('Seed Sender') for row in group['messages'] if not row['from_me'])
    assert any(row['quoted_msg_id'] for row in group['messages']), 'Seeded replies were not loaded'
    requests = read('real-size.requests.json')
    assert any(row.get('seed') == MANIFEST and row['status'] == 200 for row in requests)
    for expected in (INBOX, ARCHIVED):
        assert any(row.get('rows') == expected and row['status'] == 200 for row in requests), 'Seed chat rows were not served'
    history = [row for row in requests if row.get('chat') == BUSY and row['status'] == 200 and 'message_ids' in row]
    served = {message for row in history for message in row['message_ids']}
    assert served >= {row['MsgID'] for row in MESSAGES[BUSY][-1000:]}, 'Busy history pages missing'
    downloads = [row for row in requests if row.get('status') == 200 and '/v1/wazig/media/' in row.get('wire_path', '')]
    assert downloads and all(row.get('sha256') for row in downloads)
    for phase, count, archived in [('list-scrolled', len(INBOX), False), ('busy', len(INBOX), False),
                                    ('busy-top', len(INBOX), False), ('voice', len(INBOX), False),
                                    ('group', len(INBOX), False), ('archived', len(ARCHIVED), True), ('after', len(INBOX), False)]:
        state = read(f'{phase}.state.json')
        assert state['chat_count'] == count and state['show_archived'] is archived, phase
    for phase in ('before', 'list-scrolled', 'busy', 'busy-top', 'search', 'voice', 'group', 'archived', 'after'):
        image = (folder / f'{phase}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, phase
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: real-size' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print(f'EVIDENCE VERIFIED: real-size {COUNTS}, list scrolling, busy history, search, media, group and archive round trip')

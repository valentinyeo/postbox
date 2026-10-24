from datetime import datetime
from pathlib import Path
import hashlib
import json
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
def read(name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))

def passage_messages(rows, id_key='id'):
    messages = {row[id_key]: row for row in rows}
    assert len(messages) == len(rows) == 7
    assert set(messages) == {f'PASSAGE-{number}' for number in range(1, 8)}
    return messages

assert session['sha256'] and session['commit']
assert read('result.json') == dict(feature='passage-copy', status='passed')
checks = read('clipboard.json')
fixture = read('passage-fixture.json')
assert len(checks) == 4
for provider, chat in [('whatsapp', 'fixture-beta'), ('slack', 'fixture-alpha')]:
    rows = fixture[chat]
    assert len(rows) >= 7 and len({r['SenderName'] for r in rows}) >= 2
    assert any(r['FromMe'] for r in rows)
    fixture_messages = passage_messages(rows, 'MsgID')
    timestamps = [fixture_messages[f'PASSAGE-{number}']['Timestamp'] for number in range(1, 8)]
    assert timestamps == sorted(timestamps) and len(set(timestamps)) == 7
    assert all(fixture_messages[f'PASSAGE-{number}']['Text'] == 'alpha MIDDLE omega' for number in range(2, 6))
    assert fixture_messages['PASSAGE-6']['Text'].split('\n') == ['alpha MIDDLE omega'] * 40
    for stage, last in [('partial', 5), ('edge', 7)]:
        check, = [r for r in checks if r['provider'] == provider and r['stage'] == stage]
        canvas = check['canvas']
        assert canvas['width'] > 0 and canvas['height'] > 0 and canvas['dpi'] > 0
        before = passage_messages(check['before'])
        if stage == 'partial':
            for number in range(2, 6):
                left, top, right, bottom = before[f'PASSAGE-{number}']['bubble']
                assert 0 <= left < right <= canvas['width'] and 0 <= top < bottom <= canvas['height']
            assert before['PASSAGE-5']['bubble'][3] - before['PASSAGE-2']['bubble'][1] <= canvas['height']
        blocks, day = [], ''
        for index in range(2, last + 1):
            row = fixture_messages[f'PASSAGE-{index}']
            text = row['Text']
            if index == 2:
                text = text[text.index('MIDDLE'):]
            if stage == 'partial' and index == last:
                text = text[:text.index('MIDDLE') + 6]
            local = datetime.fromisoformat(row['Timestamp'].replace('Z', '+00:00')).astimezone()
            next_day = local.strftime('%Y-%m-%d')
            if day and day != next_day:
                blocks.append(next_day)
            day = next_day
            sender = 'You' if row['FromMe'] else row['SenderName']
            time = local.strftime('%H:%M')
            blocks.append(f"{sender}, {time}: {text}".replace('\n', '\r\n'))
        assert check['actual'] == check['expected'] == '\r\n'.join(blocks)
        if stage == 'edge':
            after = passage_messages(check['after'])
            assert before['PASSAGE-7']['bubble'][2] == 0
            assert after['PASSAGE-7']['bubble'][2] > 0
            assert before['PASSAGE-2']['bubble'] != after['PASSAGE-2']['bubble']
            left, top, right, bottom = before['PASSAGE-2']['bubble']
            assert 0 <= left < right <= canvas['width'] and 0 <= top < bottom <= canvas['height']
            held = check['held']
            held_messages = passage_messages(held['messages'])
            assert before['PASSAGE-6']['bubble'][2] > before['PASSAGE-6']['bubble'][0]
            assert held_messages['PASSAGE-6']['bubble'][2] > held_messages['PASSAGE-6']['bubble'][0]
            assert held['scroll_before'] == before['PASSAGE-6']['bubble'][1]
            assert held['scroll_after'] == held_messages['PASSAGE-6']['bubble'][1] < held['scroll_before']
            assert after['PASSAGE-6']['bubble'][2] > after['PASSAGE-6']['bubble'][0]
            assert after['PASSAGE-6']['bubble'][1] < held['scroll_before']
            left, top, right, bottom = held_messages['PASSAGE-7']['bubble']
            assert 0 <= left < right <= canvas['width'] and 0 <= top < bottom <= canvas['height']
    images = []
    for phase in ['before', 'after', 'edge-after']:
        image = (folder / f'{provider}-{phase}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        images.append(hashlib.sha256(image).hexdigest())
        state = read(f'{provider}-{phase}.state.json')
        assert state['selected']['id'] == chat and state['selected']['provider'] == provider
    assert len(set(images)) == 3
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
assert actions.count('passage message 2 middle to message 5 middle') == 2
assert actions.count('held drag beyond canvas 1024 bottom') == 2
final = read('side-effects.json')
assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: stamped partial passage and held-edge scrolling on WhatsApp and Slack')
raise SystemExit(0)

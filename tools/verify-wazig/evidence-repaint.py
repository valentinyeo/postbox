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
assert read('result.json') == dict(feature='repaint', status='passed')
assert not (folder / 'failure.txt').exists()
paints = read('paints.json')
assert 60 <= paints['elapsed_seconds'] < 70
fields = {'window', 'window_full', 'canvas', 'canvas_full', 'list', 'list_full'}
assert set(paints['before']) == set(paints['after']) == set(paints['delta']) == fields
for field in fields:
    assert paints['delta'][field] == paints['after'][field] - paints['before'][field] >= 0
full = sum(paints['delta'][field] for field in fields if field.endswith('_full'))
assert full == paints['full'] and full <= 3, f'repaint: {full} full repaints in 60 s, limit 3'
assert paints['provider']['ticks'] >= 29 and paints['provider']['incoming'] >= 5
assert paints['selected_before'] == paints['selected_after'] == 'fixture-alpha'
before = read('before.chats.json')['chats']
after = read('after.chats.json')['chats']
beta_before, = [row for row in before if row['id'] == 'fixture-beta']
beta_after, = [row for row in after if row['id'] == 'fixture-beta']
assert beta_after['unread_count'] - beta_before['unread_count'] >= 5
assert beta_after['last_message_time'] > beta_before['last_message_time']
requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
updates = [row for row in requests if row['method'] == 'SSE']
assert sum(row['kind'] == 'reset' for row in updates) >= 30
assert sum(row['kind'] == 'msg' for row in updates) >= 5
assert len([row for row in requests if row['method'] == 'GET' and row['wire_path'].startswith('/v1/wazig/chats?') and row.get('incoming') is not None]) >= 25
for phase in ['before', 'after']:
    image = (folder / f'{phase}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    tree = (folder / f'{phase}.uia.txt').read_text(encoding='utf-8-sig')
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', tree.splitlines()[0])
    assert read(f'{phase}.state.json')['selected']['id'] == 'fixture-alpha'
final = read('side-effects.json')
assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert 'JOURNEY PASSED: repaint' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: no-input repaint workload, incoming chat updates, surface deltas and isolation')
raise SystemExit(0)

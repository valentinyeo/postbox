from pathlib import Path
import json
import re
import sys

folder = Path(sys.argv[1])

def read(name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))

session = read('session.json')
assert session['feature'] == 'archive-inbox' and session['sha256'] and session['commit']
assert read('result.json') == dict(feature='archive-inbox', status='passed')
assert not (folder / 'failure.txt').exists()
presses = read('ctrl-a.json')
assert [row['press'] for row in presses] == list(range(1, 11))
assert all(row['ok'] is True for row in presses)
targets = [row['target'] for row in presses]
assert targets == ['1032', '1016'] * 5, targets
assert all(row['focused'] is True for row in presses), targets
log = (folder / 'run.log').read_text(encoding='utf-8-sig')
assert re.findall(r'ctrl_a_press=(\d+) ok=(true|false)', log) == [(str(n), 'true') for n in range(1, 11)]
assert re.search(r'ctrl_a_ok=10\b', log)
timing = read('bulk-timing.json')
assert timing['chats'] == 264 and timing['remote_chats'] == 261
assert timing['single_requests'] == 0 and timing['batch_requests'] == 1
assert timing['total_ms'] > 0 and abs(timing['per_chat_ms'] * 264 - timing['total_ms']) < 0.001
assert re.search(rf'bulk_archive_ms_total={timing["total_ms"]} bulk_archive_ms_per_chat=\d+\.\d+', log)
assert re.search(r'archived_among_shown=264\b', log)
requests = read('archive.requests.json')
responses = [row for row in requests if row['method'] == 'GET' and row.get('rows')]
assert responses and all('archived' not in row for reply in responses for row in reply['rows'])
initial = read('before.chats.json')['chats']
assert len(initial) == 264 and all(row['archived'] is False for row in initial)
identities = {(row['provider'], row['account'], row['id']) for row in initial}
assert len(identities) == 264
remote = {row['id'] for row in initial if row['provider'] == 'whatsapp'}
writes = [row for row in requests if row['wire_path'] == '/v1/wazig/archive']
assert not writes, len(writes)
batches = [row for row in requests if row['wire_path'] == '/v1/wazig/archive-batch']
assert len(batches) == 1
batch = batches[0]
assert batch['status'] == 200 and batch['body']['archived'] is True
assert len(batch['body']['chats']) == len(batch['results']) == len(remote)
assert {row['chat'] for row in batch['body']['chats']} == remote
assert {row['chat'] for row in batch['results'] if row['ok']} == remote
lines = (folder / 'saved-archive-state.txt').read_text(encoding='utf-8-sig').splitlines()
assert len(lines) == 264
assert {line.split('\t')[0] for line in lines if line.split('\t')[0] in remote} == remote
assert all(line.split('\t')[1] == '0' for line in lines if line.split('\t')[0] in remote)
for provider in ('slack', 'telegram', 'signal'):
    row, = [row for row in initial if row['provider'] == provider]
    assert f"{provider}\t{row['account']}\t{row['id']}" in lines
for phase, count, archived in [('before', 264, False), ('selected', 264, False), ('empty', 0, False),
                                ('archived', 264, True), ('account-empty', 0, False),
                                ('restart-empty', 0, False), ('after', 264, True)]:
    state = read(f'{phase}.state.json')
    rows = read(f'{phase}.chats.json')
    assert state['show_archived'] is archived and state['chat_count'] == rows['total'] == len(rows['chats']) == count, phase
    assert all(row['archived'] is archived for row in rows['chats']), phase
    if archived:
        assert {(row['provider'], row['account'], row['id']) for row in rows['chats']} == identities, phase
        assert all(row['archive_label'] in ('Archived', 'Kept archived') for row in rows['chats']), phase
    if not count:
        assert state['selected'] is None, phase
    image = (folder / f'{phase}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, phase
    title = (folder / f'{phase}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', title), phase
restart = read('restart.json')
assert restart['new_pid'] == session['pid'] and restart['new_start'] == session['startTicks']
assert (restart['old_pid'], restart['old_start']) != (restart['new_pid'], restart['new_start'])
assert all(restart[key] == session[key] for key in ('root', 'id', 'sha256'))
final = read('side-effects.json')
assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert 'JOURNEY PASSED: archive-inbox' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: metadata-free archives, ten Ctrl+A presses, 264-chat timing, every provider path and restart')

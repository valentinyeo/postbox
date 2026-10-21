from pathlib import Path
import hashlib
import json
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
assert session['feature'] == 'search'
assert session['sha256'] and session['commit']
for name in ['doctor.json', 'before.state.json', 'after.state.json', 'empty.state.json', 'side-effects.json']:
    data = json.loads((folder / name).read_text(encoding='utf-8-sig'))
    assert data['version'] == '0.0.526', name
    assert data['pending_sends'] == 0 and data['pending_archives'] == 0, name
    assert data['sync'] == 'stopped' and not data['slack_connected'], name
before = json.loads((folder / 'before.state.json').read_text(encoding='utf-8-sig'))
after = json.loads((folder / 'after.state.json').read_text(encoding='utf-8-sig'))
empty = json.loads((folder / 'empty.state.json').read_text(encoding='utf-8-sig'))
final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
assert before['chat_count'] == 2 and before['search'] == ''
assert after['chat_count'] == 1 and after['search'] == 'Beta'
assert after['selected']['name'] == 'Verification Beta'
assert empty['chat_count'] == 0 and empty['search'] == 'NoSuchFixture'
assert final['chat_count'] == 2 and final['search'] == ''
assert 'JOURNEY PASSED: search' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
assert not (folder / 'failure.txt').exists()
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
for keys in ['^f', 'Beta', '{ESC}', 'NoSuchFixture']:
    assert f'keys: {keys}' in actions
images = []
for name in ['before', 'after', 'empty']:
    image = (folder / f'{name}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig')
    images.append(hashlib.sha256(image).hexdigest())
assert len(set(images)) == 3
cached = json.loads((folder / 'final-data/chats-0000000000000526.json').read_text(encoding='utf-8-sig'))
assert sorted(row['name'] for row in cached['data']) == ['Verification Alpha', 'Verification Beta']
assert not (folder / 'final-data/telegram').exists()
print('EVIDENCE VERIFIED: search action, match, empty state, restoration, isolation, surviving screenshots and cleanup')

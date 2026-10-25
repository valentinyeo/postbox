from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
assert session['sha256'] and session['commit']
assert 'JOURNEY PASSED: menus' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
assert 'PIXEL ORACLE PASSED:' in (folder / 'pixel-oracle-controls.txt').read_text(encoding='utf-8-sig')
assert not (folder / 'failure.txt').exists()
measurements = json.loads((folder / 'menu-luminances.json').read_text(encoding='utf-8-sig'))
popups = ['amoled-' + name for name in ['chat', 'composer', 'search', 'message', 'selection', 'palette', 'accounts', 'emoji', 'shortcuts', 'shortcode']] + ['green-chat']
popup_records = [row for row in measurements if row['expected'] != 'dark-edit']
assert sorted(row['screenshot'] for row in popup_records) == sorted(name + '-after.png' for name in popups)
for popup, count in [('palette', 1), ('accounts', 1), ('emoji', 1)]:
    edits = [row for row in measurements if row['expected'] == 'dark-edit' and row['screenshot'] == f'amoled-{popup}-after.png']
    assert len(edits) == count, popup
for row in measurements:
    metric = row['measurement']
    assert metric['pixels'] > 0
    assert metric['rect']['Right'] > metric['rect']['Left']
    assert metric['rect']['Bottom'] > metric['rect']['Top']
    if row['expected'] == 'light':
        assert metric['background'] >= 0.7
    else:
        assert metric['background'] <= 0.05126945837404324
        assert metric['lightTileFraction'] <= 0.02
    if row['expected'] != 'dark-edit':
        assert metric['contrast'] >= 4.5 and metric['textPixels'] >= 24
for name in popups:
    images = []
    for phase in ['before', 'after']:
        path = folder / f'{name}-{phase}.png'
        data = path.read_bytes()
        assert data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) > 10000
        images.append(hashlib.sha256(data).hexdigest())
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}-{phase}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
    assert images[0] != images[1], name
state = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
assert state['theme'] == 'green' and state['chat_count'] == 2
assert state['sync'] == 'stopped' and state['pending_sends'] == 0 and state['pending_archives'] == 0
assert state['production_preferences_absent'] and state['whatsapp_store_absent'] and state['telegram_store_absent']
cached = json.loads((folder / 'final-data/chats-0000000000000526.json').read_text(encoding='utf-8-sig'))
assert sorted(row['name'] for row in cached['data']) == ['Verification Alpha', 'Verification Beta']
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
assert 'drag-select synthetic message text and right-click' in actions and 'keys: Theme: Green' in actions
print('EVIDENCE VERIFIED: menus popup pairs, fixed pixel thresholds, negative controls, isolated state and cleanup')
sys.exit(0)

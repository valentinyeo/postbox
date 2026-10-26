from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
feature = session['feature']
assert session['sha256'] and session['commit']
assert not (folder / 'failure.txt').exists()
assert f'JOURNEY PASSED: {feature}' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
if feature == 'palette':
    search_api = runpy.run_path(str(Path(__file__).with_name('check-search-evidence.py')))
    search_api['check_shortcuts'](json.loads((folder / 'search-shortcuts.json').read_text(encoding='utf-8-sig')))
    assert 'hub no-url-unavailable PASS' in (folder / 'fallback-proof.log').read_text(encoding='utf-8-sig')
    launch = (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8-sig')
    assert 'whatsapp backend: unavailable (URL not configured)' in launch
    assert all(label not in launch for label in ('message backend: hub', 'whatsapp backend: hub', 'whatsapp backend: wacli'))
    cached = json.loads((folder / 'final-data/chats-0000000000000526.json').read_text(encoding='utf-8-sig'))
    assert sorted(row['name'] for row in cached['data']) == ['Verification Alpha', 'Verification Beta']
    assert not (folder / 'final-data/telegram').exists()
    removed = json.loads((folder / 'removed-status.json').read_text(encoding='utf-8-sig'))
    assert removed['positive_query'] == 'Keyboard shortcuts' and removed['positive_matches'] == 1
    assert removed['query'] == 'Status' and removed['status_rows'] == 0
    assert removed['sidebar_status_controls'] == 0
    stages = ['before', 'removed-status', 'action', 'after']
    keys = ['^k', 'Keyboard shortcuts', '^a', 'Status', '{ENTER}', '{ESC}']
else:
    scale = json.loads((folder / 'text-scale.json').read_text(encoding='utf-8-sig'))
    assert scale['initial_saved'] is False and scale['larger'] == 92 and scale['reset'] == 82
    assert 0 < scale['baseline_points'] < scale['larger_points']
    assert scale['reset_points'] == scale['baseline_points']
    stages = ['before', 'action', 'text-larger', 'after']
    keys = ['^k', 'Theme: Green', 'Make text larger', '{ENTER}', '^0']
    preferences = (folder / 'preferences.txt').read_text(encoding='utf-8-sig')
    assert 'FontScale' in preferences and '82' in preferences
for keys_sent in keys:
    assert f'keys: {keys_sent}' in actions
images = []
for name in stages:
    image = (folder / f'{name}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    images.append(hashlib.sha256(image).hexdigest())
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
    state = json.loads((folder / f'{name}.state.json').read_text(encoding='utf-8-sig'))
    assert state['version'] == '0.0.526' and state['chat_count'] == 2
    assert state['pending_sends'] == state['pending_archives'] == 0 and state['sync'] == 'stopped'
assert images[0] != images[1] and images[2] != images[3]
final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
assert final['chat_count'] == 2 and final['search'] == ''
assert final['theme'] == ('green' if feature == 'appearance' else 'amoled')
print(f'EVIDENCE VERIFIED: {feature} input, new assertions, surviving screenshots and isolation')
raise SystemExit(0)

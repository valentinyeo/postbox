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
assert read('result.json') == dict(feature='window', status='passed')
assert not (folder / 'failure.txt').exists()
steps = read('window.json')
assert [row['step'] for row in steps] == ['start-1', 'restored', 'start-2', 'start-3', 'start-4', 'start-5']
assert [row['zoomed'] for row in steps] == [True, False, True, True, True, True], 'Unexpected zoomed sequence'
assert [row['update_relaunch'] for row in steps] == [False, False, False, True, False, True]
assert all(row['root'] == session['root'] and row['id'] == session['id'] for row in steps)
assert len({(row['pid'], row['start_ticks']) for row in steps}) == 5
assert steps[0]['pid'] == steps[1]['pid'] and steps[0]['start_ticks'] == steps[1]['start_ticks']
assert steps[-1]['pid'] == session['pid'] and steps[-1]['start_ticks'] == session['startTicks']
starts = [row for row in steps if row['step'] != 'restored']
assert [row['start_method'] for row in starts] == ['process-start'] * 3 + ['createprocess-shownormal', 'createprocess-update-relaunch']
for row in starts:
    assert row['launch_zoomed_after'] > row['launch_zoomed_before'] >= 0, (row['step'], 'launch log lacks a new startup: window zoomed=true line')
assert [row['launch_zoomed_after'] for row in starts] == sorted(row['launch_zoomed_after'] for row in starts)
launch_log = (folder / 'final-data' / 'launch-log.txt').read_text(encoding='utf-8-sig')
assert sum(line.endswith(' startup: window zoomed=true') for line in launch_log.splitlines()) >= 5
assert not any(line.endswith(' startup: window zoomed=false') for line in launch_log.splitlines())
assert read('doctor.json')['version'] == '0.0.526'
assert len({row['monitor_handle'] for row in steps}) == 1
for row in steps:
    assert row['hwnd'] and row['monitor_handle'] and row['start_ticks']
    for field in ['monitor_rect', 'work_rect', 'normal_rect']:
        rect = row[field]
        assert rect['Right'] > rect['Left'] and rect['Bottom'] > rect['Top'], (row['step'], field)
    image = (folder / (row['step'] + '.png')).read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v0\.0\.526', (folder / (row['step'] + '.uia.txt')).read_text(encoding='utf-8-sig').splitlines()[0])
    state = read(row['step'] + '.state.json')
    assert state['sync'] == 'stopped' and state['pending_sends'] == state['pending_archives'] == 0
normal = steps[1]['normal_rect']
assert normal == steps[2]['normal_rect'] == steps[3]['normal_rect'] == steps[4]['normal_rect'] == steps[5]['normal_rect']
initial = steps[0]['normal_rect']
assert normal['Right'] - normal['Left'] < initial['Right'] - initial['Left']
assert normal['Bottom'] - normal['Top'] < initial['Bottom'] - initial['Top']
preferences = (folder / 'preferences.txt').read_text(encoding='utf-8-sig')
for name in ['WindowLeft', 'WindowTop', 'WindowRight', 'WindowBottom']:
    assert name in preferences, name
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
assert actions.count('keys: %{F4}') == 4 and 'keys: r' in actions and 'keys: s' in actions
final = read('side-effects.json')
assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert 'JOURNEY PASSED: window' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: zoomed startups, keyboard restore and Alt+F4, same-profile update relaunch, Start-menu style and updater CreateProcessW launches and retained monitor')
raise SystemExit(0)

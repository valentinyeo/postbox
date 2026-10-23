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
assert read('result.json') == dict(feature='reactions', status='passed')
assert not (folder / 'failure.txt').exists()
bodies = [json.loads(line) for line in (folder / 'react-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
clicks = read('reaction-clicks.json')
assert len(clicks) == 2 and {row['provider'] for row in clicks} == {'whatsapp', 'slack'}
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
expected = chr(0x1f602)
for provider, chat, message in [('whatsapp', 'fixture-beta', 'BASELINE_BETA'), ('slack', 'fixture-alpha', 'BASELINE')]:
    observed = [row for row in bodies if row['chat'] == chat and row['msg'] == message]
    assert observed and all(row['msg'] == message and row['emoji'] == expected for row in observed), (provider, observed)
    assert all(set(row) == {'chat', 'msg', 'emoji', 'client_id'} and row['client_id'] for row in observed)
    accepted = [row for row in requests if row['wire_path'] == '/v1/wazig/react' and row.get('body', {}).get('chat') == chat and row['body'].get('msg') == message]
    assert accepted and all(row['authorized'] and row['status'] == 200 and row['body'] in observed for row in accepted)
    click, = [row for row in clicks if row['provider'] == provider]
    assert click['chat'] == chat and click['message'] == message and click['expected'] == expected
    assert click['menu_class'] == '#32768' and click['menu_pid'] == session['pid']
    assert click['index'] == 2 and click['cell_width'] > 0
    assert click['x'] == click['row_left'] + click['index'] * click['cell_width'] + click['cell_width'] // 2
    assert click['y'] == click['row_top'] + click['cell_width'] // 2
    rect = click['menu']
    assert rect['Left'] < click['x'] < rect['Right'] and rect['Top'] < click['y'] < rect['Bottom']
    shown = read(f'{provider}-after.messages.json')
    assert shown['chat']['id'] == chat and shown['chat']['provider'] == provider
    incoming, = [row for row in shown['messages'] if row['id'] == message]
    assert not incoming['from_me'] and incoming['reaction'] == expected
    images = []
    for phase in ['before', 'after']:
        name = f'{provider}-{phase}'
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        images.append(hashlib.sha256(image).hexdigest())
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
        selected = read(f'{name}.state.json')['selected']
        assert selected['id'] == chat and selected['provider'] == provider
    assert images[0] != images[1]
    assert f'SendInput: right-click {provider} message={message}' in actions
    assert f'SendInput: left-click {provider} laughing-face cell=2' in actions
    assert f'reactions {provider}-laughing-face PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
chip_bodies = [row for row in bodies if row['chat'] == 'fixture-beta' and row['msg'] == 'CHIP']
heart = '\u2764\ufe0f'
assert [row['emoji'] for row in chip_bodies] == [heart, ''], chip_bodies
for body in chip_bodies:
    assert set(body) == {'chat', 'msg', 'emoji', 'client_id'} and body['client_id']
    assert any(row['wire_path'] == '/v1/wazig/react' and row.get('body') == body and
               row['authorized'] and row['status'] == 200 for row in requests)
for phase, own in [('added', heart), ('removed', '')]:
    shown = read(f'chip-{phase}.messages.json')
    assert shown['chat']['id'] == 'fixture-beta' and shown['chat']['provider'] == 'whatsapp'
    chip, = [row for row in shown['messages'] if row['id'] == 'CHIP']
    assert not chip['from_me'] and heart in chip['reaction'] and chip['my_reaction'] == own
    image = (folder / f'chip-{phase}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    selected = read(f'chip-{phase}.state.json')['selected']
    assert selected['id'] == 'fixture-beta' and selected['provider'] == 'whatsapp'
    assert f'SendInput: left-click CHIP {phase}' in actions
    assert f'reactions chip-{phase} PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
assert {row['chat'] for row in bodies} == {'fixture-alpha', 'fixture-beta'}
assert not any(row['wire_path'] in ('/v1/wazig/send', '/v1/wazig/archive') for row in requests)
final = read('side-effects.json')
assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert 'JOURNEY PASSED: reactions' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: real mouse menu reactions and CHIP add/remove, exact hub bodies, preserved friend heart and isolation')
raise SystemExit(0)

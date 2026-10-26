from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
assert session['feature'] in ('search', 'archive')
feature = session['feature']
assert session['sha256'] and session['commit']
snapshots = ['doctor', 'before', 'after', 'side-effects']
if feature == 'search':
    assert 'hub no-url-unavailable PASS' in (folder / 'fallback-proof.log').read_text(encoding='utf-8-sig')
    launch = (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8-sig')
    assert 'whatsapp backend: unavailable (URL not configured)' in launch and 'message backend: hub' not in launch and 'whatsapp backend: hub' not in launch and 'whatsapp backend: wacli' not in launch
    snapshots += ['empty']
else:
    snapshots += ['action', 'kept', 'inbox']
for name in [f'{stage}.json' if stage in ('doctor', 'side-effects') else f'{stage}.state.json' for stage in snapshots]:
    data = json.loads((folder / name).read_text(encoding='utf-8-sig'))
    assert data['version'] == '0.0.526', name
    assert data['pending_sends'] == 0 and data['pending_archives'] == 0, name
    assert data['sync'] == 'stopped' and not data['slack_connected'], name
before = json.loads((folder / 'before.state.json').read_text(encoding='utf-8-sig'))
after = json.loads((folder / 'after.state.json').read_text(encoding='utf-8-sig'))
final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
assert before['chat_count'] == 2 and before['search'] == ''
if feature == 'search':
    empty = json.loads((folder / 'empty.state.json').read_text(encoding='utf-8-sig'))
    assert after['chat_count'] == 1 and after['search'] == 'Beta'
    assert after['selected']['name'] == 'Verification Beta'
    assert empty['chat_count'] == 0 and empty['search'] == 'NoSuchFixture'
    assert final['chat_count'] == 2 and final['search'] == ''
else:
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def alpha(provider):
        rows = [row for row in provider['data'] if row['jid'] == 'verify-alpha@s.whatsapp.net']
        assert len(rows) == 1
        return rows[0]

    action = read('action.state.json')
    kept = read('kept.state.json')
    inbox = read('inbox.state.json')
    assert before['selected']['name'] == 'Verification Alpha' and not before['show_archived']
    assert before['selected']['unread_count'] == 0
    assert action['show_archived'] and action['selected']['archived']
    assert action['selected']['name'] == 'Verification Alpha' and action['selected']['unread_count'] == 0
    assert kept['show_archived'] and kept['selected']['unread_count'] == 0
    assert not inbox['show_archived'] and inbox['chat_count'] == 1
    assert inbox['selected']['name'] == 'Verification Beta'
    for state in (after, final):
        assert state['show_archived'] and state['chat_count'] == 1 and state['search'] == ''
        row = state['selected']
        assert row['name'] == 'Verification Alpha' and row['archived'] and row['unread']
        assert row['unread_count'] == 1 and row['last_message_time'] == '2026-10-10T11:00:00Z'
    for stage, names in [('before', ['Verification Alpha', 'Verification Beta']), ('action', ['Verification Alpha']), ('kept', ['Verification Alpha']), ('inbox', ['Verification Beta']), ('after', ['Verification Alpha'])]:
        chats = read(f'{stage}.chats.json')
        assert chats['total'] == len(names) and sorted(row['name'] for row in chats['chats']) == names
    incoming = read('incoming-provider.json')
    assert alpha(incoming)['archived'] and alpha(incoming)['unread_count'] == 1
    messages = incoming['messages']['verify-alpha@s.whatsapp.net']['data']['messages']
    assert len(messages) == 1 and messages[0]['MsgID'] == 'verify-incoming-1' and not messages[0]['FromMe']
    assert messages[0]['Timestamp'] == alpha(incoming)['last_message_ts'] == '2026-10-10T11:00:00Z'
    provider = read('final-data/verification-provider.json')
    assert sorted(row['name'] for row in provider['data']) == ['Verification Alpha', 'Verification Beta']
    assert alpha(provider)['archived'] and alpha(provider)['unread_count'] == 1
    assert provider['messages'] == incoming['messages']
    assert 'archive: jid=verify-alpha@s.whatsapp.net archived=true source=shortcut' in (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8-sig')
    for name in ('kept-archive-state.txt', 'final-data/archive-state.txt'):
        assert 'verify-alpha@s.whatsapp.net\t0\t' in (folder / name).read_text(encoding='utf-8-sig')
    assert 'Show inbox chats' in (folder / 'action.palette.uia.txt').read_text(encoding='utf-8-sig')
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
assert f'JOURNEY PASSED: {feature}' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
assert not (folder / 'failure.txt').exists()
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
keys_required = ['^f', 'Beta', '{ESC}', 'NoSuchFixture'] if feature == 'search' else ['^e', '^k', 'Show inbox chats', 'Show archived chats', '{ENTER}']
for keys in keys_required:
    assert f'keys: {keys}' in actions
images = []
stages = ['before', 'after', 'empty'] if feature == 'search' else ['before', 'action', 'kept', 'inbox', 'after']
for name in stages:
    image = (folder / f'{name}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v0\.0\.526', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
    images.append(hashlib.sha256(image).hexdigest())
assert len(set(images)) == len(stages)
if feature == 'search':
    cached = json.loads((folder / 'final-data/chats-0000000000000526.json').read_text(encoding='utf-8-sig'))
    assert sorted(row['name'] for row in cached['data']) == ['Verification Alpha', 'Verification Beta']
else:
    ordered_actions = ['keys: ^e', 'keys: Show archived chats', 'keys: Show inbox chats', 'provider: incoming verify-incoming-1; archived=true; unread_count=1', 'keys: Show archived chats']
    position = 0
    for action in ordered_actions:
        position = actions.index(action, position) + len(action)
assert not (folder / 'final-data/telegram').exists()
print(f'EVIDENCE VERIFIED: {feature} action, state transitions, isolation, surviving screenshots and cleanup')

from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
from importlib.util import module_from_spec, spec_from_file_location


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))

spec = spec_from_file_location('workspace_icons', Path(__file__).with_name('check-workspace-icons.py'))
icons = module_from_spec(spec)
spec.loader.exec_module(icons)

def read(name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))

assert session['sha256'] and session['commit']
assert read('result.json') == dict(feature='workspace-icons', status='passed')
assert not (folder / 'failure.txt').exists()
icons.check_pixels(folder)
rows = read('workspace-icons-list.chats.json')
layout = read('workspace-icons-layout.json')
ids = [row['id'] for row in rows['chats']]
assert rows['total'] == 5
assert ids == layout['ids']
assert sorted(ids) == sorted(icons.IDS)
assert all(row['provider'] == ('signal' if row['id'] == 'signal:fixture-contact' else 'whatsapp' if row['id'] == 'whatsapp:fixture:contact-delta' else 'slack') for row in rows['chats'])
state = read('workspace-icons-list.state.json')
assert state['view'] == 'all' and state['theme'] == 'amoled'
assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), (folder / 'workspace-icons-list.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
assert all(row['wire_path'].startswith('/v1/wazig/') for row in requests)
for team, status in [('fixture-amber', 200), ('fixture-cobalt', 200), ('fixture-empty', 404)]:
    route = '/v1/wazig/workspace-icon/' + team
    fetched = [row for row in requests if row['wire_path'] == route and row['authorized']]
    assert len(fetched) == 1 and fetched[0]['status'] == status, team
    assert any(row['wire_path'] == route and not row['authorized'] and row['status'] == 401 for row in requests), team
    if status == 200:
        cached = list((folder / 'final-data/avatars').glob('*.img'))
        assert any(hashlib.sha256(path.read_bytes()).hexdigest() == fetched[0]['sha256'] for path in cached), team
assert all(row['authorized'] or row['status'] == 401 for row in requests if row['method'] != 'SSE')
assert not any(row['wire_path'] in ('/v1/wazig/send', '/v1/wazig/archive') for row in requests)
assert len(list((folder / 'final-data/avatars').glob('*.none'))) >= 2
final = read('side-effects.json')
assert final['chat_count'] == 5 and final['pending_sends'] == final['pending_archives'] == 0
assert final['sync'] == 'stopped' and not final['slack_connected']
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert 'workspace-icons workspace-icons-pixels PASS' in (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
assert 'keys: %1' in (folder / 'actions.log').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
assert 'JOURNEY PASSED: workspace-icons' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: workspace icon badge pixels, authenticated team cache, fallback, WhatsApp green, Signal blue and isolation')
raise SystemExit(0)

from pathlib import Path
import json
import re
import sys
from urllib.parse import parse_qs, urlsplit

folder = Path(sys.argv[1])


def read(name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))


session = read('session.json')
assert session['sha256'] and session['commit'] and session['feature'] == 'slack-mentions'
assert read('result.json') == dict(feature='slack-mentions', status='passed')
assert not (folder / 'failure.txt').exists()
chat = 'slack:fixture-mentions:channel'
shown = read('after.messages.json')
assert shown['chat']['id'] == chat and shown['chat']['provider'] == 'slack'
rows = {row['id']: row for row in shown['messages']}
assert len(shown['messages']) == len(rows) == 3
assert set(rows) == {'MENTION-NAMED', 'MENTION-UNKNOWN', 'MENTION-LABELLED'}
assert rows['MENTION-NAMED']['text'] == '@Fixture Peer hello'
assert rows['MENTION-UNKNOWN']['text'] == '@someone joins later'
assert rows['MENTION-LABELLED']['text'] == '@Outside Guest thanks report'
assert rows['MENTION-LABELLED']['links'] == ['https://example.org/report']
assert not re.search(r'UUNKNOWN99|UHIDDEN01|<@|<https://', json.dumps(shown))
for row in rows.values():
    left, top, right, bottom = row['bubble']
    assert 0 <= left < right and 0 <= top < bottom
for stage in ['before', 'after']:
    image = (folder / f'{stage}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    tree = (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig')
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Wazig v0\.0\.526', tree.splitlines()[0])
    assert not re.search(r'UUNKNOWN99|UHIDDEN01', tree)
after = read('after.state.json')
assert after['view'] == 'slack' and after['selected']['id'] == chat
assert after['selected']['provider'] == 'slack'
proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
assert 'slack-mentions mention-display PASS' in proof
requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
api = [row for row in requests if row['wire_path'].startswith('/v1/wazig/')]
assert api and all(row['authorized'] for row in api if row['method'] != 'SSE')
assert any(urlsplit(row['wire_path']).path == '/v1/wazig/chats' and row['status'] == 200 for row in api)
assert any(urlsplit(row['wire_path']).path == '/v1/wazig/messages' and row['status'] == 200
           and parse_qs(urlsplit(row['wire_path']).query).get('chat') == [chat] for row in api)
assert not any(urlsplit(row['wire_path']).path in ('/v1/wazig/send', '/v1/wazig/archive', '/v1/wazig/react') for row in api)
final = read('side-effects.json')
assert final['chat_count'] == 1 and final['pending_sends'] == final['pending_archives'] == 0
assert final['sync'] == 'stopped' and not final['slack_connected']
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
for keys in ['%1', '^{TAB}']:
    assert f'keys: {keys}' in actions
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
assert 'JOURNEY PASSED: slack-mentions' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
print('EVIDENCE VERIFIED: named and labelled Slack mentions, neutral fallback, no raw ids, report link and keyboard navigation')

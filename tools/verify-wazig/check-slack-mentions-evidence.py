import json
import re
from urllib.parse import parse_qs, urlsplit


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))


def check_slack_mentions(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit'] and session['feature'] == 'slack-mentions'
    assert read('result.json') == dict(feature='slack-mentions', status='passed')
    assert not (folder / 'failure.txt').exists()
    chat = 'slack:fixture-mentions:channel'
    expected = {
        'MENTION-NAMED': '@Fixture Peer hello',
        'MENTION-UNKNOWN': '@someone joins later',
        'MENTION-LABELLED': '@Outside Guest thanks report',
        'MENTION-GUEST': '@Guest Person joins @Fixture Peer',
        'MENTION-CONNECT': '@Guest Person meets @Connect Person',
    }
    raw_markup = r'<@|<https://'
    fixture_ids = ('U4A59H6UT', 'UUNKNOWN99', 'UHIDDEN01', 'UEXT00001', 'WCONNECT01')

    def has_raw_id(text):
        return bool(re.search(raw_markup, text)) or any(name in text for name in fixture_ids)

    for stage in ['before', 'after']:
        shown = read(f'{stage}.messages.json')
        assert shown['chat']['id'] == chat and shown['chat']['provider'] == 'slack'
        assert shown['chat']['name'] == 'Verification Mentions'
        rows = {row['id']: row for row in shown['messages']}
        assert len(shown['messages']) == len(rows) == len(expected)
        assert {key: row['text'] for key, row in rows.items()} == expected
        assert rows['MENTION-NAMED']['text'] == '@' + rows['MENTION-NAMED']['sender'] + ' hello'
        assert rows['MENTION-GUEST']['sender'] == 'Guest Person'
        assert rows['MENTION-CONNECT']['sender'] == 'Connect Person'
        assert rows['MENTION-LABELLED']['links'] == ['https://example.org/report']
        rendered = dict(shown, messages=[{key: value for key, value in row.items() if key != 'sender_id'}
                                         for row in shown['messages']])
        assert read(f'{stage}.rendered.json') == rendered
        assert not has_raw_id(json.dumps(rendered))
        for row in rows.values():
            left, top, right, bottom = row['bubble']
            assert 0 <= left < right and 0 <= top < bottom
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        tree = (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig')
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), tree.splitlines()[0])
        assert not has_raw_id(tree)
        for control in ['1032']:
            assert re.search(rf'^{control} \| ', tree, re.M), (stage, control)
        state = read(f'{stage}.state.json')
        assert state['view'] == 'slack' and state['selected']['id'] == chat
        assert state['selected']['provider'] == 'slack'
        assert state['pending_sends'] == state['pending_archives'] == 0
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert 'slack-mentions mention-display PASS' in proof
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    api = [row for row in requests if row['wire_path'].startswith('/v1/wazig/')]
    assert api and all(row['authorized'] for row in api if row['method'] != 'SSE')
    assert any(urlsplit(row['wire_path']).path == '/v1/wazig/chats' and row['status'] == 200 for row in api)
    histories = [row for row in api if urlsplit(row['wire_path']).path == '/v1/wazig/messages'
                 and row['status'] == 200 and parse_qs(urlsplit(row['wire_path']).query).get('chat') == [chat]]
    assert histories
    for history in histories:
        assert history['members'] == {'U4A59H6UT': 'Fixture Peer'}
        assert history['users_info'] == {'UEXT00001': 'Guest Person', 'WCONNECT01': 'Connect Person'}
        assert not set(history['members']) & set(history['users_info'])
        wire = {row['MsgID']: row for row in history['rows']}
        assert wire['MENTION-NAMED']['Text'] == '<@U4A59H6UT> hello'
        assert wire['MENTION-UNKNOWN']['Text'] == '<@UUNKNOWN99> joins later'
        assert wire['MENTION-LABELLED']['Text'] == '<@UHIDDEN01|Outside Guest> thanks <https://example.org/report|report>'
        assert wire['MENTION-GUEST']['Text'] == '<@UEXT00001> joins @Fixture Peer'
        assert wire['MENTION-CONNECT']['Text'] == '@Guest Person meets <@WCONNECT01>'
        for key, user in [('MENTION-GUEST', 'UEXT00001'), ('MENTION-CONNECT', 'WCONNECT01')]:
            assert wire[key]['SenderJID'] == user and wire[key]['SenderName'] == history['users_info'][user]
    assert not any(urlsplit(row['wire_path']).path in ('/v1/wazig/send', '/v1/wazig/archive', '/v1/wazig/react') for row in api)
    final = read('side-effects.json')
    assert final['chat_count'] == 1 and final['pending_sends'] == final['pending_archives'] == 0
    assert final['sync'] == 'stopped' and not final['slack_connected']
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for keys in ['%2', '^{TAB}']:
        assert f'keys: {keys}' in actions
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert 'JOURNEY PASSED: slack-mentions' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: cached Slack sender names, labelled mentions, guest and Connect names, neutral fallback and no rendered raw ids')

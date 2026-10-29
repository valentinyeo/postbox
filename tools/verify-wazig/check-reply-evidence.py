from pathlib import Path
import hashlib
import json
import sys


def check_reply(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='reply', status='passed')
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    for provider, chat in [('whatsapp', 'fixture-beta'), ('slack', 'fixture-alpha')]:
        accepted = [row for row in requests if row.get('wire_path') == '/v1/wazig/send' and
                    row.get('body', {}).get('chat') == chat and row['status'] == 200]
        assert len(accepted) == 1 and accepted[0]['authorized']
        assert accepted[0]['body']['reply_to'] == 'REPLY-ORIGINAL'
        assert accepted[0]['body']['text'] == f'Synthetic {provider} reply\nSecond line'
        hashes = []
        for phase in ['before', 'replying', 'sent', 'jumped', 'unavailable']:
            name = f'{provider}-{phase}'
            image = (folder / f'{name}.png').read_bytes()
            assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
            hashes.append(hashlib.sha256(image).hexdigest())
            state = read(f'{name}.state.json')
            assert state['selected']['id'] == chat and state['selected']['provider'] == provider
            if phase == 'replying':
                assert state['reply']['id'] == 'REPLY-ORIGINAL'
                assert state['reply']['sender'] == 'Fixture Sender'
                assert state['reply']['preview'] == 'First words of the original'
            if phase == 'sent':
                assert state['composer']['lines'] == 1
            if phase == 'jumped':
                assert state['reply_flash'] == 'REPLY-ORIGINAL'
            if phase == 'unavailable':
                assert state['reply_notice']
        assert hashes[0] != hashes[1] and hashes[1] != hashes[2]
        sent, = [row for row in read(f'{provider}-sent.messages.json')['messages'] if row['from_me']]
        assert sent['quoted_msg_id'] == 'REPLY-ORIGINAL'
        assert sent['quote_line'][3] < sent['bubble'][1]
    effects = read('side-effects.json')
    assert effects['pending_sends'] == effects['pending_archives'] == 0
    assert effects['production_preferences_absent'] and effects['whatsapp_store_absent']
    assert not (folder / 'failure.txt').exists()
    print('REPLY_NATIVE_OK')


if __name__ == '__main__':
    check_reply(Path(sys.argv[1]))

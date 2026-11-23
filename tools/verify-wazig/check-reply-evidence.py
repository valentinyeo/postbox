from pathlib import Path
import hashlib
import json
import runpy
import sys


def check_reply(folder):
    runpy.run_path(str(Path(__file__).with_name('real_size_seed.py')))['check_background_size'](folder)

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
                assert state['reply']['preview'] == 'First words of the original \U0001F642'
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
    keyboard_reply = read('whatsapp-enter-reply.json')
    previews = {'REPLY-ORIGINAL': 'First words of the original \U0001F642', 'REPLY-ORPHAN': 'Reply to an unloaded message'}
    assert keyboard_reply['focused'] == keyboard_reply['reply']
    assert keyboard_reply['expected'] == keyboard_reply['preview'] == previews[keyboard_reply['focused']]
    assert read('whatsapp-enter-reply.state.json')['reply']['preview'] == keyboard_reply['preview']
    for name in ['slack-threaded', 'slack-thread']:
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        state = read(f'{name}.state.json')
        assert state['selected']['id'] == 'fixture-alpha' and state['selected']['provider'] == 'slack'
        thread = state['slack_threads']
        assert thread['threads_option'] == 'on' and thread['parent_id'] == 'REPLY-ORIGINAL'
        assert thread['parent_reply_line'] == '1 reply' and thread['inline_replies'] == 0
        if name == 'slack-thread':
            assert thread['open'] and thread['replies'] == 1
    assert read('slack-sent.state.json')['slack_threads']['threads_option'] == 'off'
    shots = []
    for name in ['whatsapp-sent', 'whatsapp-slack-style', 'whatsapp-slack-thread', 'whatsapp-slack-remembered', 'whatsapp-style-restored']:
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        shots.append(hashlib.sha256(image).hexdigest())
        assert read(f'{name}.state.json')['selected']['id'] == 'fixture-beta'
    assert shots[0] != shots[1] and shots[1] != shots[2] and shots[1] != shots[4]
    for name in ['whatsapp-slack-style', 'whatsapp-slack-thread', 'whatsapp-slack-remembered']:
        threads = read(f'{name}.state.json')['slack_threads']
        assert threads['parent_id'] == 'REPLY-ORIGINAL' and threads['parent_reply_line'] == '1 reply'
        assert threads['inline_replies'] == 0
    thread = read('whatsapp-slack-thread.state.json')['slack_threads']
    assert thread['open'] and thread['replies'] == 1
    effects = read('side-effects.json')
    assert effects['pending_sends'] == effects['pending_archives'] == 0
    assert effects['production_preferences_absent'] and effects['whatsapp_store_absent']
    assert not (folder / 'failure.txt').exists()
    print('REPLY_NATIVE_OK')


if __name__ == '__main__':
    check_reply(Path(sys.argv[1]))

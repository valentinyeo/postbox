import json
import re


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))


def check_read_ticks(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='read-ticks', status='passed')
    assert not (folder / 'failure.txt').exists()
    expected = {
        'ticks-read': ('whatsapp', 'ticks-read@s.whatsapp.net', True),
        'ticks-sent': ('whatsapp', 'ticks-sent@s.whatsapp.net', False),
        'ticks-group': ('whatsapp', 'ticks-group@g.us', False),
        'ticks-slack': ('slack', 'slack:fixture-ticks:channel', False),
    }
    pictures = set()
    for stage, (provider, chat, shown) in expected.items():
        tick = read(f'{stage}.json')
        assert tick == dict(shown=shown, message='tick-own'), (stage, tick)
        state = read(f'{stage}.state.json')
        assert state['selected']['provider'] == provider and state['selected']['id'] == chat, stage
        assert state['read_tick'] == tick, stage
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, stage
        pictures.add(image)
        title = (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), title), title
    assert len(pictures) == len(expected), 'chat screenshots are not distinct'
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: read-ticks' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: grey double tick only on a read one-to-one WhatsApp message, none for unread, group or Slack')

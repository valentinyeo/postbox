import json
import re


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))


READ_TICK_STAGES = {
    'ticks-read': ('whatsapp', 'ticks-read@s.whatsapp.net', 'tick-own', 'tick-own', True),
    'ticks-sent': ('whatsapp', 'ticks-sent@s.whatsapp.net', '', 'tick-own', False),
    'ticks-late': ('whatsapp', 'ticks-late@s.whatsapp.net', 'tick-old', 'tick-old', True),
    'ticks-group': ('whatsapp', 'ticks-group@g.us', 'tick-own', 'tick-own', False),
    'ticks-slack': ('slack', 'slack:fixture-ticks:channel', '', 'tick-own', False),
    'ticks-signal': ('signal', 'signal:ticks-contact', 'tick-own', 'tick-own', True),
    'ticks-signal-group': ('signal', 'signal:group:ticks-group', 'tick-own', 'tick-own', False),
    'ticks-telegram': ('telegram', 'telegram:user:ticks-contact', 'tick-own', 'tick-own', True),
    'ticks-telegram-unread': ('telegram', 'telegram:user:ticks-unread', '', 'tick-own', False),
}


def check_read_ticks(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='read-ticks', status='passed')
    assert not (folder / 'failure.txt').exists()
    pictures = set()
    for stage, (provider, chat, tick_id, mark_id, shown) in READ_TICK_STAGES.items():
        tick = read(f'{stage}.json')
        assert tick == dict(shown=shown, message=tick_id), (stage, tick)
        state = read(f'{stage}.state.json')
        assert state['selected']['provider'] == provider and state['selected']['id'] == chat, stage
        assert state['read_tick'] == tick, stage
        shown_rows = read(f'{stage}.messages.json')['messages']
        band = [row for row in shown_rows if row['id'] == mark_id]
        assert len(band) == 1 and band[0]['bubble'][2] > band[0]['bubble'][0] and band[0]['bubble'][3] > band[0]['bubble'][1], stage
        mark = read(f'{stage}.mark.json')
        assert mark['bubble'] == band[0]['bubble'], (stage, mark['bubble'], band[0]['bubble'])
        if shown:
            assert mark['blue_below'] >= 6, (stage, mark)
        else:
            assert mark['blue_below'] == 0, (stage, mark)
        if stage == 'ticks-late':
            own = [row for row in shown_rows if row['id'] == 'tick-own']
            assert len(own) == 1, stage
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, stage
        pictures.add(image)
        title = (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), title), title
    hold = read('ticks-hold.json')
    assert not hold['shown_before'] and hold['shown_after'], hold
    assert hold['before']['id'] == hold['after']['id'], hold
    assert hold['before']['id'] != 'hold-39' and hold['before']['painted'] > 3, hold
    assert hold['moved'] == abs(hold['after']['y'] - hold['before']['y']), hold
    assert hold['moved'] <= 2, hold
    assert (folder / 'ticks-hold.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert len(pictures) == len(READ_TICK_STAGES), 'chat screenshots are not distinct'
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert 'read-ticks ticks-late=True' in proof and 'read-ticks ticks-sent=False' in proof, proof[-400:]
    assert 'read-ticks ticks-hold=hold-' in proof, proof[-400:]
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: read-ticks' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: blue double tick and Read label below the bubble right edge on the newest read own message only, none for unread, group or Slack, and the chat stays put when the mark appears')

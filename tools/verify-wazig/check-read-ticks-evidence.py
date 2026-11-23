import json
import re


def expected_product_version(folder):
    return re.escape(json.loads((folder / 'session.json').read_text(encoding='utf-8-sig')).get('expected_version', '0.0.526'))


TICK_STAGES = {
    'ticks-sent': ('whatsapp', 'ticks-sent@s.whatsapp.net', 'sent', 'grey'),
    'ticks-delivered': ('whatsapp', 'ticks-delivered@s.whatsapp.net', 'delivered', 'grey'),
    'ticks-read': ('whatsapp', 'ticks-read@s.whatsapp.net', 'read', 'blue'),
    'ticks-late': ('whatsapp', 'ticks-late@s.whatsapp.net', 'delivered', 'grey'),
    'ticks-group': ('whatsapp', 'ticks-group@g.us', 'delivered', 'grey'),
    'ticks-slack': ('slack', 'slack:fixture-ticks:channel', 'none', 'none'),
    'ticks-signal': ('signal', 'signal:ticks-contact', 'read', 'blue'),
    'ticks-signal-group': ('signal', 'signal:group:ticks-group', 'none', 'none'),
    'ticks-telegram': ('telegram', 'telegram:user:ticks-contact', 'read', 'blue'),
    'ticks-telegram-unread': ('telegram', 'telegram:user:ticks-unread', 'sent', 'grey'),
}


def check_inks(stage, inks, mark):
    if inks == 'none':
        assert mark['grey'] == 0 and mark['blue'] == 0, (stage, mark)
    elif inks == 'blue':
        assert mark['blue'] >= 8, (stage, mark)
        assert mark['grey'] <= 4, (stage, mark)
    else:
        assert mark['grey'] >= 6, (stage, mark)
        assert mark['blue'] == 0, (stage, mark)


def check_read_ticks(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='read-ticks', status='passed')
    assert not (folder / 'failure.txt').exists()
    pictures = set()
    for stage, (provider, chat, ticks, inks) in TICK_STAGES.items():
        mark = read(f'{stage}.json')
        assert mark['id'] == 'tick-own' and mark['ticks'] == ticks, (stage, mark)
        check_inks(stage, inks, mark)
        state = read(f'{stage}.state.json')
        assert state['selected']['provider'] == provider and state['selected']['id'] == chat, stage
        shown_rows = read(f'{stage}.messages.json')['messages']
        own = [row for row in shown_rows if row['id'] == 'tick-own']
        assert len(own) == 1 and own[0]['ticks'] == ticks, (stage, own)
        assert own[0]['bubble'][2] > own[0]['bubble'][0] and own[0]['bubble'][3] > own[0]['bubble'][1], stage
        assert mark['bubble'] == own[0]['bubble'], (stage, mark['bubble'], own[0]['bubble'])
        if stage == 'ticks-late':
            older = read(f'{stage}.older.json')
            assert older['id'] == 'tick-old' and older['ticks'] == 'read' and older['blue'] >= 8, older
            older_row = [row for row in shown_rows if row['id'] == 'tick-old']
            assert len(older_row) == 1 and older_row[0]['ticks'] == 'read', older_row
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, stage
        pictures.add(image)
        title = (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0]
        assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + expected_product_version(folder), title), title
    hold = read('ticks-hold.json')
    assert hold['before']['id'] == hold['after']['id'], hold
    assert hold['before']['id'] != 'hold-39' and hold['before']['painted'] > 3, hold
    assert hold['moved'] == abs(hold['after']['y'] - hold['before']['y']), hold
    assert hold['moved'] <= 2, hold
    assert hold['grey_before'] >= 6 and hold['blue_after'] >= 8, hold
    assert hold['height'] == hold['bubble'][3] - hold['bubble'][1], hold
    for name in ('ticks-hold-delivered', 'ticks-hold-read'):
        assert (folder / f'{name}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), name
    assert len(pictures) == len(TICK_STAGES), 'chat screenshots are not distinct'
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    for stage, (_, _, ticks, _) in TICK_STAGES.items():
        line = f'read-ticks {stage}={ticks} grey='
        assert line in proof, (line, proof[-600:])
    assert 'read-ticks ticks-hold=hold-' in proof, proof[-400:]
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: read-ticks' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: one grey tick for sent, two grey for delivered and two blue for read inside each own bubble, none for Slack or a Signal group, and the bubble keeps its size when a status changes')

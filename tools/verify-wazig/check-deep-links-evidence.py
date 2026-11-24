from pathlib import Path
import hashlib
import json
import sys


def check_evidence(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='deep-links', status='passed')
    proof = read('deep-links.json')
    reg = proof['registry']
    assert reg['description'] == 'URL:Postbox Protocol'
    assert reg['url_protocol'] == ''
    assert reg['command'] == reg['expected_command'] and reg['command'].endswith('" "%1"')

    wa = proof['whatsapp_link']['selected']
    assert wa['id'] == 'business:15550000101@s.whatsapp.net' and wa['provider'] == 'whatsapp' and wa['view_account'] == 'business'

    slack = proof['slack_link']
    assert slack['selected']['id'] == 'slack:T0ALPHA1:C0LAUNCH1' and slack['selected']['provider'] == 'slack' and slack['selected']['view_account'] == 'T0ALPHA1'
    assert slack['scroll_y'] > 0
    assert slack['target_id'] == '1700000005.000100'
    assert slack['target_bubble'][2] > slack['target_bubble'][0]
    assert 0 <= slack['target_bubble'][1] and slack['target_bubble'][3] <= slack['canvas_bottom']

    missing = proof['missing_link']
    assert missing['error'] == 'Could not find that WhatsApp chat.'
    assert missing['before_selected'] == missing['after_selected'] == 'slack:T0ALPHA1:C0LAUNCH1'
    assert missing['before_scroll'] == missing['after_scroll']
    assert missing['draft'] == 'Keep draft unchanged'
    assert missing['selected_message'] == '1700000005.000100'

    cold = proof['cold_start_link']
    assert cold['selected']['id'] == 'personal:15550000101@s.whatsapp.net' and cold['selected']['provider'] == 'whatsapp'
    assert cold['scroll_y'] > 0
    assert cold['target_id'] == 'personal:WA-TARGET-MSG'
    assert cold['target_bubble'][2] > cold['target_bubble'][0]
    assert 0 <= cold['target_bubble'][1] and cold['target_bubble'][3] <= cold['canvas_bottom']

    hashes = {}
    for name in ['whatsapp-link', 'slack-link', 'missing-link', 'cold-start-link']:
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        hashes[name] = hashlib.sha256(image).hexdigest()
    assert len(set(hashes.values())) == 4

    assert read('whatsapp-link.state.json')['selected']['id'] == 'business:15550000101@s.whatsapp.net'
    assert read('slack-link.state.json')['selected']['id'] == 'slack:T0ALPHA1:C0LAUNCH1'
    missing_state = read('missing-link.state.json')
    assert missing_state['selected']['id'] == 'slack:T0ALPHA1:C0LAUNCH1'
    assert missing_state['update_card']['visible'] and missing_state['update_card']['error'] == 'Could not find that WhatsApp chat.'
    assert read('cold-start-link.state.json')['selected']['id'] == 'personal:15550000101@s.whatsapp.net'

    effects = read('side-effects.json')
    assert effects['pending_sends'] == effects['pending_archives'] == 0
    assert effects['production_preferences_absent'] and effects['whatsapp_store_absent']
    assert not (folder / 'failure.txt').exists()
    print('DEEP_LINKS_OK')


if __name__ == '__main__':
    check_evidence(Path(sys.argv[1]))

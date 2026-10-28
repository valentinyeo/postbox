import hashlib
import json
from pathlib import Path
import sys


def check_display(folder, results):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))
    session = read('session.json')
    assert results['version'] == session['expected_version']
    assert session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='voice', status='passed')
    records = read('displayed-results.json')
    assert [row['language'] for row in records] == ['de', 'en']
    sources = {row['id']: row for row in results['cases']}
    images = []
    for row in records:
        assert row['case'] == row['language'] + '-short'
        assert row['formatted'] == sources[row['case']]['formatted']
        assert row['chars'] == len(row['formatted'].encode('utf-16-le')) // 2
        shown = read(row['language'] + '.messages.json')
        assert shown['chat']['id'] == 'fixture-alpha'
        voice = [message for message in shown['messages'] if message['media_type'] == 'audio']
        assert len(voice) == 5 and all(message['local'] and message['transcript_chars'] == row['chars'] for message in voice)
        target = next(message for message in voice if message['id'] == row['message'])
        assert target['bubble'][3] > target['bubble'][1]
        assert row['screenshot'] == row['language'] + '.png'
        image = (folder / row['screenshot']).read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        images.append(hashlib.sha256(image).hexdigest())
    assert len(set(images)) == 2, 'Language screenshots did not change'
    effects = read('side-effects.json')
    assert effects['production_preferences_absent'] and effects['whatsapp_store_absent'] and effects['telegram_store_absent']
    assert effects['pending_sends'] == effects['pending_archives'] == 0
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    return 'VOICE_LANGUAGE_DESKTOP_VERIFIED'


if __name__ == '__main__':
    folder = Path(sys.argv[1])
    results = json.loads((folder.parent / 'results.json').read_text(encoding='utf-8-sig'))
    print(check_display(folder, results))

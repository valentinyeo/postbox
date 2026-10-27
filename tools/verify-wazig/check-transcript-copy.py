from datetime import datetime
import json
from pathlib import Path


def check_transcript_copy(folder):
    folder = Path(folder)

    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    copied = read('transcript-copy.json')
    rows = copied['raw_rows']
    assert [row['id'] for row in rows] == ['VOICE-3', 'VOICE-4', 'VOICE-5']
    assert [datetime.fromisoformat(row['time'].replace('Z', '+00:00')) for row in rows] == sorted(
        datetime.fromisoformat(row['time'].replace('Z', '+00:00')) for row in rows)
    assert all('Grüße, café' in row['raw'] and '\nSecond line stays raw.' in row['raw'] for row in rows)
    expected = '\r\n\r\n'.join(row['raw'] for row in rows)
    assert copied['actual'] == copied['expected'] == expected
    assert set(copied['marked']) == {'VOICE-3', 'VOICE-TEXT', 'VOICE-4', 'VOICE-5'}
    assert copied['labels'] == ['Copy all transcripts']
    assert '4 messages marked' in copied['title'] and 'Copied 3 transcripts' in copied['title']
    missing = read('transcript-missing.json')
    assert missing['missing_id'] == 'VOICE-4'
    assert missing['actual'] == missing['expected'] == '\r\n\r\n'.join(row['raw'] for row in rows if row['id'] != 'VOICE-4')
    assert 'Copied 2 transcripts. Missing: ' + missing['missing_time'] in missing['title']
    selection = read('transcript-selection.json')
    assert selection['range'] == ['VOICE-3', 'VOICE-TEXT', 'VOICE-4', 'VOICE-5']
    assert selection['escape_cleared'] is True and selection['chat_switch_cleared'] is True
    pasted = (folder / 'transcripts-pasted.txt').read_text(encoding='utf-8')
    assert pasted == selection['pasted'].replace('\r\n', '\n') == expected.replace('\r\n', '\n')
    for name in ['transcripts-marked', 'transcripts-palette', 'transcripts-copied', 'transcripts-missing', 'transcripts-pasted']:
        image = (folder / (name + '.png')).read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
    print('TRANSCRIPT_COPY_VERIFIED: marked mixed messages, exact raw clipboard, missing notice, range selection and separate-app paste')

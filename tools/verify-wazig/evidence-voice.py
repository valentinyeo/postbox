from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
def read(name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))

assert session['sha256'] and session['commit']
assert read('result.json') == dict(feature='voice', status='passed')
assert not (folder / 'failure.txt').exists()
transcripts = read('transcripts.json')
assert len(transcripts) == 5 and all(row['chars'] >= 900 and row['file'].endswith('.ogg') for row in transcripts)
checks = read('voice-checks.json')
steps = [check['step'] for check in checks]
assert steps == ['voice-opened', 'voice-scrolled-up', 'voice-scrolled-down', 'voice-expanded', 'voice-expanded-up', 'voice-expanded-down'], steps
tops = set()
for check in checks:
    assert check['problems'] == [] and check['differing'] <= 16 and check['outside'] == 0, check['step']
    assert len(check['repainted']) >= 1, check['step']
    voice = [row for row in check['messages'] if row['media_type'] == 'audio']
    assert len(voice) == 5 and all(row['local'] and row['transcript_chars'] >= 900 for row in voice), check['step']
    tops.add(tuple(row['bubble'][1] for row in voice))
    for name in (check['partial'], check['full']):
        image = (folder / name).read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
assert len(tops) >= 4, 'scrolling and expanding did not move the voice bubbles'
assert not any(row['expanded'] for row in checks[2]['messages']) and any(row['expanded'] for row in checks[3]['messages'])
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
assert actions.count('SendInput: wheel') == 4 and 'SendInput: Show more on VOICE-' in actions
requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
media = {row['wire_path'] for row in requests if row['method'] == 'GET' and row['wire_path'].startswith('/v1/wazig/media/') and row['status'] == 200}
assert len(media) == 5, media
final = read('side-effects.json')
assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert 'JOURNEY PASSED: voice' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
runpy.run_path(str(Path(__file__).with_name('check-transcript-copy.py')))['check_transcript_copy'](folder)
print('EVIDENCE VERIFIED: five downloaded voice notes with cached transcripts, scroll and expand, partial repaints match full repaints')
raise SystemExit(0)

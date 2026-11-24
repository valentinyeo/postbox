import json
import os
import re
from pathlib import Path


def check_evidence(folder):
    folder = Path(folder)

    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'dictation-live' and session['expected_product'] == 'Postbox'
    assert re.fullmatch(r'[0-9a-f]{40}', session['commit'])
    assert re.fullmatch(r'[0-9A-Fa-f]{64}', session['sha256'])
    assert not os.environ.get('GITHUB_SHA') or session['commit'] == os.environ['GITHUB_SHA']
    assert read('result.json') == dict(feature='dictation-live', status='passed')
    assert 'JOURNEY PASSED: dictation-live' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert not (folder / 'failure.txt').exists()
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert not any(row.get('wire_path') == '/v1/wazig/send' for row in requests)
    wire = [row for row in requests if row.get('kind') == 'dictation-live']
    assert wire == read('dictation-live-wire.json')
    assert [row['stage'] for row in wire] == ['open', 'interim', 'revised', 'stop', 'final'] * 3
    cases = [('automatic', 'multi', 'hello', 'hello world', 'Hello world.'),
             ('english', 'en', 'hello', 'hello world', 'Hello world.'),
             ('german', 'de', 'Grü', 'Grüße aus', 'Grüße aus Berlin.')]
    for index, (name, language, first, revised, final) in enumerate(cases):
        rows = wire[index * 5:index * 5 + 5]
        assert all(row['language'] == language for row in rows)
        query = rows[0]['query']
        assert query['interim_results'] == ['true'] and query['encoding'] == ['linear16']
        assert query['sample_rate'] == ['16000'] and query['channels'] == ['1']
        if language == 'multi':
            assert query['language_hint'] == ['en', 'de']
        else:
            assert 'language_hint' not in query
        assert 0 < rows[1]['audio_bytes'] < rows[2]['audio_bytes'] <= rows[3]['audio_bytes']
        assert rows[3]['audio_bytes'] == rows[4]['audio_bytes']
        generation = None
        for stage, text, phase in [('interim', first, 'recording'), ('revised', revised, 'recording'), ('final', final, 'idle')]:
            stem = f'{name}-{stage}'
            observed = read(stem + '.live.json')
            assert observed['pid'] == session['pid'] and str(observed['start_ticks']) == str(session['startTicks'])
            assert observed['commit'] == session['commit'] and observed['sha256'] == session['sha256']
            assert observed['text'] == f'Before {text} after'
            state = observed['state']
            assert state['version'] == session['expected_version']
            assert state['selected']['id'] == 'slack:fixture-workspace:channel-alpha'
            dictation = state['dictation']
            assert dictation['phase'] == phase and dictation['consumed'] == index + (stage == 'final')
            assert dictation['microphone_entries'] == dictation['transcription_attempts'] == 0
            assert not dictation['cancelled'] and dictation['accepted'] == 0
            generation = dictation['generation'] if generation is None else generation
            assert dictation['generation'] == generation == index + 1
            assert (folder / (stem + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
            title = (folder / (stem + '.uia.txt')).read_text(encoding='utf-8-sig').splitlines()[0]
            assert title.endswith('Postbox v' + session['expected_version'])
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert final['dictation']['phase'] == 'idle' and final['dictation']['consumed'] == 3
    assert final['dictation']['microphone_entries'] == final['dictation']['transcription_attempts'] == 0
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert actions.count('keys: ^d') == 6

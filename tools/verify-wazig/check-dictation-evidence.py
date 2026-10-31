import hashlib
import json
import os
from pathlib import Path
import re


ALPHA = 'slack:fixture-workspace:channel-alpha'
BETA = 'slack:fixture-workspace:channel-beta'
ACCOUNT = 'fixture-workspace'
TRANSCRIPT = 'Grüße 世界\nZweite Zeile'


def read(folder, name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))


def jsonlines(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines() if line.strip()]


def snapshot(folder, name, session):
    data = read(folder, name + '.dictation.json')
    assert data['pid'] == session['pid'] and str(data['start_ticks']) == str(session['startTicks'])
    assert data['sha256'] == session['sha256'] and data['commit'] == session['commit']
    state = data['state']
    assert state['version'] == session['expected_version']
    assert state['dictation']['microphone_entries'] == state['dictation']['transcription_attempts'] == 0
    assert (folder / (name + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    title = (folder / (name + '.uia.txt')).read_text(encoding='utf-8-sig').splitlines()[0]
    assert re.fullmatch(r'MessagesZig \| (?:.+ - )?Postbox v' + re.escape(session['expected_version']), title), title
    return data


def origin_text(name):
    return 'Voränderung old\nTail ' + name


def expected_send(name):
    return 'Voränderung ' + TRANSCRIPT + '\nTail ' + name


def check_scope(data, chat=ALPHA):
    selected = data['state']['selected']
    assert selected['id'] == chat and selected['provider'] == 'slack' and selected['account'] == ACCOUNT


def count_sends(folder, name):
    path = folder / (name + '.requests.jsonl')
    if not path.exists():
        return 0
    return sum(row.get('wire_path') == '/v1/wazig/send' for row in jsonlines(path))


def check_evidence(folder):
    folder = Path(folder)
    session = read(folder, 'session.json')
    assert session['feature'] == 'dictation-shortcuts' and session['expected_product'] == 'Postbox'
    assert re.fullmatch(r'\d+\.\d+\.\d+', session['expected_version'])
    assert re.fullmatch(r'[0-9A-Fa-f]{64}', session['sha256'])
    assert re.fullmatch(r'[0-9a-f]{40}', session['commit'])
    assert not os.environ.get('GITHUB_SHA') or session['commit'] == os.environ['GITHUB_SHA']
    assert int(session['pid']) > 0 and int(session['startTicks']) > 0
    assert read(folder, 'result.json') == {'feature': 'dictation-shortcuts', 'status': 'passed'}
    assert 'JOURNEY PASSED: dictation-shortcuts' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert not (folder / 'failure.txt').exists()
    guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
    assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
    final = read(folder, 'side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert final['dictation']['microphone_entries'] == final['dictation']['transcription_attempts'] == 0
    assert final['dictation']['accepted'] == 2 and final['dictation']['phase'] == 'idle'

    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert actions.count('keys: ^d') >= 9
    assert actions.count('keys: ^{ENTER}') >= 4
    assert actions.count('dictation-key: 13 up=False') >= 3
    assert 'dictation-key: 17 up=True' in actions and 'dictation-key: 13 up=True' in actions
    assert actions.count('dictation-key: 27 up=False') >= 8 and actions.count('dictation-key: 27 up=True') >= 4
    for action in ('keys: %a', 'keys: ^f', 'owned-search: {ESC}', 'keys: ^{TAB}', 'keys: ^+{TAB}', 'keys: {ENTER}', 'keys: {ESC}'):
        assert action in actions, action
    assert actions.count('keys: %a') >= 2

    held = snapshot(folder, 'happy-held', session)
    check_scope(held)
    assert held['text'] == origin_text('happy') and held['selection'] == {'start': 12, 'end': 15}
    assert held['state']['dictation']['intent'] == 'sending' and held['state']['dictation']['gate_phase'] == 1
    assert count_sends(folder, 'happy-held') == 0
    sent = snapshot(folder, 'happy-sent-held', session)
    assert sent['text'] == '' and sent['state']['dictation']['accepted'] == 1
    assert count_sends(folder, 'happy-sent-held') == 1
    transcribing = snapshot(folder, 'transcribing-armed', session)
    check_scope(transcribing)
    assert transcribing['text'] == origin_text('transcribing')
    assert transcribing['state']['dictation']['intent'] == 'sending' and transcribing['state']['dictation']['gate_phase'] == 1
    assert count_sends(folder, 'transcribing-armed') == 1
    second = snapshot(folder, 'transcribing-sent', session)
    assert second['text'] == '' and second['state']['dictation']['accepted'] == 2
    assert count_sends(folder, 'transcribing-sent') == 2

    for gate in ('recording', 'transcribe', 'publish', 'consume'):
        name = 'cancel-' + gate
        before = snapshot(folder, name + '-before', session)
        cancelled = snapshot(folder, name + '-cancelled', session)
        released = snapshot(folder, name + '-released', session)
        for stage in (before, cancelled, released):
            check_scope(stage)
            assert stage['text'] == origin_text(name)
            assert count_sends(folder, name + ('-before' if stage is before else '-cancelled' if stage is cancelled else '-released')) == 2
        assert cancelled['selection'] == before['selection'] == {'start': 12, 'end': 15}
        assert cancelled['state']['dictation']['cancelled'] and not released['state']['dictation']['draining']
        assert not released['state']['dictation']['ready'] and released['state']['dictation']['accepted'] == 2
        generation = before['state']['dictation']['generation']
        assert cancelled['state']['dictation']['generation'] == released['state']['dictation']['generation'] == generation
        if gate == 'recording':
            assert before['state']['dictation']['phase'] == 'recording'
        elif gate == 'consume':
            assert before['state']['dictation']['ready'] and not before['state']['dictation']['consume_open']
        else:
            assert before['state']['dictation']['gate_phase'] == (1 if gate == 'transcribe' else 2)
            waiting = snapshot(folder, name + '-still-draining', session)
            assert waiting['state']['dictation']['draining'] and waiting['state']['dictation']['generation'] == generation
            assert waiting['text'] == before['text'] and count_sends(folder, name + '-still-draining') == 2

    inserted = snapshot(folder, 'insert-only', session)
    check_scope(inserted)
    assert inserted['text'] == expected_send('insert-only') and count_sends(folder, 'insert-only') == 2
    for name in ('archive-roundtrip', 'search-roundtrip', 'other-chat'):
        armed = snapshot(folder, name + '-armed', session)
        changed = snapshot(folder, name + '-changed', session)
        finished = snapshot(folder, name + '-finished', session)
        check_scope(armed)
        assert armed['text'] == origin_text(name) and armed['state']['dictation']['intent'] == 'sending'
        assert armed['state']['dictation']['gate_phase'] == 1 and changed['state']['dictation']['intent'] == 'manual'
        assert count_sends(folder, name + '-armed') == count_sends(folder, name + '-changed') == count_sends(folder, name + '-finished') == 2
        if name == 'archive-roundtrip':
            assert armed['state']['include_archived'] == changed['state']['include_archived']
        if name == 'other-chat':
            check_scope(changed, BETA)
            check_scope(finished, BETA)
            assert finished['text'] == 'Other draft stays'
            finished = snapshot(folder, name + '-origin', session)
            check_scope(finished)
            assert count_sends(folder, name + '-origin') == 2
        assert finished['text'] == origin_text(name) + ' ' + TRANSCRIPT

    inactive = snapshot(folder, 'inactive-keys', session)
    assert inactive['text'] == 'Inactive Escape' and count_sends(folder, 'inactive-keys') == 4
    requests = [row for row in jsonlines(folder / 'bridge-requests.jsonl') if row.get('wire_path') == '/v1/wazig/send']
    expected = [expected_send('happy'), expected_send('transcribing'), 'Inactive Enter', 'Inactive Ctrl Enter']
    assert len(requests) == len(expected)
    ledger = jsonlines(folder / 'dictation-accepted.jsonl')
    assert len(ledger) == len(expected)
    captures = jsonlines(folder / 'identity-attempts' / 'index.jsonl')
    assert len(captures) == len(expected)
    ids = set()
    for request, record, capture, text in zip(requests, ledger, captures, expected):
        body = request['body']
        identity = body['client_id']
        assert re.fullmatch(r'[0-9a-f]{32}', identity) and identity not in ids
        ids.add(identity)
        assert request['status'] == 200 and request['authorized'] and request['accepted'] and not request['duplicate']
        assert request['source_provider'] == 'slack' and request['source_account'] == ACCOUNT
        assert body == {'chat': ALPHA, 'text': text, 'reply_to': '', 'client_id': identity}
        assert all(record[key] == value for key, value in dict(provider='slack', account=ACCOUNT, chat=ALPHA,
                                                                  text=text, reply_to='', client_id=identity).items())
        assert record['status'] == 'sent' and record['msg_id'] == 'dictation-' + identity
        assert capture['id'] == identity and capture['attempt'] == 1 and capture['payload'] == ''
        assert capture['snapshot'] == identity + '-1.snapshot.json'
        raw = (folder / 'identity-attempts' / capture['snapshot']).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == capture['snapshot_sha256']
        snapshot_data = json.loads(raw.decode('utf-8-sig'))
        assert snapshot_data['version'] == 2 and snapshot_data['backend'] == session['bridge_url']
        rows = [item for item in snapshot_data['records'] if item['id'] == identity]
        assert len(rows) == 1
        saved = rows[0]
        assert saved['phase'] == 'uncertain' and saved['attempt_serial'] == 1
        assert (saved['provider'], saved['account'], saved['jid'], saved['text'], saved['reply_to']) == ('slack', ACCOUNT, ALPHA, text, '')
    print('DICTATION SHORTCUT EVIDENCE VERIFIED')

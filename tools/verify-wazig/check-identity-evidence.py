from copy import deepcopy
from datetime import datetime
import hashlib
import json
from pathlib import Path, PureWindowsPath
import re


FIELDS = {'id', 'provider', 'account', 'jid', 'text', 'file', 'reply_to', 'reply_sender',
          'client_msg_id', 'attempts', 'ambiguous', 'upload_file_id', 'queued_unix', 'ptt',
          'voice_seconds', 'phase', 'attempt_serial', 'owned_file', 'wire_filename',
          'file_sha256', 'file_bytes', 'attachment_ready', 'failure_reason'}
MUTABLE = {'attempts', 'ambiguous', 'phase', 'attempt_serial', 'failure_reason'}


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def read_identity(folder, requests, backend):
    attempts_dir = folder / 'identity-attempts'
    index = [json.loads(line) for line in (attempts_dir / 'index.jsonl').read_text(encoding='utf-8').splitlines()]
    captures = []
    for row in index:
        assert re.fullmatch(r'[0-9a-f]{32}', row['id'])
        stem = f"{row['id']}-{row['attempt']}"
        assert row['snapshot'] == stem + '.snapshot.json'
        assert row['payload'] in ('', stem + '.payload')
        captures.append(dict(index=row, snapshot=read_json(attempts_dir / row['snapshot']),
                             payload=(attempts_dir / row['payload']).read_bytes() if row['payload'] else b''))
    states = {}
    for prefix in ('identity', 'file-identity'):
        states[prefix] = {}
        for stage in (('held', 'collision', 'restart', 'idle') if prefix == 'file-identity' else ('held', 'restart', 'idle')):
            name = f'{prefix}-{stage}'
            states[prefix][stage] = dict(snapshot=read_json(folder / f'{name}.snapshot.json'),
                                        status=read_json(folder / f'{name}.status.json'),
                                        messages=read_json(folder / f'{name}.messages.json'))
            if stage in ('restart', 'idle'):
                states[prefix][stage]['requests'] = read_json(folder / f'{name}.requests.json')
    return dict(backend=backend, requests=requests, captures=captures, states=states,
                text_source=read_json(folder / 'identity-source.json'),
                text_source_messages=read_json(folder / 'identity-source.messages.json'),
                second_source=read_json(folder / 'identity-second-source.json'),
                file_source=read_json(folder / 'file-identity-source.json'),
                boundaries={prefix: read_json(folder / f'{prefix}-boundary.json')
                            for prefix in ('identity', 'file-identity')},
                original=(folder / 'identity-original.png').read_bytes(),
                held_payload=(folder / 'identity-held.payload').read_bytes())


def record(snapshot, client_id, backend):
    assert set(snapshot) == {'version', 'backend', 'records'}
    assert snapshot['version'] == 2 and snapshot['backend'] == backend
    matches = [r for r in snapshot['records'] if r['id'] == client_id]
    assert len(matches) == 1 and set(matches[0]) == FIELDS
    return matches[0]


def fingerprint(row):
    return {key: row[key] for key in FIELDS - MUTABLE}


def verify_identity(data):
    sends = [r for r in data['requests'] if r.get('wire_path') == '/v1/wazig/send' and
             r.get('body', {}).get('text') in ('Identity fixture', 'Identity file')]
    text = [r for r in sends if r['body']['text'] == 'Identity fixture']
    files = [r for r in sends if r['body']['text'] == 'Identity file']
    assert len(text) == 6 and len(files) == 5 and len(sends) == 11
    text_id, second_id, file_id = text[0]['body']['client_id'], text[-1]['body']['client_id'], files[0]['body']['client_id']
    assert len({text_id, second_id, file_id}) == 3
    assert all(r['body']['client_id'] == text_id for r in text[:5])
    assert all(r['body']['client_id'] == file_id for r in files)
    assert [r['status'] for r in text] == [409, 409, 409, 409, 200, 200]
    assert [r['status'] for r in files] == [409, 409, 409, 409, 200]
    assert sum(r['accepted'] for r in text) == 2 and sum(r['accepted'] for r in files) == 1
    assert all(r['body'] == text[0]['body'] for r in text[:5])
    assert dict(text[-1]['body'], client_id=text_id) == text[0]['body']
    assert all(r['body'] == files[0]['body'] for r in files)
    assert len(data['captures']) == len(sends)
    initial = {}
    for wire, captured in zip(sends, data['captures']):
        index = captured['index']
        client_id = wire['body']['client_id']
        assert index['id'] == client_id
        row = record(captured['snapshot'], client_id, data['backend'])
        assert row['phase'] == 'uncertain' and row['attempt_serial'] == index['attempt']
        assert index['attempt'] == len(initial.get(client_id, [])) + 1
        initial.setdefault(client_id, []).append(row)
        assert wire['body']['chat'] == row['jid'] and wire['body']['text'] == row['text']
        assert wire['body']['reply_to'] == row['reply_to']
        assert wire['body']['client_id'] == row['id']
        if client_id == file_id:
            assert row['attachment_ready'] and not row['ptt'] and row['voice_seconds'] == 0
            assert wire['body']['account'] == 'hub' and wire['body']['ptt'] == 'false'
            assert wire['body']['file'] == row['wire_filename'] == PureWindowsPath(row['file']).name
            owned = PureWindowsPath(row['owned_file'])
            assert owned.name == 'payload' and owned.parent.name == client_id and owned.parent.parent.name == 'new'
            assert owned.parent.parent.parent.name == 'files' and owned.parent.parent.parent.parent.parent.name == 'unified-journal-v2'
            payload = captured['payload']
            assert payload == data['original'] == data['held_payload']
            assert len(payload) == row['file_bytes'] == wire['file_size']
            assert hashlib.sha256(payload).hexdigest() == row['file_sha256'] == wire['file_sha256']
        else:
            assert set(wire['body']) == {'chat', 'text', 'reply_to', 'client_id'}
            assert not captured['payload'] and not row['attachment_ready'] and not row['file'] and not row['owned_file']
            assert not row['ptt'] and row['voice_seconds'] == 0 and row['file_bytes'] == 0
    assert [len(initial[k]) for k in (text_id, second_id, file_id)] == [5, 1, 5]
    for client_id in (text_id, file_id):
        assert all(fingerprint(r) == fingerprint(initial[client_id][0]) for r in initial[client_id])
        assert [r['attempts'] for r in initial[client_id]] == [0, 1, 2, 3, 0]
    for source, client_id in ((data['text_source'], text_id), (data['second_source'], second_id), (data['file_source'], file_id)):
        selected = source['selected']
        row = initial[client_id][0]
        assert selected['id'] and selected['provider'] and selected['account']
        assert (row['jid'], row['provider'], row['account']) == (selected['id'], selected['provider'], selected['account'])
        assert 'view_account' in selected
        assert row['reply_to'] == source['reply']['id']
    assert data['text_source']['reply']['id'] == data['second_source']['reply']['id'] == 'BASELINE'
    source_messages = data['text_source_messages']
    assert all(source_messages['chat'][k] == data['text_source']['selected'][k] for k in ('id', 'provider', 'account'))
    original = [m for m in source_messages['messages'] if m['id'] == 'BASELINE']
    assert len(original) == 1 and initial[text_id][0]['reply_sender'] == original[0]['sender_id']
    assert initial[second_id][0]['reply_sender'] == original[0]['sender_id']
    for prefix, client_id, label in (('identity', text_id, 'Identity fixture'), ('file-identity', file_id, 'Identity file')):
        stages = data['states'][prefix]
        for stage in ('held', 'restart', 'idle'):
            observed = stages[stage]
            row = record(observed['snapshot'], client_id, data['backend'])
            assert row['phase'] == 'held' and row['attempt_serial'] == 4 and row['attempts'] == 4 and row['ambiguous']
            assert fingerprint(row) == fingerprint(initial[client_id][0])
            assert observed['status']['pending_sends'] == 0
            status = observed['status']['unified_snapshot']
            assert status['loaded'] and status['ready'] == 0 and status['inflight'] == 0 and status['held'] >= 1
        assert stages['held']['snapshot'] == stages['restart']['snapshot'] == stages['idle']['snapshot']
        if prefix == 'file-identity':
            collision = stages['collision']
            assert collision['snapshot'] == stages['held']['snapshot']
            assert any(m['id'] == 'identity-collision' and m['text'] == 'Identity file' for m in collision['messages']['messages'])
        expected_requests = text[:4] if prefix == 'identity' else files[:4]
        assert stages['restart']['requests'] == stages['idle']['requests'] == expected_requests
        for stage in ('restart', 'idle'):
            bubbles = [m for m in stages[stage]['messages']['messages'] if m['time'] == client_id and
                       m['text'] == label + ' (unconfirmed)' and m['from_me'] and m['send_state'] == 'failed']
            assert len(bubbles) == 1 and bubbles[0]['bubble'][2] > bubbles[0]['bubble'][0]
        boundary = data['boundaries'][prefix]
        assert boundary['before'] == 4 and boundary['after'] == 5
        assert (datetime.fromisoformat(boundary['click']) - datetime.fromisoformat(boundary['idle_start'])).total_seconds() >= 45


def verify_negative_controls(data):
    def changed_record(mutant, capture, field, value):
        attempt = mutant['captures'][capture]
        row = record(attempt['snapshot'], attempt['index']['id'], mutant['backend'])
        row[field] = value

    controls = {
        'retry source account': lambda m: changed_record(m, 4, 'account', 'wrong-account'),
        'retry reply': lambda m: changed_record(m, 4, 'reply_to', 'other-reply'),
        'retry voice bit': lambda m: changed_record(m, 4, 'ptt', True),
        'file filename': lambda m: changed_record(m, 10, 'wire_filename', 'changed.png'),
        'wire filename': lambda m: next(r for r in reversed(m['requests']) if r.get('body', {}).get('text') == 'Identity file')['body'].update(file='changed.png'),
        'wire reply': lambda m: next(r for r in reversed(m['requests']) if r.get('body', {}).get('text') == 'Identity fixture')['body'].update(reply_to='changed'),
        'autoqueue before click': lambda m: m['states']['identity']['restart']['status']['unified_snapshot'].update(ready=1),
        'inflight before click': lambda m: m['states']['file-identity']['idle']['status']['unified_snapshot'].update(inflight=1),
        'missing terminal bubble': lambda m: m['states']['identity']['restart']['messages'].update(messages=[]),
        'unexpected restart request': lambda m: m['states']['identity']['restart']['requests'].append(m['requests'][-1]),
        'lost collision history': lambda m: m['states']['file-identity']['collision']['messages'].update(messages=[]),
        'short idle': lambda m: m['boundaries']['identity'].update(click=m['boundaries']['identity']['idle_start']),
    }
    for name, mutate in controls.items():
        mutant = deepcopy(data)
        mutate(mutant)
        try:
            verify_identity(mutant)
        except AssertionError:
            continue
        raise AssertionError('accepted identity evidence mutation: ' + name)


def check_identity(folder, requests, backend):
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert 'picker: UIA filename, keyboard path and Enter' in actions
    assert actions.count('SendInput: explicit identity retry') == 2
    assert actions.count('SendInput: choose measured identity Reply menu row') == 2
    for name in ('identity-restart.png', 'file-identity-restart.png'):
        assert (folder / name).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    data = read_identity(folder, requests, backend)
    verify_identity(data)
    verify_negative_controls(data)

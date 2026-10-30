from copy import deepcopy
from datetime import datetime
import hashlib
import json
from pathlib import Path, PureWindowsPath
import re


IMMUTABLE = ('id', 'provider', 'account', 'jid', 'text', 'file', 'reply_to', 'reply_sender',
             'client_msg_id', 'upload_file_id', 'queued_unix', 'ptt', 'voice_seconds',
             'owned_file', 'wire_filename', 'file_sha256', 'file_bytes', 'attachment_ready')
CASES = {'checkpoint': ('Fault checkpoint', 0, 'checkpoint', '1'),
         'terminal': ('Fault terminal file', 4, 'held', '4'),
         'ack': ('Fault ack file', 1, 'acknowledged', '1')}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def load(folder):
    session = read(folder / 'session.json')
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    stages = {}
    for name in CASES:
        stages[name] = {}
        names = ('blocked', 'still-blocked') if name == 'checkpoint' else ('blocked', 'still-blocked', 'restart', 'idle', 'preclick')
        for stage in names:
            stem = f'{name}-{stage}'
            snapshot_bytes = (folder / f'{stem}.snapshot.json').read_bytes()
            payload = folder / f'{stem}.payload'
            stages[name][stage] = dict(snapshot=json.loads(snapshot_bytes.decode('utf-8-sig')), raw=snapshot_bytes,
                                      status=read(folder / f'{stem}.status.json'), requests=read(folder / f'{stem}.requests.json'),
                                      messages=read(folder / f'{stem}.messages.json'), meta=read(folder / f'{stem}.meta.json'),
                                      payload=payload.read_bytes() if payload.exists() else b'')
    captures = []
    directory = folder / 'identity-attempts'
    for line in (directory / 'index.jsonl').read_text(encoding='utf-8').splitlines():
        entry = json.loads(line)
        assert re.fullmatch(r'[0-9a-f]{32}', entry['id'])
        stem = f"{entry['id']}-{entry['attempt']}"
        assert entry['snapshot'] == stem + '.snapshot.json' and entry['payload'] in ('', stem + '.payload')
        captures.append(dict(index=entry, snapshot=read(directory / entry['snapshot']),
                             payload=(directory / entry['payload']).read_bytes() if entry['payload'] else b''))
    return dict(session=session, requests=requests, stages=stages, captures=captures,
                checkpoint_resumed=read(folder / 'checkpoint-resumed.meta.json'),
                sources={name: read(folder / f'{name}.source.json') for name in CASES},
                originals={name: (folder / f'{name}.original.png').read_bytes() for name in ('terminal', 'ack')},
                boundaries={name: read(folder / f'{name}.boundary.json') for name in ('terminal', 'ack')},
                complete={name: read(folder / f'{name}.complete.status.json') for name in CASES},
                retry_markers={p.name: read(p) for p in (folder / 'final-data').glob('verification-retry-*.json')},
                dispatch_markers={p.name: read(p) for p in (folder / 'final-data').glob('verification-dispatch-*.json')})


def get_record(snapshot, identity, backend):
    assert snapshot['version'] == 2 and snapshot['backend'] == backend
    rows = [row for row in snapshot['records'] if row['id'] == identity]
    assert len(rows) == 1 and all(key in rows[0] for key in IMMUTABLE)
    return rows[0]


def immutable(row):
    return tuple(row[key] for key in IMMUTABLE)


def verify(data):
    session = data['session']
    assert session['feature'] == 'hub-fault' and session['sha256'] and session['commit'] and session['root']
    requests = [r for r in data['requests'] if r.get('wire_path') == '/v1/wazig/send' and r.get('body', {}).get('text') in [v[0] for v in CASES.values()]]
    assert len(requests) == len(data['captures']) == 8
    ids = {}
    for name, (label, before, transition, attempt) in CASES.items():
        case_requests = [r for r in requests if r['body']['text'] == label]
        assert len(case_requests) == before + 1
        identity = case_requests[0]['body']['client_id']
        ids[name] = identity
        assert re.fullmatch(r'[0-9a-f]{32}', identity)
        assert all(r['body']['client_id'] == identity for r in case_requests)
        assert sum(r['accepted'] for r in case_requests) == 1 and case_requests[0]['accepted']
        assert [r['status'] for r in case_requests] == ([409] * 4 + [200] if name == 'terminal' else [200] * (before + 1))
        assert all(r['body'] == case_requests[0]['body'] for r in case_requests)
        if before:
            assert case_requests[-1]['duplicate'] and not case_requests[-1]['accepted']
        source = data['sources'][name]
        blocked = data['stages'][name]['blocked']
        durable = get_record(blocked['snapshot'], identity, session['bridge_url'])
        selected = source['selected']
        assert (durable['provider'], durable['account'], durable['jid']) == (selected['provider'], selected['account'], selected['id'])
        assert durable['reply_to'] == source['reply']['id'] and 'view_account' in selected
        assert durable['text'] == label and durable['ptt'] is False and durable['voice_seconds'] == 0
        expected_phase = 'ready' if name == 'checkpoint' else 'uncertain'
        assert durable['phase'] == expected_phase
        assert durable['attempt_serial'] == (0 if name == 'checkpoint' else before)
        for stage in ('blocked', 'still-blocked'):
            item = data['stages'][name][stage]
            row = get_record(item['snapshot'], identity, session['bridge_url'])
            assert row == durable and item['raw'] == blocked['raw']
            meta = item['meta']
            assert hashlib.sha256(item['raw']).hexdigest() == meta['snapshot_sha256']
            assert (meta['fault'], meta['transition'], meta['attempt']) == ('replace', transition, attempt)
            assert meta['pid'] == blocked['meta']['pid'] and meta['start_ticks'] == blocked['meta']['start_ticks']
            state = item['status']['unified_snapshot']
            assert state['loaded'] and state['storage_blocked'] and state['fault_hits'] > 0
            assert state['unsaved_outcomes'] == (0 if name == 'checkpoint' else 1)
            assert state['ready'] == (1 if name == 'checkpoint' else 0)
            assert state['uncertain'] == (0 if name == 'checkpoint' else 1)
            assert state['inflight'] == state['hub_jobs'] == 0
            assert item['requests'] == case_requests[:before]
        if name != 'checkpoint':
            assert data['stages'][name]['still-blocked']['status']['unified_snapshot']['fault_hits'] > blocked['status']['unified_snapshot']['fault_hits']
            original = data['originals'][name]
            assert original.startswith(b'\x89PNG\r\n\x1a\n') and durable['attachment_ready']
            path = PureWindowsPath(durable['owned_file'])
            assert path.name == 'payload' and path.parent.name == identity and path.parent.parent.name == 'new'
            assert path.parent.parent.parent.name == 'files' and path.parent.parent.parent.parent.parent.name == 'unified-journal-v2'
            assert durable['wire_filename'] == PureWindowsPath(durable['file']).name
            for stage in ('blocked', 'still-blocked', 'restart', 'idle', 'preclick'):
                item = data['stages'][name][stage]
                assert item['payload'] == original and len(original) == durable['file_bytes']
                assert hashlib.sha256(original).hexdigest() == durable['file_sha256'] == item['meta']['payload_sha256']
            for stage in ('restart', 'idle', 'preclick'):
                item = data['stages'][name][stage]
                row = get_record(item['snapshot'], identity, session['bridge_url'])
                assert item['raw'] == blocked['raw'] and row['phase'] == 'uncertain' and immutable(row) == immutable(durable)
                state = item['status']['unified_snapshot']
                assert state['loaded'] and not state['storage_blocked'] and state['fault_hits'] == 0 and state['unsaved_outcomes'] == 0
                assert state['ready'] == 0 and state['uncertain'] == 1 and state['inflight'] == 0 and state['hub_jobs'] == 0
                assert item['requests'] == case_requests[:before]
                assert not any(item['meta'][key] for key in ('fault', 'transition', 'attempt'))
                assert (item['meta']['pid'], item['meta']['start_ticks']) != (blocked['meta']['pid'], blocked['meta']['start_ticks'])
                bubbles = [m for m in item['messages']['messages'] if m['time'] == identity and m['text'] == label + ' (unconfirmed)' and m['send_state'] == 'failed' and m['from_me']]
                assert len(bubbles) == 1 and bubbles[0]['bubble'][2] > bubbles[0]['bubble'][0]
            boundary = data['boundaries'][name]
            assert boundary['before'] == before and boundary['after'] == before + 1
            assert (datetime.fromisoformat(boundary['click']) - datetime.fromisoformat(boundary['idle_start'])).total_seconds() >= 45
        else:
            assert not durable['file'] and not durable['owned_file'] and not durable['attachment_ready']
            assert blocked['meta']['composer_text'] == ''
            resumed = data['checkpoint_resumed']
            assert all(resumed[k] == session[k] for k in ('exe', 'sha256', 'commit', 'root'))
            assert resumed['backend'] == session['bridge_url'] and resumed['pid'] and resumed['start_ticks']
            assert (resumed['pid'], resumed['start_ticks']) != (blocked['meta']['pid'], blocked['meta']['start_ticks'])
            assert not any(resumed[key] for key in ('fault', 'transition', 'attempt'))
        complete = data['complete'][name]['unified_snapshot']
        assert complete['ready'] == complete['uncertain'] == complete['held'] == complete['inflight'] == complete['hub_jobs'] == 0
        assert not complete['storage_blocked'] and complete['unsaved_outcomes'] == 0
    assert len(set(ids.values())) == 3
    for case in data['stages'].values():
        for item in case.values():
            meta = item['meta']
            assert all(meta[k] == session[k] for k in ('exe', 'sha256', 'commit', 'root'))
            assert meta['backend'] == session['bridge_url'] and meta['pid'] and meta['start_ticks']
    for wire, capture in zip(requests, data['captures']):
        index = capture['index']
        label = wire['body']['text']
        name = next(k for k, value in CASES.items() if value[0] == label)
        row = get_record(capture['snapshot'], ids[name], session['bridge_url'])
        durable = get_record(data['stages'][name]['blocked']['snapshot'], ids[name], session['bridge_url'])
        assert index['id'] == ids[name] and row['phase'] == 'uncertain' and row['attempt_serial'] == index['attempt']
        assert immutable(row) == immutable(durable)
        assert wire['body']['chat'] == row['jid'] and wire['body']['reply_to'] == row['reply_to']
        manual = name != 'checkpoint' and index['attempt'] == CASES[name][1] + 1
        dispatch = dict(id=ids[name], attempt=index['attempt'], mouse=manual)
        assert index['dispatch_marker'] == dispatch
        assert data['dispatch_markers'][f"verification-dispatch-{ids[name]}-{index['attempt']}.json"] == dispatch
        if manual:
            marker = dict(id=ids[name], attempt=index['attempt'], input='mouse', phase='ready')
            assert index['retry_marker'] == marker
            assert data['retry_markers'][f"verification-retry-{ids[name]}-{index['attempt']}.json"] == marker
        else:
            assert index['retry_marker'] is None
        if name != 'checkpoint':
            assert set(wire['body']) == {'account', 'chat', 'text', 'reply_to', 'client_id', 'ptt', 'file'}
            assert wire['body']['account'] == 'hub' and wire['multipart']
            assert capture['payload'] == data['originals'][name]
            assert wire['body']['file'] == row['wire_filename'] and wire['body']['ptt'] == 'false'
            assert wire['file_size'] == row['file_bytes'] and wire['file_sha256'] == row['file_sha256']
        else:
            assert set(wire['body']) == {'chat', 'text', 'reply_to', 'client_id'}
            assert not capture['payload'] and not wire['multipart']
    for name, (_, before, _, _) in CASES.items():
        attempts = [c['index']['attempt'] for c in data['captures'] if c['index']['id'] == ids[name]]
        assert attempts == list(range(1, before + 2))


def negative_controls(data):
    def record_at(m, case, stage):
        return m['stages'][case][stage]['snapshot']['records'][0]

    controls = {
        'missing fault hit': lambda m: m['stages']['terminal']['blocked']['status']['unified_snapshot'].update(fault_hits=0),
        'wrong durable phase': lambda m: record_at(m, 'terminal', 'blocked').update(phase='held'),
        'wrong durable hash': lambda m: m['stages']['ack']['blocked']['meta'].update(snapshot_sha256='0' * 64),
        'automatic restart request': lambda m: m['stages']['ack']['restart']['requests'].append(m['requests'][-1]),
        'changed identity': lambda m: m['captures'][-1]['index'].update(id='f' * 32),
        'changed filename': lambda m: record_at(m, 'terminal', 'idle').update(wire_filename='wrong.png'),
        'changed reply': lambda m: record_at(m, 'terminal', 'idle').update(reply_to='changed'),
        'changed voice': lambda m: record_at(m, 'terminal', 'idle').update(ptt=True),
        'duplicate acceptance': lambda m: next(r for r in reversed(m['requests']) if r.get('body', {}).get('text') == 'Fault ack file').update(accepted=True),
        'missing owned bytes': lambda m: m['stages']['terminal']['idle'].update(payload=b''),
        'premature unblock': lambda m: m['stages']['ack']['still-blocked']['status']['unified_snapshot'].update(storage_blocked=False),
        'pre-click dispatch': lambda m: m['captures'][-1]['index']['dispatch_marker'].update(mouse=False),
    }
    for name, change in controls.items():
        mutant = deepcopy(data)
        change(mutant)
        try:
            verify(mutant)
        except AssertionError:
            continue
        raise AssertionError('accepted fault evidence mutation: ' + name)


def check_hub_fault(folder):
    data = load(folder)
    verify(data)
    negative_controls(data)
    assert all(row['authorized'] for row in data['requests'] if row['method'] != 'SSE')
    final = read(folder / 'side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
    assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    for name in ('checkpoint-ready-recovery', 'terminal-uncertain-recovery', 'acknowledgement-uncertain-recovery'):
        assert f'hub-fault {name} PASS' in proof
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert actions.count('picker: UIA filename, keyboard path and Enter') == 2
    assert 'SendInput: fault retry terminal ' in actions and 'SendInput: fault retry ack ' in actions
    for name in ('terminal-restart.png', 'ack-restart.png'):
        assert (folder / name).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert 'JOURNEY PASSED: hub-fault' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert not (folder / 'failure.txt').exists()
    print('HUB FAULT EVIDENCE VERIFIED')

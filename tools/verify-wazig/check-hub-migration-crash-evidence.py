from copy import deepcopy
from datetime import datetime, timedelta
import hashlib
import json
from pathlib import Path, PureWindowsPath
import re

OLD = '84769d3edc2a927eab428bfdbc5e98a31fa0bfc0'
IDENTITY = 'dddddddddddddddddddddddddddddddd'
FIELDS = ('id', 'provider', 'account', 'jid', 'text', 'file', 'reply_to', 'reply_sender',
          'client_msg_id', 'upload_file_id', 'queued_unix', 'ptt', 'voice_seconds', 'attempts')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def tree(folder):
    return {p.relative_to(folder).as_posix(): p.read_bytes() for p in folder.rglob('*') if p.is_file()}


def load(folder):
    proof = folder / 'historical-847'
    return dict(session=read(folder / 'session.json'), ownership=read(folder / 'crash-ownership.json'),
                provenance=read(proof / 'provenance.json'), old_binary=(proof / 'old-bin/bin/Messages.exe').read_bytes(),
                old_ctl=(proof / 'old-bin/bin/wazigctl.exe').read_bytes(),
                marker=read(folder / 'crash-marker.json'), process=read(folder / 'crash-process.json'),
                original=read(folder / 'crash-original-before.json'), original_after=read(folder / 'crash-original-after-old.json'),
                original_bytes=(folder / 'crash-original.png').read_bytes(), control=(folder / 'offline-aged-control.before').read_bytes(),
                control_remaining=(folder / 'final-data/msg-cache-r/rollback-aged-control.msg').exists(),
                original_remaining=(folder / 'final-data/msg-cache-r/interrupted-image.png').exists(),
                seed_bytes=(folder / 'crash-seed.jsonl').read_bytes(),
                source_after_old=(folder / 'crash-source-after-old.jsonl').read_bytes() if (folder / 'crash-source-after-old.jsonl').exists() else None,
                boundary=read(folder / 'crash-boundary.private.json'), boundary_files=tree(folder / 'crash-boundary-private'),
                offline_before=read(folder / 'offline-private-before.json'), offline_after=read(folder / 'offline-private-after.json'),
                offline_files_before=tree(folder / 'offline-private-before'), offline_files_after=tree(folder / 'offline-private-after'),
                offline=read(folder / 'offline-cleanup.json'), acl=read(folder / 'offline-acl.json'),
                log_before=(folder / 'offline-before.launch.log').read_text(encoding='utf-8-sig'),
                log_after=(folder / 'offline-after.launch.log').read_text(encoding='utf-8-sig'),
                recovery=read(folder / 'crash-recovery.process.json'), status=read(folder / 'crash-recovery.status.json'),
                snapshot_bytes=(folder / 'crash-recovery.snapshot.json').read_bytes(),
                recovery_manifest=read(folder / 'crash-recovery.private.json'), recovery_files=tree(folder / 'crash-recovery-private'),
                payload=(folder / 'crash-recovery.payload').read_bytes(),
                boundary_requests=read(folder / 'crash-boundary.requests.json'), recovery_requests=read(folder / 'crash-recovery.requests.json'),
                idle_requests=read(folder / 'crash-idle.requests.json'), idle=read(folder / 'crash-idle.json'),
                retry_requests=read(folder / 'crash-retry.requests.json'), retry_status=read(folder / 'crash-retry.status.json'),
                retry_marker=read(folder / 'crash-retry.marker.json'), dispatch=read(folder / 'crash-dispatch.marker.json'))


def verify(data):
    session, own, prov = data['session'], data['ownership'], data['provenance']
    root = PureWindowsPath(own['root'])
    assert session['feature'] in ('hub-migration-crash', 'hub-migration-before-rename') and re.fullmatch(r'r[0-9a-f]{16}', root.name)
    before_rename = session['feature'] == 'hub-migration-before-rename'
    assert own['id'] == session['id'] and re.fullmatch(r'[0-9a-fA-F-]{36}', own['id'])
    assert PureWindowsPath(own['local']) == root / 'local' and PureWindowsPath(own['profile']) == root / 'profile'
    assert own['backend'] == session['bridge_url'] and own['runner_sid']
    assert (session['exe'], session['sha256']) == (own['new_exe'], own['new_sha256'])
    assert re.fullmatch(r'[0-9a-f]{16}', own['source_tag'])
    assert prov['old_commit'] == prov['checked_out_commit'] == prov['checkout_after'] == OLD
    assert prov['candidate_commit'] == session['commit'] and prov['clean_before'] and prov['clean_after'] and prov['build_exit'] == 0
    for name, content in (('Messages.exe', data['old_binary']), ('wazigctl.exe', data['old_ctl'])):
        info = prov['files'][name]
        assert content and info['path'] == 'old-bin/bin/' + name and info['bytes'] == len(content)
        assert info['sha256'] == hashlib.sha256(content).hexdigest()
    assert own['old_sha256'].lower() == prov['files']['Messages.exe']['sha256'] != own['new_sha256'].lower()
    marker, process = data['marker'], data['process']
    assert marker['phase'] == ('after-protect-before-rename' if before_rename else 'after-quarantine-before-import')
    assert marker['id'] == own['id'] and marker['root'] == own['root'] and marker['pid'] == process['pid']
    assert process['start_ticks'] and process['exit_code'] == (85 if before_rename else 86) and process['sid'] == own['runner_sid']
    assert (process['exe'], process['sha256'], process['root'], process['local']) == (own['new_exe'], own['new_sha256'], own['root'], own['local'])
    original = data['original']
    assert PureWindowsPath(original['path']) == root / 'local' / 'Messages' / 'msg-cache-r' / 'interrupted-image.png'
    assert original['exists'] and original['pattern_bytes'] <= 80
    assert original['pattern_bytes'] == len((str(PureWindowsPath(original['path']).parent) + '\\*').encode('utf-8'))
    assert datetime.fromisoformat(original['captured_utc']) - datetime.fromisoformat(original['written_utc']) > timedelta(days=14)
    assert original['bytes'] == len(data['original_bytes']) and original['sha256'] == hashlib.sha256(data['original_bytes']).hexdigest()
    seed = json.loads(data['seed_bytes'].decode('utf-8-sig'))
    assert seed['id'] == IDENTITY and seed['state'] == 'queued' and seed['file'] == original['path']
    assert seed['provider'] == 'slack' and seed['jid'] == 'fixture-alpha' and seed['reply_to'] == 'BASELINE'
    assert seed['text'] == 'Interrupted image' and seed['ptt'] is False and seed['voice_seconds'] == 0
    assert data['boundary'] == data['offline_before'] == data['offline_after']
    assert data['boundary_files'] == data['offline_files_before'] == data['offline_files_after']
    def check_manifest(manifest, files):
        rows = {row['path']: row for row in manifest}
        assert len(rows) == len(manifest) and set(rows) == set(files)
        for path, content in files.items():
            assert all(part not in ('', '.', '..') for part in path.split('/'))
            assert rows[path]['bytes'] == len(content) and rows[path]['sha256'] == hashlib.sha256(content).hexdigest()
    check_manifest(data['boundary'], data['boundary_files'])
    pending = [path for path in data['boundary_files'] if path.startswith('imports/hub-' + own['source_tag'] + '-outbox.jsonl.') and path.endswith('.pending')]
    source_name = 'hub-' + own['source_tag'] + '-outbox.jsonl'
    pending_name = source_name + '.' + hashlib.sha256(data['seed_bytes']).hexdigest()[:32] + '.pending'
    if before_rename:
        assert not pending and marker['pending_name'] == pending_name
        assert PureWindowsPath(marker['source']) == root / 'local' / 'Messages' / source_name
        assert data['source_after_old'] == data['seed_bytes']
    else:
        assert len(pending) == 1 and pending[0] == 'imports/' + pending_name and data['boundary_files'][pending[0]] == data['seed_bytes']
    token = hashlib.sha256((pending_name + '\0' + IDENTITY + '\0' + original['path']).encode('utf-8')).hexdigest()
    assert data['boundary_files']['imports-files/' + token + '/payload'] == data['original_bytes']
    offline, acl = data['offline'], data['acl']
    assert offline['sid'] != own['runner_sid'] == offline['runner_sid'] and offline['sid'] == acl['sid']
    assert acl['registry_absent'] and acl['files_opened_readwrite'] == len(data['boundary_files'])
    assert acl['directories_read_write_delete'] == len({str(Path(path).parent) for path in data['boundary_files']})
    assert (offline['probe_pid'], offline['probe_start_ticks']) == (acl['pid'], acl['start_ticks'])
    assert offline['pid'] and offline['start_ticks'] and offline['sha256'].lower() == prov['files']['Messages.exe']['sha256']
    assert PureWindowsPath(offline['exe']) == root / 'offline' / 'Messages.exe' and offline['local'] == own['local'] and offline['root'] == own['root']
    assert re.fullmatch(r'pb[0-9a-f]{12}', offline['username'])
    assert PureWindowsPath(offline['user_profile_path']).parent.name.lower() == 'users'
    assert PureWindowsPath(offline['user_profile_path']).name.lower().startswith(offline['username'])
    assert re.fullmatch(r'postbox-rollback-[0-9a-f]{32}', offline['firewall_rule'])
    assert not offline['fixture'] and offline['hub_disabled'] and offline['firewall_program'] == offline['exe']
    assert offline['firewall_direction'] == 'Outbound' and offline['firewall_action'] == 'Block' and offline['firewall_profiles_enabled']
    assert all(offline[key] for key in ('profile_removed', 'user_removed', 'firewall_removed', 'control_deleted'))
    assert PureWindowsPath(offline['control_path']) == root / 'local' / 'Messages' / 'msg-cache-r' / 'rollback-aged-control.msg'
    assert data['control'] == b'historical cleanup positive control' and not data['control_remaining']
    assert datetime.fromisoformat(offline['observed_utc']) - datetime.fromisoformat(offline['control_written_utc']) > timedelta(days=14)
    assert data['original_after'] == dict(path=original['path'], absent=True, pid=offline['pid'], start_ticks=offline['start_ticks'])
    assert not data['original_remaining']
    assert data['log_after'].startswith(data['log_before'])
    assert 'whatsapp backend: unavailable (URL not configured)' in data['log_after'][len(data['log_before']):]
    recovery = data['recovery']
    assert recovery['absent'] and recovery['sid'] == own['runner_sid'] and recovery['root'] == own['root'] and recovery['backend'] == own['backend']
    assert (recovery['exe'], recovery['sha256']) == (own['new_exe'], own['new_sha256'])
    assert (recovery['pid'], recovery['start_ticks']) == (session['pid'], session['startTicks']) != (process['pid'], process['start_ticks'])
    snapshot = json.loads(data['snapshot_bytes'].decode('utf-8-sig'))
    assert snapshot['version'] == 2 and snapshot['backend'] == own['backend'] and len(snapshot['records']) == 1
    record = snapshot['records'][0]
    assert all(record[field] == seed[field] for field in FIELDS)
    assert record['phase'] == 'held' and record['ambiguous'] and record['attempt_serial'] == 0 and record['attachment_ready']
    assert record['wire_filename'] == PureWindowsPath(original['path']).name
    assert data['payload'] == data['original_bytes'] and record['file_bytes'] == len(data['payload']) and record['file_sha256'] == original['sha256']
    check_manifest(data['recovery_manifest'], data['recovery_files'])
    assert data['recovery_files']['imports-files/' + token + '/payload'] == data['original_bytes']
    private_root = root / 'local' / 'Messages' / 'unified-journal-v2'
    owned = PureWindowsPath(record['owned_file']).relative_to(private_root).as_posix()
    assert data['recovery_files'][owned] == data['payload']
    snapshots = [p for p in data['recovery_files'] if p.endswith('/snapshot.v2')]
    assert len(snapshots) == 1 and data['recovery_files'][snapshots[0]] == data['snapshot_bytes']
    state = data['status']['unified_snapshot']
    assert state['loaded'] and state['held'] == 1 and state['ready'] == state['uncertain'] == state['inflight'] == state['hub_jobs'] == 0
    assert state['imports_clean'] and state['import_unresolved'] == state['import_overflow'] == 0 and not state['storage_blocked']
    for rows in (data['boundary_requests'], data['recovery_requests'], data['idle_requests']):
        assert not [row for row in rows if row.get('wire_path', '').split('?')[0] == '/v1/wazig/send']
    assert datetime.fromisoformat(data['idle']['idle_end']) - datetime.fromisoformat(data['idle']['idle_start']) >= timedelta(seconds=45)
    sends = [row for row in data['retry_requests'] if row.get('wire_path', '').split('?')[0] == '/v1/wazig/send']
    assert len(sends) == 1
    wire = sends[0]
    assert wire['accepted'] and not wire['duplicate'] and wire['status'] == 200 and wire['multipart']
    assert wire['file_size'] == len(data['payload']) and wire['file_sha256'] == original['sha256']
    body = wire['body']
    assert body['client_id'] == IDENTITY and body['chat'] == seed['jid'] and body['text'] == seed['text']
    assert body['account'] == 'hub' and body['reply_to'] == seed['reply_to'] and body['ptt'] == 'false' and body['file'] == record['wire_filename']
    assert data['retry_marker'] == dict(id=IDENTITY, attempt=1, input='mouse', phase='ready')
    assert data['dispatch'] == dict(id=IDENTITY, attempt=1, mouse=True)
    final = data['retry_status']['unified_snapshot']
    assert final['ready'] == final['uncertain'] == final['inflight'] == final['hub_jobs'] == 0 and not final['storage_blocked']


def negative_controls(data):
    controls = {
        'wrong phase': lambda m: m['marker'].update(phase='before-quarantine'),
        'original retained': lambda m: m['original_after'].update(absent=False),
        'private payload changed': lambda m: m.update(payload=b'changed'),
        'automatic send': lambda m: m['idle_requests'].append({'wire_path': '/v1/wazig/send'}),
        'wrong id': lambda m: m['retry_marker'].update(id='e' * 32),
        'wrong historical binary': lambda m: m['offline'].update(sha256=m['ownership']['new_sha256']),
        'missing aged control': lambda m: m['offline'].update(control_deleted=False),
    }
    if data['session']['feature'] == 'hub-migration-before-rename':
        controls['changed planned name'] = lambda m: m['marker'].update(pending_name='different.pending')
        controls['changed source'] = lambda m: m.update(source_after_old=b'changed')
    for name, mutation in controls.items():
        mutant = deepcopy(data)
        mutation(mutant)
        try:
            verify(mutant)
        except AssertionError:
            continue
        raise AssertionError('accepted migration crash mutation: ' + name)


def check_hub_migration_crash(folder):
    data = load(folder)
    verify(data)
    negative_controls(data)
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    feature = data['session']['feature']
    assert feature + ' old-offline-cache-cleanup PASS' in proof
    assert feature + ' interrupted-migration-recovered PASS' in proof
    final = read(folder / 'side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    assert 'JOURNEY PASSED: ' + feature in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert not (folder / 'failure.txt').exists()
    print('HUB INTERRUPTED MIGRATION EVIDENCE VERIFIED')

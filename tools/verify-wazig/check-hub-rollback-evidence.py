from copy import deepcopy
from datetime import datetime, timedelta
import hashlib
import json
from pathlib import Path, PureWindowsPath
import re

OLD = '84769d3edc2a927eab428bfdbc5e98a31fa0bfc0'
IDS = ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
FIELDS = ('id', 'provider', 'account', 'jid', 'text', 'file', 'reply_to', 'reply_sender',
          'client_msg_id', 'upload_file_id', 'queued_unix', 'ptt', 'voice_seconds', 'attempts')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def load(folder):
    proof = folder / 'historical-847'
    provenance = read(proof / 'provenance.json')
    binaries = {name: (proof / info['path']).read_bytes() for name, info in provenance['files'].items()}
    imports = {p.name: p.read_bytes() for p in (folder / 'rollback-new-imports').glob('*.pending')}
    journals = {p.name: p.read_bytes() for p in (folder / 'rollback-old-journals').glob('*outbox.jsonl')}
    offline_files = [{p.relative_to(folder / directory).as_posix(): p.read_bytes()
                      for p in (folder / directory).rglob('*') if p.is_file()}
                     for directory in ('offline-private-before', 'offline-private-after')]
    return dict(session=read(folder / 'session.json'), provenance=provenance, binaries=binaries,
                offline=read(folder / 'offline-cleanup.json'), offline_acl=read(folder / 'offline-acl.json'),
                offline_before=read(folder / 'offline-private-before.json'), offline_after=read(folder / 'offline-private-after.json'),
                offline_files=offline_files, offline_control=(folder / 'offline-aged-control.before').read_bytes(),
                offline_control_remaining=(folder / 'final-data/msg-cache-r/rollback-aged-control.msg').exists(),
                offline_log_before=(folder / 'offline-before.launch.log').read_text(encoding='utf-8-sig'),
                offline_log_after=(folder / 'offline-after.launch.log').read_text(encoding='utf-8-sig'),
                old_binary_path=str((proof / 'old-bin/bin/Messages.exe').resolve()),
                old_control_path=str((proof / 'old-bin/bin/wazigctl.exe').resolve()),
                log=(proof / 'build.log').read_bytes(), checkout_log=(proof / 'checkout.log').read_bytes(),
                ownership=read(folder / 'rollback-ownership.json'),
                source_status=read(folder / 'rollback-source.status.json'),
                account_tag=(folder / 'rollback-account-tag.txt').read_text(encoding='utf-8-sig').strip(),
                seed=[json.loads(line) for line in (folder / 'rollback-seed.jsonl').read_text(encoding='utf-8-sig').splitlines()],
                direct_before=(folder / 'rollback-direct-before.jsonl').read_bytes(),
                direct_after=(folder / 'rollback-direct-after-new.jsonl').read_bytes(),
                original=(folder / 'rollback-original.png').read_bytes(),
                private_before=(folder / 'rollback-private.payload').read_bytes(),
                private_after=(folder / 'rollback-old.payload').read_bytes(),
                new_snapshot=(folder / 'rollback-new.snapshot.json').read_bytes(),
                old_snapshot=(folder / 'rollback-old.snapshot.json').read_bytes(),
                new_private=read(folder / 'rollback-new.private.json'), old_private=read(folder / 'rollback-old.private.json'),
                imports=imports, journals=journals,
                new_status=read(folder / 'rollback-new.status.json'), old_status=read(folder / 'rollback-old.status.json'),
                new_process=read(folder / 'rollback-new.process.json'), old_process=read(folder / 'rollback-old.process.json'),
                new_requests=read(folder / 'rollback-new.requests.json'), old_start_requests=read(folder / 'rollback-old-start.requests.json'),
                old_requests=read(folder / 'rollback-old.requests.json'),
                mutex=read(folder / 'mutex.json'), mutex_before=read(folder / 'mutex-before.profile.json'),
                mutex_after=read(folder / 'mutex-after.profile.json'), mutex_requests_before=read(folder / 'mutex-before.requests.json'),
                mutex_requests_after=read(folder / 'mutex-after.requests.json'),
                log_before=(folder / 'rollback-before-old.launch.log').read_text(encoding='utf-8-sig'),
                log_after=(folder / 'rollback-old.launch.log').read_text(encoding='utf-8-sig'))


def verify(data):
    session, old, ownership = data['session'], data['provenance'], data['ownership']
    assert session['feature'] == 'hub-rollback' and re.fullmatch(r'[0-9a-fA-F-]{36}', session['id'])
    assert old['old_commit'] == old['checked_out_commit'] == old['checkout_after'] == OLD
    assert re.fullmatch(r'[0-9a-f]{40}', old['old_tree']) and old['clean_before'] and old['clean_after']
    assert old['candidate_commit'] == session['commit'] and old['zig_version'] == '0.16.0' and old['build_exit'] == 0
    assert set(['build', '-Dtarget=x86_64-windows-gnu', '--release=small', '-Dversion=0.0.526', '--prefix']) <= set(old['build_arguments'])
    assert old['worktree'] != old['candidate_checkout'] and old['build_log'] == 'build.log'
    assert data['checkout_log'] and data['log'] is not None
    files = old['files']
    expected_files = {'Messages.exe', 'wazigctl.exe', 'postboxctl.exe', 'IBMPlexSans-Regular.ttf', 'IBMPlexSans-Medium.ttf', 'IBMPlexSans-SemiBold.ttf', 'IBMPlexSans-Bold.ttf', 'IBMPlexSans-Italic.ttf', 'IBMPlexMono-Regular.ttf', 'IBM-Plex-LICENSE.txt'}
    assert set(files) == set(data['binaries']) == expected_files
    for name in expected_files:
        content = data['binaries'][name]
        assert content and len(content) == files[name]['bytes'] and hashlib.sha256(content).hexdigest() == files[name]['sha256']
        assert files[name]['path'] == 'old-bin/bin/' + name
    assert files['wazigctl.exe']['sha256'] == files['postboxctl.exe']['sha256']
    assert all(re.fullmatch(r'[0-9a-f]{64}', row['sha256']) and re.fullmatch(r'[0-9a-f]{40}', row['git_blob']) for row in old['source_sha256'].values())
    assert {'build.zig', 'src/main.zig', 'src/wazigctl.zig', 'src/font_config.zig'} <= set(old['source_sha256'])
    assert all('assets/' + name in old['source_sha256'] and old['source_sha256']['assets/' + name]['sha256'] == files[name]['sha256'] for name in expected_files if name.endswith(('.ttf', '.txt')))
    assert ownership['id'] == session['id'] and ownership['root'] == session['root']
    root = PureWindowsPath(ownership['root'])
    assert re.fullmatch(r'r[0-9a-f]{16}', root.name)
    assert PureWindowsPath(ownership['local']) == root / 'local' and PureWindowsPath(ownership['profile']) == root / 'profile'
    assert ownership['cleanup_pattern'] == str(root / 'local' / 'Messages' / 'msg-cache-r') + '\\*'
    assert len(ownership['cleanup_pattern'].encode('utf-8')) == ownership['cleanup_pattern_bytes'] <= 80
    assert ownership['backend'] == session['bridge_url'] and ownership['runner_sid']
    assert re.fullmatch(r'[0-9a-f]{16}', ownership['source_tag'])
    assert ownership['source_tag'] == data['account_tag'] == data['source_status']['legacy_hub_tag']
    assert ownership['old_sha256'].lower() == files['Messages.exe']['sha256']
    assert ownership['new_sha256'].lower() != ownership['old_sha256'].lower()
    assert PureWindowsPath(ownership['old_exe']).name == 'Messages.exe' and ownership['old_exe'] != ownership['new_exe']
    new, old_process, mutex = data['new_process'], data['old_process'], data['mutex']
    for process in (new, old_process):
        assert process['root'] == ownership['root'] and process['local'] == ownership['local']
        assert process['backend'] == ownership['backend'] and process['sid'] == ownership['runner_sid']
        assert process['pid'] and process['start_ticks']
    assert (new['exe'], new['sha256']) == (ownership['new_exe'], ownership['new_sha256'])
    assert (old_process['exe'], old_process['sha256']) == (ownership['old_exe'], ownership['old_sha256'])
    assert (new['pid'], new['start_ticks']) != (old_process['pid'], old_process['start_ticks'])
    assert session['pid'] == old_process['pid'] and session['startTicks'] == old_process['start_ticks']
    assert session['exe'] == old_process['exe'] and session['sha256'] == old_process['sha256']
    assert PureWindowsPath(old_process['exe']) == PureWindowsPath(data['old_binary_path'])
    assert PureWindowsPath(session['ctl']) == PureWindowsPath(data['old_control_path'])
    assert mutex['sid'] == ownership['runner_sid'] and mutex['local'] == ownership['local'] and mutex['root'] == ownership['root']
    assert (mutex['exe'], mutex['sha256']) == (ownership['old_exe'], ownership['old_sha256'])
    assert mutex['incumbent_pid'] == new['pid'] and mutex['incumbent_start_ticks'] == new['start_ticks']
    assert mutex['pid'] and mutex['start_ticks'] and mutex['pid'] != new['pid']
    assert mutex['reason'] == 'Postbox is already running. Close that window before starting another instance.' and mutex['exit_code'] == 0
    def protected(rows):
        result = {}
        for row in rows:
            path = row['path']
            if path.lower().startswith('unified-journal-v2/') or ('/' not in path and path.lower().endswith('outbox.jsonl')):
                assert all(part not in ('', '.', '..') for part in path.split('/')) and path not in result
                result[path] = (row['bytes'], row['sha256'])
        return result
    before, after = protected(data['mutex_before']), protected(data['mutex_after'])
    assert before == after
    assert {path.removeprefix('unified-journal-v2/'): value for path, value in before.items() if path.startswith('unified-journal-v2/')} == {
        row['path']: (row['bytes'], row['sha256']) for row in data['new_private']
    }
    assert before['outbox.jsonl'] == (len(data['direct_after']), hashlib.sha256(data['direct_after']).hexdigest())
    assert [row for row in data['mutex_requests_before'] if row.get('method') not in ('GET', 'SSE')] == [
        row for row in data['mutex_requests_after'] if row.get('method') not in ('GET', 'SSE')
    ]
    assert data['log_after'].startswith(data['log_before'])
    assert 'verification: hub fixture ready' in data['log_after'][len(data['log_before']):]
    assert data['old_status']['version'] == '0.0.526' and data['old_status']['chat_count'] > 0 and data['old_status']['pending_sends'] == 0
    state = data['new_status']['unified_snapshot']
    assert state['loaded'] and state['imports_clean'] and not state['storage_blocked']
    assert state['held'] == 2 and state['ready'] == state['uncertain'] == state['inflight'] == state['hub_jobs'] == 0
    assert state['import_unresolved'] == state['import_overflow'] == 0
    assert data['direct_before'] == data['direct_after']
    direct = json.loads(data['direct_before'].decode('utf-8-sig'))
    assert direct['provider'] == 'signal' and direct['state'] == 'failed' and direct['id'] not in IDS
    assert len(data['seed']) == 2 and tuple(row['id'] for row in data['seed']) == IDS
    assert data['new_snapshot'] == data['old_snapshot'] and data['new_private'] == data['old_private']
    snapshot = json.loads(data['new_snapshot'].decode('utf-8-sig'))
    assert snapshot['version'] == 2 and snapshot['backend'] == ownership['backend'] and len(snapshot['records']) == 2
    manifest = {row['path']: row for row in data['new_private']}
    assert len(manifest) == len(data['new_private'])
    for path, row in manifest.items():
        parts = path.split('/')
        assert all(part not in ('', '.', '..') for part in parts)
        assert type(row['bytes']) is int and row['bytes'] >= 0 and re.fullmatch(r'[0-9a-f]{64}', row['sha256'])
    snapshots = [path for path in manifest if path.endswith('/snapshot.v2')]
    assert len(snapshots) == 1
    def matches(path, content):
        assert path in manifest and manifest[path]['bytes'] == len(content)
        assert manifest[path]['sha256'] == hashlib.sha256(content).hexdigest()
    matches(snapshots[0], data['new_snapshot'])
    assert data['imports'] and all(name.startswith('hub-' + ownership['source_tag'] + '-outbox.jsonl.') for name in data['imports'])
    assert {path for path in manifest if path.startswith('imports/') and path.endswith('.pending')} == {'imports/' + name for name in data['imports']}
    for name, content in data['imports'].items():
        matches('imports/' + name, content)
    for seed in data['seed']:
        record, = [r for r in snapshot['records'] if r['id'] == seed['id']]
        assert all(record[field] == seed[field] for field in FIELDS)
        assert seed['state'] == 'queued' and record['phase'] == 'held' and record['ambiguous'] and record['attempt_serial'] == 0
        assert record['failure_reason'] == 'delivery unconfirmed'
        if seed['file']:
            owned = PureWindowsPath(record['owned_file'])
            assert owned.name == 'payload' and 'unified-journal-v2' in owned.parts and 'files' in owned.parts
            assert record['attachment_ready'] and record['wire_filename'] == PureWindowsPath(seed['file']).name
            assert data['original'] == data['private_before'] == data['private_after']
            private_root = root / 'local' / 'Messages' / 'unified-journal-v2'
            matches(owned.relative_to(private_root).as_posix(), data['private_before'])
            assert len(data['original']) == record['file_bytes'] and hashlib.sha256(data['original']).hexdigest() == record['file_sha256']
        else:
            assert not record['attachment_ready'] and not record['owned_file'] and not record['file_bytes']
    assert data['imports'] and data['journals']
    for raw in (*data['imports'].values(), *data['journals'].values()):
        assert all(identity.encode() not in raw for identity in IDS)
    for rows in (data['new_requests'], data['old_start_requests'], data['old_requests']):
        assert all(identity not in json.dumps(rows) for identity in IDS)
    assert len(data['old_requests']) >= len(data['old_start_requests'])
    offline, acl = data['offline'], data['offline_acl']
    assert re.fullmatch(r'pb[0-9a-f]{12}', offline['username'])
    assert PureWindowsPath(offline['user_profile_path']).parent.name.lower() == 'users'
    assert PureWindowsPath(offline['user_profile_path']).name.lower().startswith(offline['username'])
    assert offline['sid'] != ownership['runner_sid'] == offline['runner_sid']
    assert offline['sid'] == acl['sid'] and acl['registry_absent']
    assert (offline['probe_pid'], offline['probe_start_ticks']) == (acl['pid'], acl['start_ticks'])
    assert offline['pid'] and offline['start_ticks'] and offline['pid'] != acl['pid']
    assert (offline['pid'], offline['start_ticks']) not in ((new['pid'], new['start_ticks']), (old_process['pid'], old_process['start_ticks']))
    assert offline['root'] == ownership['root'] and offline['local'] == ownership['local'] and offline['profile'] == ownership['profile']
    assert PureWindowsPath(offline['exe']) == root / 'offline' / 'Messages.exe'
    assert offline['sha256'].lower() == files['Messages.exe']['sha256']
    assert not offline['fixture'] and offline['hub_disabled']
    assert re.fullmatch(r'postbox-rollback-[0-9a-f]{32}', offline['firewall_rule'])
    assert offline['firewall_program'] == offline['exe'] and offline['firewall_direction'] == 'Outbound'
    assert offline['firewall_action'] == 'Block' and offline['firewall_profiles_enabled']
    assert all(offline[key] for key in ('profile_removed', 'user_removed', 'firewall_removed'))
    assert PureWindowsPath(offline['control_path']) == root / 'local' / 'Messages' / 'msg-cache-r' / 'rollback-aged-control.msg'
    assert data['offline_control'] == b'historical cleanup positive control'
    assert datetime.fromisoformat(offline['observed_utc']) - datetime.fromisoformat(offline['control_written_utc']) > timedelta(days=14)
    assert offline['control_deleted'] and not data['offline_control_remaining']
    assert data['offline_log_after'].startswith(data['offline_log_before'])
    assert 'whatsapp backend: unavailable (URL not configured)' in data['offline_log_after'][len(data['offline_log_before']):]
    assert data['offline_before'] == data['old_private'] == data['offline_after']
    assert data['offline_files'][0] == data['offline_files'][1]
    assert set(data['offline_files'][0]) == set(manifest)
    for path, content in data['offline_files'][0].items():
        matches(path, content)
    assert acl['files_opened_readwrite'] == len(manifest)
    assert acl['directories_read_write_delete'] == len({str(Path(path).parent) for path in manifest})


def negative_controls(data):
    def mutate_old_binary(m):
        m['old_process']['sha256'] = m['ownership']['new_sha256']

    incidental = deepcopy(data)
    incidental['mutex_after'].append({'path': 'launch-log.txt', 'bytes': 1, 'sha256': '0' * 64})
    incidental['mutex_requests_after'].extend([{'method': 'GET', 'path': '/v1/wazig/chats'}, {'method': 'SSE', 'path': '/v1/wazig/events'}])
    verify(incidental)

    controls = {
        'wrong historical binary': mutate_old_binary,
        'migrated identity visible': lambda m: m['journals'].update(injected=IDS[0].encode()),
        'changed private bytes': lambda m: m.update(private_after=b'changed'),
        'unlinked snapshot': lambda m: m['new_private'][0].update(sha256='0' * 64),
        'bypassed mutex': lambda m: m['mutex'].update(reason='unexpected success'),
        'mutex private bytes changed': lambda m: next(row for row in m['mutex_after'] if row['path'].startswith('unified-journal-v2/')).update(sha256='0' * 64),
        'mutex journal changed': lambda m: next(row for row in m['mutex_after'] if row['path'] == 'outbox.jsonl').update(sha256='0' * 64),
        'mutex mutating request': lambda m: m['mutex_requests_after'].append({'method': 'POST', 'path': '/v1/wazig/send'}),
        'skipped old cleanup': lambda m: m['offline'].update(control_deleted=False),
        'changed offline private bytes': lambda m: m['offline_files'][1].update({next(iter(m['offline_files'][1])): b'changed'}),
        'wrong offline binary': lambda m: m['offline'].update(sha256=m['ownership']['new_sha256']),
        'same user offline': lambda m: m['offline'].update(sid=m['ownership']['runner_sid']),
        'missing ACL probe': lambda m: m['offline_acl'].update(directories_read_write_delete=0),
    }
    for name, mutation in controls.items():
        mutant = deepcopy(data)
        mutation(mutant)
        try:
            verify(mutant)
        except AssertionError:
            continue
        raise AssertionError('accepted rollback evidence mutation: ' + name)


def check_hub_rollback(folder):
    data = load(folder)
    verify(data)
    negative_controls(data)
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert 'hub-rollback complete-migration-old-loader PASS' in proof
    assert 'hub-rollback same-user-profile-mutex PASS' in proof
    assert 'hub-rollback old-offline-cache-cleanup PASS' in proof
    final = read(folder / 'side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))
    guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
    assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
    assert 'JOURNEY PASSED: hub-rollback' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert not (folder / 'failure.txt').exists()
    print('HUB ROLLBACK LOADER AND MUTEX EVIDENCE VERIFIED')

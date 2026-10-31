import argparse
import hashlib
import json
from pathlib import Path
import runpy


HERE = Path(__file__).resolve().parent


def read(folder, name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))


def palette_chat_labels(query):
    rows = read(HERE, 'search-queries.json')['rows']
    return [row['name'] + ('  ·  Archived' if row['archived'] else '') for row in rows
            if any(query.lower() in row[key].lower() for key in ('name', 'jid'))]


def check_sample(sample, query, fixed):
    assert sample['query'] == sample['state']['search'] == query
    assert sample['focused'] and sample['palette'] == fixed
    assert sample['edit_id'] == ('1064' if fixed else '1008')
    rows = sample['rows']
    identities = [f"{row['provider']}|{row['account']}|{row['id']}" for row in rows]
    assert sample['identities'] == identities and len(set(identities)) == len(identities)
    assert sample['state']['chat_count'] == len(rows)
    labels = sample['labels']
    if not fixed:
        assert sample['native_count'] == len(rows)
        assert labels == [row['name'] for row in rows]
    else:
        assert sample['native_count'] == len(labels)
        known = palette_chat_labels(query)
        count = next((index for index, label in enumerate(labels) if label not in known), len(labels))
        chats = labels[:count]
        expected = [row['name'] + ('  ·  Archived' if row['archived'] else '') for row in rows]
        assert set(expected).issubset(chats) and len(chats) == len(set(chats)), ('search omitted or duplicated a visible chat', query, labels, expected)
        assert not any(label in known for label in labels[count:]), 'chat repeated in commands'
        if query == 'archive' and chats:
            assert count < 10 and len(labels) > count, 'commands displaced chats or disappeared'
            assert any('Archive' in label or 'archived' in label for label in labels[count:])
    assert sample['state']['pending_sends'] == sample['state']['pending_archives'] == 0
    return identities


def check_parity(data, fixture, fixed):
    assert data['schema'] == fixture['schema'] == 1 and data['baseline'] == (not fixed)
    assert data['commit'] and data['sha256'] and len(data['records']) == len(fixture['queries'])
    ordered = []
    for record, case in zip(data['records'], fixture['queries']):
        assert record['case'] == case
        samples = record['samples']
        assert [sample['shortcut'] for sample in samples] == ['^f', '/']
        first, second = [check_sample(sample, case['query'], fixed) for sample in samples]
        assert first == second, ('within-run parity', case['query'], first, second)
        expected = [row for row in fixture['rows'] if row['archived'] == case.get('archived_only', False)
                    and not case.get('unread_only', False)
                    and any(case['query'].lower() in row[key].lower() for key in ('name', 'jid'))]
        assert {(row['provider'], row['id']) for row in samples[0]['rows']} == {(row['provider'], row['jid']) for row in expected}, case
        for sample in samples:
            for row in sample['rows']:
                known = next(item for item in expected if item['jid'] == row['id'])
                provider = known['provider']
                scope = known.get('account') or (known['jid'].split(':')[1] if provider == 'slack' else known['jid'].split(':')[0] if provider == 'whatsapp' else provider)
                assert row['provider'] == provider and row['view_account'] == scope, ('source account mismatch', row)
            assert sample['state']['show_archived'] == case.get('archived_only', False)
            assert sample['state']['unread_only'] == case.get('unread_only', False)
            assert not sample['state']['include_archived'] and sample['state']['current_view']['inbox']
        if case['category'] == 'empty-list':
            assert record['empty_start'] and not first
        ordered.append(first)
    return ordered


def check_removal(removal):
    assert removal['controls'] == 0 and removal['native'] is False and removal['labels'] == []
    assert abs(removal['list_top'] - removal['client_top']) <= 1


def check_shortcuts(samples):
    assert [sample['shortcut'] for sample in samples] == ['^f', '/']
    for sample in samples:
        identities = check_sample(sample, 'Beta', True)
        assert len(identities) == 1 and sample['rows'][0]['name'] == 'Verification Beta'


def check_ink(image, layout):
    measure = runpy.run_path(str(HERE / 'check-archive-presentation.py'))['measure']
    sample = layout['sample']
    check_sample(sample, 'Verification', True)
    rows = sample['rows']
    assert len(rows) == 2 and sum(row['archived'] for row in rows) == 1
    results = {}
    for row in rows:
        label = row['name'] + ('  ·  Archived' if row['archived'] else '')
        index = sample['labels'].index(label)
        y = layout['y'] + index * layout['row_height']
        assert (index + 1) * layout['row_height'] <= layout['height']
        results['archived' if row['archived'] else 'live'] = measure(image, [layout['x'] + 46, y + 4, layout['x'] + 221, y + layout['row_height'] - 4])
    live, archived = results['live'], results['archived']
    assert live['contrast'] >= 4.5 and 1.5 < archived['contrast'] < live['contrast']
    assert max(abs(a - b) for a, b in zip(live['text'], archived['text'])) > 15, 'archived ink not dimmed'
    return results


def check_groups(image, layout):
    measure = runpy.run_path(str(HERE / 'check-archive-presentation.py'))['measure']
    sample = layout['sample']
    check_sample(sample, 'archive', True)
    known = palette_chat_labels(sample['query'])
    commands = next((index for index, label in enumerate(sample['labels']) if label not in known), len(sample['labels']))
    assert 0 < commands < len(sample['labels']) and (commands + 1) * layout['row_height'] <= layout['height']
    for index in (0, commands):
        x = layout['x'] + layout['width']
        y = layout['y'] + index * layout['row_height']
        tag = measure(image, [x - 120, y + 2, x - 16, y + 20])
        assert tag['contrast'] >= 3, 'missing readable chat/command group tag'


def load_parity(folder, fixed):
    fixture = read(folder, 'search-queries.json')
    assert fixture == read(HERE, 'search-queries.json'), 'different query/fixture contract'
    data = read(folder, 'search-parity.json')
    session = read(folder, 'session.json')
    assert data['commit'] == session['commit'] and data['sha256'] == session['sha256']
    digest = hashlib.sha256((folder / 'search-queries.json').read_bytes()).hexdigest()
    assert data['query_sha256'].lower() == digest
    return fixture, data, check_parity(data, fixture, fixed)


def source_identities(data):
    return [[f"{row['provider']}|{row['view_account']}|{row['id']}" for row in record['samples'][0]['rows']]
            for record in data['records']]


def check_cross_run(before, after):
    assert before == after, ('cross-run identity/order mismatch', before, after)


def compare(baseline, fixed):
    fixture, before, old = load_parity(baseline, False)
    other, after, new = load_parity(fixed, True)
    assert 'Sidebar search bar remains; baseline parity was captured before this intentional red assertion' in (baseline / 'failure.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (baseline / 'cleanup.txt').read_text(encoding='utf-8-sig')
    removal = read(baseline, 'search-removal.json')
    assert removal['controls'] == 1 and removal['native'] is True
    assert fixture == other and before['query_sha256'] == after['query_sha256']
    assert before['commit'] != after['commit'] and before['sha256'] != after['sha256']
    check_cross_run(source_identities(before), source_identities(after))
    check_evidence(fixed)
    print(f'SEARCH PARITY VERIFIED: {len(old)} queries, exact ordered identities across bar and palette')


def check_evidence(folder):
    fixture, data, ordered = load_parity(folder, True)
    check_removal(read(folder, 'search-removal.json'))
    check_shortcuts(read(folder, 'search-shortcuts.json'))
    read_png = runpy.run_path(str(HERE / 'check-workspace-icons.py'))['read_png']
    _, _, image = read_png(folder / 'search-archive.png')
    check_ink(image, read(folder, 'search-archive.json'))
    _, _, image = read_png(folder / 'search-groups.png')
    check_groups(image, read(folder, 'search-groups.json'))
    removed = read(folder, 'removed-status.json')
    assert removed['positive_query'] == 'Keyboard shortcuts' and removed['positive_matches'] == 1
    assert removed['query'] == 'Status' and removed['status_rows'] == removed['sidebar_status_controls'] == 0
    before = read(folder, 'before.state.json')
    matched = read(folder, 'search-match.state.json')
    empty = read(folder, 'empty.state.json')
    assert before['chat_count'] == 6 and before['search'] == ''
    assert matched['chat_count'] == 1 and matched['search'] == 'Beta' and matched['selected']['name'] == 'Verification Beta'
    assert empty['chat_count'] == 0 and empty['search'] == 'NoSuchFixture'
    for stage in ('before', 'search-match', 'empty', 'search-archive', 'search-groups', 'removed-status', 'action', 'after'):
        raw = (folder / f'{stage}.png').read_bytes()
        assert raw.startswith(b'\x89PNG\r\n\x1a\n') and len(raw) > 10000
        state = read(folder, f'{stage}.state.json')
        assert state['version'] == read(folder, 'session.json').get('expected_version', '0.0.526') and state['sync'] == 'stopped'
        assert state['pending_sends'] == state['pending_archives'] == 0
        tree = (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig')
        assert tree.splitlines()[0].startswith('MessagesZig | ') and '\n1008 |' not in tree
    final = read(folder, 'side-effects.json')
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert final['chat_count'] == 6 and final['search'] == '' and final['pending_sends'] == final['pending_archives'] == 0
    assert final['sync'] == 'stopped'
    guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
    assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
    assert not (folder / 'failure.txt').exists()
    assert 'JOURNEY PASSED: search' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for keys in ('^f', '/', 'Keyboard shortcuts', 'Status', '{ENTER}', '{ESC}') + tuple(case['query'] for case in fixture['queries']):
        assert f'keys: {keys}' in actions
    print('SEARCH EVIDENCE VERIFIED: shortcuts, ordered results, groups, empty list, removal and archived ink')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    if args.baseline:
        compare(args.baseline, args.folder)
    else:
        check_evidence(args.folder)

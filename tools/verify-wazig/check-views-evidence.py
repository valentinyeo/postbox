import hashlib
import json
from pathlib import Path


def check_workspace_names(folder, capture):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    names = ['Alpha Workspace', 'Beta Workspace']
    checks = read('workspace-names.json')
    assert set(checks) == {'view-label', 'sort-views', 'palette', 'inbox-tooltip'}
    result = read('result.json')
    assert result == dict(feature='views', status='passed', checks=checks)
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    for check_id, check in checks.items():
        assert check['status'] == 'passed' and check['names'] == names, check_id
        prefix = 'Show Slack ' if check_id == 'palette' else 'Slack '
        assert all(prefix + name in check['labels'] for name in names), check_id
        assert not any(prefix + team in check['labels'] for team in ['T0ABC123', 'T0DEF456']), check_id
        assert f'views {check_id} PASS' in proof
        assert check['screenshots'], check_id
        for screenshot in check['screenshots']:
            assert Path(screenshot).name == screenshot and screenshot.endswith('.png')
            capture(screenshot[:-4])
    assert checks['view-label']['screenshots'] == ['view-3.png', 'view-4.png']
    assert checks['sort-views']['screenshots'] == ['sort-before.png']
    assert checks['palette']['screenshots'] == ['workspace-palette.png']
    assert checks['inbox-tooltip']['screenshots'] == ['inbox-tooltip-T0ABC123.png', 'inbox-tooltip-T0DEF456.png']
    for team in ['T0ABC123', 'T0DEF456']:
        assert f'hover: {team}' in (folder / 'actions.log').read_text(encoding='utf-8-sig')
        assert capture(f'inbox-tooltip-{team}')['current_view']['inbox']
    cached = list((folder / 'final-data').glob('hub-*-workspace-names.json'))
    assert len(cached) == 1 and read(str(cached[0].relative_to(folder))) == dict(T0ABC123=names[0], T0DEF456=names[1])


def check_views(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    def identities(rows):
        result = {(row['provider'], row['account'], row['id']) for row in rows}
        assert len(result) == len(rows), 'duplicate chat identity'
        return result

    def capture(name):
        image = (folder / f'{name}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000, name
        assert 'MessagesZig | Wazig Messages v0.0.526' in (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig'), name
        return read(f'{name}.state.json')

    check_workspace_names(folder, capture)

    session = read('session.json')
    assert session['feature'] == 'views' and session['sha256'] and session['commit']
    assert not (folder / 'failure.txt').exists()
    baseline = capture('before')
    expected = [('whatsapp', 'personal', 'WhatsApp personal'), ('whatsapp', 'business', 'WhatsApp business'),
                ('slack', 'T0ABC123', 'Slack Alpha Workspace'), ('slack', 'T0DEF456', 'Slack Beta Workspace')]
    assert [(view['provider'], view['account'], view['label']) for view in baseline['view_order']] == expected + [('telegram', 'telegram', 'Telegram'), ('signal', 'signal', 'Signal')]
    assert baseline['current_view']['inbox'] and baseline['chat_count'] == 8
    catalog = read('views-catalog.json')['chats']
    assert len(catalog) == 8
    all_keys = identities(catalog)
    routing_accounts = {row['account'] for row in catalog}
    assert len(routing_accounts) == 1, 'view derivation changed the hub cache identity'
    for row in catalog:
        if row['provider'] == 'whatsapp':
            prefix, contact = row['id'].split(':', 1)
            assert '@' in contact and prefix == row['view_account']
        else:
            prefix, team, channel = row['id'].split(':')
            assert prefix == 'slack' and team == row['view_account'] and channel.startswith('C')
    partition = set()
    for number, (provider, account, label) in enumerate(expected, 1):
        state = capture(f'view-{number}')
        view = state['current_view']
        assert (view['provider'], view['account'], view['label'], view['inbox']) == (provider, account, label, False)
        rows = read(f'view-{number}.chats.json')['chats']
        assert state['chat_count'] == len(rows) == 2
        assert all((row['provider'], row['view_account']) == (provider, account) for row in rows)
        keys = identities(rows)
        assert keys.isdisjoint(partition)
        partition |= keys
        filtered = capture(f'search-{number}')
        assert filtered['search'] == 'Shared' and filtered['chat_count'] == 1
        assert filtered['selected']['view_account'] == account and filtered['selected']['name'] == 'Verification Shared'
    assert partition == all_keys
    assert sum(row['name'] == 'Verification Shared' and row['provider'] == 'whatsapp' for row in catalog) == 2
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert all(row['authorized'] for row in requests if row['method'] != 'SSE')
    sends = [row for row in requests if row['path'] == '/v1/wazig/send']
    assert sends and sum(row['accepted'] for row in sends) == 1
    assert len({row['body']['client_id'] for row in sends}) == 1
    sent = read('sent.messages.json')
    other = read('other.messages.json')
    assert sent['chat']['view_account'] == 'personal' and other['chat']['view_account'] == 'business'
    assert sent['chat']['name'] == other['chat']['name'] == 'Verification Shared'
    assert sent['chat']['account'] == other['chat']['account'] == next(iter(routing_accounts))
    assert sent['chat']['id'].startswith('personal:') and other['chat']['id'].startswith('business:')
    assert sent['chat']['id'].split(':', 1)[1] == other['chat']['id'].split(':', 1)[1]
    assert all(row['source_provider'] == 'whatsapp' and row['source_account'] == 'personal' and row['body']['chat'] == sent['chat']['id'] for row in sends)
    assert all(set(row['body']) == {'chat', 'text', 'reply_to', 'client_id'} for row in sends)
    assert sum(row['text'] == 'Verification account send' for row in sent['messages']) == 1
    assert other['messages'] and all(row['text'] != 'Verification account send' for row in other['messages'])
    for name, account in [('sent', 'personal'), ('isolated', 'business')]:
        assert capture(name)['selected']['view_account'] == account
    inbox = read('inbox.chats.json')['chats']
    assert identities(inbox) == all_keys
    assert [row['last_message_time'] for row in inbox] == sorted((row['last_message_time'] for row in inbox), reverse=True)
    assert capture('inbox')['current_view']['inbox']
    capture('sort-command')
    capture('sort-before')
    moved = capture('sort-moved')
    order = expected.copy()
    order[0], order[1] = order[1], order[0]
    assert [(view['provider'], view['account'], view['label']) for view in moved['view_order']] == order + [('telegram', 'telegram', 'Telegram'), ('signal', 'signal', 'Signal')]
    saved = (folder / 'view-order.txt').read_text(encoding='utf-8-sig').splitlines()
    assert saved == [f'{provider}:{account}' for provider, account, _ in order] + ['telegram:telegram', 'signal:signal']
    assert capture('sort-selected')['current_view']['account'] == 'personal'
    assert capture('sort-closed')['current_view']['account'] == 'personal'
    restart = read('restart.json')
    assert (restart['old_pid'], restart['old_start']) != (restart['new_pid'], restart['new_start'])
    assert restart['new_pid'] == session['pid'] and restart['new_start'] == session['startTicks']
    assert all(restart[key] == session[key] for key in ['root', 'id', 'sha256'])
    for number, (provider, account, label) in enumerate(order, 1):
        state = capture(f'restart-{number}')
        assert state['current_view'] == dict(provider=provider, account=account, label=label, inbox=False)
        assert [(view['provider'], view['account'], view['label']) for view in state['view_order']] == order + [('telegram', 'telegram', 'Telegram'), ('signal', 'signal', 'Signal')]
        rows = read(f'restart-{number}.chats.json')['chats']
        assert len(rows) == 2 and all(row['view_account'] == account for row in rows)
    capture('after')
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for keys in ['%1', '%2', '%3', '%4', '%i', '^k', 'Show', '^1', '^2', '^{TAB}', '^+{TAB}', '^f', 'Shared', 'Sort views', '^{DOWN}', '{ENTER}', '{ESC}', 'Quit Messages', 'Verification account send']:
        assert f'keys: {keys}' in actions, keys
    guards = (folder / 'launch-guards.log').read_text(encoding='utf-8-sig')
    assert 'REJECTED: not-actions' in guards and 'REJECTED: not-isolated' in guards
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ['production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'])
    assert 'JOURNEY PASSED: views' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    images = [hashlib.sha256((folder / f'view-{number}.png').read_bytes()).hexdigest() for number in range(1, 5)]
    assert len(set(images)) == 4, 'account screenshots do not change'
    print('VIEWS EVIDENCE VERIFIED: account partitions, scoped send, inbox order and same-profile saved order restart')

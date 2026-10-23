import ast
import importlib.util
import io
import json
import threading
from pathlib import Path
import re
import subprocess
import sys
from types import SimpleNamespace

root = Path(__file__).resolve().parents[2]


def read(path):
    return (root / path).read_text(encoding='utf-8')


def require(text, fragments):
    for fragment in fragments:
        assert fragment in text, fragment


def section(source, start, end):
    return source.split(start, 1)[1].split(end, 1)[0]


def view_identity(source):
    require(source, [
        'pub fn viewAccount(', 'if (account.len > 0) return account;',
        'std.mem.indexOfScalar(u8, jid,', "jid[colon + 1 ..], '@'", 'return jid[0..colon]',
        'std.mem.startsWith(u8, jid, "slack:")', 'return rest[0..colon]',
    ])


def model(source):
    require(source, [
        'pub const Account = struct', 'key: chat_key.Stored', 'pub fn mergeOrder(',
        'for ([_]Provider{ .whatsapp, .slack, .telegram })', 'try appendUnique(allocator, &result, item)',
        'pub fn forNumber(number: usize, views: []const Account)', 'number - 1',
        'pub fn accountMatches(', 'key.account', 'pub fn saveOrder(',
        'if (present)', 'views[next].key.key()', 'views[next..]',
        'pub fn inboxMoveUp(', 'by_time == .lt',
        'test "account view order merges saved missing and new accounts without losing absent entries"',
        'test "Alt+N maps saved account positions including two WhatsApp accounts"',
        'test "combined inbox sorts activity across accounts without prioritizing old pins"',
        'test "two WhatsApp account views isolate a shared contact in projection search selection and sending"',
        'try std.testing.expectEqualStrings("wa-b", merged.items[2].key.key().account)',
        'try std.testing.expect(!rows[0].pinned)', 'chat_key.indexOf(Row, &output, key)',
        'try std.testing.expectEqual(@as(usize, 2), count)',
    ])


def check_model():
    source = read('src/messenger_view.zig')
    model(source)
    hub = read('src/hub.zig')
    view_identity(hub)
    old = subprocess.check_output(['git', 'show', 'origin/main:src/hub.zig'], cwd=root, text=True)
    try:
        view_identity(old)
    except AssertionError:
        pass
    else:
        raise AssertionError('cache-account-only negative control unexpectedly accepted')
    assert section(hub, 'pub fn sourceAccount(', 'pub fn viewAccount(') == section(old, 'pub fn sourceAccount(', 'pub fn providerForView(')
    regression = read('src/hub_test.zig')
    require(regression, [
        'test "real hub prefixed jids without account produce four views without changing routing identity"',
        'test "hub view accounts prefer explicit accounts and safely fall back for unprefixed handles"',
        'personal:0000000000@s.whatsapp.net', 'business:0000000000@s.whatsapp.net',
        'slack:T0ABC123:C0000000000', 'slack:T0DEF456:C0000000000',
        'hub.viewAccount(row.object, "hub-cache")', 'try std.testing.expectEqual(@as(usize, 4), known.items.len)',
        'try std.testing.expectEqual(@as(usize, 1), count)',
        'try std.testing.expect(!chat_key.Key.eql(routing[0].key(), routing[1].key()))',
        'try std.testing.expectEqualStrings("hub-cache", routing[index].key().account)',
        'body.value.object.get("account") == null',
    ])
    for token in ['pub fn mergeOrder(', 'pub fn accountMatches(', 'pub fn inboxMoveUp(', 'pub fn forNumber(']:
        try:
            model(source.replace(token, 'removed-function(', 1))
        except AssertionError:
            pass
        else:
            raise AssertionError(f'model mutation accepted: {token}')
    main = read('src/main.zig')
    require(main, ['messenger_view.mergeOrder(a.allocator, a.view_order, known.items)',
                   'messenger_view.forNumber(key - \'0\', a.views.items)',
                   'messenger_view.inboxMoveUp(by_time, jid_order)',
                   'if (!chatInView(a, chat_key.of(cached))) continue;',
                   'if (!chatInView(a, chatViewKey(&chat))) continue;'])
    require(read('src/outbox.zig'), ['if (!source_unified or !target.unified) entry.account.set(target.account)',
                                    'test "unified outbox adoption preserves the source account for shared-contact sends"'])
    require(read('src/chat_reconcile_test.zig'), ['test "account view history accepts source accounts without confusing the hub cache namespace"'])
    require(read('src/hub_test.zig'), ['test "hub source accounts retain per-account view labels independently of cache namespace"'])
    require(read('build.zig'), ['"src/messenger_view.zig"', '"src/control.zig"', '"src/outbox.zig"', '"src/hub_test.zig"'])


def check_integration():
    source = read('src/main.zig')
    require(source, [
        'loadRegistryString(init.gpa, lit("ViewOrder"))', 'saveRegistryString(a.allocator, lit("ViewOrder"), text)',
        'loadRegistryString(init.gpa, lit("AccountView"))', 'saveRegistryString(a.allocator, lit("AccountView"), a.view_account.slice())',
        'hub.sourceAccount(object, a.cache_tag.slice())',
        'chat.view_account.set(hub.viewAccount(object, a.cache_tag.slice()))',
        'if (!messenger_view.accountMatches(view, account, chatViewKey(&chat))) continue;',
        'hub.viewAccount(row.object, a.cache_tag.slice())',
        'view_account: Utf8Text(32) = .{}', 'fn chatViewKey(chat: *const Chat) chat_key.Key',
        'if (chat.view_account.len > 0) key.account = chat.view_account.slice()',
        'slack_win.loadInstallation(a.allocator, account)', 'saved.value.team_name',
        'messenger_view.providerView(chat.provider), chatViewKey(chat).account, view.key.key()',
        'installation.team_id.slice(), installation.team_name.slice()', 'telegramReady(a)',
        'appendPalette(a, "Sort views", "", command_sort_views)', 'command_sort_views => openSortViews(a)',
        'a.palette_views_mode and control and !alt and !shift', 'moveView(a, key == win.VK_DOWN)',
        'if (!saveViewOrder(a))', 'fn buildSortViewsItems(', 'item.view_identity.account_len > 0',
        'switchAccountView(a, wanted.key())', 'appendPalette(a, "Show combined inbox", "Alt+I", command_show_all)',
        'key == \'I\'', '"Show {s}"', 'activeViewLabel(a)', 'fn updateChatTooltip(',
        'win.TTM_UPDATETIPTEXTW', 'message.hwnd == app.chats_hwnd.?',
        '\\"current_view\\"', '\\"view_order\\"', '\\"provider\\"', '\\"account\\"', '\\"label\\"', '\\"inbox\\"',
        'chat_key.Key.eql(chat_key.of(chat), item.chat_identity.key())',
        '.provider = pending.provider, .account = pending.account, .jid = pending.jid',
        '(!unifiedHub(a) and !std.mem.eql(u8, head.account.slice(), a.cache_tag.slice()))',
        'if (result.kind != .cache_tag and result.provider == .whatsapp',
        'a.view_selected[@intFromEnum(messenger_view.View.all)] = wanted',
    ])
    links = source.split('fn buildLinkPaletteItems(', 1)[1].split('fn whatsappStorePresent(', 1)[0]
    assert links.count('item.view_identity = .{};') == 2
    assert source.count('chat.account.set(hub.sourceAccount(object, a.cache_tag.slice()));') == 2
    assert source.count('chat.view_account.set(hub.viewAccount(object, a.cache_tag.slice()));') == 2
    assert source.count('hub.viewAccount(') == 3
    old = subprocess.check_output(['git', 'show', 'origin/main:src/main.zig'], cwd=root, text=True)
    for name in ['unifiedHubRequest', 'restoreOutbox', 'loadOutbox', 'bindOutboxAccount', 'startHubSend',
                 'markChatRead', 'startNextMarkRead', 'loadPendingReads', 'persistPendingReads',
                 'msgCacheGet', 'loadMsgCacheDisk', 'archiveChat', 'startNextArchive']:
        pattern = rf'^fn {name}\([^\n]*\n.*?^}}'
        current = re.search(pattern, source, re.M | re.S)
        previous = re.search(pattern, old, re.M | re.S)
        assert current and previous, f'missing identity audit function: {name}'
        assert current.group() == previous.group(), f'routing identity path changed: {name}'
    for path in ['src/outbox.zig', 'src/chat_cache.zig', 'src/read_state.zig', 'src/pending_reads.zig']:
        assert read(path) == subprocess.check_output(['git', 'show', f'origin/main:{path}'], cwd=root, text=True), path
    control = read('src/control.zig')
    require(control, ['view_number: ?usize', 'std.mem.eql(u8, items[0], "inbox")', 'std.fmt.parseInt(usize, items[0], 10)',
                      'test "view accepts an account position and combined inbox while retaining provider aliases"'])
    markers = re.findall(r'sourceSection\("((?:\\.|[^"\\])*)", "((?:\\.|[^"\\])*)"\)', read('build.zig'))
    assert markers
    for start, end in markers:
        first = ast.literal_eval('"' + start + '"')
        last = ast.literal_eval('"' + end + '"')
        assert first in source, f'missing harness start: {first}'
        assert last in source[source.index(first) + len(first):], f'missing harness end: {last}'
    require(read('src/shortcuts.zig'), ['Alt+I / Alt+1..9'])


def check_journey():
    runner = read('tools/verify-wazig/run.ps1')
    require(runner, ["'hub', 'views', 'archive'", '-Views:($Feature -eq \'views\')',
                     '. "$PSScriptRoot/views.ps1"', 'Invoke-ViewsJourney $session $messages $start'])
    journey = read('tools/verify-wazig/views.ps1')
    require(journey, ['Assert-AccountView', "@('personal', 'business', 'T0ABC123', 'T0DEF456')", 'Where-Object view_account -ne $Account',
                      "Send-Keys $Session '^1'", "Send-Keys $Session '^2'", "Send-Keys $Session '^{TAB}'", "Send-Keys $Session '^+{TAB}'",
                      "Send-Keys $Session '^f'", "Send-Keys $Session '%i'", "Send-Keys $Session '^{DOWN}'",
                      "'Sort views'", "'ViewOrder not saved at move time'", "'Quit Messages'",
                      "WAZIG_VERIFY_RESTART", "'restart.json'", 'restart-4', 'other.messages.json', 'inbox.chats.json'])
    assert set(re.findall(r'Read-Control \$Session (\w+)', journey)) == {'status', 'chats', 'messages'}
    fixture = ast.parse(read('tools/verify-wazig/fake-hub.py'))
    assignment = next(node for node in fixture.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'VIEW_ACCOUNTS' for target in node.targets))
    accounts = ast.literal_eval(assignment.value)
    assert [provider for provider, _, _ in accounts].count('whatsapp') == 2
    assert [provider for provider, _, _ in accounts].count('slack') == 2
    assert len({account for _, account, _ in accounts}) == 4
    require(read('tools/verify-wazig/fake-hub.py'), ['Verification Shared', 'range(2)', 'source_account=view_account(row)',
                                                  'class ViewsHandler(Handler)', 'bridge.Handler.respond(self', "parser.add_argument('--views'"])
    evidence = read('tools/verify-wazig/check-views-evidence.py')
    require(evidence, ['assert partition == all_keys', 'assert identities(inbox) == all_keys', 'reverse=True',
                       'source_account', "other['messages']", "restart['new_pid'] == session['pid']", "['root', 'id', 'sha256']",
                       "capture(f'restart-{number}')", "'view-order.txt'", "assert len(set(images)) == 4"])
    require(read('tools/verify-wazig/check-evidence.py'), ["session['feature'] == 'views'", 'check-views-evidence.py'])
    workflow = read('.github/workflows/verify.yml')
    require(workflow, ['hub, views, archive', '"hub","views","text-comparison"', "matrix.feature == 'views'",
                       'src/messenger_view.zig', 'src/chat_key.zig', 'src/control.zig', 'src/outbox.zig'])
    for path in (root / 'tools/verify-wazig').glob('*.py'):
        ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
    require(read('.claude/skills/verify-wazig/features/views.md'), [
        'personal and business', 'T0ABC123 and T0DEF456', 'Rows omit account and account_name',
        'Chat.view_account', 'Chat.account', 'locally saved workspace name',
        'source_account personal', 'in business', 'descending activity timestamps',
        'restart-1.png through restart-4.png',
    ])
    require(read('CHANGELOG.md'), ['IGSH-602:', 'Sort views', 'Alt+I combined inbox',
                                 'real hub prefixed chat IDs', 'preserving send and cache identities'])


def check_fixture():
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location('views_fixture', root / 'tools/verify-wazig/fake-hub.py')
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    rows = fixture.view_rows()
    assert len(rows) == 8
    assert all('account' not in row and 'account_name' not in row for row in rows)
    accounts = {(row['provider'], fixture.view_account(row)) for row in rows}
    assert accounts == {('whatsapp', 'personal'), ('whatsapp', 'business'), ('slack', 'T0ABC123'), ('slack', 'T0DEF456')}
    wa = [row for row in rows if row['provider'] == 'whatsapp']
    assert len({row['jid'].split(':', 1)[1] for row in wa}) == 2
    assert all('@s.whatsapp.net' in row['jid'] for row in wa)
    assert all(row['jid'].startswith('slack:T') and ':C' in row['jid'] for row in rows if row['provider'] == 'slack')
    state = SimpleNamespace(view_rows=rows, sends={}, lock=threading.Condition(), stamp='2026-01-02T00:00:00Z')
    handler = object.__new__(fixture.ViewsHandler)
    handler.server = SimpleNamespace(state=state)
    handler.authorized = lambda: True
    responses = []
    handler.respond = lambda status, data, **extra: responses.append((status, data, extra))
    handler.path = '/v1/wazig/chats'
    handler.do_GET()
    assert responses[-1][0] == 200 and responses[-1][1] == rows
    for index, row in enumerate(rows):
        body = dict(chat=row['jid'], text='Synthetic send', reply_to='', client_id=f'client-{index}')
        handler.path = '/v1/wazig/send'
        encoded = json.dumps(body).encode()
        handler.headers = {'Content-Length': str(len(encoded))}
        handler.rfile = io.BytesIO(encoded)
        handler.do_POST()
        status, reply, extra = responses[-1]
        assert status == 200 and extra['accepted'] and reply['chat'] == row['jid']
        assert extra['source_account'] == fixture.view_account(row)
        handler.rfile = io.BytesIO(encoded)
        handler.do_POST()
        assert responses[-1][2]['duplicate'] and not responses[-1][2]['accepted']
        body['account'] = fixture.view_account(row)
        encoded = json.dumps(body).encode()
        handler.headers = {'Content-Length': str(len(encoded))}
        handler.rfile = io.BytesIO(encoded)
        handler.do_POST()
        assert responses[-1][0] == 400, 'fixture accepted a non-unified send shape'
    handler.path = '/v1/wazig/messages?chat=' + wa[0]['jid']
    handler.do_GET()
    assert len(responses[-1][1]) == 2
    assert all(row['ChatJID'] == wa[0]['jid'] for row in responses[-1][1])
    old = subprocess.check_output(['git', 'show', 'origin/main:src/hub.zig'], cwd=root, text=True)
    require(section(old, 'pub fn sourceAccount(', 'pub fn providerForView('), ['account.len > 0', 'else fallback'])
    old_views = {(row['provider'], row.get('account', 'hub-cache')) for row in rows}
    assert len(old_views) == 2 and len(accounts) == 4

checks = {'model': check_model, 'integration': check_integration, 'journey': check_journey, 'fixture': check_fixture}
checks[sys.argv[1]]()
print(f'views {sys.argv[1]} static PASS')

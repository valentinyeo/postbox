import ast
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[2]


def read(path):
    return (root / path).read_text(encoding='utf-8')


def require(text, fragments):
    for fragment in fragments:
        assert fragment in text, fragment


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
    old = subprocess.check_output(['git', 'show', 'origin/main:src/messenger_view.zig'], cwd=root, text=True)
    try:
        model(old)
    except AssertionError:
        pass
    else:
        raise AssertionError('provider-only negative control unexpectedly accepted')
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
                   'if (!chatInView(a, chat_key.of(&chat))) continue;'])
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
        'hub.sourceAccount(object, a.cache_tag.slice())', 'getString(row.object, "account_name")',
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
    require(journey, ['Assert-AccountView', "@('wa-a', 'wa-b', 'slack-a', 'slack-b')", 'Where-Object account -ne $Account',
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
    require(read('tools/verify-wazig/fake-hub.py'), ['Verification Shared', 'range(2)', 'source_account=row[\'account\']',
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
    require(read('CHANGELOG.md'), ['IGSH-602:', 'Sort views', 'Alt+I combined inbox'])


checks = {'model': check_model, 'integration': check_integration, 'journey': check_journey}
checks[sys.argv[1]]()
print(f'views {sys.argv[1]} static PASS')

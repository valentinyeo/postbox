from pathlib import Path
import ast
import json
import re
import runpy

root = Path(__file__).resolve().parents[2]
skill = root / '.claude/skills/verify-wazig'
text = (skill / 'SKILL.md').read_text(encoding="utf-8")
assert text.startswith('---\nname: verify-wazig\ndescription: ')
assert re.findall(r'^## (.+)$', text, re.M) == ['Launch', 'Doctor', 'Drive', 'Evidence', 'Cleanup', 'Helpers']
features = sorted(p.stem for p in (skill / 'features').glob('*.md') if p.name != 'README.md')
registry_path = root / 'tools/verify-wazig/journeys.json'
registry = json.loads(registry_path.read_text(encoding='utf-8'))
journeys = registry['journeys']
options = [row['name'] for row in journeys]
entries = {row['name']: row for row in journeys}
assert options and len(options) == len(set(options)), 'duplicate or empty registry journeys'
assert features == sorted(options), 'feature maps must match the journey registry exactly'
for row in journeys:
    name = row['name']
    assert re.fullmatch(r'[a-z][a-z0-9-]*', name), name
    assert type(row['pr']) is bool and type(row['evidence']) is bool and type(row['maximize']) is bool, name
    assert row['chats'] is None or (type(row['chats']) is int and row['chats'] > 0 and row['hub']), name
    assert row['hub'] is None or re.fullmatch(r'[a-z][a-z0-9-]*', row['hub']), name
    for key in ['script', 'library', 'prepare', 'ready']:
        if key != 'script' and not row.get(key):
            continue
        filename = row[key]
        assert Path(filename).name == filename and filename.endswith('.ps1'), (name, key)
        assert (registry_path.parent / filename).is_file(), (name, 'missing journey script', filename)
    config = row['hub_handler']
    assert bool(config) == bool(row['hub']), (name, 'missing fake-hub handler')
    if config:
        assert Path(config['file']).name == config['file'], name
        path = registry_path.parent / config['file']
        assert path.is_file(), (name, 'missing fake-hub handler file')
        tree = ast.parse(path.read_text(encoding='utf-8'))
        assert any(isinstance(node, ast.ClassDef) and node.name == config['class'] for node in tree.body), (name, 'missing fake-hub handler', config)
    validator_config = row['validator']
    assert not row['evidence'] or validator_config, (name, 'missing evidence validator')
    if validator_config:
        assert Path(validator_config['file']).name == validator_config['file'], name
        path = registry_path.parent / validator_config['file']
        assert path.is_file(), (name, 'missing evidence validator file')
        tree = ast.parse(path.read_text(encoding='utf-8'))
        if validator_config.get('function'):
            assert any(isinstance(node, ast.FunctionDef) and node.name == validator_config['function'] for node in tree.body), (name, 'missing evidence function')
for filename in ['SKILL.md', 'features/README.md', 'INDEX.md']:
    prose = (skill / filename).read_text(encoding='utf-8')
    assert 'journeys.json' in prose, (filename, 'must point to the registry')
    assert not re.search(r'^\|.*\]\([^)]*\.md\)', prose, re.M), (filename, 'hand-maintained journey table')
    assert not re.search(r'^- \[[^]]+\]\((?:features/)?[^)]+\.md\)', prose, re.M), (filename, 'hand-maintained journey catalog')
    assert not re.search(r'feature=[a-z-]+\|', prose), (filename, 'hand-maintained journey options')
    assert not re.search(r'(?:Matching PRs run|path triggers run the) `', prose), (filename, 'hand-maintained PR journey list')
index = (skill / 'features/README.md').read_text(encoding='utf-8')
for feature in features:
    entry = (skill / 'features' / f'{feature}.md').read_text(encoding="utf-8")
    assert re.findall(r'^## (.+)$', entry, re.M) == [
        'Sub-features', 'How to get to it (user POV)', 'Driving it with PowerShell UI Automation', 'Gotchas'
    ], feature
    assert f'feature={feature}' in entry
source = (root / 'src/main.zig').read_text(encoding="utf-8")
for label in ['Search chats', 'Next chat', 'Previous chat', 'Compose message', 'Keyboard shortcuts', 'Theme: Green', 'Make text larger', 'Reset text size', 'Show archived chats', 'Show inbox chats', 'Archive selected chat', 'Unarchive selected chat']:
    assert f'"{label}"' in source, label
for removed in ['resurface_probe', 'enqueueResurfaceProbe', 'applyResurfaceProbe', 'command_keep_archived', 'toggleKeepArchived', 'Archive and keep archived', 'Allow resurfacing']:
    assert removed not in source, ('removed archive resurfacing path or command', removed)
for control in ['id_palette_edit = 1064', 'id_compose = 1032']:
    assert control in source
workflow = (root / '.github/workflows/verify.yml').read_text(encoding="utf-8")
for required in ['workflow_dispatch:', 'pull_request:', 'windows-latest', '.claude/skills/verify-wazig/**', 'actions/upload-artifact@v4', 'if: always()', '--release=small']:
    assert required in workflow, required
assert 'type: string' in workflow and 'options:' not in workflow, 'dispatch must accept a registry-validated string'
assert '  plan:\n    runs-on: ubuntu-latest' in workflow, 'missing plan job'
assert '    needs: plan' in workflow, 'verify must depend on plan'
assert 'matrix: ${{ fromJSON(needs.plan.outputs.matrix) }}' in workflow, 'verify must use plan-job matrix'
assert 'if: matrix.evidence' in workflow, 'evidence must use registry matrix flag'
for required in ["journeys.json", "row['pr']", "row['evidence']", "row['name'] == feature", 'Unknown verification journey:', 'GITHUB_OUTPUT']:
    assert required in workflow, ('missing registry plan wiring', required)
coverage = index.split('## Recent changes coverage\n', 1)
assert len(coverage) == 2, 'missing recent changes coverage'
coverage_ids = set()
for line in coverage[1].splitlines():
    if not line.startswith('- '):
        continue
    bullet = re.fullmatch(r'- ((?:IGSH|WAZI)-[0-9]+): .+ -> (.+)', line)
    assert bullet, ('malformed coverage bullet', line)
    ticket, disposition = bullet.groups()
    assert ticket not in coverage_ids, ('duplicate coverage ticket', ticket)
    coverage_ids.add(ticket)
    journey = re.fullmatch(r'`([^`]+)` \(.+\)', disposition)
    assert (disposition.startswith('unreachable: ') and len(disposition) > len('unreachable: ')) or (journey and journey[1] in options), (ticket, disposition)
assert coverage_ids, 'empty recent changes coverage'
assert 'default: search' in workflow
assert 'Archive\\tCtrl+E' in (root / 'src/chat_menu.zig').read_text(encoding='utf-8')
for helper in ['run', 'doctor', 'cleanup', 'harness']:
    assert (root / 'tools/verify-wazig' / f'{helper}.ps1').is_file()
assert 'RegOverridePredefKey' in source and 'VerificationRequiresActions' in source
assert 'if (verification_fixture and !hubConfigured(a)) return verificationEnqueue(a, job);' in source
assert 'if (!verification_fixture) return null;' in source
assert 'if (verification_fixture) return;' in source
assert 'whatsapp-hub' in options
assert (root / 'tools/verify-wazig/fake-wa-bridge.py').is_file()
fixture_config = source.split('fn configureWaHub(', 1)[1].split('    a.wa_bridge_url =', 1)[0]
assert 'if (verification_fixture)' in fixture_config
assert 'if (init.environ_map.get("WAZIG_VERIFY_HUB_URL"))' in fixture_config
assert 'if (init.environ_map.get("WAZIG_VERIFY_HUB_KEY")) |seed|' in fixture_config
assert 'if (!slack_win.saveSecret(lit("WaBridgeKey"), seed)) return;' in fixture_config
runner = (root / 'tools/verify-wazig/run.ps1').read_text(encoding='utf-8')
assert "if (-not $journey.hub) {\n    Set-Content (Join-Path $messages 'account-tag.txt')" in runner
for required in ["journeys.json", 'Where-Object name -CEQ $Feature', 'Unknown verification journey:', '. (Join-Path $PSScriptRoot $journey.script)', '$journey.chats', '-Mode $journey.hub', '. (Join-Path $PSScriptRoot $journey.library)', '. (Join-Path $PSScriptRoot $journey.prepare)', '. (Join-Path $PSScriptRoot $journey.ready)', 'if ($journey.maximize)', '$journey.arguments', '$journey.result_checks']:
    assert required in runner, ('missing registry runner wiring', required)
assert 'ValidateSet(' not in runner and 'switch ($Feature)' not in runner
runner += '\n' + '\n'.join((registry_path.parent / row[key]).read_text(encoding='utf-8') for row in journeys for key in ['script', 'prepare', 'ready'] if row.get(key))
harness = (root / 'tools/verify-wazig/harness.ps1').read_text(encoding='utf-8')
fake_hub = (registry_path.parent / 'fake-hub.py').read_text(encoding='utf-8')
for required in ["journeys.json", "for mode in journeys:", "modes.add_argument('--' + mode, dest='mode', action='store_const', const=mode)", "namespace[config['class']]"]:
    assert required in fake_hub, ('missing fake-hub switch or dispatch wiring', required)
for required in ["journeys.json", '$registry.journeys.hub', '$start.ArgumentList.Add("--$Mode")']:
    assert required in harness, ('missing fake bridge registry wiring', required)
hub_namespace = runpy.run_path(str(registry_path.parent / 'fake-hub.py'))
hub_parser, hub_journeys = hub_namespace['journey_parser']()
expected_modes = {row['hub'] for row in journeys if row['hub'] and row['hub'] != 'legacy'}
assert set(hub_journeys) == expected_modes, 'fake-hub mode registry drift'
actual_modes = {option[2:] for option in hub_parser._option_string_actions if option.startswith('--') and option not in {'--help', '--port-file', '--log'}}
assert actual_modes == expected_modes, ('missing fake-hub switch', expected_modes - actual_modes)
for mode in expected_modes:
    parsed = hub_parser.parse_args(['--' + mode, '--port-file', 'port', '--log', 'log'])
    assert parsed.mode == mode, ('fake-hub switch selects wrong mode', mode)
marker_namespace = runpy.run_path(str(root / 'tools/check_private_markers.py'))
for name in options:
    assert f'.claude/skills/verify-wazig/features/{name}.md' in marker_namespace['PUBLIC_SKILL_PATHS'], name
keyboard = harness.split('function Send-Keys(', 1)[1].split('function Get-PaletteWindow(', 1)[0]
for required in ['$app = Get-App $Session', '$null = Wait-Until {', '$foreground -eq [IntPtr]::Zero -or $ownerPid -ne $Session.pid',
                 '$app.Refresh()', '[VerifyWindow]::SetForegroundWindow($app.MainWindowHandle)',
                 'GetWindowThreadProcessId($foreground, [ref]$ownerPid)',
                 "Assert-That ($foreground -ne [IntPtr]::Zero -and $ownerPid -eq $Session.pid) 'Refusing keyboard input to another app'"]:
    assert required in keyboard, required
assert keyboard.index('Refusing keyboard input to another app') < keyboard.index('[System.Windows.Forms.SendKeys]::SendWait($Keys)')
for proof in ['mixed-lid-page', 'mixed-older-pages', 'chats', 'chat-switch', 'history', 'mark-read', 'live-sse-replay', 'send-client-id-dedupe', 'media-202-ready-cache', 'archive', 'auth-dpapi-backend']:
    assert f'Hub-Pass $Session {proof}' in harness, proof
bridge = (root / 'tools/verify-wazig/fake-wa-bridge.py').read_text(encoding='utf-8')
assert "last_message_ts='2026-01-01T00:00:00Z'" in bridge
assert 'if request == 1:\n                    time.sleep(3)' in bridge
for required in ['ReadToEndAsync()', '$child.WaitForExit($TimeoutMilliseconds)', '$remaining = 1000 -',
                 'Read-Control $Session messages -TimeoutMilliseconds $remaining', '$elapsed -le 1000',
                 '$shown.messages.Count -eq 0', 'Save-Screen $Session beta-empty']:
    assert required in harness, required
validator = (root / 'tools/verify-wazig/check-evidence.py').read_text(encoding='utf-8')
for required in ['journeys.json', "row['name'] == session['feature']", "journey['validator']", "validator['file']", "namespace[validator['function']](folder)"]:
    assert required in validator, ('missing evidence registry wiring', required)
validator += '\n' + '\n'.join((registry_path.parent / row['validator']['file']).read_text(encoding='utf-8') for row in journeys if row['validator'])
for artifact in ['removed-status.json', 'text-scale.json']:
    assert artifact in runner and artifact in validator, artifact
assert 'a.font_scale = 82;' in source and 'command_font_larger => changeFontScale(a, 10)' in source
for artifact in ['before-beta.requests.json', 'beta-switch.json', 'beta-empty.messages.json']:
    assert artifact in harness and artifact in validator, artifact
assert "0 <= switch['elapsed_ms'] <= 1000" in validator
assert "empty['messages'] == []" in validator
assert "delayed[0]['history_delay_ms'] >= 3000" in validator
for feature in ['whatsapp-hub', 'hub']:
    entry = (skill / 'features' / f'{feature}.md').read_text(encoding='utf-8')
    for required in ['beta-empty.png', 'beta-switch.json', 'one second', 'three seconds']:
        assert required in entry, (feature, required)

sort_map = (skill / 'features/slack-sort.md').read_text(encoding='utf-8')
assert 'last message' in sort_map
for stage in ['before', 'after', 'sent']:
    assert stage in runner and 'navigation.json' in runner and stage in validator
assert entries['slack-sort']['script'] == 'journey-slack-sort.ps1' and 'slack-sort' in {row['hub'] for row in journeys}
assert 'slack-sort' in options and entries['slack-sort']['evidence']
assert "status = 'failed'" in runner and "status = 'passed'" in runner and "read('result.json')" in validator
print('SLACK SORT MAP VERIFIED: dispatch, recipe, synthetic hub and passed/failed evidence')
assert '.claude/skills/verify-wazig/features/slack-sort.md' in marker_namespace['PUBLIC_SKILL_PATHS']

views = (root / 'tools/verify-wazig/views.ps1').read_text(encoding='utf-8')
for required in ['Sort views', 'Show combined inbox', 'Ctrl+1 / Alt+I']:
    assert f'"{required}"' in source, required
for required in ['src/messenger_view.zig', 'src/chat_key.zig', 'src/control.zig', 'src/outbox.zig']:
    assert required in workflow, required
assert 'views' in options
for required in ['Assert-AccountView', 'Verification account send', "Send-Keys $Session '%i'", "Send-Keys $Session '^{DOWN}'", 'WAZIG_VERIFY_RESTART', 'restart.json']:
    assert required in views, required
assert 'VIEW_ACCOUNTS' in (root / 'tools/verify-wazig/fake-hub.py').read_text(encoding='utf-8')
changelog = (root / 'CHANGELOG.md').read_text(encoding='utf-8')
assert 'IGSH-602:' in changelog and 'Alt+I combined inbox' in changelog
for required in ['controlSortChats(a, a.chats[0..a.chat_count], view);',
                 'controlSortChats(a, list.items, view);',
                 'messenger_view.inboxMoveUp(by_time, jid_order)',
                 'by_time, by_name, jid_order)', 'fillSlackTimestamp(a, &chat);']:
    assert required in source, required
reconcile = (root / 'src/chat_reconcile_test.zig').read_text(encoding='utf-8')
for name in ['hub Slack history refreshes ordering after caching its last message fallback',
             'account view history accepts source accounts without confusing the hub cache namespace']:
    assert f'test "{name}"' in reconcile, name
sort_journey = (registry_path.parent / 'journey-slack-sort.ps1').read_text(encoding='utf-8')
assert "Send-Keys $session '^2'" in sort_journey and 'Drive Ctrl+2' in sort_map
assert "for keys in ['^2', '^{TAB}'" in validator
signal = (skill / 'features/signal.md').read_text(encoding='utf-8')
signal_journey = (root / 'tools/verify-wazig/signal.ps1').read_text(encoding='utf-8')
signal_validator = (root / 'tools/verify-wazig/check-signal-evidence.py').read_text(encoding='utf-8')
for gate in ['linked-chats', 'history', 'mark-read', 'media', 'react', 'send-text', 'send-file', 'live-events', 'limited', 'captcha', 'local-archive-unarchive']:
    assert gate in signal_journey and gate in signal_validator, gate
for name in ['RULE-MAP.md']:
    assert '(features/signal.md)' in (skill / name).read_text(encoding='utf-8')
assert 'feature=signal' in signal and 'Invoke-SignalJourney' in runner
assert entries['signal']['library'] == 'signal.ps1' and 'signal' in {row['hub'] for row in journeys}
assert 'signal' in {row['hub'] for row in journeys}
assert 'signal' in options and entries['signal']['evidence']
assert entries['signal']['validator']['file'] == 'check-signal-evidence.py'
assert '.claude/skills/verify-wazig/features/signal.md' in marker_namespace['PUBLIC_SKILL_PATHS']
print(f'MAP VERIFIED: {len(features)} complete feature entries, workflow/index parity, {len(coverage_ids)} coverage dispositions, source labels, stable controls, bounded chat-switch journey and GitHub triggers')

icons_map = (skill / 'features/workspace-icons.md').read_text(encoding='utf-8')
assert 'workspace icon' in icons_map
assert entries['workspace-icons']['script'] == 'journey-workspace-icons.ps1' and 'Invoke-WorkspaceIconsJourney $session' in runner
assert 'workspace-icons' in {row['hub'] for row in journeys}
assert 'workspace-icons' in options and entries['workspace-icons']['evidence']
assert 'check_pixels(folder)' in validator
assert '.claude/skills/verify-wazig/features/workspace-icons.md' in marker_namespace['PUBLIC_SKILL_PATHS']
for artifact in ['workspace-icons-list', 'badge-icon-', 'workspace-icons-pixels.json']:
    assert artifact in (root / 'tools/verify-wazig/check-workspace-icons.py').read_text(encoding='utf-8')
print('WORKSPACE ICON MAP VERIFIED: dispatch, synthetic team icons, screenshot pixels and surviving cache evidence')

icons_validator = (root / 'tools/verify-wazig/check-workspace-icons.py').read_text(encoding='utf-8')
assert "'signal': (58, 118, 240)" in icons_validator
assert 'signal:fixture-contact' in icons_validator and 'signal:fixture-contact' in harness
assert 'drawProviderMark(&shapes, badge, provider_badge)' in source
assert 'provider_badge == .whatsapp_mark or provider_badge == .signal_mark' in source
print('SIGNAL MARK MAP VERIFIED: shared provider renderer and workspace-icons screenshot evidence')

telegram = (skill / 'features/telegram.md').read_text(encoding='utf-8')
telegram_journey = (root / 'tools/verify-wazig/telegram.ps1').read_text(encoding='utf-8')
telegram_validator = (root / 'tools/verify-wazig/check-telegram-evidence.py').read_text(encoding='utf-8')
for gate in ['linked-chats', 'history', 'mark-read', 'media', 'react', 'reply', 'send-text', 'send-file', 'live-events', 'limited', 'local-archive-unarchive']:
    assert gate in telegram_journey and gate in telegram_validator, gate
for name in ['RULE-MAP.md']:
    assert '(features/telegram.md)' in (skill / name).read_text(encoding='utf-8')
assert 'feature=telegram' in telegram and 'Invoke-TelegramJourney' in runner
assert entries['telegram']['library'] == 'telegram.ps1' and 'telegram' in {row['hub'] for row in journeys}
assert 'telegram' in {row['hub'] for row in journeys}
assert 'telegram' in options and entries['telegram']['evidence']
assert entries['telegram']['validator']['file'] == 'check-telegram-evidence.py'
assert '.claude/skills/verify-wazig/features/telegram.md' in marker_namespace['PUBLIC_SKILL_PATHS']
print('TELEGRAM MAP VERIFIED: prelinked hub, messaging journey, CI wiring and indexed evidence')

notrap = (skill / 'features/notrap.md').read_text(encoding='utf-8')
notrap_journey = (root / 'tools/verify-wazig/notrap.ps1').read_text(encoding='utf-8')
notrap_validator = (root / 'tools/verify-wazig/check-notrap-evidence.py').read_text(encoding='utf-8')
assert 'feature=notrap' in notrap and 'Invoke-NotrapJourney $session' in runner
assert entries['notrap']['library'] == 'notrap.ps1' and 'notrap' in {row['hub'] for row in journeys}
assert 'notrap' in {row['hub'] for row in journeys}
assert 'notrap' in options and entries['notrap']['evidence']
assert 'run-name: verify-wazig ${{ inputs.feature' in workflow
assert entries['notrap']['validator']['file'] == 'check-notrap-evidence.py'
assert '.claude/skills/verify-wazig/features/notrap.md' in marker_namespace['PUBLIC_SKILL_PATHS']
for name in ['RULE-MAP.md']:
    assert '(features/notrap.md)' in (skill / name).read_text(encoding='utf-8')
for gate in ['startup-fallback', 'every-view-escape-alt']:
    assert gate in notrap_journey and gate in notrap_validator, gate
for artifact in ['startup-seed.json', 'transitions.json', 'escape-to-first-', 'esc-']:
    assert artifact in runner + notrap_journey and artifact in notrap_validator, artifact
for fragment in ['$source -le $order.Count', '$target -le $order.Count', "@('^1', '%i')", "'{ESC}'", 'Save-Screen $Session "view-$source"']:
    assert fragment in notrap_journey, fragment
assert "-Name InboxView -Value 4" in runner and "-Name AccountView -Value 'signal'" in runner
print('NOTRAP MAP VERIFIED: saved empty startup, every-view Escape and Alt matrix, dispatch and indexed evidence')

reactions = (skill / 'features/reactions.md').read_text(encoding='utf-8')
reaction_journey = (root / 'tools/verify-wazig/reactions.ps1').read_text(encoding='utf-8')
for artifact in ['react-requests.jsonl', 'reaction-clicks.json']:
    assert artifact in reaction_journey and artifact in validator, artifact
assert 'feature=reactions' in reactions and 'Invoke-ReactionsJourney $session' in runner
assert 'reactions' in options and 'menus' in options
assert entries['reactions']['evidence']
assert 'reactions' in {row['hub'] for row in journeys}
assert '.claude/skills/verify-wazig/features/reactions.md' in marker_namespace['PUBLIC_SKILL_PATHS']
assert "'reaction_laugh'" in reaction_journey and '0x1f602' in reaction_journey
assert '[VerifyMenus]::Click' in reaction_journey and "'#32768'" in reaction_journey
print('REACTIONS MAP VERIFIED: real mouse journey, exact hub emoji evidence and PR matrix')

threads = (root / 'tools/verify-wazig/slack-threads.ps1').read_text(encoding='utf-8')
for artifact in ['threads-on', 'thread-panel', 'thread-reply', 'threads-off', 'threads-restart', 'restart.json']:
    assert artifact in threads, artifact
assert 'slack-threads' in options and entries['slack-threads']['evidence']
assert entries['slack-threads']['validator']['file'] == 'check-slack-threads-evidence.py'
assert 'slack_threads.parent_reply_line' in threads and 'WAZIG_VERIFY_RESTART' in threads
assert 'slack-threads' in {row['hub'] for row in journeys}
print('SLACK THREADS MAP VERIFIED: synthetic hub, keyboard journey, read-only measurements and restart')

archive_journey = (root / 'tools/verify-wazig/hub-archive.ps1').read_text(encoding='utf-8')
archive_validator = (root / 'tools/verify-wazig/check-hub-archive-evidence.py').read_text(encoding='utf-8')
for name in ['RULE-MAP.md']:
    assert '(features/hub-archive.md)' in (skill / name).read_text(encoding='utf-8')
assert 'feature=hub-archive' in (skill / 'features/hub-archive.md').read_text(encoding='utf-8')
assert 'Invoke-HubArchiveJourney $session $messages $start' in runner
assert 'Wait-HubArchive $session $messages' in runner
assert '120363000000000001@g.us`t1`t2026-10-10T10:00:00Z' in runner
assert runner.index('if ($journey.prepare)') < runner.index('$app = [Diagnostics.Process]::Start($start)')
assert "Copy-Item (Join-Path $messages 'archive-state.txt')" in (registry_path.parent / entries['hub-archive']['prepare']).read_text(encoding='utf-8')
assert 'hub-archive' in {row['hub'] for row in journeys} and 'hub-archive' in {row['hub'] for row in journeys}
assert 'hub-archive' in {row['hub'] for row in journeys}
assert 'hub-archive' in options and entries['hub-archive']['evidence']
assert 'src/archive_rules.zig' in workflow
assert entries['hub-archive']['validator']['file'] == 'check-hub-archive-evidence.py'
assert '.claude/skills/verify-wazig/features/hub-archive.md' in marker_namespace['PUBLIC_SKILL_PATHS']
for artifact in ['legacy-archive-state.txt', 'restart.json', 'archive-state.txt', 'provider.requests.json', 'migration-before.txt', 'migration-after.txt']:
    assert artifact in runner + archive_journey and artifact in archive_validator, artifact
for fragment in ['WAZIG_VERIFY_RESTART', 'Wait-HubArchive $Session $Messages', 'Show archived chats', 'Show inbox chats', 'Quit Postbox', 'Get-FileHash']:
    assert fragment in archive_journey, fragment
for fragment in ['PROVIDER_UNARCHIVE_REQUIRED', 'PHONE_UNARCHIVE_REQUIRED', 'PROVIDER_INCOMING_REQUIRED', 'MIGRATION_ACK_REMOVES_LOCAL_ENTRY']:
    assert fragment in archive_validator, fragment
print('HUB ARCHIVE MAP VERIFIED: provider archive, phone unarchive, incoming, kept, acknowledged migration and restart')

palette_archived_map = (skill / 'features/palette-archived.md').read_text(encoding='utf-8')
palette_archived_journey = (root / 'tools/verify-wazig/palette-archived.ps1').read_text(encoding='utf-8')
palette_archived_validator = (root / 'tools/verify-wazig/check-palette-archived-evidence.py').read_text(encoding='utf-8')
for name in ['RULE-MAP.md']:
    assert '(features/palette-archived.md)' in (skill / name).read_text(encoding='utf-8')
assert 'feature=palette-archived' in palette_archived_map
assert 'Invoke-PaletteArchivedJourney $session' in runner and entries['palette-archived']['library'] == 'palette-archived.ps1'
assert entries['palette-archived']['chats'] == 3
assert 'palette-archived' in {row['hub'] for row in journeys} and 'palette-archived' in {row['hub'] for row in journeys}
assert 'palette-archived' in {row['hub'] for row in journeys}
assert 'palette-archived' in options and entries['palette-archived']['evidence']
assert entries['palette-archived']['validator'] and entries['palette-archived']['validator']['file'] == 'check-palette-archived-evidence.py'
assert '.claude/skills/verify-wazig/features/palette-archived.md' in marker_namespace['PUBLIC_SKILL_PATHS']
for fragment in ["'1064'", "'1072'", 'Read-ListLabels', "'%i'", 'view_order', 'selected.id', '/v1/wazig/archive', '/v1/wazig/messages', 'archived=true', 'Get-ArchivedPaletteLabel']:
    assert fragment in palette_archived_journey, fragment
for forbidden in ['WM_COMMAND', 'SendMessage', 'PostMessage', 'Start-Sleep']:
    assert forbidden not in palette_archived_journey, forbidden
for fragment in ['ROW_LIMIT', "row['matches'] == 1", "state['selected']['id'] == chat", "path == '/v1/wazig/mark-read'", "journey['failures'] == []"]:
    assert fragment in palette_archived_validator, fragment
print('PALETTE ARCHIVED MAP VERIFIED: synthetic hub, every-view palette queries, Enter without unarchive, evidence and PR wiring')

window = (skill / 'features/window.md').read_text(encoding='utf-8')
window_journey = (root / 'tools/verify-wazig/window.ps1').read_text(encoding='utf-8')
assert 'feature=window' in window and 'Invoke-WindowJourney $session $start $app' in runner
assert entries['window']['library'] == 'window.ps1' and not entries['window']['maximize']
assert 'window' in options and entries['window']['evidence']
assert entries['window']['validator']
for fragment in ['IsZoomed', 'GetWindowPlacement', 'MonitorFromWindow', 'GetMonitorInfo', "'%{F4}'", '--update-relaunch', 'WAZIG_VERIFY_RESTART', 'session.json', 'window.json']:
    assert fragment in window_journey, fragment
assert '.claude/skills/verify-wazig/features/window.md' in marker_namespace['PUBLIC_SKILL_PATHS']
assert '(features/window.md)' in (skill / 'RULE-MAP.md').read_text(encoding='utf-8')
print('WINDOW MAP VERIFIED: unforced startup, real keyboard restore/close, same-profile relaunch and zoomed evidence')

repaint = (root / 'tools/verify-wazig/repaint.ps1').read_text(encoding='utf-8')
assert 'Invoke-RepaintJourney $session' in runner and 'repaint' in {row['hub'] for row in journeys}
assert 'repaint' in {row['hub'] for row in journeys}
assert 'repaint' in options and entries['repaint']['evidence']
for artifact in ['paints.json', 'before.chats.json', 'after.chats.json']:
    assert artifact in repaint and artifact in validator, artifact
assert 'Send-Keys' not in repaint
assert '$clock.Elapsed.TotalSeconds -ge 60' in repaint
assert 'full repaints in 60 s, limit 3' in repaint
voice = (root / 'tools/verify-wazig/voice.ps1').read_text(encoding='utf-8')
assert 'Invoke-VoiceJourney $session $messages' in runner and 'voice' in {row['hub'] for row in journeys}
assert 'voice' in {row['hub'] for row in journeys}
assert 'voice' in options and entries['voice']['evidence']
for artifact in ['voice-checks.json', 'transcripts.json']:
    assert artifact in voice and artifact in validator, artifact
print('VOICE MAP VERIFIED: voice notes, cached transcripts, scroll, expand and partial-repaint pixel checks')
print('REPAINT MAP VERIFIED: cumulative counters, no-input incoming workload and PR journey')

archive_map = (skill / 'features/slack-archive.md').read_text(encoding='utf-8')
archive_journey = (root / 'tools/verify-wazig/slack-archive.ps1').read_text(encoding='utf-8')
archive_validator = (root / 'tools/verify-wazig/check-slack-archive-evidence.py').read_text(encoding='utf-8')
assert 'feature=slack-archive' in archive_map
assert 'Invoke-SlackArchiveJourney $session' in runner and 'slack-archive' in {row['hub'] for row in journeys}
assert 'slack-archive' in {row['hub'] for row in journeys}
assert 'slack-archive' in options and entries['slack-archive']['evidence']
assert entries['slack-archive']['validator']['file'] == 'check-slack-archive-evidence.py'
for name in ['RULE-MAP.md']:
    assert '(features/slack-archive.md)' in (skill / name).read_text(encoding='utf-8')
for artifact in ['archived', 'incoming-inbox', 'incoming-archive-empty', 'rearchived-inbox', 'rearchived', 'restart', 'unarchived',
                 'slack-archive-state.txt', 'slack-rearchive-state.txt']:
    assert artifact in archive_journey and artifact in archive_validator, artifact
assert archive_journey.count("Send-Keys $Session '^e'") == 3
assert archive_journey.count('/fixture/live') == 1
assert 'Assert-SlackArchiveView $Session $false 1 incoming-inbox $true' in archive_journey
assert 'Assert-SlackArchiveView $Session $true 0 incoming-archive-empty $false' in archive_journey
assert "archive_label -eq $(if ($Archived) { 'Archived' } else { '' })" in archive_journey
for fragment in ["target[0]['archive_label'] == ('Archived' if archived else '')", "target[0][3] == '0' and target[0][4]",
                 "[row['incoming'] for row in deliveries] == [1]", "> archive_stamps[0]", "urlsplit(row['wire_path']).path"]:
    assert fragment in archive_validator, fragment
for fragment in ['ordinary archive', 'keep=0', 'newer message', 'incoming-archive-empty.png']:
    assert fragment in archive_map, fragment
assert 'WAZIG_VERIFY_RESTART' in archive_journey and '$old.Kill()' in archive_journey
assert '$null = Get-App $Session' in archive_journey
assert '$app = [Diagnostics.Process]::Start($Start)' in archive_journey and 'return $app' in archive_journey
assert '$restarted = @(Invoke-SlackArchiveJourney $session $messages $start)' in runner
assert '$restarted.Count -eq 1 -and $restarted[0] -is [Diagnostics.Process] -and' in runner
assert '$restarted[0].Id -eq $session.pid' in runner and '$app = $restarted[0]' in runner
assert '$app.MainWindowHandle -eq [IntPtr](Get-Window $Session).Current.NativeWindowHandle' in archive_journey
assert '.claude/skills/verify-wazig/features/slack-archive.md' in marker_namespace['PUBLIC_SKILL_PATHS']
print('SLACK ARCHIVE MAP VERIFIED: ordinary archive, one newer delivery returns to inbox, rearchive, restart, unarchive and no archive endpoint requests')
paste_journey = (root / 'tools/verify-wazig/paste-image.ps1').read_text(encoding='utf-8')
paste_validator = (root / 'tools/verify-wazig/check-paste-image-evidence.py').read_text(encoding='utf-8')
for name in ['RULE-MAP.md']:
    assert '(features/paste-image.md)' in (skill / name).read_text(encoding='utf-8')
assert 'Invoke-PasteImageJourney $session' in runner and 'paste-image.ps1' in runner
assert entries['paste-image']['script'] == 'journey-paste-image.ps1' and 'paste-image' in {row['hub'] for row in journeys}
assert 'paste-image' in {row['hub'] for row in journeys}
assert 'paste-image' in options and entries['paste-image']['evidence']
assert 'src/paste_image.zig' in workflow
assert entries['paste-image']['validator']['file'] == 'check-paste-image-evidence.py'
assert '.claude/skills/verify-wazig/features/paste-image.md' in marker_namespace['PUBLIC_SKILL_PATHS']
for artifact in ['sizes.json', 'decoded', 'paste-uploads/', 'bridge-requests.jsonl']:
    assert artifact in paste_journey + harness + (root / 'tools/verify-wazig/fake-hub.py').read_text(encoding='utf-8')
    assert artifact in paste_validator
for required in ['1920, 1032', '3840, 2160', 'DataFormats.GetFormat(17)', 'SetData("PNG", false, png)',
                 "Send-Keys $Session '^v'", "Send-Keys $Session '{ENTER}'", 'VerifyPasteImage]::Decode']:
    assert required in paste_journey, required
for artifact in ['multi-before', 'multi-staged', 'multi-sent.json', 'remove.json', 'remove-staged', 'remove-one', 'remove-sent']:
    assert artifact in paste_journey and artifact in paste_validator and artifact in (skill / 'features/paste-image.md').read_text(encoding='utf-8'), artifact
for required in ["Click-Control $Session '1136'", 'Get-PickerDialog $Session $dialog', 'AutomationElement]::FromHandle', 'Read-ImagePreviews', '[VerifyMenus]::Click', 'two-image-caption']:
    assert required in paste_journey, required
for required in ["foreach ($folder in @('Desktop', 'Documents', 'Pictures'))", 'New-Item (Join-Path $profile $folder)',
                 "$profile = Join-Path $root 'profile'", '$root = Join-Path $env:RUNNER_TEMP "wazig-verify-$id"']:
    assert required in runner, required
assert runner.index('New-Item (Join-Path $profile $folder)') < runner.index('$app = [Diagnostics.Process]::Start($start)')
for required in ['owner == pid && IsWindowVisible(window)', 'name.ToString() == "#32770"',
                 'unexpected #32770 dialog: $text', "AutomationIdProperty, '1148'", 'ControlType]::ComboBox', 'ComboBoxEx32',
                 "$labels -ccontains 'File name:'", '$filename.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)',
                 '$edit.SetFocus()', 'AutomationElement]::FocusedElement, $edit', "@('^a', $Path, '{ENTER}')",
                 "'paste-image: file dialog closed'", 'picker-dialog-$($handle.ToInt64()).uia.txt', 'throw $failure']:
    assert required in paste_journey, required
for required in ['public static extern bool IsWindow(IntPtr window)', 'public static extern bool IsWindowVisible(IntPtr window)',
                 '$Expected -ne [IntPtr]::Zero -and $handle -eq $Expected',
                 'if (-not [VerifyPasteImage]::IsWindow($handle) -or -not [VerifyPasteImage]::IsWindowVisible($handle)) { continue }']:
    assert required in paste_journey, required
picker = paste_journey.split('function Add-PickerImage(', 1)[1].split('function Read-ImagePreviews(', 1)[0]
assert "Send-Keys $Session '%n'" not in picker and '.SetValue(' not in picker
assert 'foreach ($container in @($filename, $window))' not in picker
assert picker.index('$edit.SetFocus()') < picker.index('AutomationElement]::FocusedElement, $edit') < picker.index('Send-Keys $Session $keys')
assert paste_journey.count('Add-PickerImage $Session $fixture') == 2
print('PASTE IMAGE MAP VERIFIED: native clipboard, decoded uploads, four providers, isolated folders, focused file-name picker, popup diagnostics and remove-first evidence')

for item in ['link-previews.ps1', 'check-link-previews-evidence.py']:
    assert (root / 'tools/verify-wazig' / item).is_file()
assert 'link-previews' in options and entries['link-previews']['evidence']
assert 'link-previews' in {row['hub'] for row in journeys}
assert entries['link-previews']['validator']['file'] == 'check-link-previews-evidence.py'
print('LINK PREVIEWS MAP VERIFIED: dispatch, PR matrix, hub mode and surviving evidence')

composer_border = (root / 'tools/verify-wazig/composer-border.ps1').read_text(encoding='utf-8')
assert entries['composer-border']['library'] == 'composer-border.ps1'
assert entries['composer-border']['script'] == 'journey-composer-border.ps1'
assert entries['composer-border']['pr'] and 'Invoke-ComposerBorderJourney $session $start $app' in runner
for fragment in ['@(100, 125, 150)', "Get-Edit $window '1032'", 'BoundingRectangle', 'Measure-ComposerBorder', 'Assert-ComposerBorder', 'composer-border.json', 'Test-ComposerBorderOracle', "-Name FontScale -Value $scale", 'GetDpiForWindow']:
    assert fragment in composer_border, fragment
for side in ['top', 'bottom', 'left', 'right']:
    assert f'{side} = Measure-ComposerBorder' in composer_border, side
assert '$Measurement.top -eq $Measurement.bottom' in composer_border
assert '$Measurement.left -eq $Measurement.right' in composer_border
assert '$Measurement.top -eq $Measurement.left' in composer_border
assert '.claude/skills/verify-wazig/features/composer-border.md' in marker_namespace['PUBLIC_SKILL_PATHS']
print('COMPOSER BORDER MAP VERIFIED: four screenshot edges, exact saved text scales, negative oracle and PR wiring')

caret = (root / 'tools/verify-wazig/caret.ps1').read_text(encoding='utf-8')
assert entries['caret']['library'] == 'caret.ps1'
assert entries['caret']['script'] == 'journey-caret.ps1'
assert entries['caret']['pr'] and 'Invoke-CaretJourney $session $start $app' in runner
for fragment in ['GetGUIThreadInfo', 'GetCaretBlinkTime', "Get-Edit $window '1032'", 'CopyFromScreen', 'Get-CaretOnOff', 'Test-CaretOracle', 'caret.json', 'Theme: Green', '$theme.on -ge 2 -and $theme.off -ge 2']:
    assert fragment in caret, fragment
assert '.claude/skills/verify-wazig/features/caret.md' in marker_namespace['PUBLIC_SKILL_PATHS']
print('CARET MAP VERIFIED: system caret reading, timed composer frames, both themes and PR wiring')

passage = (root / 'tools/verify-wazig/passage-copy.ps1').read_text(encoding='utf-8')
assert 'Invoke-PassageCopyJourney $session' in runner
assert entries['passage-copy']['hub'] == 'passage-copy'
assert entries['passage-copy']['hub_handler']['class'] == 'PassageCopyHandler'
assert entries['passage-copy']['chats'] == 2
assert entries['passage-copy']['pr'] and entries['passage-copy']['evidence']
for value in ['clipboard.json', 'passage-fixture.json', 'held drag beyond canvas 1024 bottom']:
    assert value in passage and value in validator, value
for value in ['[VerifyPassage]::Button', '[VerifyMenus]::Hover', "Send-Keys $Session '^c'", '$actual -ceq $expected']:
    assert value in passage, value
for value in ['$doubleClickDelay = [int][VerifyPassage]::GetDoubleClickTime() + 100',
              '[System.Threading.Thread]::Sleep($doubleClickDelay)', "'react-requests.jsonl'",
              'Assert-That (-not (Test-Path $reactionLog) -or (Get-Item $reactionLog).Length -eq 0)']:
    assert value in passage, value
assert '[DllImport("user32.dll")] public static extern uint GetDoubleClickTime();' in (root / 'tools/verify-wazig/passage-copy.cs').read_text(encoding='utf-8')
assert hub_parser.parse_args(['--passage-copy', '--port-file', 'port', '--log', 'log']).mode == 'passage-copy'
assert '.claude/skills/verify-wazig/features/passage-copy.md' in marker_namespace['PUBLIC_SKILL_PATHS']
assert not re.search(r'\$(?:\w+\.)?(?:messages|rows|before|edgeBefore|after)\[\d', passage, re.I), 'passage targets must use PASSAGE ids, not array positions'
for value in ["$messages['PASSAGE-2']", "$messages['PASSAGE-5']", "$edgeMessages['PASSAGE-6']", "$heldMessages['PASSAGE-7']", '$_.MsgID -ceq "PASSAGE-$index"', '[VerifyPassage]::Wheel($Session.pid, 120)']:
    assert value in passage, value
passage_validator = (registry_path.parent / entries['passage-copy']['validator']['file']).read_text(encoding='utf-8')
assert not re.search(r"\['(?:before|after|messages)'\]\[\d", passage_validator), 'passage evidence must resolve control messages by id'
for value in ["passage_messages(check['before'])", "passage_messages(check['after'])", "passage_messages(held['messages'])", "fixture_messages[f'PASSAGE-{index}']", 'timestamps == sorted(timestamps)']:
    assert value in passage_validator, value
assert 'self.respond(200, list(reversed(passage_rows(chat)))' in (root / 'tools/verify-wazig/fake-hub.py').read_text(encoding='utf-8'), 'passage message endpoint must be newest-first; clipboard fixture stays chronological'
print('PASSAGE COPY MAP VERIFIED: id-based targets and evidence, chronological clipboard, newest-first wire rows, real drag and held-edge scrolling on both providers')
bulk = entries['archive-bulk']
assert bulk['pr'] and bulk['provider'] and not bulk['hub']
assert bulk['prepare'] == entries['archive']['prepare'] == 'prepare-archive.ps1'
bulk_journey = (registry_path.parent / bulk['script']).read_text(encoding='utf-8')
for required in ["Send-Keys $session '^a'", "Send-Keys $session '^e'", 'bulk_selected_count -eq 2',
                 '$state.pending_archives -eq 0', '$state.chat_count -eq 0 -and $inbox.Count -eq 0',
                 "$selection[0].GetText(-1) -ceq 'hello'", 'Save-Screen $session text-selected']:
    assert required in bulk_journey, required
assert "'archive-bulk'" in harness.split('function Save-Screen(', 1)[1].split('function Invoke-Doctor(', 1)[0]
assert 'check-chat-rows.ps1' in workflow
print(f'JOURNEY REGISTRY VERIFIED: {len(journeys)} journeys, maps, scripts, hub switches, evidence and plan matrix')

media_fit = (root / 'tools/verify-wazig/media-fit.ps1').read_text(encoding='utf-8')
assert 'feature=media-fit' in (skill / 'features/media-fit.md').read_text(encoding='utf-8')
assert 'Invoke-MediaFitJourney $session' in (registry_path.parent / entries['media-fit']['script']).read_text(encoding='utf-8')
assert entries['media-fit']['hub'] == 'media-fit'
assert entries['media-fit']['hub_handler']['class'] == 'MediaFitHandler'
assert entries['media-fit']['chats'] == 1
assert entries['media-fit']['pr'] and entries['media-fit']['evidence']
assert entries['media-fit']['library'] == 'media-fit.ps1'
assert entries['media-fit']['validator'] == {'file': 'check-media-fit-evidence.py', 'function': 'check_media_fit'}
assert hub_parser.parse_args(['--media-fit', '--port-file', 'port', '--log', 'log']).mode == 'media-fit'
assert '.claude/skills/verify-wazig/features/media-fit.md' in marker_namespace['PUBLIC_SKILL_PATHS']
assert '(features/media-fit.md)' in (skill / 'RULE-MAP.md').read_text(encoding='utf-8')
for artifact in ['media-fit-checks.json', 'media-fit.requests.json', 'media-fit-fixture.json', 'media-fit-resize.json']:
    assert artifact in media_fit and artifact in (root / 'tools/verify-wazig/check-media-fit-evidence.py').read_text(encoding='utf-8')
for required in ['canvas = @($ox, $oy, $canvasWidth, $canvasHeight)',
                 '$null = [VerifyVoice]::FullRepaint', '$null = [VerifyVoice]::Wheel',
                 '$rows.Count -eq 1', '$row = $rows[0]', '$row.bubble[3] -le $height',
                 '$narrow.bubble[2] - $narrow.bubble[0] - $padding -lt $wide.media[2] - $wide.media[0]']:
    assert required in media_fit, required
assert '$row.bubble[3] - $row.bubble[1] -gt' not in media_fit
print('MEDIA FIT MAP VERIFIED: hub downloads, wide/narrow geometry and screenshot pixels, timestamp clearance and PR wiring')

sidebar = entries['sidebar-surface']
assert sidebar['pr'] and sidebar['evidence'] and sidebar['maximize'] and sidebar['hub'] is None
assert sidebar['arguments'] == ['--verify-text-comparison']
assert sidebar['validator'] == {'file': 'check-sidebar-surface.py', 'function': 'check_sidebar_surface'}
sidebar_journey = (registry_path.parent / sidebar['script']).read_text(encoding='utf-8')
sidebar_validator = (registry_path.parent / sidebar['validator']['file']).read_text(encoding='utf-8')
for required in ["@('amoled', 'green')", 'BoundingRectangle', 'GetDpiForWindow', 'ClientToScreen', 'sidebar-layout.json', 'Save-Screen', 'text-metrics.json', "'Search chats'", 'messages.json']:
    assert required in sidebar_journey, required
for required in ['sidebar-pixels.json', 'sidebar-builds.json', 'baseline_commit', 'candidate_sha256', 'baseline_sha256', 'assertion_parent', 'fixture_sha256', 'measure_pair', 'validate(metrics)', 'Historical sidebar unexpectedly matches the approved design', 'approved sidebar width', 'search pill stays above the rows']:
    assert required in sidebar_validator, required
for required in ['src/theme.zig', "if: matrix.feature == 'sidebar-surface'", 'test-sidebar-surface.py', 'git log --diff-filter=A --format=%H -- tools/verify-wazig/journey-sidebar-surface.ps1', 'sidebar-baseline-bin/bin', 'verification-evidence/baseline', 'sidebar-builds.json']:
    assert required in workflow, required
assert '.claude/skills/verify-wazig/features/sidebar-surface.md' in marker_namespace['PUBLIC_SKILL_PATHS']
print('verification skill map passed: sidebar screenshot pairs, historical baseline builds, pixel validator and both dark themes')

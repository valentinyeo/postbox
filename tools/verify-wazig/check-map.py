from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
skill = root / '.claude/skills/verify-wazig'
text = (skill / 'SKILL.md').read_text(encoding="utf-8")
assert text.startswith('---\nname: verify-wazig\ndescription: ')
assert re.findall(r'^## (.+)$', text, re.M) == ['Launch', 'Doctor', 'Drive', 'Evidence', 'Cleanup', 'Helpers']
features = sorted(p.stem for p in (skill / 'features').glob('*.md') if p.name != 'README.md')
assert features == ['appearance', 'archive', 'drafts', 'hub', 'menus', 'navigation', 'palette', 'search', 'signal', 'slack-sort', 'telegram', 'views', 'whatsapp-hub', 'workspace-icons']
index = (skill / 'features/README.md').read_text(encoding='utf-8')
for feature in features:
    entry = (skill / 'features' / f'{feature}.md').read_text(encoding="utf-8")
    assert re.findall(r'^## (.+)$', entry, re.M) == [
        'Sub-features', 'How to get to it (user POV)', 'Driving it with PowerShell UI Automation', 'Gotchas'
    ], feature
    assert f'feature={feature}' in entry
    assert f'({feature}.md)' in index
source = (root / 'src/main.zig').read_text(encoding="utf-8")
for label in ['Search chats', 'Next chat', 'Previous chat', 'Compose message', 'Keyboard shortcuts', 'Theme: Green', 'Make text larger', 'Reset text size', 'Show archived chats', 'Show inbox chats', 'Archive selected chat', 'Unarchive selected chat', 'Archive and keep archived', 'Allow resurfacing']:
    assert f'"{label}"' in source, label
for control in ['id_search = 1008', 'id_compose = 1032']:
    assert control in source
workflow = (root / '.github/workflows/verify.yml').read_text(encoding="utf-8")
for required in ['workflow_dispatch:', 'pull_request:', 'windows-latest', '.claude/skills/verify-wazig/**', 'actions/upload-artifact@v4', 'if: always()', '--release=small']:
    assert required in workflow, required
assert 'options: [search, navigation, drafts, palette, appearance, menus, whatsapp-hub, hub, slack-sort, views, workspace-icons, signal, telegram, archive, text-comparison]' in workflow
options_match = re.search(r'^        options: \[(.+)\]$', workflow, re.M)
assert options_match, 'missing workflow_dispatch journey options'
options = [option.strip() for option in options_match[1].split(',')]
assert len(options) == len(set(options)), 'duplicate workflow journey'
indexed = re.findall(r'^\| \[([^\]]+)\]\(([^)]+)\) \|', index, re.M)
assert len(indexed) == len({name for name, target in indexed}), 'duplicate README journey'
assert {name for name, target in indexed} == set(options), 'README table must list every workflow journey exactly once'
assert {Path(target).stem for name, target in indexed} == set(features), 'each feature map must be indexed'
for name, target in indexed:
    assert target in {f'{feature}.md' for feature in features} and (skill / 'features' / target).is_file(), (name, target)
    assert f'feature={name}' in (skill / 'features' / target).read_text(encoding='utf-8'), name
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
assert 'Keep archived\\tCtrl+Shift+E' in (root / 'src/chat_menu.zig').read_text(encoding='utf-8')
for helper in ['run', 'doctor', 'cleanup', 'harness']:
    assert (root / 'tools/verify-wazig' / f'{helper}.ps1').is_file()
assert 'RegOverridePredefKey' in source and 'VerificationRequiresActions' in source
assert 'if (verification_fixture and !hubConfigured(a)) return verificationEnqueue(a, job);' in source
assert 'if (!verification_fixture) return null;' in source
assert 'if (verification_fixture) return;' in source
assert 'whatsapp-hub' in workflow
assert (root / 'tools/verify-wazig/fake-wa-bridge.py').is_file()
fixture_config = source.split('fn configureWaHub(', 1)[1].split('    a.wa_bridge_url =', 1)[0]
assert 'if (verification_fixture)' in fixture_config
assert 'if (init.environ_map.get("WAZIG_VERIFY_HUB_URL"))' in fixture_config
assert 'if (init.environ_map.get("WAZIG_VERIFY_HUB_KEY")) |seed|' in fixture_config
assert 'if (!slack_win.saveSecret(lit("WaBridgeKey"), seed)) return;' in fixture_config
runner = (root / 'tools/verify-wazig/run.ps1').read_text(encoding='utf-8')
assert "if ($Feature -notin @('whatsapp-hub', 'hub', 'slack-sort', 'views', 'workspace-icons', 'signal', 'telegram')) {\n    Set-Content (Join-Path $messages 'account-tag.txt')" in runner
harness = (root / 'tools/verify-wazig/harness.ps1').read_text(encoding='utf-8')
for proof in ['chats', 'chat-switch', 'history', 'mark-read', 'live-sse-replay', 'send-client-id-dedupe', 'media-202-ready-cache', 'archive', 'auth-dpapi-backend']:
    assert f'Hub-Pass $Session {proof}' in harness, proof
bridge = (root / 'tools/verify-wazig/fake-wa-bridge.py').read_text(encoding='utf-8')
assert "last_message_ts='2026-01-01T00:00:00Z'" in bridge
assert 'if request == 1:\n                    time.sleep(3)' in bridge
for required in ['ReadToEndAsync()', '$child.WaitForExit($TimeoutMilliseconds)', '$remaining = 1000 -',
                 'Read-Control $Session messages -TimeoutMilliseconds $remaining', '$elapsed -le 1000',
                 '$shown.messages.Count -eq 0', 'Save-Screen $Session beta-empty']:
    assert required in harness, required
validator = (root / 'tools/verify-wazig/check-evidence.py').read_text(encoding='utf-8')
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
assert "'slack-sort'" in runner and '--slack-sort' in (root / 'tools/verify-wazig/fake-hub.py').read_text(encoding='utf-8')
assert '"slack-sort"' in workflow and "matrix.feature == 'slack-sort'" in workflow
assert "status = 'failed'" in runner and "status = 'passed'" in runner and "read('result.json')" in validator
print('SLACK SORT MAP VERIFIED: dispatch, recipe, synthetic hub and passed/failed evidence')
assert '.claude/skills/verify-wazig/features/slack-sort.md' in (root / 'tools/check_private_markers.py').read_text(encoding='utf-8')

views = (root / 'tools/verify-wazig/views.ps1').read_text(encoding='utf-8')
for required in ['Sort views', 'Show combined inbox', 'Alt+I']:
    assert f'"{required}"' in source, required
for required in ['views', 'src/messenger_view.zig', 'src/chat_key.zig', 'src/control.zig', 'src/outbox.zig']:
    assert required in workflow, required
assert '"views"' in workflow.split('matrix:', 1)[1]
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
sort_journey = runner.split('        slack-sort {', 1)[1].split('        views {', 1)[0]
assert "Send-Keys $session '%1'" in sort_journey and 'Drive Alt+1' in sort_map
assert "for keys in ['%1', '^{TAB}'" in validator
signal = (skill / 'features/signal.md').read_text(encoding='utf-8')
signal_journey = (root / 'tools/verify-wazig/signal.ps1').read_text(encoding='utf-8')
signal_validator = (root / 'tools/verify-wazig/check-signal-evidence.py').read_text(encoding='utf-8')
for gate in ['linking-qr', 'linked-chats', 'history', 'mark-read', 'media', 'react', 'send-text', 'send-file', 'live-events', 'limited', 'captcha', 'archive-unsupported']:
    assert gate in signal_journey and gate in signal_validator, gate
for name in ['INDEX.md', 'RULE-MAP.md']:
    assert '(features/signal.md)' in (skill / name).read_text(encoding='utf-8')
assert 'feature=signal' in signal and 'Invoke-SignalJourney' in runner
assert 'signal.ps1' in runner and '[switch]$Signal' in harness
assert '--signal' in (root / 'tools/verify-wazig/fake-hub.py').read_text(encoding='utf-8')
assert '"signal"' in workflow and "matrix.feature == 'signal'" in workflow
assert 'check-signal-evidence.py' in validator
assert '.claude/skills/verify-wazig/features/signal.md' in (root / 'tools/check_private_markers.py').read_text(encoding='utf-8')
print(f'MAP VERIFIED: {len(features)} complete feature entries, workflow/index parity, {len(coverage_ids)} coverage dispositions, source labels, stable controls, bounded chat-switch journey and GitHub triggers')

icons_map = (skill / 'features/workspace-icons.md').read_text(encoding='utf-8')
assert 'workspace icon' in icons_map
assert "'workspace-icons'" in runner and 'Invoke-WorkspaceIconsJourney $session' in runner
assert '--workspace-icons' in (root / 'tools/verify-wazig/fake-hub.py').read_text(encoding='utf-8')
assert '"workspace-icons"' in workflow and "matrix.feature == 'workspace-icons'" in workflow
assert 'check_pixels(folder)' in validator
assert '.claude/skills/verify-wazig/features/workspace-icons.md' in (root / 'tools/check_private_markers.py').read_text(encoding='utf-8')
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
for gate in ['linking-qr', 'linking-password', 'linked-chats', 'history', 'mark-read', 'media', 'react', 'reply', 'send-text', 'send-file', 'live-events', 'limited', 'archive-unsupported']:
    assert gate in telegram_journey and gate in telegram_validator, gate
for name in ['INDEX.md', 'RULE-MAP.md']:
    assert '(features/telegram.md)' in (skill / name).read_text(encoding='utf-8')
assert 'feature=telegram' in telegram and 'Invoke-TelegramJourney' in runner
assert 'telegram.ps1' in runner and '[switch]$Telegram' in harness
assert '--telegram' in (root / 'tools/verify-wazig/fake-hub.py').read_text(encoding='utf-8')
assert '"telegram"' in workflow and "matrix.feature == 'telegram'" in workflow
assert 'check-telegram-evidence.py' in validator
assert '.claude/skills/verify-wazig/features/telegram.md' in (root / 'tools/check_private_markers.py').read_text(encoding='utf-8')
assert (root / 'tools/verify-wazig/telegram-link.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
assert 'Scan in Telegram: Settings > Devices > Link Desktop Device' in source
print('TELEGRAM MAP VERIFIED: hub linking, messaging journey, CI wiring and indexed evidence')

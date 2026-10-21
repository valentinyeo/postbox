from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
skill = root / '.claude/skills/verify-wazig'
text = (skill / 'SKILL.md').read_text(encoding="utf-8")
assert text.startswith('---\nname: verify-wazig\ndescription: ')
assert re.findall(r'^## (.+)$', text, re.M) == ['Launch', 'Doctor', 'Drive', 'Evidence', 'Cleanup', 'Helpers']
features = sorted(p.stem for p in (skill / 'features').glob('*.md') if p.name != 'README.md')
assert features == ['appearance', 'drafts', 'navigation', 'palette', 'search', 'whatsapp-hub']
for feature in features:
    entry = (skill / 'features' / f'{feature}.md').read_text(encoding="utf-8")
    assert re.findall(r'^## (.+)$', entry, re.M) == [
        'Sub-features', 'How to get to it (user POV)', 'Driving it with PowerShell UI Automation', 'Gotchas'
    ], feature
    assert f'feature={feature}' in entry
    assert f'({feature}.md)' in (skill / 'features/README.md').read_text(encoding="utf-8")
source = (root / 'src/main.zig').read_text(encoding="utf-8")
for label in ['Search chats', 'Next chat', 'Previous chat', 'Compose message', 'Keyboard shortcuts', 'Theme: Green', 'Make text larger', 'Reset text size']:
    assert f'"{label}"' in source, label
for control in ['id_search = 1008', 'id_compose = 1032']:
    assert control in source
workflow = (root / '.github/workflows/verify.yml').read_text(encoding="utf-8")
for required in ['workflow_dispatch:', 'pull_request:', 'windows-latest', '.claude/skills/verify-wazig/**', 'actions/upload-artifact@v4', 'if: always()', '--release=small']:
    assert required in workflow, required
for helper in ['run', 'doctor', 'cleanup', 'harness']:
    assert (root / 'tools/verify-wazig' / f'{helper}.ps1').is_file()
assert 'RegOverridePredefKey' in source and 'VerificationRequiresActions' in source
assert 'if (verification_fixture and !hubConfigured(a)) return false;' in source
assert 'if (verification_fixture) return;' in source
assert 'whatsapp-hub' in workflow
assert (root / 'tools/verify-wazig/fake-wa-bridge.py').is_file()
fixture_config = source.split('fn configureWaHub(', 1)[1].split('    a.wa_bridge_url =', 1)[0]
assert 'if (verification_fixture)' in fixture_config
assert 'if (init.environ_map.get("WAZIG_VERIFY_HUB_URL"))' in fixture_config
assert 'if (init.environ_map.get("WAZIG_VERIFY_HUB_KEY")) |seed|' in fixture_config
assert 'if (!slack_win.saveSecret(lit("WaBridgeKey"), seed)) return;' in fixture_config
runner = (root / 'tools/verify-wazig/run.ps1').read_text(encoding='utf-8')
assert "if ($Feature -ne 'whatsapp-hub') {\n    Set-Content (Join-Path $messages 'account-tag.txt')" in runner
harness = (root / 'tools/verify-wazig/harness.ps1').read_text(encoding='utf-8')
for proof in ['chats', 'history', 'mark-read', 'live-sse-replay', 'send-client-id-dedupe', 'media-202-ready-cache', 'archive', 'auth-dpapi-backend']:
    assert f'Hub-Pass $Session {proof}' in harness, proof
print('MAP VERIFIED: six complete feature entries, source labels, stable controls, hub journey and GitHub triggers')

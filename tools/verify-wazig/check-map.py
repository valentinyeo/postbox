from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
skill = root / '.claude/skills/verify-wazig'
text = (skill / 'SKILL.md').read_text()
assert text.startswith('---\nname: verify-wazig\ndescription: ')
assert re.findall(r'^## (.+)$', text, re.M) == ['Launch', 'Doctor', 'Drive', 'Evidence', 'Cleanup', 'Helpers']
features = sorted(p.stem for p in (skill / 'features').glob('*.md') if p.name != 'README.md')
assert features == ['appearance', 'drafts', 'navigation', 'palette', 'search']
for feature in features:
    entry = (skill / 'features' / f'{feature}.md').read_text()
    assert re.findall(r'^## (.+)$', entry, re.M) == [
        'Sub-features', 'How to get to it (user POV)', 'Driving it with PowerShell UI Automation', 'Gotchas'
    ], feature
    assert f'feature={feature}' in entry
    assert f'({feature}.md)' in (skill / 'features/README.md').read_text()
source = (root / 'src/main.zig').read_text()
for label in ['Search chats', 'Next chat', 'Previous chat', 'Compose message', 'Keyboard shortcuts', 'Theme: Green', 'Make text larger', 'Reset text size']:
    assert f'"{label}"' in source, label
for control in ['id_search = 1008', 'id_compose = 1032']:
    assert control in source
workflow = (root / '.github/workflows/verify.yml').read_text()
for required in ['workflow_dispatch:', 'pull_request:', 'windows-latest', '.claude/skills/verify-wazig/**', 'actions/upload-artifact@v4', 'if: always()', '--release=small']:
    assert required in workflow, required
for helper in ['run', 'doctor', 'cleanup', 'harness']:
    assert (root / 'tools/verify-wazig' / f'{helper}.ps1').is_file()
assert 'RegOverridePredefKey' in source and 'VerificationRequiresActions' in source
assert 'if (verification_fixture) return false;' in source
assert 'if (verification_fixture) return;' in source
print('MAP VERIFIED: five complete feature entries, source labels, stable controls, helpers and GitHub triggers')

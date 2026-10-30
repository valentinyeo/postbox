from pathlib import Path
import hashlib
import json
import re
import runpy
import subprocess
import sys

folder = Path(sys.argv[1])
session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
feature = session['feature']
chat_count = 3 if feature == 'appearance' else 2
version = session['expected_version']
product = session['expected_product']
assert re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version)
assert session['sha256'] and session['commit']
assert not (folder / 'failure.txt').exists()
assert f'JOURNEY PASSED: {feature}' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
if feature == 'palette':
    search_api = runpy.run_path(str(Path(__file__).with_name('check-search-evidence.py')))
    search_api['check_shortcuts'](json.loads((folder / 'search-shortcuts.json').read_text(encoding='utf-8-sig')))
    assert 'hub no-url-unavailable PASS' in (folder / 'fallback-proof.log').read_text(encoding='utf-8-sig')
    launch = (folder / 'final-data/launch-log.txt').read_text(encoding='utf-8-sig')
    assert 'whatsapp backend: unavailable (URL not configured)' in launch
    assert all(label not in launch for label in ('message backend: hub', 'whatsapp backend: hub', 'whatsapp backend: wacli'))
    cached = json.loads((folder / 'final-data/chats-0000000000000526.json').read_text(encoding='utf-8-sig'))
    assert sorted(row['name'] for row in cached['data']) == ['Verification Alpha', 'Verification Beta']
    assert not (folder / 'final-data/telegram').exists()
    removed = json.loads((folder / 'removed-status.json').read_text(encoding='utf-8-sig'))
    assert removed['positive_query'] == 'Keyboard shortcuts' and removed['positive_matches'] == 1
    assert removed['query'] == 'Status' and removed['status_rows'] == 0
    assert removed['sidebar_status_controls'] == 0
    stages = ['before', 'removed-status', 'action', 'after']
    keys = ['^k', 'Keyboard shortcuts', '^a', 'Status', '{ENTER}', '{ESC}']
else:
    scale = json.loads((folder / 'text-scale.json').read_text(encoding='utf-8-sig'))
    assert scale['initial_saved'] is False and scale['larger'] == 110 and scale['reset'] == 100
    assert 0 < scale['baseline_points'] < scale['larger_points']
    assert scale['reset_points'] == scale['baseline_points']
    fresh = json.loads((folder / 'text-fresh-default.state.json').read_text(encoding='utf-8-sig'))
    assert fresh['font_layout']['scale'] == 100 and fresh['version'] == version
    assert (folder / 'text-fresh-default.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    viewport = json.loads((folder / 'font-viewport.json').read_text(encoding='utf-8-sig'))
    assert viewport['width'] == 1920 and viewport['height'] == 1032 and viewport['hosted_only'] is True
    presets = json.loads((folder / 'text-presets.json').read_text(encoding='utf-8-sig'))
    assert [row['scale'] for row in presets] == [80, 100, 125, 150]
    for index, row in enumerate(presets):
        layout = row['list']
        assert layout['scale'] == row['scale']
        assert row['points'] > 0 and row['list_font_height'] < 0 and row['chat_font_height'] < 0
        assert row['list_uia_height'] >= layout['row_height'] > 0
        assert row['composer_uia_height'] >= layout['body_line_height'] > 0
        assert layout['preview_top'] - layout['name_top'] >= max(layout['name_line_height'], layout['time_line_height'])
        assert layout['preview_bottom'] - layout['preview_top'] >= layout['preview_line_height'] > 0
        if index:
            previous = presets[index - 1]
            assert row['points'] > previous['points']
            assert row['list_font_height'] < previous['list_font_height']
            assert row['chat_font_height'] < previous['chat_font_height']
        image = (folder / f"text-preset-{row['scale']}.png").read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    palette = json.loads((folder / 'font-palette.json').read_text(encoding='utf-8-sig'))
    assert palette['edit_height'] >= palette['body_line_height'] > 0
    assert palette['row_height'] >= max(palette['body_line_height'], 2 * palette['small_line_height'] + 4)
    assert (folder / 'text-preset-palette.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    restart = json.loads((folder / 'font-restart.json').read_text(encoding='utf-8-sig'))
    assert restart['old_pid'] != restart['new_pid'] and restart['sha256'] == session['sha256']
    assert restart['new_pid'] == session['pid'] and restart['new_start'] == session['startTicks']
    assert restart['id'] == session['id'] and restart['root'] == session['root']
    restarted = json.loads((folder / 'text-preset-restart.state.json').read_text(encoding='utf-8-sig'))
    assert restarted['font_layout']['scale'] == 150 and restarted['version'] == version
    assert (folder / 'text-preset-restart.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert (folder / 'group-layout.txt').read_text(encoding='utf-8-sig').startswith('GROUP_LAYOUT_OK:')
    groups = json.loads((folder / 'group-senders.messages.json').read_text(encoding='utf-8-sig'))
    assert {row['id'] for row in groups['messages']} == {'GROUP-FIRST', 'GROUP-SAME', 'GROUP-DAY', 'GROUP-OTHER', 'GROUP-QUOTE', 'GROUP-OWN'}
    stages = ['before', 'action', 'text-larger', 'after', 'group-senders']
    keys = ['^k', 'Theme: Graphite', 'Make text larger', 'Text size: Small', 'Text size: Default', 'Text size: Large', 'Text size: Larger', 'Quit Postbox', '{ENTER}', '^0']
    shared = json.loads((folder / 'shared-design.json').read_text(encoding='utf-8-sig'))
    assert shared['width'] == 1920 and shared['height'] == 1032
    assert shared['draft'] == 'Shared design check'
    assert shared['foreground_pixels'] >= 10 and shared['raised_pixels'] > shared['pill']['width'] * shared['pill']['height'] / 2
    transcript = json.loads((folder / 'dictation-transcript.json').read_text(encoding='utf-8-sig'))
    assert transcript['expected'] == transcript['actual'] == 'Shared design check Go forward ten meters.'
    preferences = (folder / 'preferences.txt').read_text(encoding='utf-8-sig')
    assert 'FontScale' in preferences and '100' in preferences
for keys_sent in keys:
    assert f'keys: {keys_sent}' in actions
images = []
for name in stages:
    image = (folder / f'{name}.png').read_bytes()
    assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
    images.append(hashlib.sha256(image).hexdigest())
    assert re.fullmatch(rf'MessagesZig \| (?:.+ - )?{re.escape(product)} v{re.escape(version)}', (folder / f'{name}.uia.txt').read_text(encoding='utf-8-sig').splitlines()[0])
    state = json.loads((folder / f'{name}.state.json').read_text(encoding='utf-8-sig'))
    assert state['version'] == version and state['chat_count'] == chat_count
    assert state['pending_sends'] == state['pending_archives'] == 0 and state['sync'] == 'stopped'
assert images[0] != images[1] and images[2] != images[3]
final = json.loads((folder / 'side-effects.json').read_text(encoding='utf-8-sig'))
assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
assert final['chat_count'] == chat_count and final['search'] == ''
assert final['theme'] == 'amoled'
print(f'EVIDENCE VERIFIED: {feature} input, new assertions, surviving screenshots and isolation')
raise SystemExit(0)

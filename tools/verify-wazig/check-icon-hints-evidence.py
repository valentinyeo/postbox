import json
import os
from pathlib import Path
import re


LABELS = {
    'header-avatar': 'Current chat',
    'attach': 'Attach photo or file',
    'attach-disabled': 'Select a chat first',
    'mic': 'Record a voice note  Ctrl+Shift+M',
    'mic-recording': 'Finish voice note  Ctrl+Shift+M · Enter sends · Esc cancels',
    'dictate': 'Dictate  Ctrl+D',
    'emoji': 'Emoji menu',
    'send': 'Send message  Enter',
    'reply-close': 'Cancel reply',
    'staged-0': 'Remove attachment',
    'staged-1': 'Remove attachment',
    'staged-compacted': 'Remove attachment',
    'react-selected': 'React  Ctrl+R',
    'reply-selected': 'Reply  Ctrl+Shift+R',
    'more-selected': 'Message actions',
    'react-unselected': 'React',
    'reply-unselected': 'Reply',
    'more-unselected': 'Message actions',
}


def load(folder, name):
    return json.loads((folder / name).read_text(encoding='utf-8-sig'))


def check_evidence(folder):
    folder = Path(folder)
    session = load(folder, 'session.json')
    assert session['feature'] == 'icon-hints' and session['expected_product'] == 'Postbox'
    assert re.fullmatch(r'\d+\.\d+\.\d+', session['expected_version'])
    assert re.fullmatch(r'[0-9a-f]{40}', session['commit'])
    assert not os.environ.get('GITHUB_SHA') or session['commit'] == os.environ['GITHUB_SHA']
    assert re.fullmatch(r'[A-Fa-f0-9]{64}', session['sha256'])
    assert int(session['pid']) > 0 and int(session['startTicks']) > 0
    assert load(folder, 'result.json') == {'feature': 'icon-hints', 'status': 'passed'}
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    assert not (folder / 'failure.txt').exists()
    for name, expected in LABELS.items():
        observation = load(folder, f'hover-{name}.json')
        assert observation['id'] == name and observation['expected'] == observation['actual'] == expected
        hover_session = load(folder, 'voice-no-chat.session.json') if name == 'attach-disabled' else session
        assert observation['pid'] == hover_session['pid'] and observation['popup'] > 0
        assert observation['owner'] > 0 and observation['owner_pid'] == hover_session['pid']
        left, top, right, bottom = observation['owner_rect']
        assert left <= observation['x'] < right and top <= observation['y'] < bottom
        left, top, right, bottom = observation['bounds']
        assert right > left and bottom > top
        assert (folder / f'hover-{name}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        if name == 'header-avatar':
            state = load(folder, 'hover-header-avatar.state.json')
            rect = state['header_avatar']
            x = observation['x'] - observation['owner_rect'][0]
            y = observation['y'] - observation['owner_rect'][1]
            assert state['selected'] is not None and rect[0] <= x < rect[2] and rect[1] <= y < rect[3]
        if name in ('react-selected', 'reply-selected', 'more-selected', 'react-unselected', 'reply-unselected', 'more-unselected'):
            messages = load(folder, f'hover-{name}.messages.json')['messages']
            index = {'react': 0, 'reply': 1, 'more': 2}[name.split('-')[0]]
            wanted_selected = name.endswith('-selected') and not name.endswith('-unselected')
            x = observation['x'] - observation['owner_rect'][0]
            y = observation['y'] - observation['owner_rect'][1]
            matching = [row for row in messages if row['selected'] == wanted_selected and
                        row['action_cells'][index][0] <= x < row['action_cells'][index][2] and
                        row['action_cells'][index][1] <= y < row['action_cells'][index][3] and
                        row['bubble'][2] > row['bubble'][0]]
            assert len(matching) == 1
    transitions = load(folder, 'icon-transitions.json')
    for name in ('leave', 'adjacent', 'resize', 'scroll', 'chat', 'reply-close', 'staged-compaction'):
        item = transitions[name]
        before, after = item['before'], item['after']
        assert before['visible'] and before['hwnd'] > 0 and before['text']
        assert not after['visible'] or after['text'] != before['text']
        assert (folder / item['screenshot']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert transitions['resize']['before_window'] != transitions['resize']['after_window']
    assert transitions['chat']['before_selected']['id'] != transitions['chat']['after_selected']['id']
    assert transitions['adjacent']['before']['text'] == 'React  Ctrl+R'
    assert transitions['adjacent']['after']['text'] == 'Reply  Ctrl+Shift+R'
    snapshots = {}
    for name in ('voice-before', 'voice-held', 'voice-cancelled', 'voice-unsupported-before', 'voice-unsupported', 'voice-no-chat', 'voice-bad-fixture', 'voice-invalid-fixture', 'voice-modifiers', 'voice-inactive'):
        item = load(folder, f'{name}.icon.json')
        case_session = load(folder, f'{name}.session.json') if name in ('voice-no-chat', 'voice-bad-fixture', 'voice-invalid-fixture') else session
        assert item['pid'] == case_session['pid'] and str(item['start_ticks']) == str(case_session['startTicks'])
        assert item['exe'] == case_session['exe'] == session['exe']
        assert item['sha256'] == case_session['sha256'] == session['sha256']
        assert item['commit'] == case_session['commit'] == session['commit']
        if case_session is not session:
            assert case_session['pid'] != session['pid']
            assert 'CLEANUP PASSED:' in (folder / f'{name}.cleanup.txt').read_text(encoding='utf-8-sig')
            prior = load(folder, f'{name}-before.icon.json')
            assert prior['pid'] == item['pid'] and prior['start_ticks'] == item['start_ticks']
            assert prior['exe'] == item['exe'] and prior['sha256'] == item['sha256']
            assert prior['state']['voice_recording']['fixture_entries'] == item['state']['voice_recording']['fixture_entries'] == 0
            assert prior['state']['voice_recording']['microphone_entries'] == item['state']['voice_recording']['microphone_entries'] == 0
            assert (folder / f'{name}-before.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
            case_actions = (folder / f'{name}.actions.log').read_text(encoding='utf-8-sig')
            assert 'icon-key: 17 up=False' in case_actions and 'icon-key: 16 up=False' in case_actions and 'icon-key: 77 up=False' in case_actions
        state = item['state']
        assert state['version'] == session['expected_version']
        assert state['voice_recording']['microphone_entries'] == 0
        assert state['dictation']['microphone_entries'] == state['dictation']['transcription_attempts'] == 0
        assert state['pending_sends'] == 0
        assert (folder / f'{name}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        snapshots[name] = item
    before, held, cancelled = (snapshots[name] for name in ('voice-before', 'voice-held', 'voice-cancelled'))
    assert before['state']['selected']['provider'] == held['state']['selected']['provider'] == 'whatsapp'
    assert held['state']['voice_recording']['active'] and not held['state']['voice_recording']['finishing']
    assert held['state']['voice_recording']['samples'] > 0 and held['state']['voice_recording']['fixture_entries'] == 1
    assert not cancelled['state']['voice_recording']['active']
    assert before['draft'] == held['draft'] == cancelled['draft']
    assert before['selection'] == held['selection'] == cancelled['selection']
    for name in ('voice-before', 'voice-held', 'voice-cancelled'):
        requests = load(folder, f'{name}.requests.json')
        assert not [row for row in requests if row.get('wire_path') == '/v1/wazig/send']
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    assert actions.count('icon-key: 77 up=False') >= 5
    assert 'icon-key: 18 up=False' in actions and 'icon-key: 27 up=False' in actions
    unsupported_before = snapshots['voice-unsupported-before']['state']
    unsupported = snapshots['voice-unsupported']['state']
    assert unsupported['selected']['provider'] == 'slack' and not unsupported['voice_recording']['active']
    assert unsupported['voice_recording']['fixture_entries'] == unsupported_before['voice_recording']['fixture_entries']
    for name in ('voice-modifiers', 'voice-inactive'):
        state = snapshots[name]['state']['voice_recording']
        assert not state['active'] and state['fixture_entries'] == cancelled['state']['voice_recording']['fixture_entries']
    assert snapshots['voice-no-chat']['state']['selected'] is None
    assert not snapshots['voice-no-chat']['state']['voice_recording']['active']
    assert not snapshots['voice-bad-fixture']['state']['voice_recording']['active']
    assert not snapshots['voice-bad-fixture']['state']['voice_recording']['fixture_loaded']
    assert not snapshots['voice-invalid-fixture']['state']['voice_recording']['active']
    assert snapshots['voice-invalid-fixture']['state']['voice_recording']['fixture_loaded']
    dictation = load(folder, 'dictation-ctrl-d.json')
    assert dictation['before']['dictation']['phase'] == 'idle'
    assert dictation['recording']['dictation']['phase'] == 'recording'
    assert dictation['cancelled']['dictation']['phase'] == 'idle'
    assert all(dictation[phase]['dictation']['microphone_entries'] == dictation[phase]['dictation']['transcription_attempts'] == 0 for phase in ('before', 'recording', 'cancelled'))
    final = load(folder, 'side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert all(final[key] for key in ('production_preferences_absent', 'whatsapp_store_absent', 'telegram_store_absent'))

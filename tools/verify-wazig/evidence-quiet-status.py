from pathlib import Path
import json
import re
import sys


def check_quiet_status(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'quiet-status' and session['sha256'] and session['commit']
    assert not (folder / 'failure.txt').exists()
    quiet = read('quiet-status.json')
    assert quiet['list_rows'] == 2
    assert quiet['uia_controls'] == quiet['native_control'] == 0
    assert quiet['forbidden_labels'] == []
    assert not any(re.search(r'You are on v|newest version|[Ss]yncing', label) for label in quiet['labels'] + quiet['tooltip_labels'])
    assert abs(quiet['list_bottom'] - quiet['client_bottom']) <= 1
    assert len(quiet['point']) == 2
    for key in ('selected', 'view', 'include_archived', 'show_archived', 'chat_count', 'pending_sends', 'pending_archives'):
        assert quiet['before'][key] == quiet['after'][key], key
    version = read('version.json')
    expected = f"You are on v{quiet['after']['version']} - this is the newest version"
    assert version['query'] == 'version' and version['positive'] == ['Keyboard shortcuts']
    assert version['expected'] == expected and version['rows'] == [expected]
    problem = read('sync-problem.json')
    assert problem['surface'] == 'update_card' and problem['pid'] == session['pid']
    assert problem['dialog'] == 0
    assert problem['expected'] == 'Unable to read chats from wacli'
    for card in (problem['card'], problem['retained']):
        assert card['visible'] and card['span'] > 0
        assert card['error'] == problem['expected']
        left, top, right, bottom = card['rect']
        assert 0 <= left < right and 0 <= top < bottom
    assert problem['card'] == problem['retained']
    assert abs(problem['list_bottom'] - (problem['card_top'] - problem['gap'])) <= 1
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    recovery = read('message-read-recovery.json')
    reads = [row for row in requests if row.get('wire_path', '').startswith('/v1/wazig/messages') and re.search(r'limit=80(?:&|$)', row['wire_path'])]
    reads = reads[:len(recovery['requests'])]
    assert recovery['requests'] == reads
    begin, persistent, retried = (recovery[key] for key in ('transient_start', 'persistent_start', 'persistent_end'))
    assert 0 <= begin < persistent < retried < len(reads)
    transient = reads[begin:persistent]
    assert sum(row['status'] == 503 for row in transient) == 1 and transient[-1]['status'] == 200
    assert sum(row['status'] == 503 for row in reads[persistent:retried]) >= 3
    recovery_start = recovery['recovery_start']
    assert retried <= recovery_start < len(reads)
    assert any(row['status'] == 200 for row in reads[recovery_start:])
    for key in ('transient', 'recovered'):
        assert not recovery[key]['visible'] and recovery[key]['error'] == ''
    assert recovery['problem']['visible'] and recovery['problem']['error'] == 'Check your connection, then Retry.'
    assert len(recovery['retry']) == 2
    for stage in ('message-read-problem', 'message-read-recovered'):
        assert (folder / (stage + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    failures = [row for row in requests if row.get('wire_path', '').startswith('/v1/wazig/chats') and row['status'] == 503]
    assert failures and all(row in failures for row in problem['failures']) and problem['failures']
    chat_recovery = read('chat-read-recovery.json')
    chat_reads = [row for row in requests if row.get('wire_path', '').startswith('/v1/wazig/chats')]
    chat_reads = chat_reads[:len(chat_recovery['requests'])]
    assert chat_reads == chat_recovery['requests']
    manual, automatic = chat_recovery['manual_start'], chat_recovery['auto_start']
    assert chat_recovery['pid'] == session['pid'] and 0 < manual < automatic < len(chat_reads)
    assert any(row['status'] == 503 for row in chat_reads[:manual])
    assert any(row['status'] == 200 for row in chat_reads[manual:automatic])
    assert any(row['status'] == 503 for row in chat_reads[manual:automatic])
    assert any(row['status'] == 200 for row in chat_reads[automatic:])
    assert chat_recovery['automatic_problem']['error'] == problem['expected']
    for key in ('manual', 'automatic'):
        state = chat_recovery[key]
        assert not state['update_card']['visible'] and state['update_card']['error'] == ''
        assert state['chat_count'] == 2 and state['selected']['id'] == chat_recovery['initial']['selected']['id']
        assert [(row['id'], row['text']) for row in chat_recovery[key + '_messages']['messages']] == [(row['id'], row['text']) for row in chat_recovery['original_messages']['messages']]
    assert chat_recovery['draft'] == 'Recovery draft'
    assert 'Recovery draft' in (folder / 'chat-read-draft.json').read_text(encoding='utf-8-sig')
    assert len(chat_recovery['retry']) == 2
    for stage in ('chat-read-recovered', 'chat-read-auto-recovered'):
        assert (folder / (stage + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    ordering = read('event-order.json')
    assert ordering['pid'] == session['pid'] and ordering['draft'] == 'Recovery draft'
    assert ordering['selected'] == chat_recovery['initial']['selected']['id']
    assert ordering['visible_ids'] == ordering['before_ids'] + ['LIVE']
    phases = [row for row in requests if row.get('phase') in ('order-armed', 'order-history-response', 'order-chat-held', 'order-visible', 'order-chat-released')]
    assert ordering['trace'] == phases[:len(ordering['trace'])]
    names = [row['phase'] for row in ordering['trace']]
    history, held, visible, released = (names.index(name) for name in ('order-history-response', 'order-chat-held', 'order-visible', 'order-chat-released'))
    assert names.index('order-armed') < history < held < visible < released
    assert ordering['trace'][history]['chat'] == ordering['selected']
    assert ordering['trace'][visible]['held'] and ordering['trace'][released]['manual']
    shown = read('order-visible.messages.json')
    assert [row['id'] for row in shown['messages']] == ordering['visible_ids']
    assert (folder / 'message-before-chat-release.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert (folder / 'event-order-after.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    for stage in ('before', 'quiet-status', 'version', 'sync-problem', 'after'):
        image = (folder / f'{stage}.png').read_bytes()
        assert image.startswith(b'\x89PNG\r\n\x1a\n') and len(image) > 10000
        tree = (folder / f'{stage}.uia.txt').read_text(encoding='utf-8-sig')
        assert tree.splitlines()[0].startswith('MessagesZig | ')
        assert not re.search(r'^1048 \|', tree, re.M)
        state = read(f'{stage}.state.json')
        assert state['version'] == '0.0.526' and state['chat_count'] == 2
        assert state['pending_sends'] == state['pending_archives'] == 0
        if stage in ('sync-problem', 'after'):
            assert state['update_card'] == problem['card']
    actions = (folder / 'actions.log').read_text(encoding='utf-8-sig')
    for keys in ('^k', 'Keyboard shortcuts', 'version', 'Refresh', '{ENTER}', '{ESC}'):
        assert f'keys: {keys}' in actions
    final = read('side-effects.json')
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert 'JOURNEY PASSED: quiet-status' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: quiet sidebar, exact version and visible sync failure')


if __name__ == '__main__':
    check_quiet_status(Path(sys.argv[1]))

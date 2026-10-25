from pathlib import Path
import json
import sys


def check_alignment(checks):
    assert [row['stage'] for row in checks] == ['baseline', 'larger']
    assert checks[1]['font_height'] < checks[0]['font_height'] < 0
    for row in checks:
        assert row['body_weight'] == 400
        items = row['items']
        assert len(items) == 8
        assert items[6]['text_x'] > items[5]['text_x']
        assert items[7]['text_x'] > items[6]['text_x']
        for item in items:
            assert item['text_x'] > item['marker_x']
            assert item['continuations']
            for wrapped in item['continuations']:
                assert wrapped['x'] == item['text_x'] > item['marker_x']
                assert abs(wrapped['ink_x'] - item['ink_x']) <= 1


def check_evidence(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'chat-lists' and session['sha256'] and session['commit']
    assert not (folder / 'failure.txt').exists()
    checks = read('list-alignment.json')
    check_alignment(checks)
    for row in checks:
        stage = row['stage']
        message = read(f'{stage}.messages.json')
        assert message['id'] == 'LISTS' and message['body_weight'] == row['body_weight']
        assert message['font_height'] == row['font_height']
        assert len(message['text'].splitlines()) == 8 and len(message['words']) == 168
        assert (folder / f'{stage}.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        assert read(f'{stage}.state.json')['selected']['id'] == 'slack:fixture-lists:channel'
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert not any(row['method'] != 'GET' and row['wire_path'] in
                   ('/v1/wazig/send', '/v1/wazig/archive', '/v1/wazig/react') for row in requests)
    final = read('side-effects.json')
    assert final['pending_sends'] == final['pending_archives'] == 0 and final['sync'] == 'stopped'
    assert final['production_preferences_absent'] and final['whatsapp_store_absent'] and final['telegram_store_absent']
    assert 'JOURNEY PASSED: chat-lists' in (folder / 'result.txt').read_text(encoding='utf-8-sig')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: Regular body and six hanging bullets plus two nested levels, wrapped foreground edges within one pixel at both font sizes')


if __name__ == '<run_path>' or __name__ == '__main__':
    check_evidence(Path(sys.argv[1]))

import json


def check_inline_links(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    targets = read('inline-targets.json')
    assert session['feature'] == 'inline-links' and session['sha256'] and session['commit']
    assert targets['session'] == session['id'] and targets['app_pid'] == session['pid']
    assert targets['bridge'] == session['bridge_url'] and targets['bridge'].startswith('http://127.0.0.1:')
    assert targets['body'] == targets['bridge'] + '/inline-links/body-' + 'abcdefghij' * 18
    assert targets['quote'] == targets['bridge'] + '/inline-links/quote-' + 'klmnopqrst' * 18
    names = ['inline-before', 'inline-body-first', 'inline-body-last', 'inline-plain', 'inline-ctrl-o', 'inline-quote']
    stages = [read(name + '.json') for name in names]
    assert [stage['name'] for stage in stages] == names
    for name, stage in zip(names, stages):
        assert (folder / (name + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        assert stage['status']['pending_sends'] == 0
        assert stage['messages']['chat']['id'] == 'fixture-alpha'
    rows = {row['id']: row for row in stages[0]['messages']['messages']}
    body, plain, reply = (rows[key] for key in ['INLINE-BODY', 'INLINE-PLAIN', 'INLINE-REPLY'])
    assert body['links'] == [targets['body']] and reply['quote'] == targets['quote']
    assert reply['quoted_msg_id'] == 'INLINE-BODY'
    rects = [rect for rect in body['link_rects'][0] if rect[2] > rect[0] and rect[3] > rect[1]]
    assert len(rects) >= 2
    for stage, rect in [(stages[1], rects[0]), (stages[2], rects[-1]), (stages[3], plain['bubble']), (stages[5], reply['quote_line'])]:
        x, y = stage['point']['client']
        assert rect[0] <= x < rect[2] and rect[1] <= y < rect[3]
    assert [len(stage['receipts']) for stage in stages] == [0, 1, 2, 2, 3, 4]
    receipts = stages[-1]['receipts']
    assert [item['url'] for item in receipts] == [targets['body']] * 3 + [targets['quote']]
    for item in receipts:
        assert item['pid'] == session['pid'] and item['session'] == session['id'] and item['result'] > 32
    retained = [json.loads(line) for line in (folder / 'final-data' / 'verification-url-launches.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert retained == receipts
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert not any(row.get('wire_path', '').startswith(('/v1/wazig/send', '/v1/wazig/react', '/v1/wazig/archive')) for row in requests)
    assert read('result.json') == {'feature': 'inline-links', 'status': 'passed'}
    assert not (folder / 'failure.txt').exists()
    assert (folder / 'inline-palette.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert 'CLEANUP PASSED:' in (folder / 'cleanup.txt').read_text(encoding='utf-8-sig')
    print('EVIDENCE VERIFIED: body fragments, plain text, Ctrl+O and quoted URL dispatch')

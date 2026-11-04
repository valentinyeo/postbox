import json


def check_media_speed(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding='utf-8-sig'))

    session = read('session.json')
    assert session['feature'] == 'media-speed' and session['sha256'] and session['commit']
    assert read('result.json') == dict(feature='media-speed', status='passed')
    assert not (folder / 'failure.txt').exists()
    ids = [f'SPEED-IMG-{n}' for n in range(1, 7)] + [f'SPEED-VOICE-{n}' for n in range(1, 5)]
    proof = read('media-speed.json')
    assert proof['ids'] == ids
    assert sorted(proof['seen']) == sorted(ids), 'every image and voice note must show'
    assert proof['total_seconds'] < 15, proof['total_seconds']
    rows = [json.loads(line) for line in (folder / 'media-speed-server.jsonl').read_text(encoding='utf-8').splitlines() if line.strip()]
    first = min(row['at'] for row in rows)
    done = {}
    for row in rows:
        if row['status'] == 200:
            done.setdefault(row['id'], row['at'] - first)
    assert sorted(done) == sorted(ids), 'the server must have served every file'
    assert max(done.values()) < 15, max(done.values())
    flaky = [row['status'] for row in rows if row['id'] == 'SPEED-IMG-3']
    assert flaky[:2] == [502, 200] or flaky[:3] == [502, 202, 200], flaky
    gone = [row for row in rows if row['id'] == 'SPEED-GONE-1']
    assert len(gone) == 1 and gone[0]['status'] == 410, 'a gone file must be asked for once only'
    messages = read('media-speed.messages.json')['messages']
    gone_row = [row for row in messages if row['id'] == 'SPEED-GONE-1']
    assert len(gone_row) == 1 and not gone_row[0]['local']
    assert len([row for row in messages if row['id'] in ids and row['local']]) == len(ids)
    assert (folder / 'media-speed-done.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')

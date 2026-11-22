from pathlib import Path
import json
import sys


def check_hub_wake_refresh(folder):
    folder = Path(folder)
    session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
    assert session['sha256'] and session['commit']
    assert not (folder / 'failure.txt').exists()
    proof = (folder / 'hub-proof.log').read_text(encoding='utf-8-sig')
    assert 'hub-wake-refresh wake-resume PASS' in proof
    assert 'hub-wake-refresh safety-poll PASS' in proof
    resume = json.loads((folder / 'wake-resume.json').read_text(encoding='utf-8-sig'))
    poll = json.loads((folder / 'safety-poll.json').read_text(encoding='utf-8-sig'))
    messages = json.loads((folder / 'poll.messages.json').read_text(encoding='utf-8-sig'))['messages']
    assert resume['resume_ms'] < 15_000
    assert poll['poll_ms'] <= 75_000
    assert poll['chat_pulls'] >= 1
    assert any(row['id'] == 'POLL-ROW' for row in messages)
    requests = [json.loads(line) for line in (folder / 'bridge-requests.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    assert any(row['path'] == '/fixture/mute-sse' and row['status'] == 200 for row in requests)
    assert any(row['path'] == '/fixture/stale-row' and row['status'] == 200 for row in requests)
    live_events = [row for row in requests if row.get('path') == '/v1/events' and row.get('id') == '2']
    assert not live_events
    print('HUB_WAKE_REFRESH_VERIFIED: safety poll and resume refresh without SSE live events')


if __name__ == '__main__':
    check_hub_wake_refresh(sys.argv[1])
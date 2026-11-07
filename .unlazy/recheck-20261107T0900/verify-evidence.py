import json
from pathlib import Path
from datetime import datetime, timezone, timedelta

root = Path(__file__).parent

def load(name):
    return json.loads((root / name).read_text())

def timestamp(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00'))

pr = load('pr449.json')
run = load('run42315226773.json')
assert pr['merged'] and pr['base']['ref'] == 'main'
assert run['head_sha'] == pr['merge_commit_sha']
assert run['head_branch'] == 'main' and run['conclusion'] == 'success'
durations = []
for name in ('run42257181979-jobs.json', 'run42315226773-jobs.json'):
    jobs = [job for job in load(name)['jobs'] if job['name'] == 'ci']
    assert len(jobs) == 1 and jobs[0]['conclusion'] == 'success'
    job = jobs[0]
    durations.append(int((timestamp(job['completed_at']) - timestamp(job['started_at'])).total_seconds()))
assert 0 < durations[1] < durations[0]
print(f'SHIPMENT VERIFIED: Postbox ci execution {durations[0]}s -> {durations[1]}s; n=1 each, queue excluded')
print(f'Merge: {pr["merge_commit_sha"]}, {pr["merged_at"]}')
android = load('android-pr294.json')
print(f'Android PR294 state={android["state"]}, merged={android["merged"]}; no shipment claim')
floor = timestamp(pr['merged_at']) + timedelta(days=1)
print(f'Earliest Postbox full-day floor: {floor.isoformat()}; now: {datetime.now(timezone.utc).isoformat()}')
print('Full-day recovery remains unproved; Android observation must follow its own shipment.')

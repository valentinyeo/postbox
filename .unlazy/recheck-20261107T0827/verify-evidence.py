import json
from pathlib import Path
from datetime import datetime, timezone

root = Path(__file__).parent

def load(name):
    return json.loads((root / name).read_text())

def timestamp(text):
    return datetime.fromisoformat(text.replace('Z', '+00:00'))

pr = load('pr449.json')
run = load('run42315226773.json')
assert pr['merged'] and pr['merged_at']
assert run['head_sha'] == pr['merge_commit_sha']
assert run['head_branch'] == 'main' and run['conclusion'] == 'success'
durations = []
for name in ('run42257181979-jobs.json', 'run42315226773-jobs.json'):
    jobs = [job for job in load(name)['jobs'] if job['name'] == 'ci']
    assert len(jobs) == 1 and jobs[0]['conclusion'] == 'success'
    job = jobs[0]
    durations.append(int((timestamp(job['completed_at']) - timestamp(job['started_at'])).total_seconds()))
assert 0 < durations[1] < durations[0]
print(f'SHIPMENT VERIFIED; ci execution seconds {durations[0]} -> {durations[1]}; n=1 each, queue excluded')
print(f'Merge {pr["merge_commit_sha"]} at {pr["merged_at"]}')
print(f'Hours since merge: {(datetime.now(timezone.utc) - timestamp(pr["merged_at"])).total_seconds() / 3600:.2f}')
print(f'Android linked ticket: {load("hyci-169.json")["tasks"][0]["section"]}')

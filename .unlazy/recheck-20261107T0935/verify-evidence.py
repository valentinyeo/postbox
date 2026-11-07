import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

root = Path(__file__).parent

def load(name):
    return json.loads((root / name).read_text())

def timestamp(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00'))

pr = load('postbox-pr.json')
run = load('postbox-main.json')
assert pr['merged'] is True
assert run['head_sha'] == pr['merge_commit_sha']
assert run['head_branch'] == 'main' and run['conclusion'] == 'success'
measurements = []
for filename in ('postbox-before-jobs.json', 'postbox-main-jobs.json'):
    jobs = [job for job in load(filename)['jobs'] if job['name'] == 'ci']
    assert len(jobs) == 1 and jobs[0]['conclusion'] == 'success'
    job = jobs[0]
    seconds = (timestamp(job['completed_at']) - timestamp(job['started_at'])).total_seconds()
    assert seconds > 0
    measurements.append(seconds)
print(f'Postbox ci execution: {measurements[0]:.0f}s -> {measurements[1]:.0f}s; n=1 each; queue excluded')
floor = timestamp(pr['merged_at']) + timedelta(days=1)
print(f'Observation floor: {floor.isoformat()}; now: {datetime.now(timezone.utc).isoformat()}')
android = load('android-pr.json')
print(f'Android PR294 state={android["state"]}, merged={android["merged"]}, head={android["head"]["sha"]}')
print('SHIPMENT_VERIFIED')

import json
from datetime import datetime, timedelta
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
    seconds = (timestamp(jobs[0]['completed_at']) - timestamp(jobs[0]['started_at'])).total_seconds()
    assert seconds > 0
    measurements.append(seconds)
print(f'Postbox ci execution: {measurements[0]:.0f}s -> {measurements[1]:.0f}s; n=1 each; queue excluded')
print(f'Observation floor: {timestamp(pr["merged_at"]) + timedelta(days=1)}')
print('SHIPMENT_VERIFIED')

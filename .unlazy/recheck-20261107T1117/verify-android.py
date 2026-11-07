import json
from pathlib import Path

root = Path(__file__).parent
pr = json.loads((root / 'android-pr.json').read_text())
runs = json.loads((root / 'android-main-runs.json').read_text())['workflow_runs']
assert pr['merged'] is True
matching = [run for run in runs if run['head_sha'] == pr['merge_commit_sha']]
for name in ('Android release', 'Gitleaks'):
    checks = [run for run in matching if run['name'] == name]
    assert checks and checks[0]['status'] == 'completed' and checks[0]['conclusion'] == 'success'
    print(checks[0]['html_url'])
print('ANDROID_SHIPMENT_VERIFIED')

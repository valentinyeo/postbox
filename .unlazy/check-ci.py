import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
ci_id = '40227270044'
verify_id = '40227269901'
ci = json.loads(gh('run', 'view', ci_id, '--json', 'headSha,status,conclusion,jobs'))
assert ci['headSha'] == head and ci['status'] == 'completed' and ci['conclusion'] == 'success', ci
job, = [job for job in ci['jobs'] if job['name'] == 'ci']
steps = {step['name']: step for step in job['steps']}
assert steps['Preflight']['conclusion'] == 'success'
assert steps['IGSH-833 bulk incoming regression on original main']['conclusion'] == 'success'
log = gh('api', '--allow-escape-sequences', f"repos/valentinyeo/wazig/actions/jobs/{job['databaseId']}/logs")
Path('.unlazy/ci-proof.log').write_text(log)
assert 'IGSH-833 original main fails bulk incoming regression' in log
assert re.search(r'test\.IGSH-833 bulk plain group direct and Slack return on incoming while kept stays archived.*failed', log)
if sys.argv[1] == 'regression':
    print('BULK REGRESSION RED BEFORE GREEN AFTER')
else:
    verify = json.loads(gh('run', 'view', verify_id, '--json', 'headSha,status,conclusion'))
    assert verify['headSha'] == head and verify['status'] == 'completed' and verify['conclusion'] == 'success', verify
    checks = json.loads(gh('pr', 'checks', '387', '--json', 'name,state'))
    for check in checks:
        if check['name'] == 'code-review' or check == {'name': 'notify-release', 'state': 'SKIPPING'}:
            continue
        assert check['state'] == 'SUCCESS', check
    light = Path('.unlazy/light-proof.json')
    proof = json.loads(light.read_text())
    assert proof['head'] == head
    output = Path('.preflight-final.log').read_bytes()
    assert hashlib.sha256(output).hexdigest() == proof['sha256']
    assert b'preflight-light: all checks passed' in output
    for feature in ('archive-inbox', 'hub-archive', 'slack-archive'):
        folder = Path('.unlazy/evidence') / verify_id / feature
        session = json.loads((folder / 'session.json').read_text(encoding='utf-8-sig'))
        revision = session['commit']
        if revision != head:
            commit = json.loads(gh('api', f'repos/valentinyeo/wazig/commits/{revision}'))
            assert head in [parent['sha'] for parent in commit['parents']], revision
        subprocess.run(['python3', 'tools/verify-wazig/check-evidence.py', str(folder)], check=True)
    print('LIGHT CI AND ARCHIVE JOURNEYS VERIFIED')

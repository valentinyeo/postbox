import json
import subprocess

pr = json.loads(subprocess.check_output(['gh', 'pr', 'view', '387', '--json', 'state,title,baseRefName,headRefName,headRefOid,mergedAt,labels']))
subprocess.run(['git', 'diff', '--exit-code'], check=True)
subprocess.run(['git', 'diff', '--cached', '--exit-code'], check=True)
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
remote = subprocess.check_output(['git', 'ls-remote', 'origin', 'refs/heads/ceo/IGSH-833'], text=True).split()[0]
assert pr['state'] == 'OPEN' and pr['mergedAt'] is None
assert pr['title'] == 'IGSH-833 plain archived chat returns on new message'
assert pr['baseRefName'] == 'main' and pr['headRefName'] == 'ceo/IGSH-833'
assert pr['headRefOid'] == head == remote
assert 'hold' in [label['name'] for label in pr['labels']]
message = subprocess.check_output(['git', 'log', '-1', '--format=%B'], text=True).strip().splitlines()
assert message[-2:] == ['Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>', 'Claude-Session: https://claude.ai/code/session_01BKi1MirWEHDvZC88iSkHvJ']
print('PR OPEN AND UNMERGED')

import json
import os
import re
import subprocess
import sys
from pathlib import Path

FIX_TITLE = re.compile(r'^(?:[A-Z]+-\d+:?\s+)?fix(?=\b|\()', re.I)
LINE = re.compile(r'^[ \t]*Revert:[ \t]*([^\r\n]*?)[ \t]*\r?$', re.I | re.M)
REVERT_PR = re.compile(r'#(\d+)')
REASON = re.compile(r'none,\s*[^\s,][^,]*', re.I)


def check(title, body, lookup):
    if not FIX_TITLE.match(title.strip()):
        return None
    lines = LINE.findall(body)
    if len(lines) != 1:
        return 'revert-first: add exactly one Revert: line'
    value = lines[0]
    if REASON.fullmatch(value):
        return None
    match = REVERT_PR.fullmatch(value)
    if not match:
        return 'revert-first: write Revert: #<number of the merged revert PR>, or Revert: none, <reason>'
    pr = lookup(match.group(1))
    if not pr or not pr.get('merged') or not pr.get('title', '').lower().startswith('revert'):
        return f'revert-first: #{match.group(1)} is not a merged PR whose title starts with Revert'
    return None


def github_lookup(number):
    repo = os.environ['GITHUB_REPOSITORY']
    result = subprocess.run(['gh', 'api', f'repos/{repo}/pulls/{number}', '--jq', '{merged: .merged, title: .title}'],
                            capture_output=True, text=True)
    return json.loads(result.stdout) if result.returncode == 0 else None


if __name__ == '__main__':
    problem = check(sys.argv[1], Path(sys.argv[2]).read_text(), github_lookup)
    if problem:
        raise SystemExit(problem)

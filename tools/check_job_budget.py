import json
import re
import sys
from pathlib import Path

BUDGET = 19
PR_TRIGGER = re.compile(r'^(?:  pull_request:[ \t]*\n(?!    paths)|on:.*\bpull_request\b(?!_))', re.M)
JOB_ID = re.compile(r'^  ([A-Za-z0-9_-]+):\s*$')
OFF_PR = re.compile(r"github\.event_name == '(?:schedule|workflow_dispatch)'")


def jobs(text):
    found = {}
    current = None
    inside = False
    for line in text.splitlines():
        if line.startswith('jobs:'):
            inside = True
            continue
        if inside and line and not line.startswith(' '):
            inside = False
        match = JOB_ID.match(line) if inside else None
        if match:
            current = match.group(1)
            found[current] = []
        elif current:
            found[current].append(line)
    return {name: '\n'.join(lines) for name, lines in found.items()}


def count_pr_jobs(root):
    root = Path(root)
    journeys = root / 'tools/verify-wazig/pr-journeys.json'
    matrix_width = len(json.loads(journeys.read_text())['default']) if journeys.exists() else 1
    total = 0
    detail = {}
    for path in sorted((root / '.github/workflows').glob('*.yml')):
        text = path.read_text()
        if not PR_TRIGGER.search(text):
            continue
        for name, body in jobs(text).items():
            condition = next((line for line in body.splitlines() if line.strip().startswith('if:')), '')
            if OFF_PR.search(condition) and 'pull_request' not in condition:
                continue
            width = matrix_width if 'fromJSON(needs.plan.outputs.matrix)' in body else 1
            detail[f'{path.name}:{name}'] = width
            total += width
    return total, detail


if __name__ == '__main__':
    total, detail = count_pr_jobs(sys.argv[1] if len(sys.argv) > 1 else '.')
    if total > BUDGET:
        print(f'{total} jobs start on a typical PR, budget is {BUDGET}.')
        for key, width in detail.items():
            print(f'  {key} x{width}')
        print('Merge small checks into one job or move heavy runs to the nightly.')
        raise SystemExit(1)
    print(f'{total} jobs on a typical PR, budget {BUDGET}.')

#!/usr/bin/env bash
set -euo pipefail
cd "${1:-$(git rev-parse --show-toplevel)}"
python3 - <<'PY'
import json
import re
import sys
from pathlib import Path

rows = json.loads(Path('tools/verify-wazig/feature-map.json').read_text())['features']
journeys = {x['name'] for x in json.loads(Path('tools/verify-wazig/journeys.json').read_text())['journeys']}
source = Path('src/main.zig').read_text().split('fn buildPaletteItems(', 1)[1].split('\nfn ', 1)[0]
commands = set(re.findall(r'\b(?:command|reaction)_[a-z0-9_]+', source))
ids = set()
errors = []
for row in rows:
    feature = row['feature']
    if feature in ids or not re.fullmatch(r'[a-z][a-z0-9_-]*', feature):
        errors.append(f'give {feature} a unique valid feature id')
    ids.add(feature)
    if not row.get('source') or row['status'] not in ('GAP', 'covered'):
        errors.append(f'add a source and valid status for {feature}')
    if row['status'] == 'GAP':
        if row['proof'] != 'GAP' or not row.get('why', '').strip():
            errors.append(f'use GAP and explain the missing proof for {feature}')
    elif row['proof'] not in journeys:
        errors.append(f'add a valid journey id for {feature}: {row["proof"]}')
for command in sorted(commands - {r['feature'] for r in rows if r.get('source') == 'buildPaletteItems:' + r['feature']}):
    errors.append(f'add a row to tools/verify-wazig/feature-map.json for {command}')
limit = int(Path('tools/verify-wazig/feature-map-limits.txt').read_text().strip())
gaps = sum(row['status'] == 'GAP' for row in rows)
if limit < 0 or gaps > limit:
    errors.append(f'remove gaps or add proofs: {gaps} gaps exceeds limit {limit}')
elif gaps < limit:
    print(f'lower tools/verify-wazig/feature-map-limits.txt to {gaps}')
proven = {row['proof'] for row in rows if row['status'] == 'covered'}
listed = {}
for line in Path('tools/verify-wazig/unproven-journeys.txt').read_text().splitlines():
    if not line.strip() or line.lstrip().startswith('#'):
        continue
    parts = line.split(None, 1)
    name = parts[0]
    reason = parts[1].strip() if len(parts) > 1 else ''
    if name in listed:
        errors.append(f'list {name} once in tools/verify-wazig/unproven-journeys.txt')
    if not reason:
        errors.append(f'give a reason for {name} in tools/verify-wazig/unproven-journeys.txt')
    if name not in journeys:
        errors.append(f'drop {name} from tools/verify-wazig/unproven-journeys.txt; no journey has that name')
    listed[name] = reason
for journey in sorted(journeys - proven - set(listed)):
    errors.append(f'add a feature row to tools/verify-wazig/feature-map.json whose proof is {journey}, or list it with a reason in tools/verify-wazig/unproven-journeys.txt')
for journey in sorted(set(listed) & proven):
    print(f'remove {journey} from tools/verify-wazig/unproven-journeys.txt; a feature row proves it now')
print(f'check-feature-map: {len(rows)} features, {gaps} gaps (limit {limit}), {len(journeys) - len(proven & journeys)} journeys without a feature row')

if errors:
    sys.exit('\n'.join(errors))
PY

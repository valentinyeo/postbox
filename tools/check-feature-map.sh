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
print(f'check-feature-map: {len(rows)} features, {gaps} gaps (limit {limit})')
if errors:
    sys.exit('\n'.join(errors))
PY

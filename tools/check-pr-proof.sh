#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
python3 - "$root/tools/verify-wazig/feature-map.json" "$1" <<'PY'
import json
import re
import sys
from pathlib import Path

features = {r['feature'] for r in json.loads(Path(sys.argv[1]).read_text())['features']}
body = Path(sys.argv[2]).read_text()
for line in body.splitlines():
    match = re.match(r'^\s*Proof:\s*(.*?)\s*$', line, re.I)
    if not match:
        continue
    value = match.group(1)
    if re.search(r'\bno user-visible change\b', value, re.I):
        sys.exit(0)
    if any(token in features for token in re.findall(r'[a-z][a-z0-9_-]*', value)):
        sys.exit(0)
sys.exit('pr-proof: add a Proof: line naming a feature id from tools/verify-wazig/feature-map.json or no user-visible change')
PY

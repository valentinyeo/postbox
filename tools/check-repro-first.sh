#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
python3 - "$root/tools/verify-wazig/journeys.json" "$1" "$2" "$3" <<'PY'
import json
import re
import sys
from pathlib import Path

journeys = {row['name'] for row in json.loads(Path(sys.argv[1]).read_text())['journeys']}
title = sys.argv[2].strip()
if not re.match(r'^(?:[A-Z]+-\d+:?\s+)?fix(?=\b|\()', title, re.I):
    sys.exit(0)
body = Path(sys.argv[3]).read_text()
lines = re.findall(r'^[ \t]*Repro:[ \t]*([^\r\n]*?)[ \t]*\r?$', body, re.I | re.M)
if len(lines) != 1:
    sys.exit('repro-first: add exactly one Repro: line')
value = lines[0]
if value in journeys:
    print(value)
    sys.exit(0)
if re.fullmatch(r'none,\s*[^\s,][^,]*', value, re.I):
    paths = Path(sys.argv[4]).read_text().splitlines()
    if paths and not any(p.startswith(('src/', 'tools/verify-wazig/')) for p in paths):
        print('none')
        sys.exit(0)
sys.exit(f'repro-first: unknown or invalid journey {value!r}. Valid journeys: {", ".join(sorted(journeys))}. Use Repro: none, <reason> only for changes outside src and tools/verify-wazig')
PY

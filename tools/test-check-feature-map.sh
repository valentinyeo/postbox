#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/tools/verify-wazig" "$temp/src"
cp "$repo/tools/verify-wazig/"{feature-map.json,feature-map-limits.txt,journeys.json,unproven-journeys.txt} "$temp/tools/verify-wazig/"
cp "$repo/src/main.zig" "$temp/src/"
check="$repo/tools/check-feature-map.sh"
bash "$check" "$temp"
python3 - "$temp" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]) / 'src/main.zig'
s = p.read_text().replace('fn buildPaletteItems(a: *App) void {', 'fn buildPaletteItems(a: *App) void {\n    appendPalette(a, "New", "", command_new_test);', 1)
p.write_text(s)
PY
if bash "$check" "$temp" >"$temp/out" 2>&1; then exit 1; fi
grep -Fq 'add a row to tools/verify-wazig/feature-map.json for command_new_test' "$temp/out"
cp "$repo/src/main.zig" "$temp/src/"
python3 - "$temp" <<'PY'
import json,sys
from pathlib import Path
p = Path(sys.argv[1]) / 'tools/verify-wazig/feature-map.json'
d = json.loads(p.read_text())
d['features'][0].update(proof='missing-journey', status='covered')
p.write_text(json.dumps(d))
PY
if bash "$check" "$temp" >"$temp/out" 2>&1; then exit 1; fi
grep -Fq 'add a valid journey id' "$temp/out"
cp "$repo/tools/verify-wazig/feature-map.json" "$temp/tools/verify-wazig/"
printf '0\n' > "$temp/tools/verify-wazig/feature-map-limits.txt"
if bash "$check" "$temp" >"$temp/out" 2>&1; then exit 1; fi
grep -Fq 'gaps exceeds limit' "$temp/out"
cp "$repo/tools/verify-wazig/feature-map-limits.txt" "$temp/tools/verify-wazig/"
python3 - "$temp" <<'PY'
import json,sys
from pathlib import Path
p = Path(sys.argv[1]) / 'tools/verify-wazig/journeys.json'
d = json.loads(p.read_text())
d['journeys'].append({'name': 'new-journey'})
p.write_text(json.dumps(d))
PY
if bash "$check" "$temp" >"$temp/out" 2>&1; then exit 1; fi
grep -Fq 'add a feature row to tools/verify-wazig/feature-map.json whose proof is new-journey, or list it with a reason in tools/verify-wazig/unproven-journeys.txt' "$temp/out"
printf 'new-journey nothing to prove yet\n' >> "$temp/tools/verify-wazig/unproven-journeys.txt"
bash "$check" "$temp"
printf 'new-journey\n' >> "$temp/tools/verify-wazig/unproven-journeys.txt"
if bash "$check" "$temp" >"$temp/out" 2>&1; then exit 1; fi
grep -Fq 'list new-journey once' "$temp/out"
python3 - "$temp" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]) / 'tools/verify-wazig/unproven-journeys.txt'
lines = p.read_text().splitlines()[:-2] + ['new-journey']
p.write_text('\n'.join(lines) + '\n')
PY
if bash "$check" "$temp" >"$temp/out" 2>&1; then exit 1; fi
grep -Fq 'give a reason for new-journey' "$temp/out"
printf 'ghost-journey no such journey\n' >> "$temp/tools/verify-wazig/unproven-journeys.txt"
if bash "$check" "$temp" >"$temp/out" 2>&1; then exit 1; fi
grep -Fq 'drop ghost-journey from tools/verify-wazig/unproven-journeys.txt; no journey has that name' "$temp/out"
cp "$repo/tools/verify-wazig/journeys.json" "$temp/tools/verify-wazig/"
cp "$repo/tools/verify-wazig/unproven-journeys.txt" "$temp/tools/verify-wazig/"
printf 'window stale entry\n' >> "$temp/tools/verify-wazig/unproven-journeys.txt"
bash "$check" "$temp" >"$temp/out" 2>&1
grep -Fq 'remove window from tools/verify-wazig/unproven-journeys.txt; a feature row proves it now' "$temp/out"
printf 'test-check-feature-map: PASS\n'

#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/tools/verify-wazig" "$temp/src"
cp "$repo/tools/verify-wazig/"{feature-map.json,feature-map-limits.txt,journeys.json} "$temp/tools/verify-wazig/"
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
printf 'test-check-feature-map: PASS\n'

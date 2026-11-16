#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
check="$repo/tools/check-no-new-pixel-numbers.sh"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/tools" "$temp/src"
cp "$repo/src/main.zig" "$temp/src/main.zig"
cp "$repo/tools/pixel-number-limits.txt" "$temp/tools/"
bash "$check" "$repo"
bash "$check" "$temp"
python3 - "$temp/src/main.zig" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
needle = 'fn paintReplyBar(a: *App, shapes: *const smooth.Context, hdc: win.HDC) void {'
assert source.count(needle) == 1
path.write_text(source.replace(needle, needle + '\n    const added = px(a, 37);'))
PY
status=0
bash "$check" "$temp" > "$temp/output" 2>&1 || status=$?
if [[ $status != 1 ]] || ! grep -Fq 'src/box_layout.zig or src/quote_layout.zig' "$temp/output" || ! grep -Fq 'paintReplyBar' "$temp/output"; then
    cat "$temp/output" >&2
    printf 'test-check-no-new-pixel-numbers: expected rejection of added drawing literal, got %s\n' "$status" >&2
    exit 1
fi
cp "$repo/src/main.zig" "$temp/src/main.zig"
printf '\nfn drawNew() void { const value = 42; }\n' >> "$temp/src/main.zig"
status=0
bash "$check" "$temp" > "$temp/output" 2>&1 || status=$?
if [[ $status != 1 ]] || ! grep -Fq 'drawNew' "$temp/output"; then
    cat "$temp/output" >&2
    printf 'test-check-no-new-pixel-numbers: expected rejection in new drawing function, got %s\n' "$status" >&2
    exit 1
fi
cp "$repo/src/main.zig" "$temp/src/main.zig"
python3 - "$temp/src/main.zig" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
needle = 'fn paintReplyBar(a: *App, shapes: *const smooth.Context, hdc: win.HDC) void {'
assert source.count(needle) == 1
path.write_text(source.replace(needle, needle + '\n    const text = "42 }"; // 37 {'))
PY
bash "$check" "$temp" > "$temp/output"
printf 'test-check-no-new-pixel-numbers: PASS\n'

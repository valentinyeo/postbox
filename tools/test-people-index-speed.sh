#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${ZIG:-}" ]; then
    if [ -x "$HOME/.local/zig-0.16.0/zig" ]; then ZIG="$HOME/.local/zig-0.16.0/zig"; else ZIG=zig; fi
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

cp "$ROOT/src/people_index.zig" "$TMP/people_index.zig"
python3 - "$TMP/people_index.zig" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
anchor = "            for (entries) |entry| {\n"
if source.count(anchor) != 1:
    raise SystemExit("test-people-index-speed: FAIL search planting anchor changed")
source = source.replace(anchor, anchor + """                for (0..2) |_| {
                    for (entries) |candidate| {
                        std.mem.doNotOptimizeAway(std.mem.eql(u8, entry.jid, candidate.jid));
                    }
                }
""")
path.write_text(source)
PY

status=0
timeout 60 "$ZIG" test "$TMP/people_index.zig" > "$TMP/planted.log" 2>&1 || status=$?
if [ "$status" != 1 ] ||
    ! grep -Fq 'test.build 5000 archived and 3000 contacts and search within a second...FAIL (TestUnexpectedResult)' "$TMP/planted.log" ||
    ! grep -Fq 'try std.testing.expect(elapsed < std.time.ns_per_s);' "$TMP/planted.log" ||
    ! grep -Eq '[0-9]+ passed; [0-9]+ skipped; 1 failed\.' "$TMP/planted.log"; then
    cat "$TMP/planted.log" >&2
    printf 'test-people-index-speed: FAIL planted CPU slowdown must fail only the timing assertion, got exit %s\n' "$status" >&2
    exit 1
fi
if ! "$ZIG" test "$ROOT/src/people_index.zig" > "$TMP/real.log" 2>&1; then
    cat "$TMP/real.log" >&2
    echo 'test-people-index-speed: FAIL real tests must pass' >&2
    exit 1
fi
echo 'test-people-index-speed: PASS (planted CPU slowdown rejected by timing assertion; real tests pass)'

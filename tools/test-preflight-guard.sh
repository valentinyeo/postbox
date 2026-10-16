#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/.claude/hooks/preflight-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '%s\n' '#!/usr/bin/env bash' '[ "$1" = version ] && { echo 0.16.0; exit 0; }' '[ "$1" = fmt ] && [ -n "${FAKE_FMT_FAIL:-}" ] && { echo "src/main.zig:1:1: bad indentation"; exit 1; }' 'exit 0' > "$TMP/zig"
chmod +x "$TMP/zig"
export ZIG="$TMP/zig"

failures=0
expect() {
    local want="$1" cmd="$2" got=0
    python3 -c 'import json, sys; print(json.dumps({"cwd": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))' "${CWD_OVERRIDE:-$ROOT}" "$cmd" | "$HOOK" >/dev/null 2>"$TMP/err" || got=$?
    if [ "$got" != "$want" ]; then
        echo "FAIL: expected exit $want, got $got for: $cmd (FAKE_FMT_FAIL=${FAKE_FMT_FAIL:-})"
        cat "$TMP/err"
        failures=$((failures + 1))
    else
        echo "ok: exit $got for: $cmd"
    fi
}

FAKE_FMT_FAIL=1 expect 0 "git status"
FAKE_FMT_FAIL=1 expect 0 "git log --grep push"
expect 0 "git push -u origin HEAD"
FAKE_FMT_FAIL=1 expect 2 "git push -u origin HEAD"
FAKE_FMT_FAIL=1 expect 2 "gh pr create --fill"
FAKE_FMT_FAIL=1 expect 2 "git add -A && git commit -m x && git push"
FAKE_FMT_FAIL=1 CWD_OVERRIDE=/ expect 2 "cd $ROOT && git push"
FAKE_FMT_FAIL=1 CWD_OVERRIDE=/ expect 2 "git -C $ROOT push"
FAKE_FMT_FAIL=1 CWD_OVERRIDE=/ expect 0 "git push"

[ "$failures" = 0 ] || exit 1
echo "preflight-guard: all cases passed"

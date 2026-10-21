#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/.claude/hooks/preflight-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check_local_entrypoints() {
    python3 - "$1" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
failed = False
for name in ('.claude/hooks/preflight-guard.sh', 'tools/ship.sh'):
    source = (root / name).read_text().replace('\\\n', '')
    if re.search(r"preflight\.sh|(?<![\w.])(?:zig|\$\{?ZIG\}?)[\"']?\s+(?:build(?:-\w+)?|test|run|cc|c\+\+)\b", source):
        print(f'{name}: [J1] local pushes must not run full preflight or Zig; use tools/preflight-light.sh')
        failed = True
    if name.endswith('ship.sh'):
        light = re.search(r'(?m)^(?:nice -n \d+ (?:ionice -c\d+ )?)?(?:bash )?tools/preflight-light\.sh\s*$', source)
    else:
        light = '"$ROOT/tools/preflight-light.sh" "$ROOT"' in source
    if not light:
        print(f'{name}: [J1] local pushes must invoke tools/preflight-light.sh')
        failed = True
sys.exit(1 if failed else 0)
PY
}

check_local_entrypoints "$ROOT"
mkdir -p "$TMP/policy/.claude/hooks" "$TMP/policy/tools"
for file in .claude/hooks/preflight-guard.sh tools/ship.sh; do
    cp "$ROOT/.claude/hooks/preflight-guard.sh" "$TMP/policy/.claude/hooks/preflight-guard.sh"
    cp "$ROOT/tools/ship.sh" "$TMP/policy/tools/ship.sh"
    git -C "$ROOT" show "00d3c91d72be23846cb96435f7471e5ec674cd3e:$file" > "$TMP/policy/$file"
    status=0
    check_local_entrypoints "$TMP/policy" > "$TMP/policy-output" || status=$?
    if [ "$status" != 1 ] || ! grep -Fq "$file: [J1]" "$TMP/policy-output"; then
        cat "$TMP/policy-output" >&2
        echo "FAIL: [J1] must reject origin/main baseline $file" >&2
        exit 1
    fi
    echo "ok: [J1] rejects origin/main baseline 00d3c91 $file"
done
for file in .claude/hooks/preflight-guard.sh tools/ship.sh; do
    for command in 'tools/preflight.sh' 'bash tools/preflight.sh' 'zig build' 'zig test src/main.zig' '"$ZIG" build test' '"${ZIG}" test src/main.zig'; do
        cp "$ROOT/.claude/hooks/preflight-guard.sh" "$TMP/policy/.claude/hooks/preflight-guard.sh"
        cp "$ROOT/tools/ship.sh" "$TMP/policy/tools/ship.sh"
        printf '%s\n' "$command" >> "$TMP/policy/$file"
        status=0
        check_local_entrypoints "$TMP/policy" > "$TMP/policy-output" || status=$?
        if [ "$status" != 1 ] || ! grep -Fq "$file: [J1]" "$TMP/policy-output"; then
            cat "$TMP/policy-output" >&2
            echo "FAIL: [J1] must reject $command in $file" >&2
            exit 1
        fi
        echo "ok: [J1] rejects $command in $file"
    done
done

ROOT="$TMP/repo"
git init -q "$ROOT"
mkdir -p "$ROOT/tools"
printf '%s\n' '#!/usr/bin/env bash' '[ "$#" = 1 ] && [ "$1" = "$PREFLIGHT_ROOT" ] || exit 1' 'echo light >> "$PREFLIGHT_CALLS"' '[ -z "${FAKE_LIGHT_FAIL:-}" ]' > "$ROOT/tools/preflight-light.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo full >> "$PREFLIGHT_CALLS"' 'exit 1' > "$ROOT/tools/preflight.sh"
chmod +x "$ROOT/tools/preflight-light.sh" "$ROOT/tools/preflight.sh"
export PREFLIGHT_CALLS="$TMP/calls" PREFLIGHT_ROOT="$ROOT"

failures=0
expect() {
    local want="$1" cmd="$2" calls="${3:-1}" got=0
    : > "$PREFLIGHT_CALLS"
    python3 -c 'import json, sys; print(json.dumps({"cwd": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))' "${CWD_OVERRIDE:-$ROOT}" "$cmd" | "$HOOK" >/dev/null 2>"$TMP/err" || got=$?
    if [ "$(wc -l < "$PREFLIGHT_CALLS")" != "$calls" ] || grep -q full "$PREFLIGHT_CALLS"; then
        echo "FAIL: expected $calls light-only calls for: $cmd"
        cat "$PREFLIGHT_CALLS"
        failures=$((failures + 1))
    fi
    if [ "$got" != "$want" ]; then
        echo "FAIL: expected exit $want, got $got for: $cmd (FAKE_LIGHT_FAIL=${FAKE_LIGHT_FAIL:-})"
        cat "$TMP/err"
        failures=$((failures + 1))
    else
        echo "ok: exit $got for: $cmd"
    fi
}

FAKE_LIGHT_FAIL=1 expect 0 "git status" 0
FAKE_LIGHT_FAIL=1 expect 0 "git log --grep push" 0
expect 0 "git push -u origin HEAD"
expect 0 "gh pr create --fill"
FAKE_LIGHT_FAIL=1 expect 2 "git push -u origin HEAD"
FAKE_LIGHT_FAIL=1 expect 2 "gh pr create --fill"
FAKE_LIGHT_FAIL=1 expect 2 "gh pr ready"
FAKE_LIGHT_FAIL=1 expect 2 "gh pr merge --auto"
FAKE_LIGHT_FAIL=1 expect 2 "git add -A && git commit -m x && git push"
FAKE_LIGHT_FAIL=1 CWD_OVERRIDE=/ expect 2 "cd $ROOT && git push"
FAKE_LIGHT_FAIL=1 CWD_OVERRIDE=/ expect 2 "git -C $ROOT push"
FAKE_LIGHT_FAIL=1 CWD_OVERRIDE=/ expect 0 "git push" 0

[ "$failures" = 0 ] || exit 1
echo "preflight-guard: all cases passed"

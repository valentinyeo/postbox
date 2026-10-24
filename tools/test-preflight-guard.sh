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

check_light_tests() {
    python3 - "$1" <<'PYTHON'
from pathlib import Path
import re
import shlex
import sys

root = Path(sys.argv[1])
source = (root / 'tools/preflight-light.sh').read_text().replace('\\\n', '')
problems = []

def entries(name):
    match = re.search(r'(?m)^' + name + r'=\(\n(.*?)^\)\s*$', source, re.S)
    if not match:
        problems.append(f'missing {name} array')
        return []
    return shlex.split(match[1], comments=True)

light = entries('PYTHON_LIGHT_TESTS')
heavy = {}
for entry in entries('PYTHON_HEAVY_TESTS'):
    name, separator, reason = entry.partition(':')
    if not separator or not reason.strip():
        problems.append(f'heavy exclusion needs a reason: {entry}')
    if name in heavy:
        problems.append(f'duplicate heavy exclusion: {name}')
    heavy[name] = reason
if len(light) != len(set(light)):
    problems.append('duplicate light tests')
if set(light) & heavy.keys():
    problems.append('tests appear in both light and heavy lists')
discovered = {'.'.join(path.relative_to(root / 'tools').with_suffix('').parts)
              for path in (root / 'tools').rglob('test_*.py')}
covered = set(light) | heavy.keys()
for name in sorted(discovered - covered):
    problems.append(f'CI-discovered test is unaccounted for: {name}')
for name in sorted(covered - discovered):
    problems.append(f'listed test does not exist: {name}')
if not re.search(r'^    run python3 -m unittest "\$\{PYTHON_LIGHT_TESTS\[@\]\}"$', source, re.M):
    problems.append('unittest must run the complete PYTHON_LIGHT_TESTS array')
if not re.search(r'^run bash tools/test-preflight-guard\.sh --check-light$', source, re.M):
    problems.append('light preflight must enforce parity before running tests')
for problem in problems:
    print(f'tools/preflight-light.sh: [J2] IGSH-711 {problem}; cover every CI Python test with a light entry or a reasoned heavy exclusion')
sys.exit(1 if problems else 0)
PYTHON
}

if [ "${1:-}" = --check-light ]; then
    check_light_tests "$ROOT"
    exit 0
fi

check_light_tests "$ROOT"

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

python3 - "$ROOT" "$TMP/policy" <<'PYTHON'
from pathlib import Path
import sys

root, fixture = map(Path, sys.argv[1:])
for path in (root / 'tools').rglob('test_*.py'):
    target = fixture / path.relative_to(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.touch()
PYTHON
git -C "$ROOT" show "225da43acb18733c5cf5eaafaa025f9c8e095888:tools/preflight-light.sh" > "$TMP/policy/tools/preflight-light.sh"
status=0
check_light_tests "$TMP/policy" > "$TMP/policy-output" || status=$?
if [ "$status" != 1 ] || ! grep -Fq '[J2] IGSH-711' "$TMP/policy-output" || ! grep -Fq 'unaccounted for: test_workspace_names' "$TMP/policy-output"; then
    cat "$TMP/policy-output" >&2
    echo 'FAIL: [J2] IGSH-711 must reject origin/main baseline missing test_workspace_names' >&2
    exit 1
fi
echo 'ok: [J2] IGSH-711 rejects origin/main baseline 225da43 missing test_workspace_names'
for mutation in missing new-test no-reason overlap stale bypass no-guard; do
    cp "$ROOT/tools/preflight-light.sh" "$TMP/policy/tools/preflight-light.sh"
    python3 - "$TMP/policy" "$mutation" <<'PYTHON'
from pathlib import Path
import sys

root = Path(sys.argv[1])
mutation = sys.argv[2]
path = root / 'tools/preflight-light.sh'
source = path.read_text()
if mutation == 'missing':
    source = source.replace('    test_workspace_names\n', '')
elif mutation == 'new-test':
    (root / 'tools/test_future_quick.py').touch()
elif mutation == 'no-reason':
    source = source.replace('test_theme_runtime: unittest cases invoke Zig compiler and runtime harnesses', 'test_theme_runtime: ')
elif mutation == 'overlap':
    source = source.replace('PYTHON_LIGHT_TESTS=(\n', 'PYTHON_LIGHT_TESTS=(\n    test_theme_runtime\n')
elif mutation == 'stale':
    source = source.replace('PYTHON_LIGHT_TESTS=(\n', 'PYTHON_LIGHT_TESTS=(\n    test_nonexistent\n')
elif mutation == 'bypass':
    source = source.replace('run python3 -m unittest "${PYTHON_LIGHT_TESTS[@]}"', 'run python3 -m unittest test_check_cache_keys')
elif mutation == 'no-guard':
    source = source.replace('run bash tools/test-preflight-guard.sh --check-light', '')
path.write_text(source)
PYTHON
    status=0
    check_light_tests "$TMP/policy" > "$TMP/policy-output" || status=$?
    rm -f "$TMP/policy/tools/test_future_quick.py"
    if [ "$status" != 1 ] || ! grep -Fq '[J2] IGSH-711' "$TMP/policy-output"; then
        cat "$TMP/policy-output" >&2
        echo "FAIL: [J2] IGSH-711 must reject $mutation" >&2
        exit 1
    fi
    echo "ok: [J2] IGSH-711 rejects $mutation"
done
cp "$ROOT/tools/preflight-light.sh" "$TMP/policy/tools/preflight-light.sh"
check_light_tests "$TMP/policy"
echo 'ok: [J2] IGSH-711 accepts complete light coverage with reasoned heavy exclusions'

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

#!/usr/bin/env bash
set -euo pipefail

CWD="$(python3 -c '
import json, os, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
tool_input = data.get("tool_input")
cmd = tool_input.get("command") or "" if isinstance(tool_input, dict) else ""
match = re.search(r"(^|[;&|(\s])(git(\s+-C\s+\S+)?\s+push|gh\s+pr\s+(create|ready|merge))(\s|$)", cmd)
if match:
    dirs = re.findall(r"(?:\bcd|\bgit\s+-C)\s+([^\s;&|()]+)", cmd[:match.end()])
    cwd = data.get("cwd") or "."
    target = os.path.expanduser(dirs[-1].strip(chr(34) + chr(39))) if dirs else cwd
    print(os.path.join(cwd, target))
')"

[ -n "$CWD" ] || exit 0
ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -x "$ROOT/tools/preflight.sh" ] || exit 0

if ! OUT="$(nice -n 10 "$ROOT/tools/preflight.sh" "$ROOT" 2>&1)"; then
    {
        echo "BLOCKED: tools/preflight.sh failed in $ROOT, so this push or PR would break CI. Fix the errors below, run tools/preflight.sh until it passes, then retry."
        printf '%s\n' "$OUT" | tail -n 40
    } >&2
    exit 2
fi

exit 0

#!/usr/bin/env bash
# PreToolUse Bash guard for the wazig repo.
# Blocks commands that reference the Hypertask team's agent scope
# (slugs, conf/env paths, state dirs, systemd instances).
# Exits 2 (block) with a message on stderr when a match is found, 0 otherwise.

set -euo pipefail

INPUT="$(cat)"

CMD="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)
cmd = ""
if isinstance(data, dict):
    tool_input = data.get("tool_input") or {}
    if isinstance(tool_input, dict):
        cmd = tool_input.get("command") or ""
print(cmd)
')"

if [ -z "$CMD" ]; then
    exit 0
fi

# Hypertask team slugs, off-limits from this repo (wazig owns wazig-dev-1..5 only).
# Word-boundary match that is NOT preceded by "wazig-", so wazig-dev-2, wazig-dev-glm
# etc. never trip these patterns.
PATTERN='(?<!wazig-)\b(dev-2|dev-3|dev-4|dev-5|dev-glm(-[2-5])?|ht-bug-fixer|ht-manager|qa-agent)\b'

if printf '%s' "$CMD" | grep -qP "$PATTERN"; then
    echo "BLOCKED: command references a Hypertask team agent (dev-2..dev-5, dev-glm/dev-glm-2..5, ht-bug-fixer, ht-manager, qa-agent) or its conf/env/state/systemd resources. This repo (wazig) may only touch its own agents (wazig-dev-1..wazig-dev-5)." >&2
    exit 2
fi

exit 0

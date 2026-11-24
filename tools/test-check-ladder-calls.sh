#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
check=(python3 "$repo/tools/check-ladder-calls.py")
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT

"${check[@]}" "$repo"
for allowed in tools/check-ladder-calls.py tools/test-check-ladder-calls.sh tools/test_voice_language.py \
               tools/verify-wazig/check-voice-language.py tools/verify-wazig/verifier.py; do
    if ! awk -F: -v path="$allowed" '$1 == path && $2 != "" && $3 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { found = 1 } END { exit !found }' "$repo/.github/ladder-call-allow"; then
        printf 'test-check-ladder-calls: %s needs an allow line with a reason and a date\n' "$allowed" >&2
        exit 1
    fi
done
python3 - "$repo" <<'PY'
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
tokens = re.compile(r'(?<![A-Za-z])(?:PASS|FAIL)(?![A-Za-z])')
words = re.compile(r'verdict|judge', re.I)
bad = []
for name in ('CLAUDE.md', 'AGENTS.md'):
    for lineno, line in enumerate((root / name).read_text().splitlines(), 1):
        if tokens.search(line) or words.search(line):
            bad.append(f'{name}:{lineno}')
if bad:
    sys.exit('rule text uses retired wording: ' + ', '.join(bad))
PY

url() { printf 'https://%s.%s/%s' "$1" "$2" "$3"; }
reject() {
    local status=0
    "${check[@]}" "$1" > "$temp/output" 2>&1 || status=$?
    if [[ $status != 1 ]] || ! grep -Fq "$2" "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-check-ladder-calls: expected rejection containing %s, got %s\n' "$2" "$status" >&2
        exit 1
    fi
}
prepare() {
    rm -rf "$temp/tree"
    mkdir -p "$temp/tree/tools" "$temp/tree/.github" "$temp/tree/src"
}

prepare
printf 'API_URL = "%s"\n' "$(url api groq.com openai/v1/chat/completions)" > "$temp/tree/tools/call.py"
reject "$temp/tree" 'tools/call.py:1: direct model call (api.groq.com)'
prepare
printf 'API_URL = "%s"\n' "$(url api openai.com v1/chat/completions)" > "$temp/tree/tools/call.py"
reject "$temp/tree" 'direct model call (api.openai.com)'
prepare
printf 'API_URL = "%s"\n' "$(url api anthropic.com v1/messages)" > "$temp/tree/tools/call.py"
reject "$temp/tree" 'direct model call (api.anthropic.com)'
prepare
printf 'API_URL = "%s"\n' "$(printf 'https://%s/api/v1/chat/completions' openrouter.ai)" > "$temp/tree/tools/call.py"
reject "$temp/tree" 'direct model call (openrouter.ai/api)'
prepare
printf 'API_URL = "%s"\n' "$(url api z.ai v1)" > "$temp/tree/.github/call.yml"
reject "$temp/tree" 'direct model call (api.z.ai)'
prepare
printf 'import os\nprint(os.environ["%s"])\n' 'GROQ_API_KEY' > "$temp/tree/tools/keys.py"
reject "$temp/tree" 'direct model key'
prepare
printf 'API_URL = "%s"\n' "$(url api groq.com openai/v1/chat/completions)" > "$temp/tree/src/call.py"
"${check[@]}" "$temp/tree" > "$temp/output"
prepare
mkdir -p "$temp/tree/tools/__pycache__"
printf 'API_URL = "%s"\n' "$(url api groq.com openai/v1/chat/completions)" > "$temp/tree/tools/__pycache__/verifier.pyc"
"${check[@]}" "$temp/tree" > "$temp/output"
prepare
printf 'host = "%s.%s"\n' api anthropic.com > "$temp/tree/tools/evidence.py"
"${check[@]}" "$temp/tree" > "$temp/output"
prepare
printf 'env:\n  %s: ${{ secrets.%s }}\n' 'VERDICT_API_KEY' 'GROQ_API_KEY' > "$temp/tree/.github/workflows.yml"
"${check[@]}" "$temp/tree" > "$temp/output"
prepare
printf 'API_URL = "%s"\n' "$(url api groq.com openai/v1/chat/completions)" > "$temp/tree/tools/call.py"
printf 'tools/call.py:emergency:%s\n' "$(date -u -d tomorrow +%F)" > "$temp/tree/.github/ladder-call-allow"
"${check[@]}" "$temp/tree" > "$temp/output"
printf 'tools/call.py:emergency:%s\n' "$(date -u -d yesterday +%F)" > "$temp/tree/.github/ladder-call-allow"
reject "$temp/tree" 'expired allow for tools/call.py'
printf 'tools/call.py missing date\n' > "$temp/tree/.github/ladder-call-allow"
reject "$temp/tree" 'invalid allow line'
printf 'test-check-ladder-calls: PASS\n'

#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
REPO="${GITHUB_REPOSITORY:-valentinyeo/postbox}"
TITLE='Verification upkeep: drift report'
report="$(mktemp)"
status=0

step() {
    local name="$1"
    shift
    local out
    if out="$("$@" 2>&1)"; then
        return 0
    fi
    status=1
    printf '### %s\n\n```\n%s\n```\n\n' "$name" "$out" >> "$report"
}

step 'Feature map' bash tools/check-feature-map.sh .
step 'Skill map' python3 tools/verify-wazig/check-map.py

for workflow in verify.yml planted.yml; do
    run_json="$(gh run list -R "$REPO" --workflow "$workflow" --event schedule --status completed --limit 1 --json databaseId,url --jq '.[0] // empty' 2>/dev/null || true)"
    if [ -z "$run_json" ]; then
        continue
    fi
    run_id="$(printf '%s' "$run_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["databaseId"])')"
    run_url="$(printf '%s' "$run_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"
    failed="$(gh run view "$run_id" -R "$REPO" --json jobs --jq '.jobs[] | select(.conclusion == "failure") | .name' 2>/dev/null || true)"
    if [ -n "$failed" ]; then
        status=1
        printf '### Last nightly %s run\n\n%s\n\nFailed jobs:\n\n```\n%s\n```\n\n' "$workflow" "$run_url" "$failed" >> "$report"
    fi
done

number="$(gh issue list -R "$REPO" --state open --search "\"$TITLE\" in:title" --json number --jq '.[0].number // empty' 2>/dev/null || true)"

if [ "$status" -ne 0 ]; then
    cat "$report"
    if [ -n "$number" ]; then
        gh issue edit "$number" -R "$REPO" --body-file "$report"
    else
        gh issue create -R "$REPO" --title "$TITLE" --body-file "$report"
    fi
elif [ -n "$number" ]; then
    gh issue close "$number" -R "$REPO" --comment 'Maps and the last nightly run are clean again.'
else
    echo 'map-upkeep: clean'
fi
rm -f "$report"

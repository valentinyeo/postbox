#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
admit="$script_dir/automerge-admit.sh"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT

pr318_head=c131e1073b73305c4bf95b5b485aa3949effc33c
main_at_merge=ac9b43b7c60ccb1c4209249ad2b6daa1bb30240a
merge_base=fc4e1a09efbfa7f176dd3cb0bcd92204167a53ee
mapfile -t required < "$script_dir/required-checks.txt"

rollup=$(printf '%s\n' "${required[@]}" | jq -R '{__typename: "CheckRun", name: ., status: "COMPLETED", conclusion: "SUCCESS"}' | jq -cs .)

pr_info() {
    jq -cn --argjson rollup "$rollup" --arg head "$pr318_head" '{
        isDraft: false, labels: [], additions: 3, deletions: 1, files: [{path: "src/main.zig"}],
        mergeable: "MERGEABLE", statusCheckRollup: $rollup, headRefOid: $head,
        isCrossRepository: false, author: {login: "valentinyeo"}}'
}

base_info=$(pr_info)
base_files='["src/main.zig"]'

expect() {
    local name=$1 want=$2 info=$3 files=$4 behind=$5 owner=${6:-valentinyeo}
    printf '%s' "$info" > "$temp/info.json"
    printf '%s' "$files" > "$temp/files.json"
    local got
    got=$(bash "$admit" "$temp/info.json" "$temp/files.json" "$behind" "$owner" 2>&1) || true
    case "$got" in
        $want) printf 'test-automerge-admit: ok %s\n' "$name" ;;
        *)
            printf 'test-automerge-admit: FAIL %s: want %s, got %s\n' "$name" "$want" "$got" >&2
            failed=1
            ;;
    esac
}

failed=0

expect "pr318-behind-main (main ${main_at_merge}, merge base ${merge_base}, behind_by 1)" 'skip (*behind main*' "$base_info" "$base_files" 1
expect "up-to-date head merges" 'merge' "$base_info" "$base_files" 0
expect "unknown-behind refuses" 'skip (*compare*' "$base_info" "$base_files" ""
expect "non-numeric behind refuses" 'skip (*compare*' "$base_info" "$base_files" "abc"

expect "draft still refused" 'skip (draft)' "$(echo "$base_info" | jq -c '.isDraft = true')" "$base_files" 0
expect "red required check still refused" 'skip (required checks not green: ci)' \
    "$(echo "$base_info" | jq -c '(.statusCheckRollup[] | select(.name == "ci")) |= (.conclusion = "FAILURE")')" "$base_files" 0
expect "red check overrides behind main" 'skip (required checks not green: ci)' \
    "$(echo "$base_info" | jq -c '(.statusCheckRollup[] | select(.name == "ci")) |= (.conclusion = "FAILURE")')" "$base_files" 1
expect "superseded failed run of a check does not block" 'merge' \
    "$(echo "$base_info" | jq -c '.statusCheckRollup += [{__typename: "CheckRun", name: "ci", status: "COMPLETED", conclusion: "FAILURE", startedAt: "2026-11-18T23:29:00Z", completedAt: "2026-11-18T23:29:50Z"}] | (.statusCheckRollup[] | select(.name == "ci" and .conclusion == "SUCCESS")) |= (. + {startedAt: "2026-11-18T23:43:00Z", completedAt: "2026-11-18T23:44:00Z"})')" "$base_files" 0
expect "newer failed run of a check still blocks" 'skip (required checks not green: ci)' \
    "$(echo "$base_info" | jq -c '.statusCheckRollup += [{__typename: "CheckRun", name: "ci", status: "COMPLETED", conclusion: "FAILURE", startedAt: "2026-11-18T23:50:00Z", completedAt: "2026-11-18T23:51:00Z"}] | (.statusCheckRollup[] | select(.name == "ci" and .conclusion == "SUCCESS")) |= (. + {startedAt: "2026-11-18T23:43:00Z", completedAt: "2026-11-18T23:44:00Z"})')" "$base_files" 0
for skipped in candidate verify base-fails "verify (hub, true)"; do
    expect "skipped $skipped job does not block" 'merge' \
        "$(echo "$base_info" | jq -c --arg n "$skipped" '.statusCheckRollup += [{__typename: "CheckRun", name: $n, status: "COMPLETED", conclusion: "SKIPPED"}]')" "$base_files" 0
done
expect "skipped planted job still blocks" 'skip (required checks not green: planted (voice))' \
    "$(echo "$base_info" | jq -c '.statusCheckRollup += [{__typename: "CheckRun", name: "planted (voice)", status: "COMPLETED", conclusion: "SKIPPED"}]')" "$base_files" 0
expect "skipped unlisted job still blocks" 'skip (required checks not green: lint)' \
    "$(echo "$base_info" | jq -c '.statusCheckRollup += [{__typename: "CheckRun", name: "lint", status: "COMPLETED", conclusion: "SKIPPED"}]')" "$base_files" 0
expect "missing required check still refused" 'skip (required checks not green: tdlib)' \
    "$(echo "$base_info" | jq -c '.statusCheckRollup |= map(select(.name != "tdlib"))')" "$base_files" 0
for verdict in FAILURE CANCELLED SKIPPED; do
    expect "$verdict verifier verdict blocks" 'skip (required checks not green: verify-verdict)' \
        "$(echo "$base_info" | jq -c --arg verdict "$verdict" '(.statusCheckRollup[] | select(.name == "verify-verdict")) |= (.conclusion = $verdict)')" "$base_files" 0
done
expect "missing verifier verdict blocks" 'skip (required checks not green: verify-verdict)' \
    "$(echo "$base_info" | jq -c '.statusCheckRollup |= map(select(.name != "verify-verdict"))')" "$base_files" 0
expect "pending verifier verdict blocks" 'skip (required checks not green: verify-verdict)' \
    "$(echo "$base_info" | jq -c '(.statusCheckRollup[] | select(.name == "verify-verdict")) |= (.status = "IN_PROGRESS")')" "$base_files" 0
expect "gating workflow edit still refused" 'skip (edits a release-gating workflow, needs manual review)' \
    "$base_info" '[".github/workflows/ci.yml"]' 0
expect "unlisted files still refused" 'skip (could not list PR files)' "$base_info" "" 0
expect "other author still refused" 'skip (not a same-repo PR by the owner)' \
    "$(echo "$base_info" | jq -c '.author.login = "someone"')" "$base_files" 0
expect "cross-repo still refused" 'skip (not a same-repo PR by the owner)' \
    "$(echo "$base_info" | jq -c '.isCrossRepository = true')" "$base_files" 0
expect "hold label still refused" 'skip (hold label)' \
    "$(echo "$base_info" | jq -c '.labels = [{name: "hold"}]')" "$base_files" 0
expect "conflicting still refused" 'skip (not mergeable (CONFLICTING))' \
    "$(echo "$base_info" | jq -c '.mergeable = "CONFLICTING"')" "$base_files" 0
expect "invalid head still refused" 'skip (invalid PR head)' \
    "$(echo "$base_info" | jq -c '.headRefOid = "main"')" "$base_files" 0
expect "failed code-review alone never blocks" 'merge' \
    "$(echo "$base_info" | jq -c '.statusCheckRollup += [{__typename: "CheckRun", name: "code-review", status: "COMPLETED", conclusion: "FAILURE"}]')" "$base_files" 0
expect "failed status context blocks" 'skip (required checks not green: lint)' \
    "$(echo "$base_info" | jq -c '.statusCheckRollup += [{__typename: "StatusContext", context: "lint", state: "FAILURE"}]')" "$base_files" 0

cp "$admit" "$temp/automerge-admit.sh"
original_admit=$admit
admit="$temp/automerge-admit.sh"
expect "missing list fails closed" 'skip (could not read required checks)' "$base_info" "$base_files" 0
: > "$temp/required-checks.txt"
expect "empty list fails closed" 'skip (could not read required checks)' "$base_info" "$base_files" 0
admit=$original_admit

exit "$failed"

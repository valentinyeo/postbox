#!/usr/bin/env bash
set -euo pipefail

repo=${GITHUB_REPOSITORY:-valentinyeo/wazig}
root=$(git rev-parse --show-toplevel)
cd "$root"
dry_run=${AI_REVIEW_DRY_RUN:-0}
state=${XDG_STATE_HOME:-$HOME/.local/state}/wazig-ai-review

if [[ $dry_run != 1 ]]; then
    exec 9> "${XDG_RUNTIME_DIR:-/tmp}/wazig-ai-review.lock"
    flock -n 9 || exit 0
    if [[ -z $(git status --porcelain) ]]; then
        if ! { git fetch -q origin main && git checkout -q --detach origin/main; } > /dev/null 2>&1; then
            printf 'ai-review-poll: refresh failed\n'
        fi
    else
        printf 'ai-review-poll: tree is dirty; refresh skipped\n'
    fi
    mkdir -p "$state/attempts" "$state/done" "$state/handled"
fi

if ! prs=$(gh pr list -R "$repo" --state open --limit 100 --json number,headRefOid,isCrossRepository); then
    printf 'ai-review-poll: PR listing failed\n'
    exit 1
fi
if ! rows=$(jq -r '.[] | select(.isCrossRepository == false) | [.number, .headRefOid] | @tsv' <<< "$prs"); then
    printf 'ai-review-poll: invalid PR listing\n'
    exit 1
fi

while IFS=$'\t' read -r pr sha; do
    [[ -n $pr ]] || continue
    if [[ ! $pr =~ ^[0-9]+$ || ! $sha =~ ^[0-9a-fA-F]{40}$ ]]; then
        printf 'ai-review-poll: invalid PR metadata\n'
        continue
    fi
    if ! comments=$(gh api "repos/$repo/issues/$pr/comments" --paginate --jq '.[]' | jq -s '.'); then
        printf 'ai-review-poll: PR %s comments failed\n' "$pr"
        continue
    fi
    if ! review=$(jq -c '[.[] | select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- wazig-ai-review -->")))] | max_by(.created_at, .id) // {body: "", updated_at: ""}' <<< "$comments"); then
        printf 'ai-review-poll: PR %s invalid comments\n' "$pr"
        continue
    fi
    if ! reviewed_sha=$(jq -r '.body | split("\n") | map(select(test("^Commit [0-9a-fA-F]{40}$"))) | first // "" | sub("^Commit "; "")' <<< "$review") \
        || ! updated_at=$(jq -r '.updated_at' <<< "$review") \
        || ! requests=$(jq -r --arg updated "$updated_at" '.[] | select((.body | startswith("/ai-review")) and .user.type != "Bot" and (.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") and .created_at > $updated) | .id' <<< "$comments"); then
        printf 'ai-review-poll: PR %s invalid comments\n' "$pr"
        continue
    fi
    pending=()
    while IFS= read -r id; do
        [[ $id =~ ^[0-9]+$ && ! -e $state/handled/$id ]] || continue
        pending+=("$id")
    done <<< "$requests"
    key=$pr-$sha
    reason=''
    if [[ $sha != "$reviewed_sha" && ! -e $state/done/$key ]]; then
        reason='head'
    fi
    if (( ${#pending[@]} )); then
        reason='request'
    fi
    [[ -n $reason ]] || continue
    attempts=0
    if [[ -f $state/attempts/$key ]]; then
        read -r attempts < "$state/attempts/$key"
    fi
    if (( attempts >= 2 )); then
        if [[ $dry_run != 1 ]]; then
            printf 'ai-review-poll: PR %s attempt limit reached\n' "$pr"
        fi
        continue
    fi
    if [[ $dry_run == 1 ]]; then
        printf 'due %s %s\n' "$pr" "$reason"
        continue
    fi
    printf '%s\n' "$((attempts + 1))" > "$state/attempts/$key"
    for id in "${pending[@]}"; do
        : > "$state/handled/$id"
    done
    if bash tools/ai-review.sh "$pr" > /dev/null; then
        : > "$state/done/$key"
        printf 'ai-review-poll: PR %s dispatched (%s)\n' "$pr" "$reason"
    else
        printf 'ai-review-poll: PR %s failed (%s)\n' "$pr" "$reason"
    fi
done <<< "$rows"

exit 0

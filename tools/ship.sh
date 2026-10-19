#!/usr/bin/env bash
set -euo pipefail

if (( $# == 1 )) && [[ "$1" == --help || "$1" == -h ]]; then
    printf 'usage: tools/ship.sh <TICKET> "<what changed>"\n'
    exit 0
fi
if (( $# != 2 )) || [[ -z "$1" || -z "$2" || "$1" == -* ]]; then
    printf 'usage: tools/ship.sh <TICKET> "<what changed>"\n' >&2
    exit 2
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if ! worktree="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo 'ship: run inside a git worktree of this repo.' >&2
    exit 1
fi
if [[ "$(cd -- "$worktree" && pwd -P)" != "$root" ]]; then
    echo 'ship: run inside a git worktree of this repo.' >&2
    exit 1
fi
cd "$root"
branch="$(git symbolic-ref --quiet --short HEAD)" || {
    echo 'ship: a non-main branch is required; detached HEAD is not supported.' >&2
    exit 1
}
if [[ "$branch" == main ]]; then
    echo 'ship: refusing to ship from main; use a ticket branch.' >&2
    exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo 'ship: refusing to ship with uncommitted tracked changes.' >&2
    exit 1
fi
wait_seconds="${SHIP_TIMEOUT:-3600}"
if [[ ! "$wait_seconds" =~ ^[1-9][0-9]*$ ]]; then
    echo 'ship: SHIP_TIMEOUT must be a positive integer in seconds.' >&2
    exit 1
fi

tools/preflight.sh
git push -u origin HEAD
pr="$(gh pr list --head "$branch" --state open --json url --jq '.[0].url // empty')"
if [[ -z "$pr" ]]; then
    body="$(git log --reverse --format='- %s' origin/main..HEAD)"
    body+=$'\n\nOpened by tools/ship.sh.'
    pr="$(gh pr create --base main --head "$branch" --title "$1: $2" --body "$body")"
fi
printf '%s\n' "$pr"

deadline=$((SECONDS + wait_seconds))
while :; do
    info="$(gh pr view "$pr" --json state,mergeCommit,statusCheckRollup)"
    failed="$(jq -r '[.statusCheckRollup[]? | select((.name == "ci" or .name == "tdlib" or .name == "windows-smoke") and (.conclusion == "FAILURE" or .conclusion == "CANCELLED" or .conclusion == "TIMED_OUT")) | .name] | join(", ")' <<< "$info")"
    if [[ -n "$failed" ]]; then
        echo "ship: required check failed ($failed): $pr" >&2
        exit 1
    fi
    state="$(jq -er '.state' <<< "$info")"
    case "$state" in
        MERGED)
            merge="$(jq -er '.mergeCommit.oid' <<< "$info")"
            printf 'Merged: %s\n' "$merge"
            break
            ;;
        CLOSED)
            echo "ship: PR was closed without merging: $pr" >&2
            exit 1
            ;;
        OPEN) ;;
        *)
            echo "ship: unexpected PR state: $state" >&2
            exit 1
            ;;
    esac
    remaining=$((deadline - SECONDS))
    if (( remaining <= 0 )); then
        echo "ship: timed out after ${wait_seconds}s waiting for automerge: $pr" >&2
        exit 1
    fi
    sleep "$((remaining < 30 ? remaining : 30))"
done

git fetch --no-tags origin main
files="$(git diff --name-only "${merge}^" "$merge")"
if ! grep -E '^(src/|assets/|vendor/|build\.zig)' <<< "$files" >/dev/null; then
    echo 'No release is cut for this change (no app files changed).'
    exit 0
fi

deadline=$((SECONDS + wait_seconds))
while :; do
    git fetch --tags origin
    tags="$(git tag --list 'v*' --contains "$merge" --sort=-version:refname)"
    if [[ -n "$tags" ]]; then
        printf 'Release tag: %s\n' "${tags%%$'\n'*}"
        exit 0
    fi
    remaining=$((deadline - SECONDS))
    if (( remaining <= 0 )); then
        echo "ship: timed out after ${wait_seconds}s waiting for a release tag containing $merge" >&2
        exit 1
    fi
    sleep "$((remaining < 30 ? remaining : 30))"
done

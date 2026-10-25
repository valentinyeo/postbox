#!/usr/bin/env bash
set -euo pipefail

repo="${1:?usage: auto-release-pick.sh <repo> <ref>}"
ref="${2:?usage: auto-release-pick.sh <repo> <ref>}"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
commits="$(git rev-list --first-parent "$ref")"

for sha in $commits; do
    if GITHUB_REPOSITORY="$repo" CI_GREEN_WAIT_SECONDS=0 bash "$script_dir/ci-green.sh" "$sha" >&2; then
        tags="$(git tag -l 'v*' --points-at "$sha")"
        if [ -z "$tags" ]; then
            printf '%s\n' "$sha"
        fi
        exit 0
    fi
done

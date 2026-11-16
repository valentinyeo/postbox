#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(git rev-parse --show-toplevel)}
cd "$root"
list=tools/required-checks.txt
if [[ ! -s $list ]]; then
    printf 'check-required-checks: missing or empty %s\n' "$list" >&2
    exit 1
fi
shopt -s nullglob
workflows=(.github/workflows/*.yml)
if (( ${#workflows[@]} == 0 )); then
    printf 'check-required-checks: no workflow files found\n' >&2
    exit 1
fi
jobs=$(awk '/^    name: / { sub(/^    name: /, ""); print }' "${workflows[@]}")
failed=0
while IFS= read -r check || [[ -n $check ]]; do
    if [[ -z $check ]] || ! printf '%s\n' "$jobs" | grep -Fxq -- "$check"; then
        printf 'check-required-checks: unknown job name %s; edit tools/required-checks.txt or the workflow job name\n' "$check" >&2
        failed=1
    fi
done < "$list"
exit "$failed"

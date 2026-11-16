#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(git -C "$script_dir" rev-parse --show-toplevel)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
bash "$script_dir/check-required-checks.sh" "$repo"
mkdir -p "$temp/tools" "$temp/.github/workflows"
cp "$repo/tools/required-checks.txt" "$temp/tools/required-checks.txt"
cp "$repo"/.github/workflows/*.yml "$temp/.github/workflows/"
printf '%s\n' notify-release >> "$temp/tools/required-checks.txt"
if bash "$script_dir/check-required-checks.sh" "$temp" > "$temp/output" 2>&1; then
    printf 'test-check-required-checks: stale job passed\n' >&2
    exit 1
fi
grep -F 'notify-release; edit tools/required-checks.txt or the workflow job name' "$temp/output"
printf 'test-check-required-checks: PASS\n'

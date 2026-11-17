#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
check="$repo/tools/check-repro-first.sh"
printf 'src/main.zig\n' > "$temp/files"
printf 'Repro: search\n' > "$temp/body"
[[ $(bash "$check" 'SOFT-2592: Fix(search): repair search' "$temp/body" "$temp/files") == search ]]
printf 'Repro: none, documentation only\n' > "$temp/body"
[[ -z $(bash "$check" 'feat: add documentation' "$temp/body" "$temp/files") ]]
if bash "$check" 'fix: repair search' "$temp/body" "$temp/files" >/dev/null 2>&1; then exit 1; fi
printf 'docs/readme.md\n' > "$temp/files"
[[ $(bash "$check" 'fix: repair documentation' "$temp/body" "$temp/files") == none ]]
for body in '' 'Repro: unknown-journey' 'Repro: none,' $'Repro: search\nRepro: voice'; do
    printf '%s\n' "$body" > "$temp/body"
    if bash "$check" 'FIX: repair search' "$temp/body" "$temp/files" >/dev/null 2>&1; then echo "accepted invalid repro: $body" >&2; exit 1; fi
done
printf 'test-check-repro-first: PASS\n'

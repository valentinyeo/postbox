#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
check="$repo/tools/check-pr-proof.sh"
for body in 'Proof: gif-picker, journey gif-picker, https://example.invalid/run' 'Proof: no user-visible change'; do
    printf '%s\n' "$body" > "$temp/body"
    bash "$check" "$temp/body"
done
for body in '' 'Proof:' 'Proof: unknown-feature' 'gif-picker' 'Proof: gif-picker-extra'; do
    printf '%s\n' "$body" > "$temp/body"
    if bash "$check" "$temp/body" > "$temp/out" 2>&1; then echo "accepted invalid proof: $body" >&2; exit 1; fi
    grep -Fq 'add a Proof: line' "$temp/out"
done
printf 'test-check-pr-proof: PASS\n'

#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(git -C "$script_dir" rev-parse --show-toplevel)
lint="$script_dir/lint-repeats.sh"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
SECONDS=0

cases=(
    '7c624253dd93 A1 31d544f8'
    '9cae433dd3e2 A2 2758971'
    '5e773588 B1 2e885be'
    'ca5f46f7 B2 bdf9832'
    '0372da02 B3 90d5434'
    'f2518728 B4 a311894'
    'f169d18 B5 e955d363'
    '7ea1b5b B6 HEAD'
    'a701837 B7 HEAD'
    'dc9bdce C2 HEAD'
    '0e7c320d44f1 C2 HEAD'
    '55e826b C1 HEAD'
    '1f5853e^ D1 HEAD'
)

"$lint" "$repo"
printf 'test-lint-repeats: HEAD passes\n'
for entry in "${cases[@]}"; do
    read -r bad rule fixed <<< "$entry"
    for sha in "$bad" "$fixed"; do
        if [[ $sha == HEAD ]]; then
            tree="$repo"
        else
            tree="$temp/$sha"
            mkdir -p -- "$tree"
            git -C "$repo" archive "$sha" src/main.zig .github/workflows | tar -x -C "$tree"
        fi
        status=0
        "$lint" "$tree" > "$temp/output" 2>&1 || status=$?
        if [[ $sha == "$bad" ]]; then
            if (( status != 1 )) || ! grep -Eq "^(lint-repeats: |C1: )[^:]+:[0-9]+: \\[$rule\\] " "$temp/output"; then
                cat "$temp/output" >&2
                printf 'test-lint-repeats: FAIL %s must exit 1 with [%s], got exit %s\n' "$sha" "$rule" "$status" >&2
                exit 1
            fi
            printf '%s: ' "$bad"
            grep -E "^(lint-repeats: |C1: )[^:]+:[0-9]+: \\[$rule\\] " "$temp/output"
        elif (( status > 1 )) || grep -Fq "[$rule]" "$temp/output"; then
            cat "$temp/output" >&2
            printf 'test-lint-repeats: FAIL fix %s still triggers [%s] or lint errored\n' "$sha" "$rule" >&2
            exit 1
        fi
    done
done
if (( SECONDS >= 60 )); then
    printf 'test-lint-repeats: FAIL runtime %ss must be under 60s\n' "$SECONDS" >&2
    exit 1
fi
printf 'test-lint-repeats: PASS (%s bad commits rejected, their fixes clear their rules, %ss < 60s)\n' "${#cases[@]}" "$SECONDS"

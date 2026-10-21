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
    'dc9bdce C1 HEAD'
    '0e7c320d44f1 C1 HEAD'
    '55e826b E1 HEAD'
    '1f5853e^ D1 HEAD'
    'a735c9f F1 HEAD'
    '0c67e093c2a85bd9b42b73d2d4433551cad39b85 G1 HEAD'
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
            git -C "$repo" archive "$sha" src .github/workflows | tar -x -C "$tree"
        fi
        status=0
        "$lint" "$tree" > "$temp/output" 2>&1 || status=$?
        if [[ $sha == "$bad" ]]; then
            if (( status != 1 )) || ! grep -Eq "^lint-repeats: [^:]+:[0-9]+: \\[$rule\\] " "$temp/output"; then
                cat "$temp/output" >&2
                printf 'test-lint-repeats: FAIL %s must exit 1 with [%s], got exit %s\n' "$sha" "$rule" "$status" >&2
                exit 1
            fi
            printf '%s: ' "$bad"
            grep -E "^lint-repeats: [^:]+:[0-9]+: \\[$rule\\] " "$temp/output"
        elif (( status > 1 )) || grep -Fq "[$rule]" "$temp/output"; then
            cat "$temp/output" >&2
            printf 'test-lint-repeats: FAIL fix %s still triggers [%s] or lint errored\n' "$sha" "$rule" >&2
            exit 1
        fi
    done
done
fixture="$temp/f1-fixtures"
mkdir -p "$fixture/src" "$fixture/.github/workflows"
printf 'name: fixture\n' > "$fixture/.github/workflows/fixture.yml"
: > "$fixture/src/main.zig"
f1_cases=0
for api in RoundRect Ellipse Pie Chord Arc CreateEllipticRgn CreateRoundRectRgn; do
    for form in direct alias import_alias field field_alias multiline_alias multiline_field; do
        case "$form" in
            direct) printf '_ = win.%s();\n' "$api" ;;
            alias) printf 'const Raw = win.%s;\n' "$api" ;;
            import_alias) printf 'const gdi = @import("win32.zig").c;\nconst Raw = gdi.%s;\n' "$api" ;;
            field) printf '_ = @field(win, "%s")();\n' "$api" ;;
            field_alias) printf 'const Raw = @field(@import("win32.zig").c, "%s");\n' "$api" ;;
            multiline_alias) printf 'const Raw = win.\n    %s;\n' "$api" ;;
            multiline_field) printf 'const Raw = @field(\n    win,\n    "%s",\n);\n' "$api" ;;
        esac > "$fixture/src/bypass.zig"
        status=0
        "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
        if (( status != 1 )) || ! grep -Eq '^lint-repeats: src/bypass.zig:[0-9]+: \[F1\] ' "$temp/output"; then
            cat "$temp/output" >&2
            printf 'test-lint-repeats: FAIL F1 %s %s must exit 1 with [F1], got exit %s\n' "$api" "$form" "$status" >&2
            exit 1
        fi
        mv "$fixture/src/bypass.zig" "$fixture/src/smooth_shapes.zig"
        status=0
        "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
        if (( status != 1 )) || ! grep -Eq '^lint-repeats: src/smooth_shapes.zig:[0-9]+: \[F1\] ' "$temp/output"; then
            cat "$temp/output" >&2
            printf 'test-lint-repeats: FAIL F1 %s %s in smooth_shapes must exit 1 with [F1], got exit %s\n' "$api" "$form" "$status" >&2
            exit 1
        fi
        rm "$fixture/src/smooth_shapes.zig"
        f1_cases=$((f1_cases + 2))
        printf 'test-lint-repeats: F1 rejects %s %s including smooth_shapes\n' "$api" "$form"
    done
done
printf 'const safe = win.RoundRectangle;\nconst shape = smooth.fillRoundRect;\n' > "$fixture/src/bypass.zig"
"$lint" "$fixture"
g1_cases=0
for api in DrawTextW CLEARTYPE_QUALITY; do
    for form in direct alias import_alias field field_alias multiline_alias multiline_field bare; do
        case "$form" in
            direct) printf '_ = win.%s();\n' "$api" ;;
            alias) printf 'const Raw = win.%s;\n' "$api" ;;
            import_alias) printf 'const gdi = @import("win32.zig").c;\nconst Raw = gdi.%s;\n' "$api" ;;
            field) printf '_ = @field(win, "%s")();\n' "$api" ;;
            field_alias) printf 'const Raw = @field(@import("win32.zig").c, "%s");\n' "$api" ;;
            multiline_alias) printf 'const Raw = win.\n    %s;\n' "$api" ;;
            multiline_field) printf 'const Raw = @field(\n    win,\n    "%s",\n);\n' "$api" ;;
            bare) printf 'const Raw = %s;\n' "$api" ;;
        esac > "$fixture/src/bypass.zig"
        status=0
        "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
        if (( status != 1 )) || ! grep -Eq '^lint-repeats: src/bypass.zig:[0-9]+: \[G1\] .*text_draw.drawText' "$temp/output"; then
            cat "$temp/output" >&2
            printf 'test-lint-repeats: FAIL G1 %s %s must exit 1 with [G1] and text_draw.drawText, got exit %s\n' "$api" "$form" "$status" >&2
            exit 1
        fi
        mv "$fixture/src/bypass.zig" "$fixture/src/text_draw.zig"
        "$lint" "$fixture" > "$temp/output" 2>&1
        rm "$fixture/src/text_draw.zig"
        g1_cases=$((g1_cases + 1))
        printf 'test-lint-repeats: G1 rejects %s %s and permits only text_draw\n' "$api" "$form"
    done
done
mkdir -p "$fixture/src/nested"
printf 'const Raw = win.DrawTextW;\n' > "$fixture/src/nested/bypass.zig"
status=0
"$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
if (( status != 1 )) || ! grep -Fq '[G1]' "$temp/output"; then
    cat "$temp/output" >&2
    exit 1
fi
rm "$fixture/src/nested/bypass.zig"
printf 'const safe = win.DrawTextWrap;\nconst quality = win.CLEARTYPE_NATURAL_QUALITY;\nconst draw = text_draw.drawText;\n' > "$fixture/src/bypass.zig"
"$lint" "$fixture"
if (( SECONDS >= 60 )); then
    printf 'test-lint-repeats: FAIL runtime %ss must be under 60s\n' "$SECONDS" >&2
    exit 1
fi
printf 'test-lint-repeats: PASS (%s bad commits rejected, %s F1 bypasses rejected, %s G1 bypasses rejected, their fixes clear their rules, %ss < 60s)\n' "${#cases[@]}" "$f1_cases" "$g1_cases" "$SECONDS"

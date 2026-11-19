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
    '4064743 B8 HEAD'
    'fc4e1a0 B9 HEAD'
    'dc9bdce C1 HEAD'
    '0e7c320d44f1 C1 HEAD'
    '914331e C2 HEAD'
    'c641316 C2 HEAD'
    '55e826b E1 HEAD'
    '1f5853e^ D1 HEAD'
    'a735c9f F1 HEAD'
    '0c67e093c2a85bd9b42b73d2d4433551cad39b85 G1 HEAD'
    '4064743 H1 HEAD'
    '1a638c6 I1 HEAD'
)

"$lint" "$repo" > "$temp/head-output" 2>&1
cat "$temp/head-output"
printf 'test-lint-repeats: HEAD passes\n'
for entry in "${cases[@]}"; do
    read -r bad rule fixed <<< "$entry"
    for sha in "$bad" "$fixed"; do
        status=0
        if [[ $sha == HEAD ]]; then
            cp "$temp/head-output" "$temp/output"
        else
            tree="$temp/$sha"
            if [[ ! -d $tree ]]; then
                mkdir -p -- "$tree"
                git -C "$repo" archive "$sha" src .github/workflows | tar -x -C "$tree"
            fi
            "$lint" "$tree" > "$temp/output" 2>&1 || status=$?
        fi
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
printf 'name: fixture\nconcurrency:\n  group: fixture\n  cancel-in-progress: true\n' > "$fixture/.github/workflows/fixture.yml"
: > "$fixture/src/main.zig"
for mutation in key paid trigger; do
    case "$mutation" in
        key) sed '/secrets.GROQ_API_KEY/d' "$repo/.github/workflows/ai-review.yml" ;;
        paid) sed 's/secrets.GROQ_API_KEY/secrets.OPENAI_API_KEY/g' "$repo/.github/workflows/ai-review.yml" ;;
        trigger) sed 's/^  pull_request:/  pull_request_target:/' "$repo/.github/workflows/ai-review.yml" ;;
    esac > "$fixture/.github/workflows/ai-review.yml"
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Fq '[B6]' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL B6 must reject AI review %s regression, got exit %s\n' "$mutation" "$status" >&2
        exit 1
    fi
done
cp "$repo/.github/workflows/ai-review.yml" "$fixture/.github/workflows/ai-review.yml"
"$lint" "$fixture"
printf 'test-lint-repeats: B6 requires the free review key and rejects a paid key and pull_request_target\n'
mkdir -p "$fixture/tools"
admit_src="$repo/tools/automerge-admit.sh"
yml_src="$repo/.github/workflows/automerge.yml"
reset_automerge() {
    cp "$yml_src" "$fixture/.github/workflows/automerge.yml"
    cp "$repo/.github/workflows/verify.yml" "$fixture/.github/workflows/verify.yml"
    cp "$admit_src" "$fixture/tools/automerge-admit.sh"
}
reset_automerge
for mutation in old trigger workflow head success; do
    reset_automerge
    case "$mutation" in
        old) git -C "$repo" show 6747858248d6:.github/workflows/verify.yml > "$fixture/.github/workflows/verify.yml"; git -C "$repo" show 6747858248d6:.github/workflows/automerge.yml > "$fixture/.github/workflows/automerge.yml" ;;
        trigger) sed -i 's/^  pull_request:/  pull_request_target:/' "$fixture/.github/workflows/verify.yml" ;;
        workflow) sed -i 's/, "verify-wazig"//' "$fixture/.github/workflows/automerge.yml" ;;
        head) sed -i 's/head_sha=\$head_oid/head_sha=missing/' "$fixture/.github/workflows/automerge.yml" ;;
        success) sed -i 's/\.conclusion == "success"/.conclusion != "failure"/' "$fixture/.github/workflows/automerge.yml" ;;
    esac
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Fq '[B11]' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL B11 must reject %s\n' "$mutation" >&2
        exit 1
    fi
done
reset_automerge
"$lint" "$fixture"
printf 'test-lint-repeats: B11 rejects pre-change workflows and missing PR journey guards\n'
cp "$repo/.github/workflows/pr-title.yml" "$fixture/.github/workflows/pr-title.yml"
for mutation in title base; do
    reset_automerge
    cp "$repo/.github/workflows/pr-title.yml" "$fixture/.github/workflows/pr-title.yml"
    case "$mutation" in
        title) sed -i '/bash tools\/check-repro-first.sh/d' "$fixture/.github/workflows/pr-title.yml" ;;
        base) sed -i '/.name == ("base-fails (/d' "$fixture/.github/workflows/automerge.yml" ;;
    esac
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Fq '[B12]' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL B12 must reject missing %s guard\n' "$mutation" >&2
        exit 1
    fi
done
rm "$fixture/.github/workflows/pr-title.yml"
reset_automerge
printf 'test-lint-repeats: B12 rejects missing reproduction guards\n'
for mutation in planted schedule cron; do
    reset_automerge
    case "$mutation" in
        planted) sed -i 's/^  planted:$/  removed-planted:/' "$fixture/.github/workflows/verify.yml" ;;
        schedule) sed -i 's/^  schedule:$/  removed-schedule:/' "$fixture/.github/workflows/verify.yml" ;;
        cron) sed -i '/^    - cron: /d' "$fixture/.github/workflows/verify.yml" ;;
    esac
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Fq '[B13]' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL B13 must reject missing %s\n' "$mutation" >&2
        exit 1
    fi
done
reset_automerge
printf 'test-lint-repeats: B13 rejects missing planted job and nightly trigger\n'
mkdir -p "$fixture/.claude/skills/verify-wazig"
for mutation in missing doubled; do
    case "$mutation" in
        missing) printf 'name: verify-wazig\n' > "$fixture/.claude/skills/verify-wazig/SKILL.md" ;;
        doubled) printf 'pstack: 0.15.43\npstack: 0.15.36\n' > "$fixture/.claude/skills/verify-wazig/SKILL.md" ;;
    esac
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Fq '[B16]' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL B16 must reject %s pstack line\n' "$mutation" >&2
        exit 1
    fi
done
rm -rf "$fixture/.claude"
printf 'test-lint-repeats: B16 requires one pstack version line\n'
sed 's/needs: \[build, launch, gitleaks, proof\]/needs: [build, launch, gitleaks]/' "$repo/.github/workflows/release.yml" > "$fixture/.github/workflows/release.yml"
if cmp -s "$repo/.github/workflows/release.yml" "$fixture/.github/workflows/release.yml"; then
    printf 'test-lint-repeats: FAIL B14 mutation changed nothing\n' >&2
    exit 1
fi
status=0
"$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
if (( status != 1 )) || ! grep -Fq '[B14]' "$temp/output"; then
    cat "$temp/output" >&2
    printf 'test-lint-repeats: FAIL B14 must reject publishing without proof\n' >&2
    exit 1
fi
cp "$repo/.github/workflows/release.yml" "$fixture/.github/workflows/release.yml"
"$lint" "$fixture"
printf 'test-lint-repeats: B14 rejects publishing without proof and permits the gated release\n'
for mutation in missing cancel-release; do
    cp "$repo/.github/workflows/no-comments.yml" "$fixture/.github/workflows/no-comments.yml"
    cp "$repo/.github/workflows/release.yml" "$fixture/.github/workflows/release.yml"
    case "$mutation" in
        missing) file=no-comments.yml; sed -i '/^concurrency:/,+2d' "$fixture/.github/workflows/$file" ;;
        cancel-release) file=release.yml; sed -i 's/cancel-in-progress: false/cancel-in-progress: true/' "$fixture/.github/workflows/$file" ;;
    esac
    if cmp -s "$repo/.github/workflows/$file" "$fixture/.github/workflows/$file"; then
        printf 'test-lint-repeats: FAIL B15 %s mutation changed nothing\n' "$mutation" >&2
        exit 1
    fi
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Fq "lint-repeats: .github/workflows/$file:1: [B15] " "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL B15 must reject %s\n' "$mutation" >&2
        exit 1
    fi
done
cp "$repo/.github/workflows/release.yml" "$fixture/.github/workflows/release.yml"
"$lint" "$fixture"
printf 'test-lint-repeats: B15 rejects a missing concurrency block and publish cancellation, and permits safe workflows\n'
b8_cases=0
for guard in 'required-checks.txt' 'required=' 'as \$names' 'COMPLETED' 'match-head-commit' 'could not evaluate head checks' 'length) == 0' '!= "code-review"'; do
    reset_automerge
    if [ "$guard" = 'match-head-commit' ]; then
        sed "/$guard/d" "$yml_src" > "$fixture/.github/workflows/automerge.yml"
    else
        sed "/$guard/d" "$admit_src" > "$fixture/tools/automerge-admit.sh"
    fi
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Fq '[B8]' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL IGSH-504 B8 must reject missing guard %s, got exit %s\n' "$guard" "$status" >&2
        exit 1
    fi
    b8_cases=$((b8_cases + 1))
done
reset_automerge
"$lint" "$fixture"
printf 'test-lint-repeats: IGSH-504 B8 rejects %s incomplete check policies and permits the fixed workflow\n' "$b8_cases"
cp "$repo/tools/required-checks.txt" "$fixture/tools/required-checks.txt"
cp "$repo/tools/required-checks.txt" "$fixture/tools/copied-checks.txt"
status=0
"$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
if (( status != 1 )) || ! grep -Eq '\[B10\].*tools/required-checks.txt' "$temp/output"; then
    cat "$temp/output" >&2
    printf 'test-lint-repeats: FAIL B10 must reject a copied list\n' >&2
    exit 1
fi
rm "$fixture/tools/copied-checks.txt"
"$lint" "$fixture"
printf 'test-lint-repeats: B10 rejects a copied list\n'
b9_cases=0
for mutation in fields owner_env owner_arg same_repo owner_author; do
    reset_automerge
    case "$mutation" in
        fields) sed 's/,isCrossRepository,author//' "$yml_src" > "$fixture/.github/workflows/automerge.yml" ;;
        owner_env) sed '/REPO_OWNER:/d' "$yml_src" > "$fixture/.github/workflows/automerge.yml" ;;
        owner_arg) sed 's/ --arg owner "\$REPO_OWNER"//' "$admit_src" > "$fixture/tools/automerge-admit.sh" ;;
        same_repo) sed 's/\.isCrossRepository != false or //' "$admit_src" > "$fixture/tools/automerge-admit.sh" ;;
        owner_author) sed 's/ or \.author\.login != \$owner//' "$admit_src" > "$fixture/tools/automerge-admit.sh" ;;
    esac
    if cmp -s "$yml_src" "$fixture/.github/workflows/automerge.yml" && cmp -s "$admit_src" "$fixture/tools/automerge-admit.sh"; then
        printf 'test-lint-repeats: FAIL IGSH-635 %s mutation changed nothing\n' "$mutation" >&2
        exit 1
    fi
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Fq '[B9]' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL IGSH-635 B9 must reject missing %s, got exit %s\n' "$mutation" "$status" >&2
        exit 1
    fi
    b9_cases=$((b9_cases + 1))
done
reset_automerge
"$lint" "$fixture"
printf 'test-lint-repeats: IGSH-635 B9 rejects %s incomplete admission policies and permits the fixed workflow\n' "$b9_cases"
mkdir -p "$fixture/src/nested"
c2_cases=0
for variable in DEEPGRAM_API_KEY WA_BRIDGE_KEY; do
    for file in main.zig bypass.zig nested/bypass.zig; do
        for read in "init.environ_map.get(\"$variable\")" "$(printf 'init.environ_map\n    .get(\n        "%s"\n    )' "$variable")"; do
            printf 'const stored = slack_win.loadSecret(init.gpa, lit("WaBridgeKey"));\nconst seed = %s;\n' "$read" > "$fixture/src/$file"
            status=0
            "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
            if (( status != 1 )) || ! grep -Fq '[C2]' "$temp/output"; then
                cat "$temp/output" >&2
                printf 'test-lint-repeats: FAIL C2 must reject inherited %s read in %s, got exit %s\n' "$variable" "$file" "$status" >&2
                exit 1
            fi
            c2_cases=$((c2_cases + 1))
        done
        rm "$fixture/src/$file"
        : > "$fixture/src/main.zig"
    done
    printf 'const seed = slack_win.loadUserEnvironment(init.gpa, lit("%s"));\nconst stored = slack_win.loadSecret(init.gpa, lit("WaBridgeKey"));\n' "$variable" > "$fixture/src/main.zig"
    "$lint" "$fixture"
    : > "$fixture/src/main.zig"
done
printf 'test-lint-repeats: C2 rejects %s inherited reads throughout src and permits saved user environment readers\n' "$c2_cases"
printf 'const key = loadRegistryString(allocator, lit("WaBridgeKey"));\n' > "$fixture/src/main.zig"
status=0
"$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
if (( status != 1 )) || ! grep -Fq '[C1]' "$temp/output"; then
    cat "$temp/output" >&2
    printf 'test-lint-repeats: FAIL C1 must reject a plain WaBridgeKey read\n' >&2
    exit 1
fi
printf 'const key = slack_win.loadSecret(allocator, lit("WaBridgeKey"));\n' > "$fixture/src/main.zig"
"$lint" "$fixture"
: > "$fixture/src/main.zig"
printf 'test-lint-repeats: C1 rejects plain WaBridgeKey and permits DPAPI\n'
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
k1_cases=0
for api in Shell_NotifyIconW NOTIFYICONDATAW NIM_ADD; do
    printf 'const Raw = win.%s;\n' "$api" > "$fixture/src/bypass.zig"
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Eq '^lint-repeats: src/bypass.zig:[0-9]+: \[K1\] .*toast.show' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL K1 %s must exit 1 with [K1], got exit %s\n' "$api" "$status" >&2
        exit 1
    fi
    k1_cases=$((k1_cases + 1))
done
printf 'const note = win.Shell_NotifyIconWrap;\n// win.Shell_NotifyIconW\n' > "$fixture/src/bypass.zig"
"$lint" "$fixture"
printf 'test-lint-repeats: IGSH-1737 K1 rejects %s tray icon APIs\n' "$k1_cases"
h1_cases=0
for storage in \
    'var app = App{};' \
    'const state = App{};' \
    'var app: App = undefined;' \
    'var state: App = .{};' \
    'const state:App=.{};' \
    $'var app = App\n{};' \
    $'var app:\nApp =\nundefined;'; do
    printf '%s\n' "$storage" > "$fixture/src/main.zig"
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Eq '^lint-repeats: src/main.zig:[0-9]+: \[H1\] .*allocator.create\(App\)' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL H1 must reject App by-value storage, got exit %s\n' "$status" >&2
        exit 1
    fi
    h1_cases=$((h1_cases + 1))
done
printf 'const app = try allocator.create(App);\ndefer allocator.destroy(app);\napp.* = .{};\nvar pointer: *App = app;\nconst SmallApp = struct {};\nvar small = SmallApp{};\n' > "$fixture/src/main.zig"
"$lint" "$fixture"
printf 'test-lint-repeats: H1 rejects %s App by-value forms and permits heap storage\n' "$h1_cases"
i1_cases=0
for mutation in startup switch rollback multiline_switch mode flush; do
    case "$mutation" in
        startup) sed 's/applyTheme(loadTheme());/theme.set(loadTheme());/' "$repo/src/main.zig" ;;
        switch) sed 's/applyTheme(choice);/theme.set(choice);/' "$repo/src/main.zig" ;;
        rollback) sed 's/applyTheme(previous);/theme.set(previous);/' "$repo/src/main.zig" ;;
        multiline_switch) sed 's/applyTheme(choice);/theme.\
        set(choice);/' "$repo/src/main.zig" ;;
        mode) sed 's/_ = set_preferred_app_mode(menu_theme.preferredAppMode(choice));/_ = choice;/' "$repo/src/main.zig" ;;
        flush) sed 's/        flush_menu_themes();/        _ = raw;/' "$repo/src/main.zig" ;;
    esac > "$fixture/src/main.zig"
    if cmp -s "$repo/src/main.zig" "$fixture/src/main.zig"; then
        printf 'test-lint-repeats: FAIL IGSH-505 %s mutation changed nothing\n' "$mutation" >&2
        exit 1
    fi
    status=0
    "$lint" "$fixture" > "$temp/output" 2>&1 || status=$?
    if (( status != 1 )) || ! grep -Eq '^lint-repeats: src/main.zig:[0-9]+: \[I1\] .*applyTheme' "$temp/output"; then
        cat "$temp/output" >&2
        printf 'test-lint-repeats: FAIL IGSH-505 I1 must reject %s, got exit %s\n' "$mutation" "$status" >&2
        exit 1
    fi
    i1_cases=$((i1_cases + 1))
    printf 'test-lint-repeats: IGSH-505 I1 rejects %s bypass\n' "$mutation"
done
cp "$repo/src/main.zig" "$fixture/src/main.zig"
"$lint" "$fixture"
printf 'test-lint-repeats: IGSH-505 I1 rejects %s bypasses and permits the single apply point\n' "$i1_cases"
if (( SECONDS >= 60 )); then
    printf 'test-lint-repeats: FAIL runtime %ss must be under 60s\n' "$SECONDS" >&2
    exit 1
fi
printf 'test-lint-repeats: PASS (%s bad commits rejected, %s F1 bypasses rejected, %s G1 bypasses rejected, their fixes clear their rules, %ss < 60s)\n' "${#cases[@]}" "$f1_cases" "$g1_cases" "$SECONDS"

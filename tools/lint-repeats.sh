#!/usr/bin/env bash
set -euo pipefail

if (( $# > 1 )); then
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
fi
root=${1:-$(git rev-parse --show-toplevel)}
cd "$root"
failed=0

if ! awk '
function fail(line, rule, problem, fix) {
    printf "lint-repeats: %s:%d: [%s] %s. Use %s.\n", FILENAME, line, rule, problem, fix
    failed = 1
}
{
    code = $0
    sub(/\/\/.*$/, "", code)
    source = source code "\n"
    if (code ~ /std\.mem\.eql\(u8, [A-Za-z0-9_.\[\]]*\.jid\.slice\(\), [A-Za-z0-9_.\[\]]*\.jid\.slice\(\)\)/)
        fail(FNR, "E1", "two chat ids compared without provider and account, so two accounts that share a contact mix", "chat_key.Key.eql(chat_key.of(x), chat_key.of(y))")
    if (code ~ /loadRegistryString[[:space:]]*\(|REG_SZ/ && code ~ /lit[[:space:]]*\([[:space:]]*"([^"]*ApiKey|TelegramApiHash|WaBridgeKey)"[[:space:]]*\)/)
        fail(FNR, "C1", "API key uses plain registry storage", "slack_win.loadSecret for encrypted storage and migration")
    if (code ~ /^[[:space:]]*if \(staged_file\.len > 0/ && code ~ /\{/ && code !~ /stagedFileGoesToWacli\(/)
        fail(FNR, "D1", "staged pasted file is queued without routing by the chat\047s provider, so a Slack paste goes to WhatsApp", "if (staged_file.len > 0 and stagedFileGoesToWacli(a.chats[a.selected_chat].provider))")
    if (code ~ /^fn /) {
        worker = code ~ /^fn wacliWorkerMain\(/
        unarchive = code ~ /^fn queueUnarchiveChat\(/
    }
    if (worker) {
        if (code ~ /while[[:space:]]*\(/) {
            condition = code
            condition_line = FNR
        } else if (condition != "") condition = condition " " code
        if (condition ~ /wacliTakeJob[[:space:]]*\(.*==[[:space:]]*null/) {
            fail(condition_line, "A1", "worker wait condition destructively dequeues a job", "var job = wacliTakeJob(a, slack_lane); while (job == null and !a.wacli_quit) and retain job for wacliRunJob(a, job.?)")
            condition = ""
        }
        if (code ~ /[{};]/) condition = ""
    }
    if (unarchive) {
        if (code ~ /if[[:space:]]*\([[:space:]]*a\.pending_archive_count[[:space:]]*>=[[:space:]]*a\.pending_archives\.len[[:space:]]*\)/) {
            overflow = 1
            overflow_line = FNR
            saved = 0
            depth = 0
        }
        if (overflow) {
            if (code ~ /a\.unarchive_retry\.set[[:space:]]*\([[:space:]]*jid[[:space:]]*\)/) saved = 1
            if (code ~ /return[[:space:]]*;/ && !saved) {
                fail(overflow_line, "A2", "full archive queue silently discards an unarchive request", "if (a.unarchive_retry.len == 0) a.unarchive_retry.set(jid) before returning")
                overflow = 0
            }
            braces = code
            depth += gsub(/\{/, "", braces)
            depth -= gsub(/\}/, "", braces)
            if (depth <= 0) overflow = 0
        }
    }
    if (code ~ /^}/) {
        worker = unarchive = overflow = 0
        condition = ""
    }
}
END {
    line = 1
    pattern = "(^|[^[:alnum:]_])App[[:space:]]*\\{|:[[:space:]]*App[[:space:]]*(=|;)"
    while (match(source, pattern)) {
        prefix = substr(source, 1, RSTART - 1)
        token = substr(source, RSTART, RLENGTH)
        source = substr(source, RSTART + RLENGTH)
        line += gsub(/\n/, "", prefix)
        fail(line, "H1", "App by-value storage overflows the Windows startup stack", "allocator.create(App), defer allocator.destroy(app), and app.* = .{...}")
        line += gsub(/\n/, "", token)
    }
    exit failed ? 1 : 0
}
' src/main.zig; then
    failed=1
fi

mapfile -d '' zig_sources < <(find src -type f -name '*.zig' -print0)
if ! awk '
function scan(    rest, line, prefix, token) {
    rest = source
    line = 1
    while (match(rest, /environ_map[[:space:]]*\.[[:space:]]*get[[:space:]]*\([[:space:]]*"(DEEPGRAM_API_KEY|WA_BRIDGE_KEY)"[[:space:]]*\)/)) {
        prefix = substr(rest, 1, RSTART - 1)
        token = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        line += gsub(/\n/, "", prefix)
        printf "lint-repeats: %s:%d: [C2] Secret key read from the inherited process environment, which can hold an old key. Use slack_win.loadUserEnvironment plus slack_win.loadSecret.\n", file, line
        line += gsub(/\n/, "", token)
        failed = 1
    }
}
FNR == 1 {
    scan()
    file = FILENAME
    source = ""
}
{
    code = $0
    sub(/\/\/.*$/, "", code)
    source = source code "\n"
}
END { scan(); exit failed ? 1 : 0 }
' "${zig_sources[@]}"; then
    failed=1
fi

if ! awk '
function finish() {
    if (body ~ /theme[[:space:]]*\.[[:space:]]*set[[:space:]]*\(/ && !apply)
        fail("theme selection bypasses native menu colours", "applyTheme(choice) for startup, theme switches and rollback")
    if (apply && (body !~ /menu_theme\.preferredAppMode[[:space:]]*\(/ || body !~ /set_preferred_app_mode[[:space:]]*\(/ || body !~ /flush_menu_themes[[:space:]]*\(/))
        fail("theme apply point no longer updates and flushes native menus", "SetPreferredAppMode and FlushMenuThemes in applyTheme")
    body = ""
    apply = 0
}
function fail(problem, fix) {
    printf "lint-repeats: %s:%d: [I1] %s. Use %s.\n", FILENAME, start, problem, fix
    failed = 1
}
{
    code = $0
    sub(/\/\/.*$/, "", code)
    if (code ~ /^(pub[[:space:]]+)?fn[[:space:]]+/) {
        finish()
        start = FNR
        apply = code ~ /^fn applyTheme\(/
    }
    body = body code "\n"
    if (code ~ /^}/) finish()
}
END { finish(); exit failed ? 1 : 0 }
' src/main.zig; then
    failed=1
fi

if ! awk '
function scan(    rest, line, prefix, token) {
    rest = source
    line = 1
    while (match(rest, pattern)) {
        prefix = substr(rest, 1, RSTART - 1)
        token = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        line += gsub(/\n/, "", prefix)
        printf "lint-repeats: %s:%d: [F1] raw GDI rounded edges are jagged. Use smooth_shapes.fillRoundRect and friends with explicit colours and a paint-level Context.\n", file, line
        line += gsub(/\n/, "", token)
        failed = 1
    }
}
BEGIN {
    names = "(RoundRect|Ellipse|Pie|Chord|Arc|CreateEllipticRgn|CreateRoundRectRgn)"
    pattern = "(\\.[[:space:]]*" names "([^[:alnum:]_]|$)|@field[[:space:]]*\\([^,]+,[[:space:]]*\"" names "\")"
}
FNR == 1 {
    scan()
    file = FILENAME
    source = ""
}
{
    code = $0
    sub(/\/\/.*$/, "", code)
    source = source code "\n"
}
END { scan(); exit failed ? 1 : 0 }
' src/*.zig; then
    failed=1
fi

mapfile -d '' text_sources < <(find src -type f -name '*.zig' ! -path 'src/text_draw.zig' -print0)
if ! awk '
{
    code = $0
    sub(/\/\/.*$/, "", code)
    if (code ~ /(^|[^[:alnum:]_])(DrawTextW|CLEARTYPE_QUALITY)([^[:alnum:]_]|$)/) {
        printf "lint-repeats: %s:%d: [G1] GDI text bypasses smooth bundled DirectWrite rendering. Use text_draw.drawText and CLEARTYPE_NATURAL_QUALITY.\n", FILENAME, FNR
        failed = 1
    }
}
END { exit failed ? 1 : 0 }
' "${text_sources[@]}"; then
    failed=1
fi

shopt -s nullglob
workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
if (( ${#workflows[@]} == 0 )); then
    printf 'lint-repeats: no .github/workflows/*.yml files found\n' >&2
    exit 1
fi
if ! awk '
function fail(line, rule, problem, fix) {
    printf "lint-repeats: %s:%d: [%s] %s. Use %s.\n", file, line, rule, problem, fix
    failed = 1
}
function check_models() {
    if (file == ".github/workflows/ai-review.yml" && !models_read)
        fail(1, "B6", "AI review lacks free GitHub Models permission", "models: read with GITHUB_TOKEN; no API key or pull_request_target")
}
function finish() {
    if (tag_line && !dispatch)
        fail(tag_line, "B1", "bot-created release tag has no explicit release dispatch in its script", "gh workflow run release.yml --ref \"${next_tag}\" -R \"${GITHUB_REPOSITORY}\"")
    if (expected_three && !success_exit)
        fail(expected_three, "B3", "expected wazigctl exit 3 remains the PowerShell step exit status", "exit 0 after checking $LASTEXITCODE -ne 3")
    if (automerge_line && (!all_required || !all_checks || !completed_checks || !head_pinned || !checks_fail_closed || !missing_checks || !ai_optional))
        fail(automerge_line, "B8", "automerge can merge before every non-AI PR head check succeeds", "all required checks including unfurl-verification, every discovered non-AI check, COMPLETED and SUCCESS, fail-closed evaluation, and --match-head-commit")
    automerge_line = all_required = all_checks = completed_checks = head_pinned = checks_fail_closed = missing_checks = ai_optional = 0
    tag_line = dispatch = gui_exe = gui_call = expected_three = success_exit = status_call = 0
    running = 0
    command = ""
}
FNR == 1 {
    check_models()
    finish()
    file = FILENAME
    models_read = 0
    if (file == ".github/workflows/automerge.yml") automerge_line = 1
}
{
    code = $0
    if (code ~ ("^[[:space:]]*" sprintf("%c", 35))) next
    match(code, /[^ ]/)
    indent = RSTART - 1
    if (running && code !~ /^[[:space:]]*$/ && indent <= run_indent) finish()
    if (code ~ /^[[:space:]]*run:[[:space:]]*[|>]/) {
        running = 1
        run_indent = indent
        next
    }
    if (file == ".github/workflows/ai-review.yml") {
        if (code ~ /^[[:space:]]*models:[[:space:]]*read[[:space:]]*$/) models_read = 1
        if (code ~ /secrets[[:space:]]*\./ || code ~ /pull_request_target/)
            fail(FNR, "B6", "AI review uses a secret or privileged PR trigger", "GITHUB_TOKEN with models: read and pull_request or trusted issue_comment")
    }
    if (code ~ /openrouter\.ai|OPENROUTER_API_KEY|api\.z\.ai/)
        fail(FNR, "B6", "workflow calls OpenRouter or Z.ai instead of free GitHub Models", "ai-review.yml runs bash tools/ai-review.sh with GITHUB_TOKEN and models: read")
    if (code ~ /^[[:space:]]*runs-on:/ && code ~ /self-hosted/)
        fail(FNR, "B7", "workflow runs on a self-hosted runner, whose public logs show the server\047s name and folders", "runs-on: ubuntu-latest; the AI review runs in ai-review.yml on GitHub")
    if (!running) next
    if (file == ".github/workflows/auto-release.yml") {
        if (code ~ /git[[:space:]]+push.*next_tag/ || code ~ /ref=refs\/tags\/\$\{next_tag\}/) tag_line = FNR
        if (code ~ /gh[[:space:]]+workflow[[:space:]]+run[[:space:]]+release\.yml/ && code ~ /--ref[[:space:]]+"?\$\{next_tag\}/) dispatch = 1
    }
    if (code ~ /\$exe[[:space:]]*=.*Messages\.exe/) gui_exe = 1
    if (gui_exe && code ~ /&[[:space:]]+\$exe([[:space:]]|$)/ && code !~ /\|/) gui_call = FNR
    if (gui_call && code ~ /\$LASTEXITCODE/) {
        fail(gui_call, "B2", "GUI Messages.exe is launched without waiting before reading stale $LASTEXITCODE", "$proc = Start-Process -FilePath $exe -ArgumentList '\''--tdlib-smoke'\'' -Wait -PassThru and $code = $proc.ExitCode")
        gui_call = 0
    }
    if (code ~ /&[[:space:]]+\$ctl[[:space:]]+status([[:space:]]|$)/) {
        status_call = 1
        success_exit = 0
    }
    if (status_call && code ~ /\$LASTEXITCODE[[:space:]]+-ne[[:space:]]+3([^0-9]|$)/) expected_three = FNR
    if (expected_three && code ~ /^[[:space:]]*exit[[:space:]]+0([[:space:];]|$)/) success_exit = 1
    if (file == ".github/workflows/automerge.yml") {
        if (code ~ /required=/) {
            automerge_line = FNR
            all_required = 1
            count = split("ci|tdlib|windows-smoke|no-comments|unfurl-verification|private-markers|secret-scan|pr-title|notify-release|tdlib-cache / cache", required_checks, "[|]")
            for (i = 1; i <= count; i++)
                if (!index(code, "\"" required_checks[i] "\"")) all_required = 0
        }
        if (code ~ /\(\$checks \| length\) == 0/) missing_checks = 1
        if (code ~ /select\(\(\.name \/\/ \.context\) != "code-review"\)/) ai_optional = 1
        if (code ~ /\$req[[:space:]]*\+[[:space:]]*\[\$roll\[\]/) all_checks = 1
        if (code ~ /\.status != "COMPLETED" or \.conclusion != "SUCCESS"/) completed_checks = 1
        if (code ~ /gh pr merge/ && code ~ /--match-head-commit "\$head_oid"/) head_pinned = 1
        if (code ~ /\|\| blocked="could not evaluate head checks"/) checks_fail_closed = 1
    }
    if (file == ".github/workflows/automerge.yml" && code ~ /required=/ && code ~ /code-review/)
        fail(FNR, "B5", "automerge requires the AI code-review check, so an AI reviewer blocks merges", "all non-AI head checks; an AI reviewer may comment but never gates a merge")
    if (command == "") command_line = FNR
    command = command " " code
    if (code ~ /\\[[:space:]]*$/) next
    if (command ~ /gh[[:space:]]+api[[:space:]]/ && command ~ /[[:space:]]--slurp([[:space:]]|$)/)
        fail(command_line, "B4", "gh api --slurp is unsupported on the workflow CLI", "gh api --paginate --jq '\''.[].filename'\'' | jq -R . | jq -cs '\''.'\''")
    command = ""
}
END {
    check_models()
    finish()
    exit failed ? 1 : 0
}
' "${workflows[@]}"; then
    failed=1
fi

if (( failed )); then
    exit 1
fi
printf 'lint-repeats: PASS\n'

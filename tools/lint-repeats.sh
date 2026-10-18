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
    if (code ~ /std\.mem\.eql\(u8, [A-Za-z0-9_.\[\]]*\.jid\.slice\(\), [A-Za-z0-9_.\[\]]*\.jid\.slice\(\)\)/) {
        printf "C1: %s:%d: [C1] bare jid comparison. Compare with chat_key.Key so provider and account match.\n", FILENAME, FNR
        failed = 1
    }
    if (code ~ /loadRegistryString[[:space:]]*\(|REG_SZ/ && code ~ /lit[[:space:]]*\([[:space:]]*"([^"]*ApiKey|TelegramApiHash)"[[:space:]]*\)/)
        fail(FNR, "C2", "API key uses plain registry storage", "slack_win.loadSecret for encrypted storage and migration")
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
END { exit failed ? 1 : 0 }
' src/main.zig; then
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
function finish() {
    if (tag_line && !dispatch)
        fail(tag_line, "B1", "bot-created release tag has no explicit release dispatch in its script", "gh workflow run release.yml --ref \"${next_tag}\" -R \"${GITHUB_REPOSITORY}\"")
    if (expected_three && !success_exit)
        fail(expected_three, "B3", "expected wazigctl exit 3 remains the PowerShell step exit status", "exit 0 after checking $LASTEXITCODE -ne 3")
    tag_line = dispatch = gui_exe = gui_call = expected_three = success_exit = status_call = 0
    running = 0
    command = ""
}
FNR == 1 {
    finish()
    file = FILENAME
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
    if (code ~ /openrouter\.ai|OPENROUTER_API_KEY|api\.z\.ai/)
        fail(FNR, "B6", "workflow calls a paid OpenRouter or Z.ai API instead of the Codex or Claude subscriptions", "bash tools/ai-review.sh from tools/ai-review-poll.sh on the review server, which calls hax --provider=codex")
    if (code ~ /^[[:space:]]*runs-on:/ && code ~ /self-hosted/)
        fail(FNR, "B7", "workflow runs on a self-hosted runner, whose public logs show the server\047s name and folders", "runs-on: ubuntu-latest; the AI review runs from tools/ai-review-poll.sh on the review server")
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
    if (file == ".github/workflows/automerge.yml" && code ~ /required=/ && code ~ /code-review/)
        fail(FNR, "B5", "automerge requires the AI code-review check, so an AI reviewer blocks merges", "required='\''[\"ci\",\"tdlib\",\"windows-smoke\"]'\''; an AI reviewer may comment but never gates a merge")
    if (command == "") command_line = FNR
    command = command " " code
    if (code ~ /\\[[:space:]]*$/) next
    if (command ~ /gh[[:space:]]+api[[:space:]]/ && command ~ /[[:space:]]--slurp([[:space:]]|$)/)
        fail(command_line, "B4", "gh api --slurp is unsupported on the workflow CLI", "gh api --paginate --jq '\''.[].filename'\'' | jq -R . | jq -cs '\''.'\''")
    command = ""
}
END {
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

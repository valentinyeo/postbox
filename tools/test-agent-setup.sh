#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fail() { printf 'test-agent-setup: FAIL %s\n' "$1" >&2; exit 1; }

private="$temp/private"
mkdir -p "$private/.claude/skills" "$private/hooks"
printf 'rules\n' > "$private/CLAUDE.md"
printf 'handoff\n' > "$private/HANDOFF.md"
printf 'columns: {}\n' > "$private/board.yml"
printf '# index\n' > "$private/.claude/skills/INDEX.md"
printf 'exit 0\n' > "$private/hooks/agent-scope-guard.sh"
export WAZIG_PRIVATE_DIR="$private"

repo="$temp/repo"
mkdir -p "$repo/tools"
cp "$script_dir/agent-setup.sh" "$repo/tools/agent-setup.sh"
git -C "$repo" init -q -b main
git -C "$repo" add tools/agent-setup.sh
git -C "$repo" commit -q -m init

assert_linked() {
    local tree="$1"
    for path in CLAUDE.local.md HANDOFF.md board.yml .claude/skills .claude/hooks/agent-scope-guard.sh; do
        [ -L "$tree/$path" ] || fail "$tree/$path is not linked"
    done
    [ -f "$tree/.claude/skills/INDEX.md" ] || fail "$tree has no skills index"
    [ "$(cat "$tree/board.yml")" = 'columns: {}' ] || fail "$tree/board.yml is not the private board map"
}

(cd "$repo" && bash tools/agent-setup.sh >/dev/null)
assert_linked "$repo"
printf 'test-agent-setup: main checkout linked\n'

git -C "$repo" worktree add -q --detach "$temp/fresh" HEAD >/dev/null 2>&1 || fail "worktree add failed with the private repo present"
assert_linked "$temp/fresh"
printf 'test-agent-setup: new worktree linked with no manual run\n'

if WAZIG_PRIVATE_DIR="$temp/missing" git -C "$repo" worktree add -q --detach "$temp/orphan" HEAD 2> "$temp/err"; then
    fail "worktree add passed without the private repo"
fi
grep -q 'agent-setup: no private companion repo' "$temp/err" || fail "missing private repo was not reported"
printf 'test-agent-setup: missing private repo fails loudly\n'

git -C "$repo" worktree add -q --detach "$temp/stale" HEAD >/dev/null 2>&1
rm -f "$temp/stale/.claude/skills"
mkdir -p "$temp/stale/.claude/skills"
if (cd "$temp/stale" && bash tools/agent-setup.sh 2>/dev/null); then
    fail "a real .claude/skills folder was replaced"
fi
printf 'test-agent-setup: real skills folder refused\n'

foreign="$temp/foreign"
git init -q -b main "$foreign"
mkdir -p "$foreign/tools"
cp "$script_dir/agent-setup.sh" "$foreign/tools/agent-setup.sh"
printf 'exit 0\n' > "$foreign/.git/hooks/post-checkout"
if (cd "$foreign" && bash tools/agent-setup.sh 2>/dev/null); then
    fail "an unrelated post-checkout hook was overwritten"
fi
[ "$(cat "$foreign/.git/hooks/post-checkout")" = 'exit 0' ] || fail "the unrelated post-checkout hook changed"
printf 'test-agent-setup: unrelated hook kept\n'

public="$temp/public"
git init -q -b main "$public"
mkdir -p "$public/tools" "$public/.claude/skills/verify-wazig"
cp "$script_dir/agent-setup.sh" "$public/tools/agent-setup.sh"
printf 'public skill\n' > "$public/.claude/skills/verify-wazig/SKILL.md"
git -C "$public" add tools/agent-setup.sh .claude/skills/verify-wazig/SKILL.md
git -C "$public" commit -q -m public
(cd "$public" && bash tools/agent-setup.sh >/dev/null)
[ ! -L "$public/.claude/skills" ] || fail "public skills directory was replaced"
[ "$(cat "$public/.claude/skills/verify-wazig/SKILL.md")" = 'public skill' ] || fail "public skill changed"
[ -L "$public/.claude/skills/INDEX.md" ] || fail "private entries were not linked beside public skill"
(cd "$public" && bash tools/agent-setup.sh >/dev/null)
git -C "$public" diff --exit-code || fail "setup changed tracked public skill"
printf 'test-agent-setup: public skill preserved beside private links across repeated setup\n'

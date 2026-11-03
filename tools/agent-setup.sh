set -eu
root="$(git rev-parse --show-toplevel)"
private="${WAZIG_PRIVATE_DIR:-$HOME/projects/wazig-agent-skills/wazig-repo}"
if [ ! -d "$private" ]; then
  echo "agent-setup: no private companion repo at $private. Clone valentinyeo/wazig-agent-skills there or set WAZIG_PRIVATE_DIR." >&2
  exit 1
fi
mkdir -p "$root/.claude/hooks"
if [ -d "$root/.claude/skills" ] && [ ! -L "$root/.claude/skills" ]; then
  if ! git -C "$root" ls-files --error-unmatch .claude/skills/verify-wazig/SKILL.md >/dev/null 2>&1; then
    echo "agent-setup: $root/.claude/skills is an untracked real folder; refusing to replace it." >&2
    exit 1
  fi
  for entry in "$private/.claude/skills/"*; do
    [ -e "$entry" ] || continue
    destination="$root/.claude/skills/$(basename "$entry")"
    if [ -e "$destination" ] && [ ! -L "$destination" ]; then
      echo "agent-setup: private skill conflicts with tracked path $destination; refusing to replace it." >&2
      exit 1
    fi
    ln -sfn "$entry" "$destination"
  done
else
  ln -sfn "$private/.claude/skills" "$root/.claude/skills"
fi
ln -sfn "$private/CLAUDE.md" "$root/CLAUDE.local.md"
ln -sfn "$private/HANDOFF.md" "$root/HANDOFF.md"
ln -sfn "$private/board.yml" "$root/board.yml"
ln -sfn "$private/hooks/agent-scope-guard.sh" "$root/.claude/hooks/agent-scope-guard.sh"
echo "agent-setup: linked private agent files from $private"
hooks="$(git rev-parse --path-format=absolute --git-common-dir)/hooks"
hook="$hooks/post-checkout"
if [ -e "$hook" ] && ! grep -q 'tools/agent-setup.sh' "$hook"; then
  echo "agent-setup: $hook already exists, so new worktrees will not link the private files. Add a call to tools/agent-setup.sh to it." >&2
  exit 1
fi
mkdir -p "$hooks"
printf '%s\n' '#!/bin/sh' \
  '[ "$3" = 1 ] || exit 0' \
  'top="$(git rev-parse --show-toplevel)" || exit 0' \
  '[ -f "$top/tools/agent-setup.sh" ] || exit 0' \
  'cd "$top" && exec bash tools/agent-setup.sh' > "$hook"
chmod +x "$hook"
card_hook="$hooks/commit-msg"
if [ -e "$card_hook" ] && ! grep -q 'tools/update_cards.py' "$card_hook"; then
  echo "agent-setup: $card_hook already exists, so commits will not need a release note line. Add a call to tools/update_cards.py check to it." >&2
  exit 1
fi
printf '%s\n' '#!/bin/sh' \
  'head -n 1 "$1" | grep -q "^Merge" && exit 0' \
  'top="$(git rev-parse --show-toplevel)" || exit 0' \
  '[ -f "$top/tools/update_cards.py" ] || exit 0' \
  'files="$(mktemp)"' \
  'git diff --cached --name-only > "$files"' \
  'python3 "$top/tools/update_cards.py" check --body-file "$1" --files "$files"' \
  'status=$?' \
  'rm -f "$files"' \
  'exit $status' > "$card_hook"
chmod +x "$card_hook"

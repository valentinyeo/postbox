set -eu
root="$(git rev-parse --show-toplevel)"
private="${WAZIG_PRIVATE_DIR:-$HOME/projects/wazig-agent-skills/wazig-repo}"
if [ ! -d "$private" ]; then
  echo "agent-setup: no private companion repo at $private. Clone valentinyeo/wazig-agent-skills there or set WAZIG_PRIVATE_DIR." >&2
  exit 1
fi
mkdir -p "$root/.claude/hooks"
if [ -d "$root/.claude/skills" ] && [ ! -L "$root/.claude/skills" ]; then
  echo "agent-setup: $root/.claude/skills is a real folder. Move its changes to the private repo, delete it, then rerun." >&2
  exit 1
fi
ln -sfn "$private/CLAUDE.md" "$root/CLAUDE.local.md"
ln -sfn "$private/HANDOFF.md" "$root/HANDOFF.md"
ln -sfn "$private/board.yml" "$root/board.yml"
ln -sfn "$private/.claude/skills" "$root/.claude/skills"
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

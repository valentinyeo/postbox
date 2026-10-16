@AGENTS.md

## Work
- Board: Hypertask 4874 (WAZI), https://app.hypertask.ai/project?id=4874. Ticket: https://app.hypertask.ai/detail/project-4874/<number>.
- One git worktree per ticket under `~/projects/wazig-wt/<TICKET>`, branched from `origin/main`. Never edit or build in the main checkout.
- Ship through a PR with all checks green. `automerge.yml` merges green PRs unless they edit release-gating workflows; `auto-release.yml` tags and `release.yml` publishes.

## Build and test (Zig 0.16.0, on the VPS at `~/.local/zig-0.16.0/zig`; the `zig` on PATH is too old)
- `zig fmt --check src build.zig`
- `zig build test`
- `zig test src/stretch.zig`
- `python3 tools/check_new_comments.py origin/main`: CI fails a PR that adds code comments; put the why in the commit or PR.
- `zig build -Dtarget=x86_64-windows-gnu --release=small`
- `bash .claude/skills/evals/run-evals.sh` when `.claude/skills/` or `board.yml` changes.
- build.zig harnesses slice `src/main.zig` by text markers; editing near them breaks `unfurl-verification`.

## Agents owned by this repo
This repo owns the agent slugs `wazig-dev-1`..`wazig-dev-5`. The Hypertask team's agents are off-limits: `ht-bug-fixer`, `dev-2`..`dev-5`, `qa-agent`, `dev-glm` and `dev-glm-2`..`dev-glm-5`, `ht-manager`. `.claude/hooks/agent-scope-guard.sh` blocks Bash commands that reference them.

## Delivering releases to Valentin's PC (Valentin, 2026-10-10)
- Never stop or restart Messages on his main PC (P1) to install a release. Publish it; he installs it with the in-app update card's Update now button (shipped in v0.9.98).
- Test new functions on the X13s (`lh2`), or on the P1 only after he has updated.
- Never run a test copy of Messages (`WAZIG_FAKE_VERSION`, a scratch folder) on his visible screen.
- Never report a release as done without testing the new function on screen (keys, clicks, screenshots). `wazigctl status|chats|select|messages` reads app state without stealing focus.

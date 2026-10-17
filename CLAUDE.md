@AGENTS.md

## Work
- Board: Hypertask 4874 (WAZI), https://app.hypertask.ai/project?id=4874. Ticket: https://app.hypertask.ai/detail/project-4874/<number>.
- One git worktree per ticket under `~/projects/wazig-wt/<TICKET>`, branched from `origin/main`. Never edit or build in the main checkout.
- Ship through a PR with all checks green. `automerge.yml` merges green PRs unless they edit release-gating workflows; `auto-release.yml` tags and `release.yml` publishes.

## Build and test (Zig 0.16.0, on the VPS at `~/.local/zig-0.16.0/zig`; the `zig` on PATH is too old)
- `tools/preflight.sh`: the same format, test, Windows build and lint steps CI runs.
- `python3 tools/check_new_comments.py origin/main`: CI fails a PR that adds code comments; put the why in the commit or PR.
- `bash .claude/skills/evals/run-evals.sh` when `.claude/skills/` or `board.yml` changes.
- build.zig harnesses slice `src/main.zig` by text markers; editing near them breaks `unfurl-verification`.

## Agents owned by this repo
This repo owns the agent slugs `wazig-dev-1`..`wazig-dev-5`. The Hypertask team's agents are off-limits: `ht-bug-fixer`, `dev-2`..`dev-5`, `qa-agent`, `dev-glm` and `dev-glm-2`..`dev-glm-5`, `ht-manager`. `.claude/hooks/agent-scope-guard.sh` blocks Bash commands that reference them.

## Delivering releases to Valentin's PC (Valentin, 2026-10-17)
- Install every new release on his PC (P1) right away, without asking, unless he says not to: the update card's Update now, or the swap in HANDOFF.md.
- Then test the new function on the P1, or on the X13s (`lh2`) when it is online.
- Never run a test copy of Messages (`WAZIG_FAKE_VERSION`, a scratch folder) on his visible screen.
- Never report a release as done without testing the new function on screen (keys, clicks, screenshots). `wazigctl status|chats|select|messages` reads app state without stealing focus.

## Rules and what enforces them (WAZI-123)
| Rule | Enforced by |
|---|---|
| Format, tests and the Windows build pass before a push or PR | `.claude/hooks/preflight-guard.sh` blocks `git push` and `gh pr create/ready/merge`; CI runs the same `tools/preflight.sh` |
| The wacli worker keeps the job it dequeues; a full archive queue keeps the unarchive request | `tools/lint-repeats.sh` rules A1, A2 |
| Release workflows dispatch release.yml for bot tags, wait for GUI exes, end expected-exit-3 checks with `exit 0`, never use `gh api --slurp`; automerge never requires the AI `code-review` check; workflows never call OpenRouter or Z.ai, the AI review runs `tools/ai-review.sh` on Codex via hax on the self-hosted `wazig` runner | `tools/lint-repeats.sh` rules B1 to B6 |
| Each check still fails on the past commit it was written for | `tools/test-preflight-guard.sh`, `tools/test-lint-repeats.sh` in CI |

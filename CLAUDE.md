@AGENTS.md

## Work
- Private agent rules, board, skills and handoff live in a private companion repo. Run `bash tools/agent-setup.sh` once in the main checkout: it links them in as `CLAUDE.local.md`, `HANDOFF.md`, `board.yml` and `.claude/skills` (all gitignored) and installs a `post-checkout` hook, so every worktree cut from it is linked too and `git worktree add` fails if the private repo is missing. Never commit them back.
- Nothing that names a person's machines, servers, accounts or contacts goes in this public repo, its PR text or commit messages: the `private-markers` check fails on it.
- One git worktree per ticket under `~/projects/wazig-wt/<TICKET>`, branched from `origin/main`. Never edit or build in the main checkout.
- Ship: `tools/ship.sh <TICKET> "<what changed>"` runs preflight, pushes, opens the PR and waits for `automerge.yml` to merge it and `auto-release.yml`/`release.yml` to publish a release for app changes.

## Build and test (Zig 0.16.0, on the VPS at `~/.local/zig-0.16.0/zig`; the `zig` on PATH is too old)
- `tools/preflight.sh`: the same format, test, Windows build and lint steps CI runs.
- `python3 tools/check_new_comments.py origin/main`: CI fails a PR that adds code comments; put the why in the commit or PR.
- build.zig harnesses slice `src/main.zig` by text markers; editing near them breaks `unfurl-verification`.

## Rules and what enforces them (WAZI-123)
| Rule | Enforced by |
|---|---|
| Format, tests and the Windows build pass before a push or PR | `.claude/hooks/preflight-guard.sh` blocks `git push` and `gh pr create/ready/merge`; CI runs the same `tools/preflight.sh` |
| The wacli worker keeps the job it dequeues; a full archive queue keeps the unarchive request | `tools/lint-repeats.sh` rules A1, A2 |
| Release workflows dispatch release.yml for bot tags, wait for GUI exes, end expected-exit-3 checks with `exit 0`, never use `gh api --slurp`; automerge never requires the AI `code-review` check; workflows never call OpenRouter or Z.ai, the AI review runs from `tools/ai-review-poll.sh` (systemd user timer from `tools/systemd/`, clean checkout at `~/projects/wazig-review`) on Codex via hax and posts through `ai-review-post.yml`; no workflow runs on a self-hosted runner (B7) | `tools/lint-repeats.sh` rules B1 to B7 |
| A pasted file is routed by the chat's provider (D1, WAZI-101) | `tools/lint-repeats.sh` rule D1 |
| Anthropic and OpenRouter keys and the Telegram API hash load through `slack_win.loadSecret` (DPAPI, plain values migrate on start), never as plain registry strings (WAZI-137, WAZI-145) | `tools/lint-repeats.sh` rule C1 |
| Chat identities compare provider, account and jid with `chat_key.Key`, never two bare jids (WAZI-150) | `tools/lint-repeats.sh` rule E1 |
| No private markers in tracked files, PR title, PR body or PR commit messages; private agent files stay out of git | `tools/check_private_markers.py` in `private-markers.yml`, patterns from the `PRIVATE_MARKERS` secret (WAZI-138) |
| A dispatched auto-release waits for the running ci on main HEAD instead of refusing to tag | `tools/ci-green.sh` (WAZI-142) |
| Each check still fails on the past commit it was written for | `tools/test-preflight-guard.sh`, `tools/test-lint-repeats.sh`, `tools/test-ci-green.sh` in CI |
| New Actions run logs carry no private markers | `run-log-markers.yml` hourly, `tools/check_private_markers.py --logs` |

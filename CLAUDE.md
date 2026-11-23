@AGENTS.md

## Work
- Private agent rules, board, skills and handoff live in a private companion repo. Run `bash tools/agent-setup.sh` once in the main checkout: it links them in as `CLAUDE.local.md`, `HANDOFF.md`, `board.yml` and `.claude/skills` (all gitignored) and installs a `post-checkout` hook, so every worktree cut from it is linked too and `git worktree add` fails if the private repo is missing. Never commit them back.
- Nothing that names a person's machines, servers, accounts or contacts goes in this public repo, its PR text or commit messages: the `private-markers` check fails on it.
- One git worktree per ticket under `~/projects/wazig-wt/<TICKET>`, branched from `origin/main`. Never edit or build in the main checkout.
- Ship: `tools/ship.sh <TICKET> "<what changed>" "<card line>" "<proof: feature id or no user-visible change>"` runs light checks locally, pushes, opens the PR and waits for `automerge.yml` to merge it and `auto-release.yml`/`release.yml` to publish a release for app changes.

## Build and test
- Pushes and PR commands run `tools/preflight-light.sh` locally: fast static checks and Python/Node tooling tests with J2-enforced parity against CI Python discovery and reasoned heavy exclusions, with no Zig or Wine invocation. The private-marker scan runs when `PRIVATE_MARKERS` is available; CI always enforces it.
- GitHub CI runs the unchanged full `tools/preflight.sh` with Zig 0.16.0: format, tests, Windows builds and harnesses. Never run the full preflight on the shared build server.
- `node tools/strip-comments.mjs --check`: CI rejects code comments; put the why in the commit or PR.
- build.zig harnesses slice `src/main.zig` by text markers; editing near them breaks `unfurl-verification`.

## Rules and what enforces them (WAZI-123)
| Rule | Enforced by |
|---|---|
| PR bodies name a mapped feature proof or declare no user-visible change | `pr-proof` in `.github/workflows/pr-title.yml` and `tools/test-check-pr-proof.sh` |
| Palette commands have mapped proofs and verification gaps cannot increase | `tools/check-feature-map.sh` and `tools/test-check-feature-map.sh` |
| Pushes run only light checks locally; GitHub CI runs the full preflight. Never run full preflight on the shared build server (IGSH-518) | `.claude/hooks/preflight-guard.sh` and `tools/ship.sh` run `tools/preflight-light.sh`; `tools/test-preflight-guard.sh` rule J1 rejects full preflight and direct Zig calls in either entrypoint; rule J2 (IGSH-711) requires every CI-discovered Python test in the light list or a reasoned heavy-exclusion list; CI runs `tools/preflight.sh` |
| The wacli worker keeps the job it dequeues; a full archive queue keeps the unarchive request | `tools/lint-repeats.sh` rules A1, A2 |
| Automerge dispatches auto-release.yml after a merge and when self-healing a missing main run; release workflows dispatch release.yml for bot tags, wait for GUI exes, end expected-exit-3 checks with `exit 0`, never use `gh api --slurp`; automerge never requires the AI `code-review` check | `tools/lint-repeats.sh` rules B1 to B5 and B7 |
| Automerge waits for every non-AI check on the PR head, including unfurl-verification and the TDLib cache; missing, pending, skipped or failed checks block merging (IGSH-504) | `tools/lint-repeats.sh` rule B8 and `tools/test_no_comments.py` |
| A planted failure counts only with the journey's own failure marker (SOFT-2624) | `tools/verify-wazig/harness.ps1`, `tools/verify-wazig/run.ps1`, `tools/verify-wazig/classify_red.py`, `tools/verify-wazig/classify-red.ps1` and `tools/test_verify_failure_marker.py`; shared version pins in `.github/workflows/verify.yml` are checked by the same test |
| A release waits for recorded journey proof of every changed feature (SOFT-2595) | `tools/check_release_proof.py` in the `proof` job of `.github/workflows/release.yml`, `tools/test_release_proof.py` and `tools/lint-repeats.sh` rule B14 |
| Every workflow has a concurrency group that cancels superseded runs; release.yml never cancels a publish (SOFT-2596) | `tools/lint-repeats.sh` rule B15 |
| A scheduled `map-upkeep` run keeps one rolling issue for map drift and red nightly journeys, and closes it when clean (SOFT-2596) | `tools/test-map-upkeep.sh` and `.github/workflows/map-upkeep.yml` |
| Planted journey coverage cannot decrease and nightly verification retains its planted job (SOFT-2593) | `tools/check-planted.py`, `tools/test_check_planted.py` and `tools/lint-repeats.sh` rule B13 |
| PR journey verification runs on Windows before automerge for matching paths (SOFT-2591) | `tools/lint-repeats.sh` rule B11 |
| A journey already red on the default branch does not fail the pull request (SOFT-2904) | `tools/verify-wazig/preexisting.py` from `.github/workflows/verify.yml` and `tools/test_preexisting_journey.py` |
| Automerge only admits same-repository PRs by the repository owner (IGSH-635) | `tools/lint-repeats.sh` rule B9 and `tools/test_no_comments.py` |
| One verifier per pull request; `tools/ship.sh` refuses a pull request without `SHIP_AUTHOR_MODEL`; see pstack poteto-mode/playbooks/shipping.md step 1 (SOFT-2784) | `tools/verify-wazig/verifier.py` |
| A pasted file is routed by the chat's provider (D1, WAZI-101) | `tools/lint-repeats.sh` rule D1 |
| Anthropic, OpenRouter and Deepgram keys and the Telegram API hash load through `slack_win.loadSecret` (DPAPI, plain values migrate on start), never as plain registry strings; `DEEPGRAM_API_KEY` seeds from the user's saved environment (`HKCU\Environment`), never the inherited process environment, and refreshes encrypted storage when it changes (WAZI-137, WAZI-145, IGSH-470) | `tools/lint-repeats.sh` rules C1, C2 |
| Rounded shapes use `smooth_shapes.fillRoundRect` and friends with explicit colours and a paint-level Context, never raw GDI RoundRect, Ellipse or rounded regions anywhere in src (WAZI-159) | `tools/lint-repeats.sh` rule F1 |
| Chat identities compare provider, account and jid with `chat_key.Key`, never two bare jids (WAZI-150) | `tools/lint-repeats.sh` rule E1 |
| No private markers in tracked files, PR title, PR body or PR commit messages; private agent files stay out of git | `tools/check_private_markers.py` in `private-markers.yml`, patterns from the `PRIVATE_MARKERS` secret (WAZI-138) |
| A dispatched auto-release waits for the running ci on main HEAD instead of refusing to tag | `tools/ci-green.sh` (WAZI-142) |
| Build marker operations and Python files reading Zig source text must not increase | `tools/check-no-source-text-tests.sh` and `tools/test-check-no-source-text-tests.sh` |
| Empty catches in Zig source must not increase (SOFT-2509) | `tools/check-no-empty-catch.sh` and `tools/test-check-no-empty-catch.sh` |
| Numeric literals in `draw*` and `paint*` functions in `src/main.zig` must not increase; put layout numbers in `src/box_layout.zig` or `src/quote_layout.zig` (SOFT-2508) | `tools/check-no-new-pixel-numbers.sh` and `tools/test-check-no-new-pixel-numbers.sh` |
| A typical PR starts at most 19 jobs; merge small checks into one job instead of adding one (SOFT-2765) | `tools/check_job_budget.py`, `tools/lint-repeats.sh` rule B18 and `tools/test_job_budget.py` |
| A bug-fix PR names the merged revert that landed first, or gives a reason none was needed (SOFT-2766) | `tools/check_revert_first.py` in the `pr-title` job, `tools/lint-repeats.sh` rule B19 and `tools/test_revert_first.py` |
| The send queue and transcription retry models match the code they cover: a covered function cannot change until its model is reviewed and the hashes are recorded (SOFT-2769) | `tools/formal/check_formal.py` in both preflights; `--tlc` runs the models and every broken variant |
| Each check still fails on the past commit it was written for | `tools/test-preflight-guard.sh`, `tools/test-lint-repeats.sh`, `tools/test-ci-green.sh` in CI |
| New Actions run logs carry no private markers | `run-log-markers.yml` hourly, `tools/check_private_markers.py --logs` |
| The video tool installs through one retrying script that fails when ffmpeg is missing (SOFT-2677) | `tools/test_install_ffmpeg.py` and `tools/verify-wazig/install-ffmpeg.ps1` |
| A file under `.github/` or `tools/` calls a hosted model API only when `.github/ladder-call-allow` lists that path with a reason and an unexpired date | `tools/check-ladder-calls.py` and `tools/test-check-ladder-calls.sh` |

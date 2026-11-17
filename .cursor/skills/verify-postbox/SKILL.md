---
name: verify-postbox
description: Drive Postbox's native Windows UI on GitHub Actions. Use for the shared verification gate and retained desktop evidence.
---

# Verify Postbox

**Launch:**

Use GitHub-hosted Windows, never this Linux server.
The existing harness owns launch and isolation.
Read [its instructions](../../../.claude/skills/verify-wazig/SKILL.md).

Build on the hosted runner:

```powershell
zig build -Dtarget=x86_64-windows-gnu --release=small -Dversion=0.0.526
pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature search -Bin zig-out/bin -Evidence verification-evidence -ExpectedVersion 0.0.526
```

The runner installs Zig 0.16.0 first.
The harness starts real `Messages.exe --verify-fixture`.
It creates two synthetic cached chats.
It isolates profiles, registry settings, and control pipes.
It blocks live providers, sync, and updates.
Only production provider boundaries use fixture data.
Ready requires `DOCTOR PASSED` and enabled composer `1032`.
A living process alone proves nothing.

Dispatch the retained desktop workflow:

```sh
gh workflow run verify-desktop.yml --ref verify-gate -f feature=search -f repeat=1
gh run list --workflow verify-desktop.yml --branch verify-gate --limit 5
gh run watch RUN_ID --interval 30 --exit-status
gh run download RUN_ID --name verify-wazig-search --dir evidence/RUN_ID
```

GitHub dispatch requires the workflow on main first.
During bootstrap, `verify-adoption.yml` runs the search journey.
Never substitute an older main run.

**Doctor:**

On the same hosted Windows instance:

```powershell
pwsh -NoProfile -File tools/verify-wazig/doctor.ps1 -Evidence verification-evidence
```

Doctor checks recorded PID, start time, and executable.
It checks SHA256, window identity, and expected version.
It requires stopped sync and empty pending queues.
It reads `wazigctl status` without changing application state.
After cleanup, doctor must fail.

**Drive:**

The search journey uses UIA and real SendKeys.
It opens Ctrl+F and searches for Beta.
It compares slash search with Ctrl+F search.
It presses Escape and checks restored results.
Palette edit uses AutomationId `1064`.
Chat list uses `1016`; composer uses `1032`.
Read [the actual recipe](../../../tools/verify-wazig/journey-search.ps1).
Custom painted rows require screenshots as evidence.
Do not replace actions with pipe mutations.

The [entry inventory](features/README.md) lists source sites.
The existing journey registry identifies executable journeys.
Inventory entries do not imply completed journeys.
No routes exist in this native desktop application.
The eleven IPC endpoints belong to postboxctl.

**Evidence:**

Keep action logs, before/after screenshots, and state snapshots.
Inspect the screenshots, including visible search results.
Check restored search state and captured side effects.
Keep `session.json`, `doctor.json`, and `cleanup.txt`.
Evidence survives outside the deleted scratch profile.

The shared gate needs `pstack-verification` separately.
Its manifest needs digests and current-head identity.
It also needs an independent different-family verdict.
Current desktop artifacts alone cannot satisfy that contract.
No synthetic verdict or attestation substitutes for execution.

Production profile counts remain unavailable here.
Legacy Slack installations reserve 256 chat slots.
The active message buffer holds 1,000 messages.
The combined chat list grows dynamically.
Two synthetic chats do not prove production scale.
The verifier must report observed counts and relevance.
Release still lacks current-head video or trace proof.
Publishing jobs still need release gate dependencies.

**Cleanup:**

```powershell
pwsh -NoProfile -File tools/verify-wazig/cleanup.ps1 -Evidence verification-evidence
```

Cleanup runs after success and failure.
It checks ownership before stopping recorded processes.
It removes owned profile and registry scratch state.
It preserves copied data and evidence artifacts.
Never kill processes by name.

**Helpers:**

```sh
python3 tools/verify-postbox-map.py
python3 tools/verify-postbox-map.py --write
python3 tools/verify-postbox-map.py --json
```

The helper checks bounded Zig entry patterns.
It does not implement the shared Zig adapter.
Unsupported source keeps the shared gate failing.
Custom handlers still require semantic coverage review.
Run `/maintain-verification-skill` when entry points change.

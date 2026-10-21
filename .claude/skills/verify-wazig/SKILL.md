---
name: verify-wazig
description: Verify the Wazig Messages native Windows desktop through real keyboard input and UI Automation on GitHub Actions; use for UI regressions, user journeys and screenshot evidence without real provider accounts.
---

# Verify Wazig Messages

## Launch

Run only on GitHub-hosted Windows, never on a workstation or shared build host:

```sh
gh workflow run verify.yml -f feature=search
gh run list --workflow verify.yml --event workflow_dispatch --limit 5
gh run watch <id> --interval 60 --exit-status
gh run download <id> --name verify-wazig-search --dir evidence/<id>
```

Replace `search` with a [feature ID](features/README.md). Confirm the run's branch and commit before trusting it. Dispatch requires this workflow on the default branch. Before merge, the retained `pull_request` paths trigger runs the default `search` journey, including changes to this skill, the helper or the app source. Watch that PR run instead; do not pretend a dispatch ran on an unregistered workflow.

`verify.yml` installs Zig 0.16.0 and builds `Messages.exe`, `wazigctl.exe` and bundled IBM Plex fonts with the same Windows `--release=small` build used by ci.yml's unfurl-verification job. The evidence build version is `0.0.526`; this base desktop build does not include TDLib. It does not download or install wacli, authenticate a provider, or install the app. No provider or media transport is verified here.

The workflow runs `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature search -Bin zig-out/bin -Evidence verification-evidence`. It starts the real `Messages.exe --verify-fixture` with a fresh GUID directory under `RUNNER_TEMP`. Two entirely synthetic local cached chats, `Verification Alpha` and `Verification Beta`, load through the production cache parser. They contain no messages. Ready means a `MessagesZig` window titled `Wazig Messages v0.0.526`, an enabled composer, and `DOCTOR PASSED` in the log, not merely a living process.

The flag requires `GITHUB_ACTIONS=true`, isolated `LOCALAPPDATA` and `USERPROFILE`, and a new verification registry key. Process-local HKCU redirection keeps saved settings and secrets separate. A unique `USERNAME` also isolates the control pipe; the outbox mutex already keys on the data directory. Provider workers, authentication probes, Telegram initialization, sync and updater checks are disabled. This is launch-time fixture seeding, not an endpoint that sets the result of the journey. Normal launches are unchanged.

## Doctor

The launch helper runs the read-only doctor before input. On the same GitHub runner, to recheck its owned session:

```powershell
pwsh -NoProfile -File tools/verify-wazig/doctor.ps1 -Evidence verification-evidence
```

This checks PID plus start time, absolute executable path and SHA-256, exact build title/version, UI Automation process and class, readable search edit `1008`, enabled composer `1032`, stopped sync and no pending sends/archives. It reads `wazigctl status`; it never uses a control command to change state. `doctor.json` records the observed app state. A failed doctor invalidates the journey; fix launch rather than driving another window. The process lasts only for the workflow's drive step, so running doctor after cleanup must fail.

## Drive

Harness: **PowerShell UI Automation + SendKeys**. UI Automation resolves native controls by AutomationId; bounded read-only `WM_GETTEXT` reads their text because these subclassed edits do not expose ValuePattern; keyboard input goes through Windows Forms `SendKeys.SendWait` after checking foreground-process ownership. No `WM_COMMAND`, text-setting window message, internal state setter, control-client mutation or coordinate click replaces the user action. Palette rows and the message canvas are custom drawn; do not invent accessible row names. Filter the palette with its actual label and press Enter. Screenshots are the visual oracle for custom-drawn content.

Select one recipe via `feature=search|navigation|drafts|palette|appearance`. Each recipe starts from its own empty fixture profile. See the feature map for exact shortcuts, entry points, assertions and limitations. The helper logs every keyboard action and waits on resulting readable state rather than accepting a fixed delay as proof. Read-only `wazigctl status` supplements screenshots; it is not the driving harness.

## Evidence

Artifacts are uploaded as `verify-wazig-<feature>` even after failure. `verification-evidence/` contains:

- `before.png`, `after.png`, UI Automation trees and read-only state snapshots; search also captures `empty.png`, palette/appearance capture `action.png`.
- `actions.log`, `run.log`, `doctor.json`, `session.json` with build hash/revision, and `result.txt` or `failure.txt`.
- `side-effects.json`: no pending sends/archives, sync stopped; fixture storage unchanged, no WhatsApp or Telegram store created.
- `final-data/`, `preferences.txt` when settings exist, and `cleanup.txt`; drafts additionally copy `drafts.json` before cleanup.

Download and **look at** before and after screenshots. Require the app title, actual action and resulting visible state, plus the corresponding logged/read-only assertion. A green exit or a final screenshot alone is insufficient. Check search removal/restoration or per-chat draft persistence alongside visible results. Reject blank/obscured screenshots. An absent provider account is deliberate; never call a skipped send, media download, transcription or login verified. Never substitute test-only setters. Only the provider data boundary is fixture-backed; the UI path is production code.

## Cleanup

The drive's `finally` and the workflow's `always()` step both invoke:

```powershell
pwsh -NoProfile -File tools/verify-wazig/cleanup.ps1 -Evidence verification-evidence
```

Cleanup closes only the recorded PID after verifying start time/path/hash, waits for exit, then force-stops only that PID if necessary. It copies local data to evidence before removing the owned GUID data directory and registry subtree. `cleanup.txt` asserts that process, scratch data and scratch registry are gone. Evidence lives outside scratch data and survives cleanup. Never kill by process name, delete evidence, use a real account or reuse another session's manifest.

## Helpers

All helpers are repository-owned PowerShell scripts executed explicitly with `pwsh -NoProfile -File`; no execution-policy changes or installed runtime are needed on Windows Actions. `run.ps1`, `doctor.ps1` and `cleanup.ps1` invocations are above. `harness.ps1` is their shared library, dot-sourced by those entry points, not a separate launcher. Launch/Drive are GitHub-only, even when an agent has access to another Windows machine.

Read-only validators (no app launch): `python3 tools/verify-wazig/check-map.py` checks map structure and source labels; `python3 tools/verify-wazig/check-evidence.py evidence/<id>` checks downloaded search evidence, state transitions and surviving proof files. On Windows Actions use `python` in place of `python3`. Artifact validation does not replace looking at the images. Launch also writes `launch-guards.log`, proving that non-Actions and non-isolated fixture launches are rejected, and checks that the runner's production preferences are never created.

Maintain the map when shortcuts or commands change; `/maintain-verification-skill` is the maintenance loop.

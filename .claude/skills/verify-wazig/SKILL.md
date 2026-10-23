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

Replace `search` with a [feature ID](features/README.md). Confirm the run's branch and commit before trusting it. Dispatch requires this workflow on the default branch. Before merge, the retained `pull_request` path triggers run the `paste-image`, `reactions`, `menus`, `search`, `drafts`, `whatsapp-hub`, `hub`, `hub-archive`, `palette-archived`, `slack-sort`, `slack-archive`, `slack-threads`, `views`, `workspace-icons`, `signal`, `telegram`, `repaint`, `voice` and `text-comparison` journeys, including changes to this skill, the helper or the app source, for the source and helper paths listed in `verify.yml`. Watch that PR run instead; do not pretend a dispatch ran on an unregistered workflow.

`verify.yml` installs Zig 0.16.0 and builds `Messages.exe`, `wazigctl.exe` and bundled IBM Plex fonts with the same Windows `--release=small` build used by ci.yml's unfurl-verification job. The workflow pins the evidence build to `0.0.526` (not the default or release version); this base desktop build does not include TDLib. It does not download or install wacli, authenticate a provider, or install the app. The `whatsapp-hub` journey additionally verifies the production HTTPS backend against an authenticated loopback fake bridge; it never contacts a real provider. Loopback HTTP is allowed only inside the guarded verification fixture.

The workflow runs `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature search -Bin zig-out/bin -Evidence verification-evidence`. It starts the real `Messages.exe --verify-fixture` with a fresh GUID directory under `RUNNER_TEMP`. Two entirely synthetic local cached chats, `Verification Alpha` and `Verification Beta`, load through the production cache parser. They initially contain no messages except for menus, which seeds one synthetic cached message, and text-comparison, which loads `src/verify_text.json` through the guarded fixture; archive adds an incoming fixture message. Ready means a `MessagesZig` window titled `Wazig Messages v0.0.526`, an enabled composer, and `DOCTOR PASSED` in the log, not merely a living process.

The flag requires `GITHUB_ACTIONS=true`, isolated `LOCALAPPDATA` and `USERPROFILE`, and a new verification registry key. Process-local HKCU redirection keeps saved settings and secrets separate. A unique `USERNAME` also isolates the control pipe; the outbox mutex already keys on the data directory. Local provider workers, authentication probes, Telegram initialization, sync and updater checks are disabled. The `whatsapp-hub`, `hub`, `hub-archive`, `slack-sort`, `slack-archive`, `slack-threads`, `views`, `workspace-icons`, `signal`, `telegram` and `reactions` journeys enable the hub worker and SSE reader, using the isolated registry `WaBridgeUrl` and a fake DPAPI `WaBridgeKey`. This is launch-time fixture seeding, not an endpoint that sets the result of the journey. Normal launches are unchanged. The five original recipes use only launch-time fixture seeding. Archive additionally uses an isolated file-backed provider at the enqueue/archive transport boundary; it supplies incoming messages and archive acknowledgements to the production merge path.

## Doctor

The launch helper runs the read-only doctor before input. On the same GitHub runner, to recheck its owned session:

```powershell
pwsh -NoProfile -File tools/verify-wazig/doctor.ps1 -Evidence verification-evidence
```

This checks PID plus start time, absolute executable path and SHA-256, exact build title/version, UI Automation process and class, readable search edit `1008`, enabled composer `1032`, stopped sync and no pending sends/archives. It reads `wazigctl status`; it never uses a control command to change state. `doctor.json` records the observed app state. A failed doctor invalidates the journey; fix launch rather than driving another window. The process lasts only for the workflow's drive step, so running doctor after cleanup must fail.

## Drive

Harness: **PowerShell UI Automation + SendKeys**. UI Automation resolves native controls by AutomationId; the `RICHEDIT50W` DirectWrite hosts expose UIA ValuePattern, checked against bounded read-only `WM_GETTEXT` reads; keyboard input goes through Windows Forms `SendKeys.SendWait` after checking foreground-process ownership. Menus additionally uses owned-control UIA bounds and Win32 `SendInput` for real mouse clicks and text-selection dragging. No `WM_COMMAND`, text-setting window message, internal state setter, control-client mutation or coordinate click replaces the user action. Palette rows and the message canvas are custom drawn; do not invent accessible row names. Filter the palette with its actual label and press Enter. Screenshots are the visual oracle for custom-drawn content.

Select one recipe via `feature=paste-image|search|navigation|drafts|palette|appearance|menus|reactions|whatsapp-hub|hub|hub-archive|palette-archived|slack-sort|slack-threads|views|workspace-icons|signal|telegram|repaint|voice|archive|text-comparison|window`. Each recipe starts from its own fresh isolated fixture profile. See the feature map for exact shortcuts, entry points, assertions and limitations. The helper logs every keyboard action and waits on resulting readable state rather than accepting a fixed delay as proof. Read-only `wazigctl status` supplements screenshots; it is not the driving harness.

## Evidence

Artifacts are uploaded as `verify-wazig-<feature>` even after failure. `verification-evidence/` contains:

- `before.png`, `after.png`, UI Automation trees and read-only state snapshots; search also captures `empty.png`, palette/appearance/archive capture `action.png`; archive also captures `kept.png`, `inbox.png` and visible-chat snapshots.
- Palette retains `removed-status.json` and `removed-status.png`: one positive shortcut row, zero Status results and no former sidebar control. Appearance retains `text-scale.json` and `text-larger.png`: keyboard growth saves 92%, Ctrl+0 restores 82%.
- Text comparison retains `text-metrics.json`, `chrome.json`, matching font files/license, `wazig.png`, `chrome.png`, paragraph crops at 1x/3x and `text-comparison.png`; `check-text-comparison.cjs` validates fixture and font hashes plus metrics, not pixel equality.
- Menus captures named `amoled-*-before.png` / `amoled-*-after.png` pairs, `green-chat-before.png` / `green-chat-after.png`, `theme-green-action.png` and `menu-luminances.json` with screenshot pixel measurements and thresholds. Before means the popup closed; after means the actual open popup, not a historical app build.
- `actions.log`, `run.log`, `doctor.json`, `session.json` with build hash/revision, and `result.txt` or `failure.txt`.
- `side-effects.json`: no pending sends/archives, local sync stopped; fixture storage unchanged except for archive, no WhatsApp or Telegram store created. The hub journey intentionally updates its separate hub cache.
- Reactions retains `react-requests.jsonl`, `reaction-clicks.json`, and `whatsapp-before/after.png` / `slack-before/after.png`: the open message menu and the resulting laughing-face chip, driven with real SendInput on both providers.
- Hub journeys: `bridge-requests.jsonl`, `hub-proof.log`, history/live message snapshots and additional screenshots. Chat-switch additionally requires `before-beta.requests.json` (no Beta history request yet), `beta-switch.json` (selection and elapsed time at most 1000 ms), `beta-empty.messages.json` (Beta identity with zero messages), `beta-empty.png` and state/UIA snapshots, then `beta.messages.json` / `beta.png` with Beta's own history. The first Beta history reply is delayed three seconds; read-only control calls share a one-second deadline after keyboard input returns, so waiting for that reply cannot hide stale Alpha messages. A simulated lost send response must retry the same outbox ID with one accepted delivery, SSE must resume IDs 1 and 2, and media must return 202 then cached bytes.
- `final-data/`, `preferences.txt` when settings exist, and `cleanup.txt`; drafts additionally copy `drafts.json` before cleanup and save `composer-one-box.log` plus `composer-{amoled,green}-{wide,narrow}-{one,multiline}` screenshots, layout bounds, UI Automation trees and state snapshots; archive retains `incoming-provider.json`, `kept-archive-state.txt` and final provider data.
- Window retains `window.json`, `start-1.png`, `restored.png`, `start-2.png` and `start-3.png`: native zoomed states and monitor/normal rects across keyboard restore, Alt+F4 and same-profile normal/update relaunches. See [Window](features/window.md).

Download and **look at** before and after screenshots. Require the app title, actual action and resulting visible state, plus the corresponding logged/read-only assertion. A green exit or a final screenshot alone is insufficient. Check search removal/restoration or per-chat draft persistence alongside visible results. Reject blank/obscured screenshots. An absent provider account is deliberate; never call a skipped send, media download, transcription or login verified. Never substitute test-only setters. Only the provider data boundary is fixture-backed; the UI path is production code.

- Paste-image retains full-screen/4K uploads, sizes.json with decoded dimensions and RGBA samples, and staged/sent screenshots on all four providers. See [Clipboard images](features/paste-image.md).

## Cleanup

The drive's `finally` and the workflow's `always()` step both invoke:

```powershell
pwsh -NoProfile -File tools/verify-wazig/cleanup.ps1 -Evidence verification-evidence
```

Cleanup also stops the recorded fake bridge, when present, after checking its PID, start time and executable. It closes only the recorded app PID after verifying start time/path/hash, waits for exit, then force-stops only that PID if necessary. It copies local data to evidence before removing the owned GUID data directory and registry subtree. `cleanup.txt` asserts that process, scratch data and scratch registry are gone. Evidence lives outside scratch data and survives cleanup. Never kill by process name, delete evidence, use a real account or reuse another session's manifest.

The `signal` journey uses the unified hub fixture to observe QR linking before account chats, then text, files, reactions, read receipts, media, live updates and terminal Signal failures. See [Signal](features/signal.md) and the [rule map](RULE-MAP.md).

## Helpers

The launch, doctor and cleanup helpers are repository-owned PowerShell scripts executed explicitly with `pwsh -NoProfile -File`; no execution-policy changes are needed. The hub fixture additionally uses the GitHub runner’s Python installation, never a bundled app runtime. `run.ps1`, `doctor.ps1` and `cleanup.ps1` invocations are above. `harness.ps1` is their shared library, dot-sourced by those entry points, not a separate launcher. Launch/Drive are GitHub-only, even when an agent has access to another Windows machine.

Read-only validators (no app launch): `python3 tools/verify-wazig/check-map.py` checks map structure and source labels; `python3 tools/verify-wazig/check-evidence.py evidence/<id>` checks downloaded paste-image, search, palette, appearance, menus, reactions, hub, slack-sort, slack-archive, views, workspace-icons, signal, telegram, archive or window evidence, state transitions and surviving proof files. On Windows Actions use `python` in place of `python3`. Artifact validation does not replace looking at the images. Launch also writes `launch-guards.log`, proving that non-Actions and non-isolated fixture launches are rejected, and checks that the runner's production preferences are never created.

Maintain the map when shortcuts or commands change; `/maintain-verification-skill` is the maintenance loop.

The IGSH-531 `hub` journey seeds WAZIG_HUB_URL and WAZIG_HUB_TOKEN only in the isolated child process, stores HubToken with DPAPI, and verifies source-network labels through the unified `/v1/wazig` API. See [hub](features/hub.md) for the frozen client contract and its backend limitations.

The `slack-sort` journey proves Slack last message ordering, unknown times last and incoming/sent promotion with the unified fake hub. Its result.json records passed/failed; see [slack-sort](features/slack-sort.md).

The `views` journey uses four synthetic source accounts, per-account keyboard navigation and search, a scoped send, combined ordering and a same-profile restart after sorting. Its explicitly opted-in restart reuses only the isolated Actions registry subtree; ordinary fixture launches still require a new subtree.

The `workspace-icons` journey verifies workspace icon colours, missing-icon S, the green WhatsApp handset and the blue Signal speech bubble from the full chat-list screenshot and per-badge crops, then validates authenticated per-team fetches and persistent avatar cache bytes. See [workspace-icons](features/workspace-icons.md).

The `telegram` journey verifies the hub-only account view, QR/password linking, Saved Messages, replies and existing hub messaging actions, plus visible terminal rate limits. See [Telegram](features/telegram.md). No direct TDLib sign-in is used.

The `hub-archive` journey seeds legacy WhatsApp keep state before hub launch, requires hub re-archive and durable keep state, then repeats incoming archived=false across a same-profile restart. See [Hub archive](features/hub-archive.md).

The `palette-archived` journey seeds archived WhatsApp, Telegram and Slack chats on the unified fake hub and requires Ctrl+K to find them, and every inbox chat, from every view, with Enter opening an archived result without a hub archive write. See [Palette archived](features/palette-archived.md).

The `repaint` journey uses the unified fake hub for 60 seconds without input: unchanged baseline updates every two seconds and incoming messages in the non-selected chat every ten seconds. `paints.json`, before/after chat snapshots and screenshots prove arrival and at most three full-surface repaints. Windows CI must demonstrate the instrumentation-only commit fails and the fix passes.

The `voice` journey opens a synthetic WhatsApp chat with five downloaded voice notes and long cached transcripts, scrolls with the wheel, clicks Show more and scrolls again. After each step it repaints only the voice bubbles, as the playback timer does, and requires the canvas pixels to match a full repaint, with no ink outside bubbles, no overlaps, visible time stamps and player circles inside their own bubbles. See [voice](features/voice.md).

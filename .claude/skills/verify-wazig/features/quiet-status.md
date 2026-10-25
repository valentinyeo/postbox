# Quiet sidebar and version discovery

## Sub-features

- `quiet-status-removed`: no native status control, label, tooltip, click action or reserved list space.
- `quiet-status-version`: Ctrl+K, version finds exactly the former reassurance text with the running version.
- `quiet-status-problem`: failed hub chat synchronization reaches the existing native Messages problem-dialog surface.

## How to get to it (user POV)

The list occupies the entire left column below search unless the existing update card is offered. Ctrl+K, version shows `You are on v<version> - this is the newest version`; Enter only closes the palette. Sync failures use a native Messages dialog. The new-version update card is unchanged.

## Driving it with PowerShell UI Automation

Dispatch `feature=quiet-status`. The unified fake hub supplies two chats. Require two native list rows as a positive control; reject UIA and native control 1048, reassurance/sync labels and a list bottom short of the client bottom. Real mouse hover/click at the former status position must preserve selection, views and writes, without any status tooltip or popup. Retain quiet-status.json and screenshots. Ctrl+K first requires the readable Keyboard shortcuts row, then version requires exactly one row with the exact version from read-only app state; retain version.json and version.png. Force HTTP 503 on real hub chat reads through an authenticated fixture endpoint, use the real Refresh palette command, and require an owned #32770 dialog with the exact existing failure text. Retain sync-problem.json, sync-problem.png, UIA snapshots and bridge-requests.jsonl. Recover the fixture before dismissing the dialog with real keyboard input. The registry validator rejects missing proof and checks isolation and cleanup.

## Gotchas

Run only on GitHub-hosted Windows. No real accounts, local provider worker, updater or installation is used. This journey proves a hub sync-read failure, not a live-provider outage, updater download or update installation. Source guards independently keep existing update-card layout/rendering/actions byte-identical to the parent. A pre-fix branch with assertions only must fail the status-control assertion; a green Windows run and screenshot inspection remain required after the helper handoff.

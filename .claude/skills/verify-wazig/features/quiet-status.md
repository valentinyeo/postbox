# Quiet sidebar and version discovery

## Sub-features

- `quiet-status-removed`: no native status control, label, tooltip, click action or reserved list space.
- `quiet-status-version`: Ctrl+K, version finds exactly the former reassurance text with the running version.
- `quiet-status-problem`: failed hub chat synchronization reaches the existing sidebar update-card error surface.

## How to get to it (user POV)

The list occupies the entire left column below search unless the existing update card is offered. Ctrl+K, version shows `You are on v<version> - this is the newest version`; Enter only closes the palette. Sync failures persist in the existing sidebar update card without a modal dialog. The new-version update card is unchanged.

## Driving it with PowerShell UI Automation

Dispatch `feature=quiet-status`. The unified fake hub supplies two chats. Require two native list rows as a positive control; reject UIA and native control 1048, reassurance/sync labels and a list bottom short of the client bottom. Real mouse hover/click at the former status position must preserve selection, views and writes, without any status tooltip or popup. Retain quiet-status.json and screenshots. Ctrl+K first requires the readable Keyboard shortcuts row, then version requires exactly one row containing the exact running version. Force authenticated `/fixture/sync-failure`, invoke Refresh through the real palette, and require a logged `/v1/wazig/chats` HTTP 503. Read-only status must report the existing update card visible with positive span and the exact `Unable to read chats from wacli` error; native list bounds must leave its existing clearance. Reject any owned #32770 dialog. Capture sync-problem.png, open the palette again to prove it remains usable, then Escape closes the palette while the same error remains in the card. Retain the card state, geometry, absent-dialog result and request proof in sync-problem.json; both sync-problem and after state snapshots must agree. Recover the fixture before cleanup. Inspect both screenshots for the actual drawn failure text; read-only state alone does not prove pixels.

## Gotchas

Run only on GitHub-hosted Windows. No real accounts, local provider worker, updater or installation is used. This journey proves a hub sync-read failure, not a live-provider outage, updater download or update installation. Source guards independently keep existing update-card geometry, drawing styles and actions byte-identical to the parent, allowing only removal of pending-update suppression for errors. A pre-fix branch with assertions only must fail the status-control assertion; a green Windows run and screenshot inspection remain required after the helper handoff.

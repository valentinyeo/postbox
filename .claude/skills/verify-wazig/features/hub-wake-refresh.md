# Hub wake, safety refresh and the sync line

## Sub-features

- `sync-line`: the chat header shows `Up to date · <HH:MM>` once a chat pull has landed within the last three minutes, `Offline · last sync <HH:MM>` when the live connection is down and `Catching up…` before the first pull lands (`sync_line.classify` in `src/sync_line.zig`, `updateSyncLine` in `src/main.zig`).
- `retry-backoff`: a dropped event stream reconnects after 1000 ms, then 2000, then 4000, and the table continues to 30 s (`src/sync_gate.zig:hub_reconnect_backoff_ms`); the journey requires those first three waits, each logged once (`hubReconnectWaitMs` in `src/sync_gate.zig`).
- `wake-resume`: with SSE live events muted and a new fixture row only on the HTTP API, a Windows `WM_POWERBROADCAST` resume notification loads `POLL-ROW` within fifteen seconds.
- `safety-poll`: with the same mute, after sixty-five seconds without SSE the app issues another authenticated `/v1/chats` pull and keeps messages current (`hubSafetyPollDue` in `src/sync_gate.zig`).

## How to get to it (user POV)

Leave Postbox open and let the machine sleep. On wake the chat list catches up on its own, and a new message that arrived while it was asleep appears without pressing Refresh. The chat header keeps saying how fresh the inbox is: `Up to date 14:32` while live, and `Offline` with the time of the last successful pull when the connection is gone. Nothing here needs a menu.

## Driving it with PowerShell UI Automation

Run `feature=hub-wake-refresh`, or `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature hub-wake-refresh` on GitHub-hosted Windows. The registry starts the legacy wa-bridge fixture, which exposes `/fixture/mute-sse`, `/fixture/drop-events`, `/fixture/restore-events` and `/fixture/stale-row`.

The journey first reads the sync line through the chat canvas bounds and requires `Up to date` followed by the exact `HH:MM` the app reports, then drops the event stream through the fixture and requires `Offline` with the last sync time still present, the three retry waits 1000, 2000 and 4000 ms logged once each in order, and the line back to `Up to date` after the stream is restored. It then sends the real resume notification to the owned window and requires `POLL-ROW` within fifteen seconds, and finally waits out sixty-five seconds with SSE still muted and requires one further authenticated `/v1/chats` pull.

Prepare sets `WAZIG_VERIFY_HUB_STALE=1` so the resume notification backdates inbox freshness once, without a startup timer racing the resume gate. Retain `sync-line.json`, `wake-resume.json`, `safety-poll.json`, `poll.messages.json`, the sync-line screenshots and the `hub-proof.log` gates `sync-line`, `retry-backoff`, `wake-resume` and `safety-poll`.

## Gotchas

- The journey sends the real resume notification to the owned app window, including when testing the base binary.
- Safety poll proof sleeps sixty-five seconds; the CI timeout must stay above that.
- The fixture used here is the legacy bridge, not the unified hub, so the sync line and wake behaviour are proven against that transport only.
- The retry waits are read from the launch log, so a rotated or truncated log makes the backoff assertion fail rather than pass.

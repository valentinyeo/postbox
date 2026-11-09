# Also send a thread reply to the chat

## Sub-features

- A custom drawn checkbox under the Slack thread reply box reads "Also send to <chat name>". It exists only for a Slack chat served by the unified hub.
- It starts unticked, ticks with a click or with Tab then Space or Enter, and resets to unticked after every send.
- A ticked send carries `reply_broadcast: true` through the outbox, the unified snapshot and the hub request. An unticked send omits the field, so old files and old hubs see the same bytes as before.

## How to get to it (user POV)

- Open a Slack chat with Alt+2, select a thread parent and press Enter to open the thread panel.
- Tab from the reply box to the checkbox and press Space, or click it. Tab again returns to the reply box.
- Type and press Enter. The reply goes into the thread and, when ticked, into the main chat too.

## Driving it with PowerShell UI Automation

- Run `feature=slack-thread-broadcast` on GitHub Actions only, using the unified fake hub in `--slack-thread-broadcast` mode.
- The journey opens the thread of parent `1740000000.000100`, waits for read-only `slack_threads.broadcast_shown`, and saves `broadcast-unticked.png/json` with the label "Also send to Verification Threads".
- It sends an unticked reply and requires the POST body to have no `reply_broadcast`. Then real Tab and Space tick the box, and `broadcast-ticked.png/json` is saved with `broadcast_checked` true.
- Tab returns to the reply box. Typing and Enter send a ticked reply. The POST body must carry `reply_broadcast` true, and `broadcast-reset.png/json` must show the box unticked again.
- After the palette command Refresh, `broadcast-messages.json` must hold the reply once in the thread (quoted parent) and once at channel level. `broadcast-thread-result.png` shows the open panel, `broadcast-chat-result.png` the chat after Escape.
- `check-slack-thread-broadcast-evidence.py`, dispatched by `check-evidence.py`, cross-checks measurements, screenshots, transport, action log and isolation.

## Gotchas

- The flag is hub only. The direct Slack send path is not used by the app, so the checkbox is not offered without the unified hub.
- The hub service must accept the optional `reply_broadcast` field on `POST /v1/wazig/send`. The fixture models a hub that answers with the reply in the thread and a second channel-level row; a real hub may return one row, which the client groups by the quote chain.
- Synthetic data proves the client contract, not a live Slack service. Inspect the screenshots before claiming rendered behavior.
- Only real foreground-checked SendKeys drives this recipe; UIA and wazigctl are read-only observers.
- Source: `src/main.zig` (checkbox window, layout, send), `src/outbox.zig`, `src/unified_snapshot.zig`, `src/hub.zig`.
- Journey: `tools/verify-wazig/slack-thread-broadcast.ps1`; evidence: `tools/verify-wazig/check-slack-thread-broadcast-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

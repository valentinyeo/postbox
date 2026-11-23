# Read ticks

## Sub-features

- A mark sits below your newest own bubble once the other person read it: a blue double tick (`design.provider_colors.telegram`, `#2AABEE`) followed by the word `Read` in the small grey timestamp style, right-aligned with the bubble's right edge.
- The mark never covers bubble text, emoji or a reaction chip. The message row reserves its own vertical space, so nothing overlaps the next row or the composer.
- One-to-one WhatsApp, Signal and Telegram chats show it when the read count is at least one (`shows` in `src/read_receipt.zig`). Unread chats, groups and Slack show nothing.

## How to get to it (user POV)

- Open a one-to-one WhatsApp, Signal or Telegram chat where your last message was read. The mark shows under the right edge of that bubble, below the reactions if any.

## Driving it with PowerShell UI Automation

- Run `feature=read-ticks` on GitHub Actions only, using the unified fake hub in `--read-ticks` mode.
- The fixture has nine chats: WhatsApp read, unread, older-read/newest-unread and group; Slack; Signal one-to-one (read) and Signal group; Telegram one-to-one read and Telegram one-to-one unread. History stays newest-first, with production `MsgID`, `ChatJID`, `Timestamp`, `FromMe` and `ReadBy` fields. The older-read case retains `ReadBy=1` on `tick-read` while the newer `tick-own` has `ReadBy=0`; this must not erase the earlier Read mark.
- Real Ctrl+F and the chat name select each chat. The journey waits until the sent bubble is painted, then reads `read_tick` from read-only `wazigctl status` and saves `ticks-read`, `ticks-sent`, `ticks-late`, `ticks-group`, `ticks-slack`, `ticks-signal`, `ticks-signal-group`, `ticks-telegram` and `ticks-telegram-unread` as picture, state, json, `messages.json` and `mark.json`.
- The validator requires the mark only for the read one-to-one WhatsApp, Signal and Telegram chats. It also reads the saved screenshot under the own bubble's right edge and demands at least six blue pixels where the rule shows the mark and none where it does not.

## Gotchas

- Synthetic data proves the client contract, not live WhatsApp delivery.
- `read_tick.shown` is computed from the same rule the painter uses. The screenshot pixel count is what proves the mark is really drawn and placed.
- At the audited revision, `src/main.zig:18120` selects only the newest own message before checking its read count, so the older-read/newest-unread case is an app regression, not a reason to weaken this fixture. Keep that failure separate from upkeep changes.
- Source: `src/read_receipt.zig`, `receiptCapability` and `drawReadMark` in `src/main.zig`, geometry in `src/message_layout.zig`.
- Journey: `tools/verify-wazig/journey-read-ticks.ps1`; evidence: `tools/verify-wazig/check-read-ticks-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

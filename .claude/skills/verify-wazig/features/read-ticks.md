# Read ticks

## Sub-features

- A mark sits below the newest own message the other person read: a blue double tick (`design.provider_colors.telegram`, `#2AABEE`) followed by the word `Read` in the small grey timestamp style, right-aligned with the bubble's right edge.
- The mark never covers bubble text, emoji or a reaction chip. The message row reserves its own vertical space, so nothing overlaps the next row or the composer.
- One-to-one WhatsApp, Signal and Telegram chats show it when the read count is at least one (`shows` in `src/read_receipt.zig`). The app walks back from the newest own message to the newest one that was read, so a chat whose newest own message is still unread keeps the mark on the message that was read. Unread chats, groups and Slack show nothing.
- The reading position holds: when a row's height changes between paints (the read mark appearing or clearing, an image arriving), a chat scrolled away from the bottom keeps the top visible message at the same screen position (`src/message_anchor.zig`). At the bottom the newest message stays pinned instead.

## How to get to it (user POV)

- Open a one-to-one WhatsApp, Signal or Telegram chat where one of your messages was read. The mark shows under the right edge of that bubble, below the reactions if any.
- Scroll up in a long chat and let a read receipt arrive or clear: the messages you are reading stay where they are.

## Driving it with PowerShell UI Automation

- Run `feature=read-ticks` on GitHub Actions only, using the unified fake hub in `--read-ticks` mode.
- The fixture has ten chats. Nine end with one message you sent: WhatsApp read, unread, late-read, group; Slack; Signal one-to-one (read) and Signal group; Telegram one-to-one read and Telegram one-to-one unread. The late chat sends an unread message after one that was read, so its mark belongs on `tick-old`. The hold chat `Verification Hold` has forty messages and its newest one starts read.
- Real Ctrl+F and the chat name select each chat. The journey waits until the marked bubble is painted, then reads `read_tick` from read-only `wazigctl status` and saves `ticks-read`, `ticks-sent`, `ticks-late`, `ticks-group`, `ticks-slack`, `ticks-signal`, `ticks-signal-group`, `ticks-telegram` and `ticks-telegram-unread` as picture, state, json, `messages.json` and `mark.json`.
- The validator requires the mark only for the read one-to-one WhatsApp, Signal and Telegram chats, and never under the unread newest message of the late chat. It also reads the saved screenshot under the marked bubble's right edge and demands at least six blue pixels where the rule shows the mark and none where it does not.
- Then it opens `Verification Hold`, presses PageUp, records the top painted message, posts `/fixture/ticks/clear` so the fixture reports the newest own message unread, waits for the app to repaint without the mark, and requires that top message to be the same id within two pixels.

## Gotchas

- Synthetic data proves the client contract, not live WhatsApp delivery.
- `read_tick.shown` is computed from the same rule the painter uses. The screenshot pixel count is what proves the mark is really drawn and placed.
- Real hub rows only carry a read count when the store recorded the receipt, so many real chats have no read own message at all and correctly show nothing.
- Source: `src/read_receipt.zig`, `receiptCapability`, `readMarkIndex` and `drawReadMark` in `src/main.zig`, geometry in `src/message_layout.zig`, the held reading position in `src/message_anchor.zig`.
- Journey: `tools/verify-wazig/journey-read-ticks.ps1`; evidence: `tools/verify-wazig/check-read-ticks-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

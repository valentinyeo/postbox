# Read ticks

## Sub-features

- A small grey double tick sits inside your newest own bubble once the other person read it.
- One-to-one WhatsApp, Signal and Telegram chats show it when the read count is at least one (`shows` in `src/read_receipt.zig`). Unread chats, groups and Slack show nothing.

## How to get to it (user POV)

- Open a one-to-one WhatsApp, Signal or Telegram chat where your last message was read. The tick shows at the bottom right of that bubble.

## Driving it with PowerShell UI Automation

- Run `feature=read-ticks` on GitHub Actions only, using the unified fake hub in `--read-ticks` mode.
- The fixture has eight chats, each ending with one message you sent: WhatsApp read, unread and group; Slack; Signal one-to-one (read) and Signal group; Telegram one-to-one read and Telegram one-to-one unread. The read count comes from the fixture rows.
- Real Ctrl+F and the chat name select each chat. The journey waits until the sent bubble is painted, then reads `read_tick` from read-only `wazigctl status` and saves `ticks-read`, `ticks-sent`, `ticks-group`, `ticks-slack`, `ticks-signal`, `ticks-signal-group`, `ticks-telegram` and `ticks-telegram-unread` as picture, state and json.
- The validator requires the tick only for the read one-to-one WhatsApp, Signal and Telegram chats.

## Gotchas

- Synthetic data proves the client contract, not live WhatsApp delivery.
- `read_tick.shown` is computed from the same rule the painter uses. Look at the pictures to confirm the tick is drawn.
- Source: `src/read_receipt.zig` and `receiptCapability` in `src/main.zig`.
- Journey: `tools/verify-wazig/journey-read-ticks.ps1`; evidence: `tools/verify-wazig/check-read-ticks-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

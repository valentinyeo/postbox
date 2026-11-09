# Read ticks

## Sub-features

- A small grey double tick sits inside your newest own bubble once the other person read it.
- Only one-to-one WhatsApp chats show it. Unread chats, groups and Slack show nothing.
- Telegram and Signal show nothing, because the hub sends no read count for them.

## How to get to it (user POV)

- Open a one-to-one WhatsApp chat where your last message was read. The tick shows at the bottom right of that bubble.

## Driving it with PowerShell UI Automation

- Run `feature=read-ticks` on GitHub Actions only, using the unified fake hub in `--read-ticks` mode.
- The fixture has four chats: a read one-to-one WhatsApp chat, an unread one, a WhatsApp group with a read count and a Slack chat. Each ends with one message you sent.
- Real Ctrl+F and the chat name select each chat. The journey waits until the sent bubble is painted, then reads `read_tick` from read-only `wazigctl status` and saves `ticks-read`, `ticks-sent`, `ticks-group` and `ticks-slack` as picture, state and json.
- The validator requires the tick only for the read one-to-one WhatsApp chat.

## Gotchas

- Synthetic data proves the client contract, not live WhatsApp delivery.
- `read_tick.shown` is computed from the same rule the painter uses. Look at the pictures to confirm the tick is drawn.
- Source: `src/read_receipt.zig` and `src/main.zig`.
- Journey: `tools/verify-wazig/journey-read-ticks.ps1`; evidence: `tools/verify-wazig/check-read-ticks-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

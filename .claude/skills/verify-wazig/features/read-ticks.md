# Read ticks

## Sub-features

- Every own message in a chat shows WhatsApp ticks at the bottom-right inside its bubble, in the bubble's bottom padding so the row keeps the same height whatever the status is.
- One grey tick means sent to the server, two grey ticks mean delivered, two blue ticks mean read. Grey is the muted hint ink (`theme.current.on_surface_variant`); read is the design kit's blue (`design.provider_colors.telegram`, `#2AABEE`). Pending and failed sends keep their own state and show no ticks.
- Per-message status comes from the recipient counts the hub already returns: `DeliveredTo` and `ReadBy` (`status` in `src/read_receipt.zig`). One-to-one WhatsApp, Signal and Telegram chats read the counts directly. WhatsApp groups only turn blue once every recipient the message reached has also read it, because the hub gives counts and not the group's member total.
- Slack and Telegram channels show nothing. Groups on Signal show nothing.
- Ticks never change a row's height or the scroll position, so no reading hold is needed when a receipt arrives (`src/message_anchor.zig` is gone).

## How to get to it (user POV)

- Open a one-to-one WhatsApp chat with a message you sent. One grey tick appears as soon as the server has it, two grey when the other phone received it, two blue when the other person read it.
- Scroll up in a long chat and let a receipt arrive: the messages you are reading stay where they are.

## Driving it with PowerShell UI Automation

- Run `feature=read-ticks` on GitHub Actions only, using the unified fake hub in `--read-ticks` mode.
- The fixture has eleven chats. Ten end with messages you sent: WhatsApp sent, delivered and read; a late-read chat whose newest own message is only delivered while an older one is read; a WhatsApp group delivered to three and read by two; Slack; Signal one-to-one read and Signal group; Telegram one-to-one read and Telegram one-to-one unread (sent). The hold chat `Verification Hold` has forty messages and its newest one starts delivered, then turns read.
- Real Ctrl+F and the chat name select each chat. The journey waits until `tick-own` is painted, then reads each message's `ticks` field from read-only `wazigctl messages`, and saves every chat as picture, state, json, `messages.json` and `<stage>.json`.
- The journey counts pixels in a band across the bubble's bottom-right corner and requires the delivered band to hold at least six more grey pixels than the sent band. The validator re-checks the retained counts: at least six muted-grey pixels for sent and for delivered, at least eight blue pixels with at most four grey for read, and none for Slack or a Signal group. The late chat's older message must be blue while its newest own message is not.
- Then it opens `Verification Hold`, records the delivered newest bubble and its pixels, presses PageUp, records the top painted message, posts `/fixture/ticks/read` so the fixture reports the newest own message read, waits for the app to repaint, and requires that top message to be the same id within two pixels. It then returns to the bottom and requires the bubble's height and bottom edge to be unchanged while the ticks turned blue.

## Gotchas

- Synthetic data proves the client contract, not live WhatsApp delivery.
- Real hub rows carry `DeliveredTo` and `ReadBy` only when the store recorded the receipt, so a message nobody reported on shows one grey tick. Slack and Signal-group rows carry no counts.
- A group's blue ticks mean the recipients the message reached have all read it. WhatsApp's own rule needs the group's member total, which the hub does not send.
- Source: `src/read_receipt.zig`, `receiptCapability` and `drawReadTicks` in `src/main.zig`, geometry in `src/message_layout.zig`.
- Journey: `tools/verify-wazig/journey-read-ticks.ps1`; evidence: `tools/verify-wazig/check-read-ticks-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

# Signal through the unified hub

## Sub-features

- `account-view`: a single Signal account, labelled Signal, participates in saved account order and the combined inbox. Its rows carry a #3A76F0 mark with a white speech bubble and dashed outline through the shared provider badge path.
- `linking-qr`: an empty Signal view loads hub link status and draws the link PNG using the existing WIC media decoder and bitmap path. It polls every 30 seconds until linked, then reloads chats.
- `actions`: opaque Signal handles use existing unified history, text, multipart attachments, reactions, author/timestamp read receipts, media and live events. Archive reports unsupported.
- `terminal-errors`: rate-limit and captcha rejections remain in failed message text with their reason. They leave the send queue without automatic retry; manual resend remains available.

## How to get to it (user POV)

- Configure the unified hub, then choose Show Signal in Ctrl+K or its next assigned Alt+N view position. No new menu or dedicated shortcut is added.
- With an unlinked account, read the QR and the line: Scan in Signal > Settings > Linked devices > Link new device. Once linked, chats replace it.
- Open a chat, compose and press Enter. Attach photo or file uses the existing file picker; select a message and use the existing reaction palette command.
- A rejected send shows signal rate limited or signal captcha required in its failed bubble, not a hidden or silently retried send.

## Driving it with PowerShell UI Automation

- Run feature=signal on GitHub Actions only. run.ps1 starts fake-hub.py --signal in the isolated native desktop profile; harness.ps1 supplies read-only wazigctl and owned keyboard helpers; signal.ps1 drives the journey.
- Press the Signal account's assigned Alt key. Require an empty Signal-only account and decoded QR, capture qr.png and state, then require four Signal chats after the next 30-second poll and measure brand-blue pixels in the captured sidebar. The synthetic hub becomes linked after one PNG fetch and a subsequent status read.
- Open Verification Signal through the palette. Assert exact history identity and content, author/timestamp mark-read payload and cleared unread state, automatic attachment download and durable cache.
- Select an incoming message and choose Like; require a recorded reaction and visible reaction through wazigctl. Send Synthetic Signal outgoing; require one accepted JSON send and visible acknowledged history.
- Choose Attach photo or file, enter a generated PNG in the owned native picker, then send a caption. Require one multipart write with exact bytes, size, filename, chat and client ID, plus the visible file message.
- Trigger the synthetic live event, require production SSE and a visible message. Open the rate-limited and captcha chats, send once each, require the exact failed reason and an empty pending queue. The final request ledger must contain only one attempt per rejected chat. Attempt archive and require one 502 and no pending archive retry.
- check-evidence.py delegates to check-signal-evidence.py to validate retained screenshots, Signal account state, histories, request payloads, file hash, live event, both terminal failures, proof gates and cleanup isolation. Inspect the images before claiming visible appearance.

## Gotchas

- The fixture contains synthetic opaque contact and group handles, not real identifiers or authentication data. Its QR encodes a synthetic link URI; this journey does not authenticate a real device or prove upstream delivery.
- Windows build, Zig tests, PowerShell execution and live screenshot inspection belong to GitHub Actions, never the development host. Source review and syntax/lint checks are not runtime proof.
- Signal view identity is fixed to signal; routing and caches retain the existing hub namespace and complete handle. Read receipts use the newest incoming non-reaction message's complete author/timestamp ID from cached history, including when another chat is selected.
- The empty Signal view is registered even before the hub returns Signal rows. Existing populated account positions remain unchanged and Signal appends in default order. Non-Signal fixtures therefore have an additional empty view.
- Unit coverage in src/hub_test.zig covers parsing, provider filtering, direct/group fixed account identity, both exact error/status mappings and read receipt identity. Release startup, binary size, working set, real QR scan, voice playback and transcript caching require CI or live-provider evidence; unchanged mechanisms are not re-certified by this journey.

# Signal through the unified hub

## Sub-features

- `account-view`: a single Signal account, labelled Signal, participates in saved account order and the combined inbox. Its rows carry a #3A76F0 mark with a white speech bubble and dashed outline through the shared provider badge path.
- `hub-only-linking`: link once through the triage CLI on the hub. Wazig only lists chats already present there; an unlinked provider is an ordinary empty list, never a login screen.
- `actions`: opaque Signal handles use existing unified history, text, multipart attachments, reactions, author/timestamp read receipts, media and live events. Ctrl+E archives and unarchives locally in Wazig, without a hub archive POST.
- `terminal-errors`: rate-limit and captcha rejections remain in failed message text with their reason. They leave the send queue without automatic retry; manual resend remains available.

## How to get to it (user POV)

- Configure the unified hub, then choose Show Signal in Ctrl+K or its next assigned Alt+N view position. No new menu or dedicated shortcut is added.
- Link Signal through the triage CLI on the hub before opening its chats. Esc leaves an empty view; Alt+number and Alt+I work normally. A saved empty Signal view falls back to the combined inbox at startup.
- Open a chat, compose and press Enter. Attach photo or file uses the existing file picker; select a message and use the existing reaction palette command.
- A rejected send shows signal rate limited or signal captcha required in its failed bubble, not a hidden or silently retried send.

## Driving it with PowerShell UI Automation

- Run feature=signal on GitHub Actions only. run.ps1 starts fake-hub.py --signal in the isolated native desktop profile; harness.ps1 supplies read-only wazigctl and owned keyboard helpers; signal.ps1 drives the journey.
- The fake hub starts linked. Press the Signal account's assigned Alt key, require four Signal-only chats, capture linked.png and measure brand-blue pixels in the sidebar. No linking is driven through Wazig.
- Open Verification Signal through the palette. Assert exact history identity and content, author/timestamp mark-read payload and cleared unread state, automatic attachment download and durable cache.
- Select an incoming message and choose Like; require a recorded reaction and visible reaction through wazigctl. Send Synthetic Signal outgoing; require one accepted JSON send and visible acknowledged history.
- Choose Attach photo or file, enter a generated PNG in the owned native picker, then send a caption. Require one multipart write with exact bytes, size, filename, chat and client ID, plus the visible file message.
- Trigger the synthetic live event, require production SSE and a visible message. Open the rate-limited and captcha chats, send once each, require the exact failed reason and an empty pending queue. The final request ledger must contain only one attempt per rejected chat. Press Ctrl+E on Verification Signal: require its row to leave the inbox, pending_archives=0 and archived-inbox evidence. Choose Show archived chats, require exactly that archived Signal row and capture archived. Press Ctrl+E again, capture the empty unarchived-archive list, choose Show inbox chats and require the unarchived row back in after. The final request ledger must contain no POST /v1/wazig/archive for that chat; retain local-archive-unarchive proof and both Ctrl+E actions.
- check-evidence.py delegates to check-signal-evidence.py to validate retained screenshots, Signal account state, histories, request payloads, file hash, live event, both terminal failures, proof gates and cleanup isolation. Inspect the images before claiming visible appearance.

## Gotchas

- The fixture contains synthetic opaque contact and group handles, not real identifiers or authentication data. The fixture starts with hub chats; this journey does not authenticate a real device or prove upstream delivery.
- Windows build, Zig tests, PowerShell execution and live screenshot inspection belong to GitHub Actions, never the development host. Source review and syntax/lint checks are not runtime proof.
- Signal view identity is fixed to signal; routing and caches retain the existing hub namespace and complete handle. Read receipts use the newest incoming non-reaction message's complete author/timestamp ID from cached history, including when another chat is selected.
- The empty Signal view is registered even before the hub returns Signal rows. Existing populated account positions remain unchanged and empty Telegram and Signal follow populated WhatsApp/Slack accounts in default provider order. Non-Signal fixtures therefore have additional empty views.
- Unit coverage in src/hub_test.zig covers parsing, provider filtering, direct/group fixed account identity, both exact error/status mappings and read receipt identity. Release startup, binary size, working set, hub CLI linking, voice playback and transcript caching require CI or live-provider evidence; unchanged mechanisms are not re-certified by this journey.

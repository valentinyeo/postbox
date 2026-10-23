# Telegram through the unified hub

## Sub-features

- `account-view`: one Telegram view participates in saved Alt-key order and the combined inbox. User, basic-group and channel handles remain opaque. The existing badge path paints a blue paper-plane mark; the saved flag identifies Saved Messages.
- `hub-only-linking`: link once through the triage CLI on the hub. Wazig only lists existing hub chats; unlinked Telegram is an ordinary empty list with no QR or password input.
- `actions`: history, text, files, replies, reactions, read receipts, automatic media downloads and live SSE use the unified routes. Telegram rate limited stays in failed message text without automatic resend. Archive and avatar are unsupported.
- `hub-only-login`: when a hub is configured, no direct Telegram connect/logout/remove palette entries, TDLib initialization or phone, code or app-key screens are reachable.

## How to get to it (user POV)

- Configure the triage hub and choose Show Telegram in Ctrl+K or its assigned Alt+N position. Account linking belongs to that hub, not a second Wazig connection.
- Link Telegram through the triage CLI on the hub, never inside Wazig. Esc leaves an empty view and Alt+number/Alt+I remain usable; a saved empty Telegram view falls back to the combined inbox at startup.
- Select a chat and use the existing composer, Attach photo or file, Reply to selected message and reaction commands. Saved Messages appears in the same list.

## Driving it with PowerShell UI Automation

- Run feature=telegram on GitHub Actions only. run.ps1 starts fake-hub.py --telegram in the isolated profile; telegram.ps1 drives the native window with owned keyboard input and read-only control snapshots.
- The fake hub starts linked; use the assigned Alt key to open its existing Telegram chats without any authentication interaction.
- Require five Telegram rows spanning user, basic-group and channel handles, with exactly one saved row. Capture linked.png, measure blue badge pixels and retain the palette's positive Show Telegram row and absence of direct account commands.
- Open Verification Telegram; capture history and read state, require a decimal message ID in mark-read, cleared unread state and automatic cached media.
- React to the selected incoming message, reply with reply_to=1001, send text and use the native attachment picker to send generated PNG bytes. Capture reacted, reply, text and file messages; compare file hash and size to the multipart ledger.
- Trigger the fake live SSE message and capture live.png plus history. Send once to the rate-limited chat; require the visible reason, empty queue and exactly one 429 request. Archive must settle one unsupported 502 without retrying.
- check-evidence.py delegates to check-telegram-evidence.py. Require result.json with feature telegram and status passed, proof gates, screenshots, histories, authenticated request records and surviving cleanup/isolation evidence. Inspect the screenshots from the exact PR commit before accepting visible behavior.

## Gotchas

- Every identifier and message in this fixture is synthetic. Prelinked hub rows do not prove real account linking or upstream delivery.
- Windows builds, Zig tests, PowerShell parsing/execution and desktop evidence belong to GitHub Actions. Static source checks on the development host are not runtime verification.
- Empty Telegram and Signal views are registered before provider rows exist. Default provider order puts Telegram before Signal; existing saved order still takes precedence.
- Routing and cache accounts remain in the existing hub namespace. The view account is fixed to telegram, independent of user/group/channel identifiers. src/hub_test.zig covers opaque IDs, view isolation, badge fallback, exact rate-limit text/status and saved-flag parsing.
- Startup time, release size, working set, hub CLI linking, voice playback and cached transcription need CI or live-provider evidence; unchanged mechanisms are not re-certified here.

# Changelog

## Unreleased

- IGSH-645: Right-click message reactions send the emoji clicked in the quick reaction row instead of always sending thumbs up.

- IGSH-607: Link Signal and Telegram only through the hub CLI; remove in-app QR/password screens, fall back to the combined inbox on empty startup views, and keep Esc/Alt navigation available.

- IGSH-465: Telegram has its own view through the triage hub, with a paper-plane mark, QR/password linking, Saved Messages, text/file sending, replies, reactions, read receipts and live updates. Hub users no longer see direct Telegram sign-in; rate limits stay visible without automatic resend.

- IGSH-607: Signal has its own account view through the hub, a blue row mark, QR linking, messaging, attachments, reactions, read receipts and live updates. Rate-limit and captcha rejections stay visible in failed messages without automatic retries.

- IGSH-602: Derive separate account views from real hub prefixed chat IDs when account metadata is absent, preserving send and cache identities. WhatsApp labels show the account; Slack labels use a locally saved workspace name or team ID.

- IGSH-602: Separate account and workspace views with saved Alt+1..9 ordering, a Ctrl+K Sort views list, and an Alt+I combined inbox. Search, navigation and sending keep account identities separate; read-only control status reports the current view and order.

- IGSH-545: Chat-row, composer-button and window paint buffers are sized to the area being redrawn instead of the whole window, so a 4K row no longer allocates a full-window bitmap. A chat row whose brush cannot be created is left untouched instead of showing a black row.
- IGSH-533: Reactions appear in small chips below message bubbles with their own row space, so emojis no longer overlap message text at 100% or 150% display scaling.
- IGSH-461: AMOLED popup and account-dialog inputs show focus borders, and the Telegram input keeps its raised surface while checking credentials. AMOLED remains the default unless a theme was explicitly saved.
- IGSH-538: Remove WhatsApp Status and stories, including the sidebar, viewer, commands, unread badges and background requests. Chats now start directly below search in both themes.
- IGSH-517: Use saved Windows user API keys instead of stale inherited keys. Voice transcription recovers from a key rotation while the app is running, and failed voice notes try again when their chat is reopened.

- IGSH-526: Add a GitHub-only native desktop verification skill with five feature maps, isolated offline fixture launch, keyboard/UI Automation journeys and screenshot artifacts.
- IGSH-517: Sent voice notes try multilingual recognition when automatic recognition returns no words. Failed transcriptions show a short error below the player instead of an empty space. Microphone dictation still sends each recording only once, and saved transcripts are reused.
- IGSH-510: Buffer desktop and chat-row painting, clip updates to the dirty area, and avoid full-window layout while typing at an unchanged composer height.

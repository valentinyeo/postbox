# Slack emoji and Giphy

## Sub-features

- Every standard Slack shortcode and alias uses the generated public emoji-data table, including skin tones and adjacent shortcode pairs.
- Workspace custom emoji and aliases draw as inline images in message text and reaction chips, scoped to the Slack account.
- Giphy attachment images download through the authenticated hub media route and animate through the existing WIC image path.
- Unknown shortcode text stays unchanged. Emoji metadata, images and GIF bytes are cached.

## How to get to it (user POV)

- Open a Slack chat containing shortcodes, custom reactions or a Giphy post.
- Images download and GIFs animate automatically; no toolbar command or manual load is needed.

## Driving it with PowerShell UI Automation

- Run feature=slack-emoji on GitHub Windows Actions only. SlackEmojiHandler supplies two synthetic chats, the emoji index/media endpoints and a two-frame GIF attachment.
- Search through Ctrl+F using real foreground-checked keyboard input. Require exact standard Unicode, a tone suffix and adjacent pair, unchanged unknown text, custom-to-standard aliases, alias-cycle fallback, and no known raw shortcode in the read-only app message state.
- Capture emoji.png and emoji.messages.json; require amber custom image pixels inside both the custom message bubble and the reaction chip. Reaction state must also contain the standard tear-face and tea glyphs.
- Capture frame-a.png and frame-b.png from the real app. Require two decoded frames, opposing amber/cobalt image pixels and more than 70% differing pixels inside the reported GIF media rectangle, not just different full-screen hashes.
- Retain emoji-pixels.json, emoji-cache.json, UIA/state snapshots, bridge-requests.jsonl and final-data. check-slack-emoji-evidence.py independently remeasures screenshots, requires authenticated account-scoped requests and cached bytes, and rejects missing custom pixels or a static GIF.

## Gotchas

- This journey must fail on the baseline that leaves shortcodes unresolved; CI on the journey-only baseline and on the implementation is required before runtime acceptance.
- Local Python fixture/validator checks do not prove Windows rendering. Inspect the actual Actions screenshots; never claim a local build or runtime pass.
- The private hub must add emoji.list proxying and attachment-aware media resolution. The client never logs in to Slack or fetches custom image URLs directly.
- Source: src/slack_emoji.zig, src/slack_emoji.tsv, src/hub.zig and src/main.zig. The app reuses its existing WIC animation and image viewer code.

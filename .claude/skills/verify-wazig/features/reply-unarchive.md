# Reply brings an archived chat back

## Sub-features

- Replying in an archived chat returns it to the Combined inbox right away.
- It also returns to its own messenger inbox, shown here for the WhatsApp test chat. The same rule covers Slack, Telegram and Signal chats.
- The chat is still back after an app restart.
- A chat marked Keep archived stays archived after a reply.

## How to get to it (user POV)

Archive a chat, open it from the archived list or from search, and send a reply. Open the Combined inbox and the messenger inbox: the chat is listed again. Quit and start Postbox: it is still there. Mark another chat Keep archived with Ctrl+Shift+E and reply in it: it stays in the archive.

## Driving it with PowerShell UI Automation

Run `feature=reply-unarchive` through `tools/verify-wazig/run.ps1` on hosted Windows. The registry in `journeys.json` selects the isolated hub in `send-once-fixture.py`. The journey archives the test chat with Ctrl+E, opens it from the archived list, sends one test message, then checks the WhatsApp inbox and Combined, restarts the app and checks Combined again. It then marks the chat Keep archived, replies once more and checks the chat is still missing from the inbox. A screenshot is saved at every step.

## Gotchas

- Fake hub acceptance proves client behaviour, not delivery to a real phone.
- The restart reuses the same profile through `WAZIG_VERIFY_RESTART`.
- Test data only. No real contact names or message text.

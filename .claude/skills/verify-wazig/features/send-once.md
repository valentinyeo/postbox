# Sent message shows once

## Sub-features

- One sent message makes exactly one bubble, in a normal chat and in an archived chat.
- No bubble keeps the "(sending)" ending after the hub confirms the send.
- The waiting copy and the confirmed copy are matched, never hidden.

## How to get to it (user POV)

Open a chat, type one message and press Enter. Then archive the chat, open it from the archived list and send another. Each message shows once and the "(sending)" ending goes away.

## Driving it with PowerShell UI Automation

Run `feature=send-once` through `tools/verify-wazig/run.ps1` on hosted Windows. The registry in `journeys.json` selects the isolated hub in `send-once-fixture.py`. The hub accepts one send per client id and echoes it back as a confirmed message. The journey sends one test message in the WhatsApp test chat, archives that chat, sends a second test message from the archived list, and counts bubbles by text after each. It saves the message list and a screenshot before it asserts, so a failed run still shows what was on screen.

## Gotchas

- Fake hub acceptance proves client reconciliation, not delivery to a real phone.
- Input stays inside the owned hosted process. Never type on a user's device.
- Test data only. No real contact names or message text.

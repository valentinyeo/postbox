# Reply preview and quoted-message navigation

## Sub-features

- Reply preview shows the original sender and first line.
- Close and Escape cancel without sending.
- WhatsApp and Slack sends retain their reply target.
- One grey quote line sits above replies.
- Clicking that line finds and briefly highlights the original.

## How to get to it (user POV)

Right-click a message, choose Reply, write an answer, and send. Click the quote above the answer to return to the original.

## Driving it with PowerShell UI Automation

Run `feature=reply` through `tools/verify-wazig/run.ps1` on hosted Windows. The registry in `journeys.json` selects the isolated two-provider hub and native input journey. The workflow first proves the same journey rejects the original source for its missing reply preview. Candidate and published-release runs preserve screenshots, read-only geometry, send requests and temporary-highlight evidence.

## Gotchas

- Fake hub acceptance proves client transport, not delivery to a real phone or live Slack workspace.
- Input stays inside the owned hosted process. Never type on a user's device.
- Forwarded-message quote blocks retain their existing style; only actual reply references use the single line.

# Hub wake and safety refresh

## Sub-features

- `wake-resume`: with SSE live events muted and a new fixture row only on the HTTP API, a Windows `WM_POWERBROADCAST` resume notification must load `POLL-ROW` within fifteen seconds.
- `safety-poll`: with the same mute, after sixty-five seconds without SSE the app must issue another authenticated `/v1/chats` pull and keep messages current.

## How to get to it (user POV)

Run the verification journey `feature=hub-wake-refresh` on GitHub Actions. The fake bridge exposes `/fixture/mute-sse` and `/fixture/stale-row`; the app uses the legacy wa-bridge fixture like `whatsapp-hub`.

## Driving it with PowerShell UI Automation

- `feature=hub-wake-refresh` or `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature hub-wake-refresh`.
- Prepare sets `WAZIG_VERIFY_HUB_STALE=1` so the resume notification backdates inbox freshness once, without a startup timer racing the resume gate.
- Retain `wake-resume.json`, `safety-poll.json`, `poll.messages.json`, and `hub-proof.log` gates `wake-resume` and `safety-poll`.

## Gotchas

- The journey sends the real resume notification to the owned app window, including when testing the base binary.
- Safety poll proof sleeps sixty-five seconds; CI timeout must stay above that.
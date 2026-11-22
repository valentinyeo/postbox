# Hub wake and safety refresh

## Sub-features

- `wake-resume`: with SSE live events muted and a new fixture row only on the HTTP API, `hub-resume` (verification stand-in for system resume) must load `POLL-ROW` within fifteen seconds.
- `safety-poll`: with the same mute, after sixty-five seconds without SSE the app must issue another authenticated `/v1/chats` pull and keep messages current.

## How to get to it (user POV)

Run the verification journey `feature=hub-wake-refresh` on GitHub Actions. The fake bridge exposes `/fixture/mute-sse` and `/fixture/stale-row`; the app uses the legacy wa-bridge fixture like `whatsapp-hub`.

## Driving it with PowerShell UI Automation

- `feature=hub-wake-refresh` or `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature hub-wake-refresh`.
- Prepare sets `WAZIG_VERIFY_HUB_STALE=1` so the first inbox fetch is backdated for the resume gate.
- Retain `wake-resume.json`, `safety-poll.json`, `poll.messages.json`, and `hub-proof.log` gates `wake-resume` and `safety-poll`.

## Gotchas

- The journey relies on `hub-resume` control command, available only under the verification fixture.
- Safety poll proof sleeps sixty-five seconds; CI timeout must stay above that.
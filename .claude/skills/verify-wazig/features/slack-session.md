# Imported Slack web sessions

## Sub-features

- One-time import from `%LOCALAPPDATA%\Messages\slack-session-import.json` into the existing per-workspace DPAPI store; the import is deleted, including malformed and empty files.
- Slack chat list and badge, history, replies, sends, files and read state use the existing Slack worker and UI.
- Session Web API requests POST form fields with the workspace token and shared `d` cookie. Live events use `rtm.connect` and the existing WinHTTP websocket, with the same cookie on upgrade and no Socket Mode acknowledgement.
- Existing OAuth and Socket Mode credentials remain supported alongside session workspaces. Rejected sessions require sign-in rather than an OAuth refresh attempt.

## How to get to it (user POV)

Place the one-time import in the existing local data folder, then open Messages normally. No app creation, Client ID, pasted app token or new UI is required. The JSON shape is `{"xoxd":"xoxd-fake-shared-cookie","workspaces":{"TFAKE001":{"xoxc":"xoxc-fake-session-token","team":"Fake Workspace","url":"https://fake-workspace.invalid","user_id":"UFAKE001"}}}`. These values are intentionally fake. Never put real sessions in the repository or evidence.

## Driving it with PowerShell UI Automation

Run `feature=slack-session`, or `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature slack-session`, on GitHub Actions. Matching PRs include this journey in the verification matrix.

The harness starts `tools/verify-wazig/fake-slack.py`, runs `zig build test-slack-session` against it, resets its synthetic messages, and drops the import into an isolated app data directory. The real app imports and protects the session, lists `fake-slack-chat` with Slack provider identity, displays fake history, sends through the composer, and shows a fake incoming RTM message. Screenshots, control snapshots, token-free request metadata, protected-value kind and server state survive cleanup.

Native Zig tests cover list, read/replies/mark, escaped send/client message ID, cookie-bearing RTM upgrade and raw live receive, rejected auth, consumed/deleted import, DPAPI ciphertext, two-workspace isolation and OAuth record compatibility. Pure parser tests cover edits, reactions and header injection. Python tests exercise the fake server and reject missing cookies, wrong tokens and old bearer-only requests.

## Gotchas

The fixture proves client behavior against a fake Slack server, not acceptance or longevity of any real Slack session. Production uses HTTPS/WSS; the loopback override is enabled only after the existing GitHub-only isolated verification guards. No build, desktop, Wine or Zig test execution is performed on the development VPS.

Session expiry reuses the existing sign-in-required state. The existing OAuth settings remain available, but importing a fresh session is the no-app way to replace an expired session. The journey does not prove real delivery, file transfer, voice playback, upstream permissions or installed-app deployment.

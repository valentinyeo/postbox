# WhatsApp hub

Use the production hub backend against a synthetic authenticated bridge on the GitHub Windows runner, without an installed local provider or a real account.

## Sub-features

- `hub-chats-history`: remote chat rows retain provider/account identity and load real message rows.
- `chat-switch`: opening timestamped, uncached Beta clears Alpha immediately, before delayed Beta history arrives.
- `hub-live-replay`: a new SSE message appears and reconnects carry Last-Event-ID.
- `hub-send-dedupe`: a lost response retries the persisted outbox client_id with one accepted send.
- `hub-read-archive`: viewing marks read; a palette archive reaches the bridge and removes the row.
- `hub-media`: automatic media fetch receives 202, polls, and caches the exact ready bytes.
- `hub-outbox-adoption`: startup adopts a queued foreign-backend send, strips the legacy namespace, preserves the reply and removes its old journal line.
- `hub-secret`: the fake key is stored as DPAPI binary; the backend log contains no key or URL.

## How to get to it (user POV)

- Configure HKCU Software Messages value WaBridgeUrl with an HTTPS bridge origin. Seed the saved user environment variable WA_BRIDGE_KEY or `%USERPROFILE%/.wacli/bridge-send.key` once; the app saves it through DPAPI.
- Open a WhatsApp chat with Ctrl+Tab or Ctrl+Shift+Tab. Type in the composer and press Enter to send.
- Ctrl+K → Archive selected chat archives the opened chat. Incoming events refresh it automatically; attachments download without clicks.

## Driving it with PowerShell UI Automation

- Run `feature=whatsapp-hub`, or `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature whatsapp-hub` on GitHub Actions only.
- The helper starts tools/verify-wazig/fake-wa-bridge.py on an ephemeral loopback port. The guarded fixture seeds only its redirected registry WaBridgeUrl and fake key; all real provider paths remain disabled.
- Before normal input, require the preseeded foreign outbox send to be accepted exactly once with the reply `BASELINE` and no legacy namespace; retain `foreign-outbox-startup` proof and the emptied foreign journal.
- Require the owned-window doctor, two remote sidebar chats and Alpha's BASELINE. Beta has a nonempty last-message timestamp and no cached history in the fresh profile; reject any Beta history request before the switch and retain before-beta.requests.json. The fake delays only the first Beta history response by three seconds, recording its request number and measured delay.
- Use Ctrl+Tab to select Beta. Within one second of keyboard input returning, require selected Beta and a read-only messages response with matching provider/account/id and zero messages. Both control processes share this deadline; a blocked messages request is killed and fails, not retried until history arrives. Retain beta-switch.json (elapsed time and selection), beta-empty.messages.json, beta-empty.png and its state/UIA snapshots.
- Then require exactly BASELINE_BETA / Fixture Beta history in beta.messages.json and beta.png, plus the recorded three-second delay. Use Ctrl+Shift+Tab to return to Alpha; preserve history.png and history.messages.json showing BASELINE, no Beta messages and no LIVE yet.
- The fake emits reset ID 1, closes, and requires a reconnect with Last-Event-ID 1. After history is proven, a fixture-only HTTP trigger adds a message upstream. Require LIVE in live.messages.json and live.png, then a reconnect with Last-Event-ID 2.
- Use Ctrl+K → Compose message, type Fixture outgoing and Enter. The fake accepts once but loses the first response; require a retry with the same 32-character client_id and exactly one accepted send.
- Require a mark-read request for Alpha, media requests at the same path returning 202 then 200, and a durable cache file with the response SHA-256. Save sent.png.
- Use Ctrl+K → Archive selected chat. Require its POST and a one-chat sidebar in after.png, with no pending writes.
- Older history paging (IGSH-681) runs only through the unified `/v1/wazig` contract, see [hub](hub.md) `mixed-older-pages`; this legacy bridge journey requests only the newest page.
- Every assertion prints `whatsapp-hub <gate> PASS`; misses fail the job. Preserve bridge-requests.jsonl, hub-proof.log, read-only snapshots, screenshots, final-data and cleanup.txt. check-evidence.py rechecks the artifacts, not merely the PASS lines.

## Gotchas

- The bridge is a runner-only Python fixture, not a bundled client runtime. Non-HTTPS transport is rejected outside the isolated loopback fixture.
- Only keyboard input drives the app. The fixture trigger changes upstream provider state; it never writes app state or invokes a control mutation.
- A linked saved `WaBridgeAccount` preference wins, otherwise linked `personal` wins, then the first linked account; its identity namespaces the account-scoped cache. The fake lists two linked accounts with the nonpreferred one first; simultaneous multi-account UI is not covered.
- The frozen bridge has no pairing, account-removal, or contact-directory endpoint. Hub mode directs account administration to the hub and derives searchable contacts from chats.
- This proves contract integration, not real WhatsApp delivery, voice playback, transcription, external TLS availability or production deployment. Inspect screenshots before claiming visible behavior.
- Source: `src/main.zig:19325` migrates the saved bridge key, `src/main.zig:19418` configures the legacy backend, and `src/wa_hub.zig:177` chooses a linked account. `tools/verify-wazig/harness.ps1:239` asserts foreign-outbox adoption.

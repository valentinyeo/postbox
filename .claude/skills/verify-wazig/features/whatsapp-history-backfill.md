# WhatsApp older history recovery

## Sub-features

- Fetch missing phone history through one authenticated, chat-scoped POST, without sending a message or changing page sizes.
- Preserve exhaustion on 409 in-progress, 504 timeout and 503 unavailable; show a retry notice instead of completion.
- On confirmed success, reopen only the matching chat's older boundary and merge normal stored pages by message ID.
- Retain 65 recent plus 68 recovered historical messages in exact order, with no duplicates, and one additional live arrival during recovery. Other personal and same-contact business chats stay isolated.

## How to get to it (user POV)

- Select a WhatsApp chat backed by the unified hub. Press Ctrl+K, type `Fetch older history`, then Enter.
- Success shows the recovered count, then loads stored older pages. In-progress asks you to try later. Timeout and unavailable explicitly say not completed and invite retrying the same command.

## Driving it with PowerShell UI Automation

- Run `feature=whatsapp-history-backfill` on GitHub Actions through the existing verification workflow and `journeys.json` registry.
- The fake hub initially returns 75 raw rows: 65 conversation messages, nine reactions and one protocol placeholder. Older reads return empty until a correctly scoped POST succeeds.
- Real PageUp and palette input first exercise 409, 504 and 503. Additional PageUp input must leave the exhausted boundary alone after each failure.
- A fourth POST waits for a fixture live arrival before releasing 68 older rows. Repeating the command while it waits must not issue another POST.
- Preserve `initial.messages.json`, `initial.requests.json`, per-outcome status/messages/request snapshots, `recovered.messages.json`, both other chats' before/after JSON, screenshots, state/UIA snapshots and the harness's `bridge-requests.jsonl`.
- The evidence validator requires 133 historical IDs plus `HB-LIVE` (134 total), exact oldest-first order, no duplicates or placeholders, a live SSE event during recovery, unchanged other-chat/account messages, unchanged limit 80, authorized requests and no unexpected writes.

## Gotchas

- Current main has no palette command or history POST, so it cannot release the fixture's older rows or satisfy this journey. The red/green execution belongs on GitHub, not the development host.
- The synthetic journey proves only the client contract. Real hub authentication, account routing, phone recovery, server timeout bounds and sync pause/resume require integration verification against the separately shipped server.

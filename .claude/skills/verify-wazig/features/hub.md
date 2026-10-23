# Unified message hub

The IGSH-531 backend runs through the existing transport interface with no new UI. The hub resolves opaque conversation handles; Wazig retains Slack, Telegram and WhatsApp labels and filters.

## Sub-features

- `hub-list-history`: synthetic Slack and WhatsApp chats load through authenticated `/v1/wazig` requests, not local connector credentials.
- `provider-views`: explicit `wazigctl chats --json --messenger slack|whatsapp|all`, with and without `--all`, return nonempty provider-pure lists; Slack plus WhatsApp exactly partitions All. Alt+1/Alt+2/Alt+0 sidebar lists match those identities.
- `chat-switch`: opening timestamped, uncached WhatsApp Beta clears Slack Alpha before delayed history arrives.
- `hub-live`: fragmented SSE framing, reconnect replay and live history invalidation use the existing cancellable WinHTTP reader.
- `hub-send`: a lost response retries the persisted client_id; exactly one send is accepted.
- `hub-read-archive`: opening a remote chat marks it read and keyboard archiving removes it from the inbox.
- `hub-media`: automatic fetch polls 202 then caches the exact 200 binary response.
- `hub-config`: the ticket switch defaults on when WAZIG_HUB_URL is set; its token uses saved user environment/process environment and existing DPAPI HubToken storage. Missing URL retains direct connectors. Configured-but-invalid hubs never silently send directly.

## How to get to it (user POV)

- Set WAZIG_HUB_URL to an HTTPS origin and seed WAZIG_HUB_TOKEN through the same saved user environment used by other provider credentials. Subsequent starts can use the encrypted HubToken value.
- Open Messages normally. Use the existing network filters, chat navigation, composer, Enter to send, and Ctrl+K → Archive selected chat. No hub-specific controls are added.
- Clear WAZIG_HUB_URL to use existing direct connectors. The independently configured WhatsApp bridge remains available; unified hub and direct queues do not share an outbox file.

## Driving it with PowerShell UI Automation

- Run `feature=hub`, or `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature hub`, on GitHub Actions only. The existing verification workflow includes this journey on matching pull requests.
- The helper starts `tools/verify-wazig/fake-hub.py`, reusing the synthetic bridge state machine under a distinct `/v1/wazig` contract. The real Zig app, transport vtable, workers and WinHTTP/SSE reader execute; Python is fixture infrastructure, not a bundled app runtime.
- Require Slack Alpha and WhatsApp Beta without local provider credentials. Beta has a last-message timestamp but no cached history in the fresh profile; retain before-beta.requests.json proving no earlier Beta request. The shared bridge delays its first Beta history response by three seconds and records the measured delay.
- After Alpha's BASELINE appears, select Beta with Ctrl+Tab. Within one second of keyboard input returning, require selected Beta and matching provider/account/id with zero displayed messages, using bounded read-only control clients. Preserve beta-switch.json, beta-empty.messages.json, beta-empty.png and state/UIA snapshots. Then require only BASELINE_BETA / Fixture Beta history and retain beta.messages.json and beta.png. Switch back with Ctrl+Shift+Tab, require Alpha's baseline without Beta messages, then trigger the synthetic upstream event and require LIVE after SSE replay.
- Before opening Beta, retain `provider-views.json` and `provider-unfiltered-views.json` from explicit messenger queries while All is active. After the chat-switch proof, drive Alt+1, Alt+2 and Alt+0, retaining `provider-sidebar.json` and `provider-whatsapp.png`, `provider-slack.png`, `provider-all.png`. `check-hub-views.py` rejects empty/truncated views, wrong-provider rows, duplicates, incomplete partitions and CLI/sidebar identity mismatches. `hub provider-views PASS` is required in the surviving proof log.
- Send Fixture outgoing through the composer; require stable client_id retries and one acceptance. Require read state, pending-to-ready media with matching cache SHA-256, and keyboard archive with one remaining WhatsApp row.
- Require every original wire path to use `/v1/wazig` except the fixture-only event trigger, no source-account query, DPAPI HubToken storage, redacted launch logging and surviving evidence after cleanup.
- `src/hub_test.zig` joins the normal unit-test roots for switch/fallback, escaped opaque handles, all source networks, reads, archive/unarchive, multipart, malformed responses, duplicate handles and SSE resume validation. The existing search journey runs without either hub configuration; no runtime checks run on the development host.

## Gotchas

- The fake service proves only the client contract; this source-side map does not establish deployment or availability of a production unified endpoint.
- A configured URL with missing/invalid credentials remains hub-selected and fails closed. Network failures never switch to direct sends.
- The fixture contains Slack Alpha and WhatsApp Beta, not a Telegram row; Telegram provider filtering is covered by `src/hub_test.zig`, not this live recipe.
- Opaque chat handles must be globally unique across all source accounts and fit the existing 191-byte chat identity. Network identity remains presentation metadata, while the hub resolves source accounts.
- This journey proves list/history/live/send/read/archive/media against a fake service, not production delivery, upstream Slack archive semantics, TLS deployment, voice playback, or transcription.
- Source: `src/hub.zig:11` selects the configured backend, `src/hub.zig:15` defines unified paths, and `src/main.zig:19362` loads URL/token and DPAPI state. `tools/verify-wazig/fake-hub.py:34` assigns the two fixture networks.

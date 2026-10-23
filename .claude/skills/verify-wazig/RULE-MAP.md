# Verification rule map

| Rule | Executable coverage | Feature map |
| --- | --- | --- |
| Telegram has one saved view, opaque user/group/channel handles, a paper-plane badge and Saved Messages | src/hub_test.zig, Telegram journey row/state and blue-pixel assertions | [Telegram](features/telegram.md) |
| Telegram linking uses hub QR and a single password field, never direct phone/app-key screens | telegram journey QR/password captures, 401/200 ledger, positive palette row and direct-command absence | [Telegram](features/telegram.md) |
| Telegram text, files, replies, reactions, reads, media and live events stay on the hub | telegram.ps1 and check-telegram-evidence.py wire/history assertions | [Telegram](features/telegram.md) |
| Telegram rate limits stay visible without retries; unsupported archive settles | src/hub_test.zig, Telegram journey failed bubble and one-attempt 429/502 ledger | [Telegram](features/telegram.md) |
| Signal is one account with opaque handles and its own saved view | src/hub_test.zig, src/messenger_view.zig, signal journey account/state assertions | [Signal](features/signal.md) |
| Linking precedes chats, with a decoded PNG and 30-second status refresh | signal journey QR and linked captures, recorded ordered link requests | [Signal](features/signal.md) |
| Signal history, text, files, reactions, read receipts, media and live events stay on the hub | signal journey, recorded writes and read-only histories, check-signal-evidence.py | [Signal](features/signal.md) |
| Signal 429/403 failures retain their reasons and never retry automatically | src/hub_test.zig mappings, signal journey failed bubbles and one-attempt ledger assertions | [Signal](features/signal.md) |
| Unsupported Signal archive settles without a retry loop | signal journey 502 and empty pending archive state | [Signal](features/signal.md) |
| New journeys appear in dispatch, PR matrix, evidence validation and maps | tools/verify-wazig/check-map.py checks Signal wiring and index links | [Index](features/README.md) |
| Slack icons and WhatsApp/Signal marks share the provider badge mechanism | src/hub_test.zig, workspace-icons journey screenshot crops and check-workspace-icons.py | [Workspace icons](features/workspace-icons.md) |
| Existing account order remains stable when empty Telegram and Signal are registered | views journey and check-views-evidence.py | [Views](features/views.md) |

IGSH-589: update the maps with the implementation and describe only actual assertions. GitHub execution and screenshot inspection remain required before claiming runtime success. The Signal fixture does not prove production authentication or delivery.

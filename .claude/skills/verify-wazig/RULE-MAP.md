# Verification rule map

| Rule | Executable coverage | Feature map |
| --- | --- | --- |
| Signal is one account with opaque handles and its own saved view | src/hub_test.zig, src/messenger_view.zig, signal journey account/state assertions | [Signal](features/signal.md) |
| Linking precedes chats, with a decoded PNG and 30-second status refresh | signal journey QR and linked captures, recorded ordered link requests | [Signal](features/signal.md) |
| Signal history, text, files, reactions, read receipts, media and live events stay on the hub | signal journey, recorded writes and read-only histories, check-signal-evidence.py | [Signal](features/signal.md) |
| Signal 429/403 failures retain their reasons and never retry automatically | src/hub_test.zig mappings, signal journey failed bubbles and one-attempt ledger assertions | [Signal](features/signal.md) |
| Unsupported Signal archive settles without a retry loop | signal journey 502 and empty pending archive state | [Signal](features/signal.md) |
| New journeys appear in dispatch, PR matrix, evidence validation and maps | tools/verify-wazig/check-map.py checks Signal wiring and index links | [Index](features/README.md) |
| Slack icons and WhatsApp/Signal marks share the provider badge mechanism | src/hub_test.zig, workspace-icons journey screenshot crops and check-workspace-icons.py | [Workspace icons](features/workspace-icons.md) |
| Existing account order remains stable when empty Signal is appended | views journey and check-views-evidence.py | [Views](features/views.md) |

IGSH-589: update the maps with the implementation and describe only actual assertions. GitHub execution and screenshot inspection remain required before claiming runtime success. The Signal fixture does not prove production authentication or delivery.

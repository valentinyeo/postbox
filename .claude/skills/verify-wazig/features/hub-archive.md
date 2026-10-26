# WhatsApp archive stays in Wazig on the unified hub (IGSH-902)

## Sub-features

- On the unified hub, archiving a WhatsApp chat is stored in Wazig only, like Slack, Telegram and Signal. No archive, archive-batch or unarchive request ever reaches the hub for WhatsApp.
- A new message from someone else returns an archived chat to the inbox right away. The app marks the chat returned in its archive state, so the choice survives restart even while the hub keeps reporting the chat archived.
- His own messages, own reactions and a bare hub row-time change leave the chat archived.
- A chat the phone already shows as archived is seeded as archived the first time, then follows the same rule. These seeded entries carry a `phone` marker in the saved state. When the 2048 entry table is full, a plain unarchive, archive or keep drops the oldest `phone` entry to make room, never a user, kept or returned entry. A `phone` entry is removed when the phone no longer reports the chat archived (IGSH-920).
- Ctrl+Shift+E still keeps a chat archived: a kept chat does not return on incoming messages.
- Legacy bare keep flags migrate into the account-prefixed hub archive state, with a hub-scoped completion marker, without any hub request.

## How to get to it (user POV)

Start Messages with a configured unified hub. Ctrl+E archives the open WhatsApp chat locally and the phone list is untouched. When someone writes in it, the chat is back in the inbox. Ctrl+K, Show archived chats lists archived chats.

## Driving it with PowerShell UI Automation

Run `feature=hub-archive` on GitHub Windows Actions. Matching pull requests also run it. `run.ps1` seeds `archive-state.txt` with `120363000000000001@g.us<TAB>1<TAB>2026-10-10T10:00:00Z` and preserves its exact bytes as `legacy-archive-state.txt`.

The fake hub rejects every archive write with HTTP 400 "unexpected archive fixture write" and logs it, so one stray request is visible in `*.requests.json`. The hub never reports a WhatsApp chat as archived after a Wazig archive, which proves the archive is held in Wazig.

Legacy phase: the group is listed archived=false with a newer message. The app must keep it in Archive with keep=1, leave only the other chat in the inbox, write the prefixed state and the scoped marker, and send no archive request. Restart on the same profile with a newer incoming timestamp and require the same result and still zero writes.

Plain phase: `/fixture/plain-dms` adds two inbox direct chats. Archive each with Ctrl+E. `/fixture/plain-activity` then moves the hub row time of `personal:15550000005@s.whatsapp.net` (own reaction as newest message) and `personal:15550000006@s.whatsapp.net` (row time only), and the app is refreshed. The evidence requires the app to read the messages of both chats after the activity, both chats to stay in Archive, only the other chat in the inbox, zero archive requests, and the `plain-archive-state.txt` baseline lines. Evidence files: `plain-dms.json`, `plain-activity.json`, `plain.requests.json`, `plain-inbox` and `plain-archived` screenshots and snapshots.

Incoming phase: `/fixture/plain-incoming` gives WhatsApp `personal:15550000006@s.whatsapp.net` and Telegram `telegram:user:7001` a strictly newer message from the other side. The app reads the new message of the archived chat (a probe), and the chats return to the inbox with archived=false (`plain-incoming-inbox`), while the kept group, the original inbox chat and the reaction-only chat stay archived (`plain-incoming-archived`). Zero archive requests at every step.

Telegram part (IGSH-736, IGSH-828): `/fixture/telegram-dm` adds `telegram:user:7001` with provider `telegram` and account `telegram`. Ctrl+E, explicit unarchive, one-row bulk Ctrl+A then Ctrl+E and a profile restart all stay local with no hub request at any status. After the restart Archive holds Telegram with its real account while the inbox is empty. The state file uses `telegram<TAB>telegram<TAB>telegram:user:7001`. Proof marker: `telegram-single-bulk-restart-incoming`.

Unknown ids (IGSH-920): the control client archives and unarchives `telegram:user:99999`, `signal:ghost` and `99999`, which no chat row carries. Every call must answer `Unknown chat id`, send no hub request, and leave no line for those ids in the saved hub archive state (`UNKNOWN_ID_NOT_SAVED`). The full 2048 entry table case is proven in `src/archive_actions_test.zig` instead, because the app shows at most 256 chats per refresh.

Final state: explicitly unarchiving the original inbox chat leaves the final inbox with four chats. The returned chat is stored as `<jid><TAB>0<TAB><TAB>returned` and the checker accepts only that marker for it.

`check-hub-archive-evidence.py`, dispatched by `check-evidence.py`, requires zero archive and archive-batch requests (`NO_WHATSAPP_ARCHIVE_WRITES`), keep=1 for the legacy group, owned same-profile restart, scoped marker, screenshots and UIA, unchanged legacy bytes and isolation. Runtime and screenshot inspection are GitHub-only.

## Gotchas

- This replaces the IGSH-734 rule that kept plain archives archived and the IGSH-833 queued unarchive. Do not keep both rules.
- Unit coverage is in `src/archive_rules.zig` (returned entries, format and parse) and `src/archive_actions_test.zig` (no hub request on archive, return on incoming, phone-archived seeding, own sends, restart).
- The legacy non-unified WhatsApp path and its queue are unchanged.
- This is synthetic client-contract proof, not live WhatsApp delivery or production hub availability.
- Font, media, voice, toolbar and atomic installed executable invariants are unchanged. Builds, Zig tests, real window execution and screenshot inspection run on GitHub, never on the development host.

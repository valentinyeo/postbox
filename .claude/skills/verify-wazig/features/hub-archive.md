# Legacy Keep archived on the unified hub

## Sub-features

- Migrate a bare WhatsApp group keep flag into its account-prefixed hub archive state.
- Re-archive incoming provider-unarchived groups and retain the keep flag across restart.
- Preserve the legacy file and record migration completion in a hub-scoped marker.
- Keep a plain Ctrl+E archived direct chat archived when only his own reaction follows the archive, and when a genuinely newer incoming message arrives.

## How to get to it (user POV)

Start Messages with a configured unified hub after previously using Keep archived with the direct WhatsApp backend. The group stays out of the inbox; Ctrl+K → Show archived chats finds it with the Kept archived marker. No migration command or toolbar is added.

## Driving it with PowerShell UI Automation

Run `feature=hub-archive` on GitHub Windows Actions. Matching pull requests also run it. `run.ps1` seeds `archive-state.txt` before launch with the synthetic line `120363000000000001@g.us<TAB>1<TAB>2026-10-10T10:00:00Z` and preserves its exact bytes as `legacy-archive-state.txt`.

The unified fake hub initially lists `personal:120363000000000001@g.us` as archived=false, unread_count=1, with an incoming message and last_message_ts `2026-10-10T11:00:00Z`, plus one other inbox chat. The real app must send an authenticated `/v1/wazig/archive` request, leave only the other chat in the inbox, persist the prefixed group with keep=1, and write `hub-<tag>-archive-legacy-done.txt`.

Capture `first-inbox.png`, `first-archived.png`, their state/chat/UIA snapshots, `first-archive-state.txt`, `first-archive-legacy-done.txt` and `first.requests.json`. Archive navigation uses foreground-checked SendKeys through the palette; control clients only read state.

Quit through the palette, then have the same fake hub report archived=false again with a newer incoming timestamp `2026-10-10T13:00:00Z`. Restart the same fixture root and isolated registry using the existing restart opt-in. Require another archive request, the kept group in Archive, and only the other chat in the inbox. Capture the equivalent `restart-*` evidence plus `restart.json`, `restart-incoming.json`, `after.png` and final data through normal cleanup.

Plain archive phase (IGSH-734), after the restart phase: `/fixture/plain-dms` adds two inbox direct chats, each with one incoming message from `2026-10-10`, then the journey selects each with Ctrl+Tab and archives it with Ctrl+E. On the archive write the fake hub lists the chat as archived with a row time five seconds ahead: for `personal:15550000005@s.whatsapp.net` the new newest message is its own reaction (FromMe, ReactionToID set), for `personal:15550000006@s.whatsapp.net` it is a new incoming message. Retain the existing 360-second wait window so the idle archived scan runs after both archives. Require no archived=false write for either chat, only the other chat in the inbox, and both plain chats still listed in Archive. Preserve `plain-dms.json`, `plain-archive-state.txt`, `plain-scan.json` with elapsed time and the pre-wait request count, `plain.requests.json`, and `plain-inbox` / `plain-archived` screenshots and snapshots. The fake hub continues to accept unarchive writes so the old app's unwanted request is observable, not masked.

`check-hub-archive-evidence.py`, dispatched by `check-evidence.py`, requires the two incoming-before-write sequences, keep=1 in both snapshots, owned same-profile restart, scoped marker, screenshots/UIA, unchanged legacy bytes and isolation. Runtime and screenshot inspection are GitHub-only.

## Gotchas

- For the legacy-migration negative control, removing migration must fail at the first hub archive request: the fresh hub state has no kept row. Do not preseed the hub state or use a control archive write.
- The completion marker prevents later unarchive choices being undone by the retained legacy file. Unit coverage handles missing-row precedence, non-kept entries and provider/account matching; this journey does not exercise those user choices.
- The plain phase retains the 360-second window beyond the 300-tick idle archived scan. On the app before IGSH-734, the newer incoming message triggers an archived=false write for 0006; this must fail even if the inbox later changes.
- This is synthetic client-contract proof, not live WhatsApp delivery, production hub availability or Slack archive semantics.
- Font, media, voice, toolbar and atomic installed executable invariants are unchanged. Builds, Zig tests, real window execution and screenshot inspection must run on GitHub, never on the development host.

### Sticky plain archives and the last Telegram row (IGSH-736)

The original migration, restart, reaction and 360-second scan steps above remain required. After those steps, `/fixture/telegram-dm` adds the direct handle `telegram:user:7001` with provider `telegram` and account `telegram`, deliberately different from the hub cache tag. Archive the original remaining WhatsApp inbox row with Ctrl+E. Press Alt+I and capture `telegram-only`: the combined inbox must contain exactly that Telegram row. Ctrl+E archives it locally, empties the inbox and clears the selection; capture `telegram-empty`. No Telegram archive request may reach the hub, whose `/v1/wazig/archive` response for this chat is HTTP 502 `{"error":"Telegram action unsupported"}`, matching the live hub rather than pretending the action is supported.

Explicitly unarchive Telegram with Ctrl+E in Archive, return to its sole inbox row and capture `telegram-unarchived`, then select it with Ctrl+A and press Ctrl+E. This preserves the one-row bulk account-identity regression check. Capture `telegram-bulk-empty`. Single-row and bulk actions both stay local; neither archive nor unarchive may issue a Telegram hub request, including failed requests.

Restart the same isolated app profile again. Capture `telegram-restart-empty`, `telegram-restart-archived` and `telegram-restart.json`. Archive must contain Telegram with its real account and archived=true, while the combined inbox stays empty. Both restart ownership records must form one chain ending at the final session PID/start identity.

`/fixture/plain-incoming` then reports the plain WhatsApp DM `personal:15550000006@s.whatsapp.net` and Telegram as archived=false, with strictly newer incoming last_message_ts and FromMe=false messages. The fake hub rejects WhatsApp archive writes with 409 until `/fixture/rearchive-enable`, so UI filtering cannot pass merely because a fast server already re-archived the rows. Capture `plain-incoming-inbox` (empty) and `plain-incoming-archived` (all five chats still archived), including read-only control state, screenshots and UIA. Telegram remains archived solely from local state, despite the stale flag and new message.

Enable writes and require exactly one additional successful WhatsApp archive, no extra re-archive on an unchanged timestamp, no Telegram archive request and no unsolicited unarchive. Refresh, capture `plain-rearchived-inbox` and `plain-rearchived-archived`, and save `telegram-archive-state.txt`. WhatsApp DMs remain keep=0; Telegram uses the account-scoped local line `telegram<TAB>telegram<TAB>telegram:user:7001`. Explicitly unarchive only the original inbox chat to preserve the existing final inbox assertion. Save `telegram.requests.json` and the `telegram-single-bulk-restart-incoming` proof marker.

Telegram and Signal use the same local archive path as Slack only in hub mode. Local entries store provider, account and id; the existing `slack<TAB>account<TAB>id` and WhatsApp formats remain readable and unchanged. Old plain `telegram:` and `signal:` entries with keep=0 or keep=1 load as local archives with account-independent legacy matching. Saving upgrades them to provider-tagged local entries; explicit unarchive removes them. Unit coverage in `src/archive_rules.zig` checks both legacy formats, provider/account separation and restart round trips. `src/archive_actions_test.zig` covers both providers' single-row focus paths, bulk actions, no hub writes, explicit unarchive, stale incoming flags, send completion, late 502 preservation and the unchanged non-hub unsupported status. Both displayed rows and read-only account/combined list queries use local archive state; provider flags cannot override local unarchive.

Negative controls: the pre-fix client sends Telegram archive writes and removes its saved intent on the real 502, failing the zero-write and empty-inbox requirements. The Python source-contract test is red on commit A and green only once both unsupported providers enter the hub-local route. The evidence checker independently rejects Telegram requests at any status, duplicate WhatsApp re-archives, unchanged timestamps, absent hub flags, wrong provider identity, inbox returns, missing restart rows, missing explicit-unarchive proof and lost local state. The earlier migration, plain WhatsApp and reaction checks remain required.

This journey proves only the configured Telegram client contract; Signal behavior has unit coverage, not a Windows UI journey. Windows runtime execution, Zig unit execution and screenshot inspection still require authorized CI verification. It does not prove live provider delivery or production hub availability. Font, media, voice, toolbar and atomic executable invariants remain untouched.

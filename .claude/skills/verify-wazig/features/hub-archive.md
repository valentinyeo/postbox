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

The original migration, restart, reaction and 360-second scan steps above remain required. After those steps, `/fixture/telegram-dm` adds the direct handle `telegram:user:7001` with provider `telegram` and account `telegram`, deliberately different from the hub cache tag. Archive the original remaining WhatsApp inbox row with Ctrl+E. Press Alt+I and capture `telegram-only`: the combined inbox must contain exactly that Telegram row. Ctrl+E must issue the real client body `{"chat":"telegram:user:7001","archived":true}` to `/v1/wazig/archive` and empty the inbox (`telegram-empty`).

Explicitly unarchive Telegram with Ctrl+E in Archive, return to its sole inbox row, select it with Ctrl+A, then Ctrl+E. This second case covers the concrete early-return bug: `archiveBulkSelection` used to compare every non-Slack account to the local WhatsApp cache tag even in unified hub mode. It rejected the Telegram key before `archiveChat` could write state or queue the request. The ordinary single-row path is measured separately, not assumed broken. Its focus whitelist accepts the composer, list, canvas and main window; its displayed-key safety guard and bounds checks remain intact.

Restart the same isolated app profile again. Capture `telegram-bulk-empty`, `telegram-restart-empty`, `telegram-restart-archived` and `telegram-restart.json`. The archive snapshot must contain Telegram with its real account and archived=true, while the combined inbox stays empty. Both restart ownership records must form one chain ending at the final session PID/start identity.

`/fixture/plain-incoming` then flips the plain WhatsApp DM `personal:15550000006@s.whatsapp.net` and Telegram to archived=false, with a strictly newer incoming last_message_ts and FromMe=false messages. The fake hub rejects archive writes with 409 until `/fixture/rearchive-enable`, so UI filtering cannot pass merely because a fast server already re-archived the rows. Capture `plain-incoming-inbox` (empty) and `plain-incoming-archived` (all five chats still archived), including read-only control snapshots. The real hub GET log must show both archived=false rows at the new timestamp.

Enable writes and require exactly one additional successful archive per changed chat, no extra re-archive on an unchanged timestamp, and no unsolicited unarchive. Refresh, capture `plain-rearchived-inbox` and `plain-rearchived-archived`, save `telegram-archive-state.txt` with both DMs still keep=0, and explicitly unarchive only the original inbox chat to preserve the existing final inbox assertion. Save `telegram.requests.json` and the `telegram-single-bulk-restart-incoming` proof marker.

Negative controls: origin/main's keep-only hold produces no re-archive for either plain DM; its hub-flag list filter exposes those chats and omits them from Archive. Its bulk account guard rejects the sole Telegram selection without a request or state entry. The extended evidence checker rejects each missing archive independently, duplicate re-archives, unchanged timestamps, absent network flips, wrong provider identity, inbox returns, missing restart rows and lost plain state. These controls and fixture contracts run in the lightweight Python suite; real Zig tests and the Windows journey still run only on GitHub. This does not claim a runtime reproduction on the development host or identify unobserved focus state on a production PC.

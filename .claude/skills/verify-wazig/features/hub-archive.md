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

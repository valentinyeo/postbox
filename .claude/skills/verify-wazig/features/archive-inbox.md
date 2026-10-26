# Archive intent, repeated select all and batched bulk timing

## Sub-features

- Local archive intent survives hub rows with no archived field, Ctrl+2 and same-profile restart.
- Sidebar and read-only control rows report archived=true and an archive label.
- Ten independent Ctrl+A presses select all 264 visible chats, including rows beyond the old 256-row snapshot.
- Ctrl+E sends one WhatsApp batch request, completes every selected provider path and reports total and per-chat elapsed milliseconds.
- Ctrl+E writes an ordinary archive in every channel: Slack, Telegram and Signal store lines carry keep=0 and an archive time, and every archived row reads Archived, never Kept archived (IGSH-828).
- One failed batch item does not discard later successes or erase saved archive intent; the native archive harness covers mixed results.

## How to get to it (user POV)

Open the combined inbox. Focus the empty composer, chat list or message canvas and press Ctrl+A. Ctrl+E archives the complete selection. Ctrl+2 must not bring the sessions back. Open Show archived chats through Ctrl+K to see their archive labels. Composer text still uses text select all.

## Driving it with PowerShell UI Automation

Run after the freeze, once the branch is available on GitHub:

`gh workflow run verify.yml --ref ceo/IGSH-777 -f feature=archive-inbox`

Recipe: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature archive-inbox -Bin zig-out/bin -Evidence verification-evidence`.

The fake unified hub returns 261 WhatsApp chats and one Slack, Telegram and Signal chat. Every chat response omits the archived field, including after successful archive writes. The archived endpoint returns no rows, so archive identity must come from durable local intent. All data is synthetic.

Type hello and require text select all first. Clear the text. Alternate empty composer 1032 and chat list 1016 focus for ten actual Ctrl+A presses. Between presses, Esc must clear the preceding selection; read-only `bulk_selected_count` must return to zero and then reach 264, so stale selection state cannot pass. Emit `ctrl_a_press=<n> ok=<true|false>` ten times and `ctrl_a_ok=<count of 10>`. Save ctrl-a.json and selected.png.

Time Ctrl+E through zero pending archives and an empty sidebar. WhatsApp archive stays in Wazig (IGSH-902), so the hub must see zero `/v1/wazig/archive` and zero `/v1/wazig/archive-batch` requests. Emit `bulk_archive_ms_total=<n> bulk_archive_ms_per_chat=<n>`. bulk-timing.json records the fixed 264-chat workload, 261 remote chats and single and batch request counts, both zero. Save timing and archive.requests.json before asserting. Slack, Telegram and Signal paths also issue no hub archive request. The measurement includes local persistence and harness observation. It imposes no new timing threshold or artificial delay.

Refresh, open Archive, require all 264 sidebar and control rows archived with labels and emit `archived_among_shown=264`. Preserve saved-archive-state.txt. Return to Inbox, press Ctrl+2 and require zero rows. Quit and restart the same isolated profile, return to the combined inbox and require zero rows, then Archive and require all 264 identities again. Save restart.json, archive.requests.json, before/selected/empty/archived/account-empty/restart-empty/after screenshots and matching state, chat and UIA snapshots.

## Gotchas

- This proves the client contract against an exact metadata-free hub shape, not live provider delivery or production hub latency.
- The old client discards plain WhatsApp intent, treats keep=0 as unarchived and truncates selection at 256. It cannot satisfy all 264 archived rows after acknowledgement and refresh.
- Single-chat selections retain `/v1/wazig/archive` (or `/v1/archive` on the direct bridge); multi-chat selections use the batch route, including a mixed selection with only one remote chat. Slack remains local because the production hub rejects Slack archive; Telegram and Signal remain local too.
- The baseline fixture has 261 WhatsApp chats, not 264, and none of them send a request: the other three selected chats are local-only. No archive entries may be cleared to change that workload or make the assertions pass.
- `TestArchiveBatchIndependentResults` and `TestArchiveBatchForwardedOnce` cover server-side partial failure and one bridge forward; the client archive harness covers independent acknowledgements. None of these synthetic results prove live delivery.
- Existing condition-based harness synchronization is reused. No fixed waits, settings, timeouts or caps are added. Windows execution, screenshot inspection and old-code failure output remain GitHub-only.

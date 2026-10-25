# Archive intent, repeated select all and bulk timing

## Sub-features

- Local archive intent survives hub rows with no archived field, Alt+1 and same-profile restart.
- Sidebar and read-only control rows report archived=true and an archive label.
- Ten independent Ctrl+A presses select all 264 visible chats, including rows beyond the old 256-row snapshot.
- Ctrl+E completes every selected provider path and reports total and per-chat elapsed milliseconds.

## How to get to it (user POV)

Open the combined inbox. Focus the empty composer, chat list or message canvas and press Ctrl+A. Ctrl+E archives the complete selection. Alt+1 must not bring the sessions back. Open Show archived chats through Ctrl+K to see their archive labels. Composer text still uses text select all.

## Driving it with PowerShell UI Automation

Run after the freeze, once the branch is available on GitHub:

`gh workflow run verify.yml --ref ceo/IGSH-767 -f feature=archive-inbox`

Recipe: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature archive-inbox -Bin zig-out/bin -Evidence verification-evidence`.

The fake unified hub returns 261 WhatsApp chats and one Slack, Telegram and Signal chat. Every chat response omits the archived field, including after successful archive writes. The archived endpoint returns no rows, so archive identity must come from durable local intent. All data is synthetic.

Type hello and require text select all first. Clear the text. Alternate empty composer 1032, chat list 1016 and canvas 1024 focus for ten actual Ctrl+A presses. Between presses, Esc must clear the preceding selection, so stale success text cannot pass. Emit `ctrl_a_press=<n> ok=<true|false>` ten times and `ctrl_a_ok=<count of 10>`. Save ctrl-a.json and selected.png.

Time Ctrl+E through zero pending writes, an empty sidebar and all 261 successful WhatsApp acknowledgements. Emit `bulk_archive_ms_total=<n> bulk_archive_ms_per_chat=<n>`. bulk-timing.json records the fixed 264-chat workload and 261 remote writes. Local-only Slack, Telegram and Signal paths must issue no hub archive request. The measurement includes local persistence, dispatch, acknowledgements and harness observation, not just optimistic row removal. It imposes no new timing threshold or artificial delay.

Refresh, open Archive, require all 264 sidebar and control rows archived with labels and emit `archived_among_shown=264`. Preserve saved-archive-state.txt. Return to Inbox, press Alt+1 and require zero rows. Quit and restart the same isolated profile, return to the combined inbox and require zero rows, then Archive and require all 264 identities again. Save restart.json, archive.requests.json, before/selected/empty/archived/account-empty/restart-empty/after screenshots and matching state, chat and UIA snapshots.

## Gotchas

- This proves the client contract against an exact metadata-free hub shape, not live provider delivery or production hub latency.
- The old client discards plain WhatsApp intent, treats keep=0 as unarchived and truncates selection at 256. It cannot satisfy all 264 archived rows after acknowledgement and refresh.
- There is still one hub POST per WhatsApp chat, not a new batch API. The fix removes redundant inbox refreshes between archive acknowledgements without skipping provider writes.
- Existing condition-based harness synchronization is reused. No fixed waits, settings, timeouts or caps are added. Windows execution, screenshot inspection and old-code failure output remain GitHub-only.

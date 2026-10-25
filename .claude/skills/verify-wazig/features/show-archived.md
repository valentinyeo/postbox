# Show archived in each view

## Sub-features

- Independent Show archived switches for all accounts and the combined inbox.
- Archived rows remain marked; Ctrl+E toggles archive without removing mixed rows.
- Ctrl+K → archive finds the per-view switch with its current On/Off state; the former sidebar button, tooltip and click target are absent. Alt+A remains a keyboard shortcut.
- Archived rows use theme-derived dimming in the sidebar, combined inbox and search, returning to full strength on hover or selection.
- Same-profile restart restores inbox and account preferences; archived-only stays separate.
- With Show archived off in hub mode, the sidebar and the read-only chat scans ask the hub for both lists and hide a row only when its local archive entry keeps it archived (IGSH-763).

## How to get to it (user POV)

Alt+I opens the combined inbox; Alt+1..9 opens an account. Alt+A toggles Show archived for that view. There is no sidebar Show archived button. Ctrl+K offers Toggle archived chats in this view: On/Off, with Alt+A shown. Inbox mixed mode keeps only unread chats, normal and archived, by time. Account mixed mode retains its existing unread filter and includes archived chats. Ctrl+E unarchives an archived selection or archives a normal selection; both stay visible in mixed mode. Show archived chats remains the separate archived-only palette command.

## Driving it with PowerShell UI Automation

Run `feature=show-archived` on GitHub Windows Actions; the registry adds it to the PR workflow matrix. `ShowArchivedHandler` seeds two WhatsApp accounts, Slack, Telegram and Signal. Each has normal read/unread and archived read/unread rows. Probe requests (limit=20) supply synthetic unread timestamps; normal history is empty so automatic reading does not consume the unread filter fixture while navigating.

`show-archived.ps1` drives Alt+I, the unread command and Alt+A, records inbox-off and inbox-on, then requires UIA button 1146 and its drawn label to be absent, clicks its former centre with real mouse input, and observes unchanged state for a second. Each account is off independently before being enabled. All five accounts exercise Ctrl+E archive/unarchive on the normal read row, retaining counts, selection and archive labels. Account one remains enabled while all others are disabled. The journey checks the archived-only command, quits by keyboard and relaunches the exact same isolated profile. restart-inbox, restart-one and restart-two prove independent saved values. Screenshots, UIA, status and visible chat snapshots accompany every phase. The strict evidence checker is dispatched by check-evidence.py through journeys.json and has Python positive and mutation controls.

## Gotchas

The IGSH-823 journey-only commit is red on its main baseline: button 1146 is still present, the palette switch lacks its state, and archived rows are not dimmed. No live provider accounts or real delivery are verified. Windows execution and screenshot inspection must happen on Actions, not locally. Telegram, Signal and Slack actions must have no archive endpoint writes; WhatsApp actions must send both archive and unarchive.

IGSH-823 extends this same isolated fixture with `archive-{sidebar,inbox,search}-{dim,hover,selected}` screenshots, layout/state snapshots and independently recomputed `.contrast.json` measurements. `archive-palette-*.palette.json` proves typing archive finds one stateful switch above the fold and Enter flips it twice; `archive-identities.json` proves archived identities are unchanged. Archived text, muted text and accent colours mix each RGB channel as `floor((180 * foreground + 75 * row_background) / 255)` before buffered drawing; hover, selection and bulk selection bypass the mix. There is no row overlay or additional DC/bitmap. Layout evidence records `theme-foreground-mix` and the theme foreground weight. The pixel validator independently checks the measured text against this mix within eight channel levels, requires the unchanged row background, measures foreground/background WCAG contrast and reports `(archived_contrast - 1) / (live_contrast - 1)` as contrast evidence, not an alpha/opacity estimate, with a blank old-footer pixel crop as a drawn-label absence assertion. Full-strength probes require archived text contrast at least 90% of the live row's contrast, with live contrast at least 4.5, tolerating ClearType channel differences without accepting dimmed hover/selection. Synthetic negative controls reject the old footer, inert-click regression, missing dimming and dimmed hover/selection.

The workflow repeats the production journey in `light/` after rebuilding with only the sixteen AMOLED colour tokens inverted. This is a light fixture palette, not a new product theme or setting; all rendering and input paths remain production code. `fixture-palette.json` retains both token sets and the two session records retain distinct executable hashes. Both polarities must pass, and `--both` reports all measured contrast numbers. No local build or test execution substitutes for the Windows runs.

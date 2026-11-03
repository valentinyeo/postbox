# First search finds archived chats

## Sub-features

- The very first search after a fresh app start lists archived chats, marked `Archived`, without a second try.
- The archived list loads when the app connects to the hub, not twenty seconds later.
- Archive and return changes still refresh the archived list.

## How to get to it (user POV)

Start Postbox. Straight away press Ctrl+F and type the name of an archived chat. The chat is listed with its Archived mark on the first search. Before the fix the list stayed empty until the second try.

## Driving it with PowerShell UI Automation

Run `feature=archived-search` through `tools/verify-wazig/run.ps1` on hosted Windows. The registry in `journeys.json` selects the isolated palette hub in `fake-hub.py` (`PaletteArchivedHandler`). The journey quits the app and starts it again, which is a fresh start on the same profile. It presses Ctrl+F, types the name of the archived test chat and waits up to 8 seconds for the row `Archived Person Alpha  ·  Archived`. The time since start and the rows are saved in `first-search.json`, plus a screenshot.

## Gotchas

- The restart reuses the same profile through `WAZIG_VERIFY_RESTART`.
- The old code scanned for archived chats about 20 seconds after start, so a first search inside that window found nothing.
- Test data only. No real contact names or message text.

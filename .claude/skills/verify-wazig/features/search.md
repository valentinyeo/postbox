# Chat search

Find a chat by its displayed name or identifier, distinguish a no-match result and restore the inbox without changing stored chats.

## Sub-features

- `search-center`: placeholder and typed ink are horizontally and vertically centered in the pill.
- `search-focus`: focus the sidebar search.
- `search-match`: live filtering matches names and identifiers case-insensitively.
- `search-empty`: an absent query produces zero visible chats.
- `search-clear`: Escape restores the complete chat list.

## How to get to it (user POV)

- Press Ctrl+F, or `/` outside an editable field.
- Click the sidebar search field, whose cue is `Search All  Ctrl+F` in the baseline view.
- Ctrl+K → `Search chats` focuses that same field.

## Driving it with PowerShell UI Automation

Preconditions: a successful doctor, Alpha and Beta in the baseline sidebar, no draft.

- **Run:** dispatch `feature=search`; the helper is `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature search` on GitHub only.
- **Before:** `before.png` shows both chats. UI Automation resolves search by AutomationId `1008`.
- **Center placeholder:** focus `Compose message` through the palette, confirm search is empty and unfocused, and capture `search-center-placeholder.png` cropped to the pill.
- **Match:** `Send-Keys $session '^f'`, then `Send-Keys $session 'Beta'`. Wait for read-only status `search=Beta`, `chat_count=1`, selected name `Verification Beta`. `after.png` must visibly show Beta and no Alpha.
- **Center typed:** with search focused and exactly `Beta`, capture `search-center-typed.png`. `search-center-layout.json` records each crop's pill and edit bounds, the UI Automation `1008` screen bounds, DPI, text and focus. Recover the pill from the edit by undoing `layoutRegion`'s one physical pixel vertical inset and `field_pill.compute`'s horizontal inset: ceil(min(scaled 56, edit height + 2) / 2). Both crops use pill-local physical pixels, not window-relative or DPI-scaled coordinates.
- **Center oracle:** `python tools/verify-wazig/check-search-center.py verification-evidence` compares the text ink bounding-box center to the pill center, excluding rounded edges and thin tall caret columns. It writes `search-center.json` with placeholder and typed `dx`/`dy`. Both must satisfy `|dx| <= 2` and `|dy| <= 1` physical pixels; the search matrix job fails otherwise. The `verify-wazig-search` artifact includes both crops, bounds and offsets, even when the pixel check fails.
- **Clear:** `Send-Keys $session '{ESC}'`; wait for two chats.
- **No match:** Ctrl+F, type `NoSuchFixture`; wait for zero chats and capture `empty.png`.
- **Restore:** Escape must return two chats. Check the unchanged two-entry cached chat file plus zero pending writes in `side-effects.json`.

## Gotchas

- Filtering is debounced by a 240 ms timer; wait for resulting state.
- Slash in an editable field inserts text instead of focusing search.
- Palette fuzzy search is a different feature; a palette result is not proof of sidebar filtering.
- The screenshot, not just a status count, must show the query and remaining chat. The archive provider fixture does not supply `.archived_scan` or `.contacts_index` jobs, so neither this recipe nor archive proves cross-inbox archived/contact lookup. That requires a populated provider people index.
- Source: `src/main.zig:3915` builds the view-specific cue, `src/main.zig:2410` merges indexed people into inbox search, and `src/main.zig:16157` debounces for 240 ms. `src/main.zig:16521` handles Ctrl+F.

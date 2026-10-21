# Chat search

Find a chat by its displayed name or identifier, distinguish a no-match result and restore the inbox without changing stored chats.

## Sub-features

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
- **Match:** `Send-Keys $session '^f'`, then `Send-Keys $session 'Beta'`. Wait for read-only status `search=Beta`, `chat_count=1`, selected name `Verification Beta`. `after.png` must visibly show Beta and no Alpha.
- **Clear:** `Send-Keys $session '{ESC}'`; wait for two chats.
- **No match:** Ctrl+F, type `NoSuchFixture`; wait for zero chats and capture `empty.png`.
- **Restore:** Escape must return two chats. Check the unchanged two-entry cached chat file plus zero pending writes in `side-effects.json`.

## Gotchas

- Filtering is debounced by a 240 ms timer; wait for resulting state.
- Slash in an editable field inserts text instead of focusing search.
- Palette fuzzy search is a different feature; a palette result is not proof of sidebar filtering.
- The screenshot, not just a status count, must show the query and remaining chat. Fixtures do not cover the live contacts/archived lookup.

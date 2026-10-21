# Keyboard chat navigation

Move between chats while keeping the selected conversation and its composer aligned.

## Sub-features

- `navigation-next`: next and previous chat, with wraparound.
- `navigation-position`: Ctrl+1 through Ctrl+9 selects a list position.
- `navigation-edges`: jump to the first or last chat.
- `navigation-page`: move by a page; sidebar arrow keys and mouse selection are also available.

## How to get to it (user POV)

- Ctrl+Tab / Ctrl+Shift+Tab, or Ctrl+K → `Next chat` / `Previous chat`.
- Ctrl+1..9; Ctrl+Shift+Home / Ctrl+Shift+End; Ctrl+Page Up / Ctrl+Page Down.
- Focus the chat list for Up/Down, or click a chat row.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes, two unfiltered chats, Alpha selected and composer empty.

- **Run:** dispatch `feature=navigation`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature navigation`.
- **Before:** capture Alpha selected in `before.png` and `before.state.json`.
- **Next:** `Send-Keys $session '^{TAB}'`; wait for `status.selected.name=Verification Beta`. Capture `after.png`; the sidebar selection must agree with the read-only selected-chat identity.
- **Back:** `Send-Keys $session '^+{TAB}'`; wait for Alpha again.
- **Side effects:** the fixture file retains both chats, sync stays stopped and no send/archive is pending. Positional, edge and page shortcuts are mapped entry points, not exercised by this default recipe.

## Gotchas

- Search changes list positions; reset it before positional navigation.
- Up/Down in a non-empty composer edits text; with an empty composer and loaded messages it can move the message highlight.
- The fixture has no messages, so it cannot prove selection/scrolling within a message history or mark-read transport.

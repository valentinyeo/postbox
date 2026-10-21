# Composer and per-chat drafts

Type a message draft, leave the chat and return to the same unsent text without leaking it to another conversation.

## Sub-features

- `draft-type`: enter and edit composer text.
- `draft-switch`: restore each chat's own draft when switching conversations.
- `draft-persist`: unsent drafts are saved to local storage.
- `draft-newline`: Shift+Enter inserts a newline; Enter normally sends.

## How to get to it (user POV)

- Click the message box, or choose Ctrl+K → `Compose message`.
- `C` outside editable fields focuses the composer; selecting a chat also focuses it.
- Type text; Ctrl+A selects the text. Switch chats using the sidebar or Ctrl+Tab.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes; Alpha selected, both chats have empty drafts, composer `1032` enabled.

- **Run:** dispatch `feature=drafts`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature drafts`.
- **Type:** `Send-Keys $session 'Verification draft'` into the focused composer after capturing `before.png`.
- **Switch:** `Send-Keys $session '^{TAB}'`; read composer through bounded read-only `WM_GETTEXT` and require empty text in Beta.
- **Restore:** `Send-Keys $session '^+{TAB}'`; wait for native edit text `Verification draft`. Capture `after.png` showing the draft in Alpha.
- **Persistence:** wait for `Messages/drafts.json` containing the synthetic text; preserve it as `drafts.json` and in `final-data/`. Require zero pending sends and no provider store. The recipe proves disk save plus in-session restoration, not restoration after process restart.

## Gotchas

- Never press Enter for this journey. Verification disables sending; a disabled send is not proof of transport.
- Draft persistence runs on the one-second refresh timer and on chat changes/close; wait for the file.
- User drafts are private. Use only the provided synthetic text and disposable GUID profile, never copy real stores into evidence.

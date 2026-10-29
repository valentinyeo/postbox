# Composer and per-chat drafts

Type a message draft, leave the chat and return to the same unsent text without leaking it to another conversation.

## Sub-features

- `draft-type`: enter and edit composer text.
- `composer-compact`: ignore old saved height floors; start empty at one line, clear hint pixels while typing, grow to the existing cap, scroll internally, and shrink after clearing.
- `draft-switch`: restore each chat's own draft when switching conversations.
- `draft-persist`: unsent drafts are saved to local storage.
- `draft-newline`: Shift+Enter inserts a newline; Enter normally sends.
- `composer-one-box`: one visible rounded composer contains Attach, text, mic, Dictate, emoji and Send; icons stay bottom-anchored as text grows at wide and narrow widths in AMOLED and Green.

## How to get to it (user POV)

- Click the message box, or choose Ctrl+K → `Compose message`.
- `C` outside editable fields focuses the composer; selecting a chat also focuses it.
- Type text; Ctrl+A selects the text. Switch chats using the sidebar or Ctrl+Tab.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes; Alpha selected, both chats have empty drafts, composer `1032` enabled.

- **Run:** dispatch `feature=drafts`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature drafts`.
- **Compact sizing:** seed the isolated legacy height preference, capture empty and typed states, compare incremental painting with a clean redraw below the first text row, then prove two-line growth, the existing height cap, native scroll positions and clear/reset screenshots. Preserve `composer-behavior.json`.
- **Type:** `Send-Keys $session 'Verification draft'` into the focused composer after capturing `before.png`.
- **Edit:** replace a Shift-arrow selection, undo/redo it, delete a word with Ctrl+Backspace, then exercise Ctrl+V and Shift+Insert guarded paste exactly once. Compare the bounded native text with UIA ValuePattern after each operation; preserve `paste.png`. Shift+Enter plus `second` must produce exactly two lines before restoring the baseline draft.
- **Switch:** `Send-Keys $session '^{TAB}'`; read composer through bounded read-only `WM_GETTEXT` and require empty text in Beta.
- **Restore:** `Send-Keys $session '^+{TAB}'`; wait for native edit text `Verification draft`. Capture `after.png` showing the draft in Alpha.
- **One-box layout:** after the existing draft checks, use the palette to select AMOLED black and Green. Repeat at maximized and 600-DIP window widths. Type `One`, then Shift+Enter with `Two` and `Three` so soft wrapping does not change the expected line count. Read-only `status.composer` reports the painted box, native control bounds and edit line count. Measure client origin, bottom and DPI through native APIs; require the box at the client bottom inset and every icon bottom at the box bottom inset. Cross-check UI Automation bounds/names, require every control inside the box, no overlaps, upward growth and unchanged icon positions. Require eight `composer-one-box ... PASS` lines in `composer-one-box.log`; preserve `composer-{amoled,green}-{wide,narrow}-{one,multiline}.png`, `.layout.json`, `.state.json` and `.uia.txt`. Inspect screenshots for the continuous surface/border and existing Dictate rendering. PRs run both search and drafts; `feature=drafts` dispatch runs this full leg.
- **Persistence:** wait for `Messages/drafts.json` containing the synthetic text; preserve it as `drafts.json` and in `final-data/`. Require zero pending sends and no provider store. The recipe proves disk save plus in-session restoration, not restoration after process restart.

## Gotchas

- Ctrl+End belongs to global chat scrolling. Move Down through the capped draft to prove its own internal scrolling.

- Never press bare Enter in the composer for this journey; Shift+Enter adds lines and palette Enter applies the selected theme. Verification disables sending; a disabled send is not proof of transport.
- Draft persistence runs on the one-second refresh timer and on chat changes/close; wait for the file.
- Attach reuses Ctrl+K → `Attach photo or file`: the existing picker stages Slack/Telegram files, with the button disabled and its tooltip explaining unsupported providers or Slack bridges. This journey does not open the picker, record audio or send.
- User drafts are private. Use only the provided synthetic text and disposable GUID profile, never copy real stores into evidence.
- Source: `src/main.zig:10320` saves composer drafts, `src/main.zig:10373` restores the selected identity, and `src/shortcuts.zig:49` lists composer keys. The editing/layout assertions are in `tools/verify-wazig/run.ps1:193`.

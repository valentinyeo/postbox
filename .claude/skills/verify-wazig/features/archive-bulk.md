# Bulk chat archive

Select every visible chat from the empty composer and archive the selection without moving focus to the chat list.

## Sub-features

- `archive-bulk`: Ctrl+A selects the filtered chat list from list focus or an empty main composer; Ctrl+E archives the selection.
- `archive-bulk-text`: Ctrl+A with composer text still selects that text rather than chats.
- `archive-bulk-cancel`: the palette command Cancel selection clears the selected chats.

## How to get to it (user POV)

- Focus the chat list or leave the main message box empty and press Ctrl+A.
- Ctrl+E archives all selected chats; Ctrl+Shift+E keeps them archived; Esc cancels selection.
- With text in the message box, Ctrl+A selects the text instead.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes; synthetic Alpha and Beta are unarchived in `verification-provider.json` and the matching chat cache. No real provider is connected.

- **Run:** dispatch `feature=archive-bulk`; recipe: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature archive-bulk`.
- **Before:** focus composer `1032`, require empty text and save `before.png` with status and chat snapshots.
- **Select:** send `^a`; read `wazigctl status` and require `bulk_selected_count=2`. Save `selected.png` and require composer focus remains unchanged. Picking a chat through the palette clears the selection; Ctrl+A then the palette command `Cancel selection` clears it again, and Ctrl+A selects both once more.
- **Archive:** send `^e`; require zero pending archives, both fixture provider rows archived and zero inbox chats through read-only `chats`. Save `after.png` and matching snapshots. Cleanup preserves the provider file in `final-data`.
- **Text:** the empty inbox disables the composer, so open `Show archived chats` through Ctrl+K before refocusing composer `1032`. Type `hello`, send `^a`, require UIA TextPattern selection to contain all of `hello` and no chats-selected status. Save `text-selected.png`, then clear the composer.

## Gotchas

- Failure messages include `bulk`; the original keyboard handler fails at `bulk: Ctrl+A in empty composer selected no chats` because composer focus always selects text.
- This journey proves Ctrl+A from the empty composer, `Cancel selection`, Ctrl+E bulk archive, and, only when the combined inbox lists at least five chats (`journey-archive-bulk.ps1` skips the step otherwise), Ctrl+click to add chats, Shift+click for a range and Esc to clear the selection. It does not drive Ctrl+A from list focus or Ctrl+Shift+E on a selection. Those reuse existing production paths; the pure shortcut tests cover the focus decision.
- All actions use the existing foreground-checked SendKeys or UI Automation focus. Provider reads and archive acknowledgements use the isolated fixture boundary; control status/chats and native text reads do not mutate app state.
- No live delivery, font, scale, toolbar, media, updater or installed executable changes are involved.

# Command palette and shortcut discovery

Find commands without a toolbar and open the keyboard-shortcuts overlay through the same palette a user sees.

## Sub-features

- `palette-open`: open the command palette.
- `palette-filter`: fuzzy-filter registered command labels and chat names.
- `palette-activate`: Enter activates the selected item; Escape cancels.
- `palette-no-status`: the removed WhatsApp Status command and sidebar entry stay absent.
- `palette-help`: discover keyboard shortcuts in the help overlay.

## How to get to it (user POV)

- Ctrl+K opens the palette; type a command label.
- Up/Down changes the selection; Enter runs it; Escape closes the palette.
- Choose `Keyboard shortcuts` in the palette, or press F1 directly to open the same overlay.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes, no overlay open and no search query.

- **Run:** dispatch `feature=palette`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature palette`.
- **Open/filter:** after `before.png`, `Send-Keys $session '^k'`, resolve `Get-PaletteWindow $session`, then type `Keyboard shortcuts`. The shared helper used by `Invoke-PaletteCommand` searches `Get-Window $session` descendants for class `MessagesPalette` and the session PID, not desktop root children. Edit `1064` is a DirectWrite-backed `RICHEDIT50W`; `Read-Edit` checks bounded read-only `WM_GETTEXT` against its UIA ValuePattern. Capture `action.png` showing the filtered command.
- **Removal:** resolve the owned palette's native `LISTBOX` `1072`. `Read-ListCount` sends only read-only `LB_GETCOUNT` (`0x018B`, zero parameters) through `SendMessageTimeoutW` with `SMTO_ABORTIFHUNG` and a 2000 ms timeout; a timeout or invalid count fails, never becomes zero. The `Keyboard shortcuts` filter must have one native row as a positive control. Replace the query with `Status`; require zero native rows and no former sidebar control `1120`. Preserve `removed-status.json`, `removed-status.png` and state/UIA snapshots, then restore the shortcut query and its one row.
- **Activate:** `Send-Keys $session '{ENTER}'`; wait for a descendant of the owner window with class `MessagesShortcutHelp` and the session PID, then capture `after.png`. Inspect the screenshot for the shortcut text; the automated assertion proves the overlay class exists, not its drawn contents.
- **Close:** Escape returns to the app; no sends/archives or fixture storage mutations are expected.

## Gotchas

- List `1072` uses `LBS_OWNERDRAWFIXED` without `LBS_HASSTRINGS`; `paletteFilter` adds one native item per match with item data, not text. UIA ListItem children/labels are not a reliable row-count oracle for this non-string owner-drawn control; `LB_GETCOUNT` reads the actual native item count without changing text, selection or state. Do not invoke a synthetic row or send `WM_COMMAND`; use the real filter and Enter path.
- Keep keyboard focus in the palette; reactivating the main window between keystrokes can lose popup focus.
- The help popup has no title; its stable selector is its class and owned process, not a fabricated window name.
- Source: `src/main.zig:12591` registers commands without Status, `src/main.zig:12716` filters real list rows, `src/main.zig:13149` creates edit `1064`, `src/main.zig:13154` creates list `1072`, and `src/main.zig:13417` opens owned shortcut help. `src/shortcuts.zig:69` lists app shortcuts.
- On a unified hub the palette also lists archived chats and chats of other views, matched by name and scored like commands; archived rows end in `  ·  Archived` and Enter opens them without unarchiving. The `palette-archived` journey drives this; see [palette-archived](palette-archived.md).

The `quiet-status` journey requires Ctrl+K → version to contain exactly `You are on v<running version> - this is the newest version`, with no replacement sidebar status. It also exercises real hub sync failure delivery through the existing sidebar update-card error surface.

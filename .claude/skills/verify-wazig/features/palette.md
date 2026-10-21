# Command palette and shortcut discovery

Find commands without a toolbar and open the keyboard-shortcuts overlay through the same palette a user sees.

## Sub-features

- `palette-open`: open the command palette.
- `palette-filter`: fuzzy-filter registered command labels and chat names.
- `palette-activate`: Enter activates the selected item; Escape cancels.
- `palette-help`: discover keyboard shortcuts in the help overlay.

## How to get to it (user POV)

- Ctrl+K opens the palette; type a command label.
- Up/Down changes the selection; Enter runs it; Escape closes the palette.
- Choose `Keyboard shortcuts` in the palette, or press F1 directly to open the same overlay.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes, no overlay open and no search query.

- **Run:** dispatch `feature=palette`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature palette`.
- **Open/filter:** after `before.png`, `Send-Keys $session '^k'` then `Send-Keys $session 'Keyboard shortcuts'`. Capture `action.png` showing the filtered command.
- **Activate:** `Send-Keys $session '{ENTER}'`; wait for a top-level UI Automation window with class `MessagesShortcutHelp`, then capture `after.png`. The visible overlay must list real shortcuts, not merely an empty popup.
- **Close:** Escape returns to the app; no sends/archives or fixture storage mutations are expected.

## Gotchas

- Palette rows are custom drawn and do not expose reliable accessible labels. Do not invoke a synthetic row or send `WM_COMMAND`; use the real filter and Enter path.
- Keep keyboard focus in the palette; reactivating the main window between keystrokes can lose popup focus.
- The help popup has no title; its stable selector is its class and owned process, not a fabricated window name.

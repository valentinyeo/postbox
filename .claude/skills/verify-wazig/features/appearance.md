# Theme and saved text size

Switch the app's colour scheme and control saved text scaling while retaining privately loaded IBM Plex Sans.

## Sub-features

- `appearance-theme`: AMOLED black and Green update the native UI and persist the choice.
- `appearance-scale`: smaller/larger text follows the saved scale.
- `appearance-reset`: reset text size to the existing 82% default.

## How to get to it (user POV)

- Ctrl+K → `Theme: AMOLED black` or `Theme: Green`.
- Ctrl+K → `Make text smaller`, `Make text larger`, `Reset text size`.
- Ctrl+- / Ctrl++ / Ctrl+0 are the corresponding text-size shortcuts.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes, baseline AMOLED black and IBM Plex Sans loaded from files beside Messages.exe.

- **Run:** dispatch `feature=appearance`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature appearance`.
- **Before:** `before.png` captures AMOLED black without changing scale.
- **Choose:** `Send-Keys $session '^k'`, then `Send-Keys $session 'Theme: Green'`; `action.png` shows the actual palette command.
- **Apply:** `Send-Keys $session '{ENTER}'`; wait for read-only status `theme=green`. The GUID-isolated registry's `Software/Messages/Theme` must be DWORD `0`. Capture `after.png` showing green surfaces.
- **Persistence:** cleanup captures `preferences.txt` before deleting only the temporary registry subtree. No provider state changes are permitted. Font-size controls are mapped, but this automated recipe changes only the theme.

## Gotchas

- Green is enum value 0; AMOLED is 1. Absence of a saved value means AMOLED, not Green.
- Do not alter default font, default scale or production preferences for screenshots.
- Status plus persisted preference proves the selected setting; inspect the screenshot to prove repainting. The fixture run does not claim restart persistence or every DPI combination.

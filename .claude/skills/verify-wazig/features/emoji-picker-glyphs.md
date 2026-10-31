# Emoji picker glyphs

## Sub-features

- Missing glyphs leave the real picker grid.
- Recent and search results retain canonical identity.
- Heart and wink insert their exact Unicode.
- Hover and arrow selection cross the catalog gap.
- Compose and reaction cancellation preserve the draft.

## How to get to it (user POV)

- Open a synthetic WhatsApp chat.
- Choose Insert emoji from the command palette.
- Search, select and reopen the picker.

## Driving it with PowerShell UI Automation

- Run feature=emoji-picker-glyphs on hosted Windows.
- Native input drives the actual popup.
- Isolated preferences seed an actually missing recent.
- Status records native coverage, geometry and cells.
- Screenshots provide per-cell foreground measurements.
- The complete request log is checked after shutdown.

## Gotchas

- Missing coverage requires the installed font.
- No missing glyph makes this proof inconclusive.
- Coverage does not prove painted pixels.
- No real provider or microphone is used.

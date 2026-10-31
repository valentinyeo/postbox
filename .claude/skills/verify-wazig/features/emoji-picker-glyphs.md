# Emoji picker glyphs

## Sub-features

- Empty picker grid and renderer availability.
- Original catalog target and supported positive control.

## How to get to it (user POV)

- Open a synthetic WhatsApp chat.
- Choose Insert emoji from the command palette.

## Driving it with PowerShell UI Automation

- Run feature=emoji-picker-glyphs on hosted Windows.
- Native keyboard input opens the real popup.
- Fixture status records visible cells and geometry.
- Evidence includes a screenshot and request log.

## Gotchas

- This baseline expects every visible cell supported.
- Renderer metrics do not prove painted pixels.
- Only synthetic loopback provider data is used.
- Unexpected provider writes are rejected and recorded.

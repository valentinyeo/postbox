# Inline links

## Sub-features

- Body URLs open from wrapped fragments.
- Incoming and outgoing reply previews open URLs.
- Two-line fallback quotes open complete URLs.
- Plain text and dragging do not dispatch.
- Ordinary reply navigation and Ctrl+O remain usable.
- Control-click marks and unmarks a message.
- Cursor shape and underlines use native evidence.
- Four synthetic providers share the journey.

## How to get to it (user POV)

- Open a synthetic inline-links chat.
- Click body and quoted-reply URLs.

## Driving it with PowerShell UI Automation

- Run feature=inline-links on hosted Windows.
- The fixture serves synthetic loopback URLs.
- No real provider or account is used.
- Mouse and keyboard actions use `SendInput`.
- Fixture geometry guides actual screen input.
- Each mouse-up has a handled acknowledgment.
- Positive actions also await exact launch receipts.
- Screenshots and cursor handles capture appearance.
- The checker examines receipts and screenshot pixels.

## Gotchas

- Receipts follow the real `ShellExecuteW` call.
- Windows acceptance does not prove page loading.
- Loopback requests may come from link previews.
- Browser associations and certificates remain unchanged.
- Missing browser support makes dispatch inconclusive.
- The historical baseline had a sampling race.
- Its quote result is not clean red.
- Current evidence does not cover upper-band links.
- See `tools/verify-wazig/inline-links-proof.md`.

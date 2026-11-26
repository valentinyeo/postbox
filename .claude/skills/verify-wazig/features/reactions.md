# Right-click message reactions

## Sub-features

- WhatsApp and Slack incoming messages send exactly the laughing-face emoji selected in the quick reaction row.
- The actual hub request and the visible reaction chip agree with the mouse selection.
- The palette selects the next, previous and latest message and sends or removes five reactions.

## How to get to it (user POV)

Open a chat, right-click an incoming message bubble, then left-click the laughing face (😂) in the message menu's reaction row.

## Driving it with PowerShell UI Automation

Run `feature=reactions` on GitHub-hosted Windows with `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature reactions`. Doctor must pass with the default AMOLED theme and saved-scale default. The unified fake hub serves one WhatsApp chat and one Slack chat. Alpha holds one incoming message; Beta holds two incoming messages plus a friend's heart reaction row on the second.

For each provider, search for its synthetic chat through Ctrl+F. Resolve the message canvas with UI Automation and find painted message text in the screenshot. Use real `SendInput` right-click input and wait for the process-owned `#32768` menu. Measure the menu window, native client origin and client height. Its four equal text rows, three eight-pixel separators and DPI-scaled 36-pixel reaction row determine the laughing-face center. Read its index from `quick_reactions` in `src/main.zig`; the reaction the hub receives must be exactly U+1F602. Never call an app setter or send WM_COMMAND.

Capture `whatsapp-before.png` and `slack-before.png` with the menu open, then real `SendInput` left-click the laughing-face center. Wait for a `/v1/wazig/react` body for the selected chat and incoming message. Require emoji exactly 😂, not 👍 or another emoji. Report `REACTION MISMATCH` with the provider, chat and actual received emoji on failure; exercise both providers even when the first fails. Require the received emoji in read-only message state and capture the resulting chip in `whatsapp-after.png` and `slack-after.png`.

Retain `react-requests.jsonl` with every reaction body, `bridge-requests.jsonl` with authenticated response status, `reaction-clicks.json` with native menu geometry, PID, cell index and click coordinates, `*-after.messages.json`, screenshot UIA/state companions, `actions.log`, doctor, `result.json` passed/failed, side-effect assertions and cleanup proof. Validate with `python tools/verify-wazig/check-evidence.py verification-evidence` and inspect the screenshots. Matching PRs run both reactions and menus.

In the two-message WhatsApp chat, use the palette to select the latest message, move to the previous and next messages, and jump back to latest. Check the selected message after each command. Select CHIP and use the palette for Like, Love, Sad, Surprised, Thanks and Remove reaction. Check each hub request and the displayed own reaction.

## Gotchas

- The old code sends 👍 because it asks for menu-item bounds after the popup has closed. The red-first journey must fail on that actual payload, not on setup or a script error.
- Menu coordinates come from the visible native menu window and row layout, not app internals. All mouse input checks process ownership.
- Fake hub acceptance proves client selection and transport, not delivery to a live provider account. This journey does not claim plus-picker, other emoji cells, media or login coverage; unit tests cover cell boundaries and plus routing.

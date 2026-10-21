# Native menus and popup appearance

Prove native menu theming on real screenshot pixels, with readable custom popups and unchanged Green native menus.

## Sub-features

- `menus-native`: chat actions, composer edit, search edit, message reactions and selected-message text actions are dark in AMOLED.
- `menus-custom`: command palette, accounts palette, emoji picker, shortcut help, Slack sign-in settings and emoji shortcode suggestions stay dark with readable text.
- `menus-green`: the same chat actions menu remains standard light after choosing Green.

## How to get to it (user POV)

- Right-click a chat, the composer, the search field or a message bubble. Drag over message text and right-click the selection for its separate menu.
- Ctrl+K opens the palette. Choose `Manage accounts`, `Insert emoji`, `Keyboard shortcuts` or `Slack sign-in settings` for their popups.
- Type `:hea` in the composer for shortcode suggestions; clear without sending.
- Ctrl+K → `Theme: Green`, then right-click the same chat. Escape closes menus; Alt+F4 closes setup without signing in.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes on GitHub-hosted Windows, the default AMOLED theme and default saved scale. The two synthetic cached chats are Verification Alpha/Beta. This journey alone seeds one synthetic text message through the account-scoped production message-cache envelope; no app endpoint injects UI state.

- **Run:** dispatch `feature=menus`; helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature menus`.
- **Input:** resolve stable UIA control bounds, then use real `SendInput` right-clicks and selection dragging. Require a process-owned visible `#32768` menu window, not a status response. Require `Copy selection` in the selected-text menu to distinguish it from the reaction menu.
- **AMOLED:** capture a named `amoled-<popup>-before.png` with each popup closed and `amoled-<popup>-after.png` with it open. Find custom windows by their real class and PID. Exclude the outer eight pixels; measure sRGB-linear relative luminance inside the observed window rectangle. Median background must not exceed the luminance of the theme's brightest neutral pressed control, `#404040` (0.05126945837404324). No more than 2% of 16-pixel tiles may have median luminance above 0.5, catching light embedded panels. Check setup/palette/emoji edit fields separately with four-pixel insets.
- **Text:** require at least 24 neutral foreground pixels with contrast at least 4.5:1 against the measured median background. The representative foreground is the 24th brightest neutral pixel in dark mode, or 24th darkest in light mode, excluding window borders. Inspect the screenshot too: pixel contrast is not OCR or a claim about every glyph.
- **Green:** choose `Theme: Green` through the palette, preserve `theme-green-action.png`, require read-only theme status and saved DWORD 0, then capture `green-chat-before.png` and `green-chat-after.png`. Require native menu median luminance at least 0.7 and text contrast at least 4.5:1.
- **Evidence:** `menu-luminances.json` records each popup rectangle, screenshot name, measured background/text luminance, contrast, text-pixel count, light-tile fraction and fixed thresholds, including failures. All pairs also have state snapshots and UIA trees. Retain doctor, actions, unchanged synthetic storage, zero transport side effects and cleanup proof.

## Gotchas

- Before/after means closed/open on the tested build, not reconstructed screenshots from before IGSH-505.
- Source inventory: `openChatMenu`, `openReactionMenu` and the selected-text branch of `canvasProc` are all three `CreatePopupMenu` / `TrackPopupMenu` callers. Composer/search are native edit-control menus. There is no tray menu or separate attachment menu.
- Attachment file dialogs require a configured Slack or Telegram chat; neither is reachable from these offline WhatsApp fixture chats. The base verification build has TDLib disabled, so `Connect Telegram account` only reports unavailability and cannot open Telegram setup. Slack setup is reachable without credentials and is covered; no login, transport, media or external file chooser is claimed.
- Custom popup text is checked inside its own rectangle, never against bright desktop pixels. Missing, offscreen, unpainted or unreadable popups fail. Do not weaken thresholds to accommodate regressions.

# Native menus and popup appearance

Prove native menu theming on real screenshot pixels, with readable custom popups and native menus that stay dark after reapplying the only theme, Graphite.

## Sub-features

- `menus-native`: chat actions, composer edit, search edit, message reactions and selected-message text actions are dark in the default Graphite theme (internal name `amoled`).
- `menus-custom`: command palette, accounts palette, emoji picker, shortcut help and emoji shortcode suggestions stay dark with readable text. The Slack sign-in settings popup is not driven by this journey.
- `menus-green`: the same chat actions menu stays dark after `Theme: Graphite` is chosen again. Graphite is the only theme, so there is no light menu to check.

## How to get to it (user POV)

- Right-click a chat, the composer, the search field or a message bubble. Drag over message text and right-click the selection for its separate menu.
- Ctrl+K opens the palette. Choose `Manage accounts`, `Insert emoji` or `Keyboard shortcuts` for their popups.
- Type `:hea` in the composer for shortcode suggestions; clear without sending.
- Ctrl+K → `Theme: Graphite`, then right-click the same chat. Escape closes menus.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes on GitHub-hosted Windows, the default Graphite theme and default saved scale. The two synthetic cached chats are Verification Alpha/Beta. This journey alone seeds one synthetic text message through the account-scoped production message-cache envelope; no app endpoint injects UI state.

- **Run:** dispatch `feature=menus`; helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature menus`.
- **Input:** temporary synthetic composer/search text keeps edit-menu actions enabled; clear both without sending. Filter emoji with `heart` to check real edit text as well as the grid. Resolve stable UIA control bounds, then use real `SendInput` right-clicks and selection dragging. Require a process-owned visible `#32768` menu window, not a status response. Require `Copy selection` in the selected-text menu to distinguish it from the reaction menu.
- **Graphite:** capture a named `amoled-<popup>-before.png` with each popup closed and `amoled-<popup>-after.png` with it open. Find custom windows by their real class and PID. Exclude the outer eight pixels; measure sRGB-linear relative luminance inside the observed window rectangle. Median background must not exceed the luminance of the theme's brightest neutral pressed control, `#404040` (0.05126945837404324). No more than 2% of 16-pixel tiles may have neutral-pixel median luminance above 0.5 (neutral means `max(R,G,B) - min(R,G,B) <= 12`; saturated emoji are foreground and tiles with no neutral pixels are not light), catching light embedded panels. Check setup/palette/emoji edit fields separately with four-pixel insets.
- **Text:** require at least 24 neutral foreground pixels with contrast at least 4.5:1 against the measured median background. The representative foreground is the 24th brightest neutral pixel in dark mode, or 24th darkest in light mode, excluding window borders. Inspect the screenshot too: pixel contrast is not OCR or a claim about every glyph.
- **Reapply:** choose `Theme: Graphite` through the palette, preserve `theme-green-action.png`, require read-only theme status `amoled` and saved Theme DWORD 1, then capture `green-chat-before.png` and `green-chat-after.png` (names kept from the old Green theme). The popup is measured as dark, with the same limits as the other native menus. No row is marked light.
- **Evidence:** `menu-luminances.json` records each popup rectangle, screenshot name, measured background/text luminance, contrast, text-pixel count, light-tile fraction and fixed thresholds, including failures. Require one measured edit in palette/accounts/emoji, matching both native `Edit` and DirectWrite `RICHEDIT50W` classes. All pairs also have state snapshots and UIA trees. Retain doctor, actions, unchanged synthetic storage, zero transport side effects and cleanup proof.

## Gotchas

- Before/after means closed/open on the tested build, not reconstructed screenshots from before IGSH-505.
- Source inventory: `openChatMenu`, `openReactionMenu` and the selected-text branch of `canvasProc` are three of the four `CreatePopupMenu` callers in `src/main.zig` (the fourth is `openQuickReactions`); the DirectWrite edit-menu caller is `contextMenu` in `src/directwrite_edit.zig`. Composer/search are custom owner-drawn DirectWrite edit context menus, not unstyled system menus. There is no tray menu or separate attachment menu.
- Attachment file dialogs require a configured Slack or Telegram chat; neither is reachable from these offline fixture chats. The Slack sign-in settings popup (`Slack sign-in settings` in the palette) exists but this journey does not open it, so it is not covered. No login, transport, media or external file chooser is claimed.
- Custom popup text is checked inside its own rectangle, never against bright desktop pixels. Missing, offscreen, unpainted or unreadable popups fail. Do not weaken thresholds to accommodate regressions.
- Source: `openChatMenu` opens chat actions, the selected-text menu is in `canvasProc`, and `contextMenu` in `src/directwrite_edit.zig` builds the edit menus. `Invoke-Menus` in `tools/verify-wazig/menus.ps1` drives the pixel recipe.

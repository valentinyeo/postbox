# Archive and Keep archived

Move a chat out of the inbox, keep it archived across incoming messages, and find its updated unread badge in Archive.

## Sub-features

- `archive-chat`: archive or unarchive the selected WhatsApp chat; the message pane immediately follows the remaining selection.
- `archive-keep`: persist Keep archived; Allow resurfacing removes that preference.
- `archive-view`: toggle between inbox and Archive.
- `archive-incoming`: plain archives can resurface on new incoming messages; kept chats are re-archived when the provider itself unarchives them.
- `archive-bulk`: Ctrl+A in the chat list selects all; Ctrl+E archives and Ctrl+Shift+E keeps the selection archived.

## How to get to it (user POV)

- Ctrl+E archives the open chat, including from the composer; in Archive it unarchives. Bare E works outside editable fields. Ctrl+Shift+E archives and keeps archived.
- Right-click a chat, or focus the chat list and press Shift+F10, for `Archive` / `Unarchive`, `Keep archived` / `Allow resurfacing`, and pinning. Labels come from `src/chat_menu.zig:items`; keyboard context menus reach `src/main.zig:openChatMenu`.
- Ctrl+K → `Archive selected chat` / `Unarchive selected chat`, `Archive and keep archived` / `Allow resurfacing`.
- Ctrl+K → `Show archived chats` opens Archive; `Show inbox chats` returns. These commands live in `src/main.zig:buildPaletteItems`; shortcuts are in `handleKeyboard` and `src/shortcuts.zig`.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes; Alpha selected, unread count zero, both synthetic chats in the inbox. Only this recipe seeds `verification-provider.json`; search, navigation, drafts, palette and appearance keep empty message caches; menus and text-comparison seed text, while both hub journeys use separate fake services.

- **Run:** dispatch `feature=archive`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature archive`.
- **Before:** capture `before.png`, UI Automation tree, status and visible-chat snapshots. Send `^e`; wait for Alpha's provider archive acknowledgement, zero pending archives and only Beta in the inbox.
- **Keep:** use Ctrl+K → `Show archived chats`, then Ctrl+K → `Archive and keep archived`. The harness reads native palette edit `1064` through UI Automation and bounded read-only WM_GETTEXT. Capture `action.png` with that query before Enter. Wait for the persisted keep flag and zero pending archives; preserve `kept-archive-state.txt` and `kept.png` plus snapshots.
- **Incoming:** return through `Show inbox chats`. Atomically replace only fixture provider data with one incoming `verify-incoming-1` message, timestamp `2026-10-10T11:00:00Z`, unread count 1, and provider `archived=false`, as WhatsApp can report on arrival. Retain that exact input as `incoming-provider.json`. No control command or harness call sets archive state.
- **Merge:** the fixture refresh timer requests chats through `verificationEnqueue`, which posts the normal `WacliResult` to `wm_wacli_done`. Production `applyChats(..., true)` calls `holdKeptArchived`, queues a real archive action and hides Alpha; the fixture provider acknowledges that queued transport write. The production unread probe reads the same incoming message payload to compute the unread badge. Require the provider flag to become archived again, zero pending archives, and only Beta in read-only `chats`; capture `inbox.png` and its snapshots.
- **After:** Ctrl+K → `Show archived chats`; require exactly Alpha, archived and unread, with count 1 and the new timestamp. Capture `after.png`, status, visible-chat snapshot and UI Automation tree. Cleanup preserves `final-data/verification-provider.json` and `archive-state.txt`. `check-evidence.py` checks this transition chain; inspect all three required screenshots, especially the unread badge and Kept archived marker.

## Gotchas

- WAZI-106 introduced immediate pane switching, resurfacing, keeping and bulk archive; WAZI-115 made the context-menu path discoverable and race-safe; WAZI-144 restored plain-archive resurfacing; WAZI-153 restored Ctrl+E from the composer. IGSH-515 (`d6acd95`, PR 281) repairs provider-side unarchiving via `holdKeptArchived`, not just `archive_rules.shouldResurface`.
- The incoming provider input must say `archived=false`. Leaving it true would pass without exercising IGSH-515. A negative control is to replace the inbox `holdKeptArchived` call in `applyChats` with a no-op; this journey must then fail waiting for provider re-archive.
- Provider reads and archive acknowledgements alone are fixture-backed. All user actions use foreground-checked SendKeys; status/chats are read-only. The hook shares the existing `--verify-fixture` Actions/path/registry isolation guard and cannot enable real provider traffic.
- Opening a chat explicitly normally marks it read. The recipe changes Archive views without explicitly selecting Alpha after arrival, so the refreshed sidebar can prove its unread badge before a read receipt. It does not verify live WhatsApp delivery, plain-archive resurfacing, bulk archive, restart persistence or the context-menu path.
- This verification does not alter the font, saved scale, toolbar policy, media behaviour or updater. No real provider account, store or installed executable is touched.
- Source: `src/chat_menu.zig:9` builds provider-specific actions; `src/main.zig:11622` holds kept chats, `src/main.zig:2371` applies provider updates, and `src/main.zig:17285` defines the restricted fixture jobs.

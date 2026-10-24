# Archive

Move a chat out of the inbox, keep it archived across incoming messages, and find its updated unread badge in Archive.

## Sub-features

- `archive-chat`: archive or unarchive the selected WhatsApp or Slack chat; the message pane immediately follows the remaining selection.
- `archive-legacy-keep`: existing keep flags still re-archive a chat if the provider unarchives it; the separate keep/resurfacing commands are removed.
- `archive-view`: toggle between inbox and Archive.
- `archive-incoming`: incoming messages never trigger a client unarchive; legacy kept chats are still re-archived when the provider itself unarchives them.
- `archive-bulk`: Ctrl+A in the chat list or empty composer selects all visible chats; Ctrl+E archives the selection. The dedicated `archive-bulk` journey proves the empty-composer path and preserves text select-all.

## How to get to it (user POV)

- Ctrl+A selects all visible chats when the chat list or the empty main composer has focus. With composer text, or in search, thread composer, emoji or palette edits, Ctrl+A still selects text. Esc clears the chat selection.
- Ctrl+E archives the open chat, including from the composer; in Archive it unarchives. Bare E works outside editable fields. Ctrl+Shift+E is unbound.
- Right-click a chat, or focus the chat list and press Shift+F10, for `Archive` / `Unarchive` and pinning. Labels come from `src/chat_menu.zig:items`; keyboard context menus reach `src/main.zig:openChatMenu`.
- Ctrl+K → `Archive selected chat` / `Unarchive selected chat`.
- Ctrl+K → `Show archived chats` opens Archive; `Show inbox chats` returns. These commands live in `src/main.zig:buildPaletteItems`; shortcuts are in `handleKeyboard` and `src/shortcuts.zig`.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes; Alpha selected, unread count zero, both synthetic chats in the inbox. This recipe and `archive-bulk` seed `verification-provider.json`; search, navigation, drafts, palette and appearance keep empty message caches; menus and text-comparison seed text, while both hub journeys use separate fake services.

- **Run:** dispatch `feature=archive`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature archive`.
- **Before:** capture `before.png`, UI Automation tree, status and visible-chat snapshots. Send `^e`; wait for Alpha's provider archive acknowledgement, zero pending archives and only Beta in the inbox.
- **Archive:** use Ctrl+K → `Show archived chats`, then capture `action.png` with the `Show inbox chats` query before Enter. Return to Archive through the palette. Require the persisted plain archive flag and zero pending archives. Existing artifact names `kept-archive-state.txt` and `kept.png` are retained, but now record an ordinary archive, not a separate preference.
- **Incoming:** return through `Show inbox chats`. Atomically replace only fixture provider data with one incoming `verify-incoming-1` message, timestamp `2026-10-10T11:00:00Z`, unread count 1, and provider `archived=true`. Retain that exact input as `incoming-provider.json`. No control command or harness call sets archive state. Require zero pending archives and only Beta in the inbox; capture `inbox.png`. The production unread probe reads the same payload to compute the unread badge.
- **After:** Ctrl+K → `Show archived chats`; require exactly Alpha, archived and unread, with count 1 and the new timestamp. Capture `after.png`, status, visible-chat snapshot and UI Automation tree. Cleanup preserves `final-data/verification-provider.json` and `archive-state.txt`. `check-evidence.py` checks this transition chain; inspect all three required screenshots, especially the unread badge and Archived marker.

The dedicated [bulk archive journey](archive-bulk.md), `feature=archive-bulk`, focuses the empty composer, selects both visible chats with Ctrl+A and archives both with Ctrl+E. It retains before/selected/after screenshots and checks text select-all separately. The single-chat `archive` journey does not exercise bulk selection.

## Gotchas

- Slack archives are local to Wazig, keyed by provider, account and chat ID. Channels, groups and DMs stay in Archive across incoming messages, hub sync and restarts until explicitly unarchived. No Slack API archive or hub archive request is sent. See [Slack archive](slack-archive.md).
- IGSH-734 removes the incoming-message resurfacing path and the separate keep/resurfacing menu and palette commands. Sending into an archived WhatsApp chat still unarchives it. Legacy keep flags and baseline timestamps remain readable; [Hub archive](hub-archive.md) proves legacy keep enforcement, same-profile restart and both plain direct chats staying archived beyond the idle scan.
- The ordinary archive recipe keeps provider `archived=true` on delivery. Provider-side unarchiving of a legacy kept chat is covered by `hub-archive`, which must fail without `holdKeptArchived`.
- Provider reads and archive acknowledgements alone are fixture-backed. All user actions use foreground-checked SendKeys; status/chats are read-only. The hook shares the existing `--verify-fixture` Actions/path/registry isolation guard and cannot enable real provider traffic.
- Opening a chat explicitly normally marks it read. The recipe changes Archive views without explicitly selecting Alpha after arrival, so the refreshed sidebar can prove its unread badge before a read receipt. It does not verify live WhatsApp delivery, idle-scan persistence, restart persistence or the context-menu path.
- This verification does not alter the font, saved scale, toolbar policy, media behaviour or updater. No real provider account, store or installed executable is touched.
- Source: `src/chat_menu.zig:items` builds chat actions; `src/main.zig:holdKeptArchived` holds legacy kept chats, `applyChats` applies provider updates, and `verificationEnqueue` defines the restricted fixture jobs.

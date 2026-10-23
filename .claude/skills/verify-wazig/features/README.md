# Wazig Messages verification map

Start with [the skill](../SKILL.md). The seven offline desktop features use the real native window, not the existing headless smoke modes. Each run creates a separate profile and synthetic cached chats `Verification Alpha` and `Verification Beta`, without provider login. Only menus seeds one synthetic cached message to reach both message menus. The baseline is the AMOLED theme, saved-scale default of 82%, All networks, Alpha selected and an empty composer. Never change the product's default font or scale to suit the harness.

| ID / workflow input | User-facing feature | Automated recipe |
| --- | --- | --- |
| [search](search.md) | Chat search | Ctrl+F, match, clear, no-match, restore |
| [navigation](navigation.md) | Keyboard chat navigation | Next chat, previous chat |
| [drafts](drafts.md) | Composer and per-chat drafts | Type, switch away/back, check disk |
| [palette](palette.md) | Command palette and shortcut discovery | Filter a command, activate the help overlay |
| [menus](menus.md) | Native menus and custom popups | Measure AMOLED darkness and text contrast, then Green native-menu lightness |
| [slack-sort](slack-sort.md) | Slack last message order | Newest first, unknown last, incoming and sent promotion with keyboard order |
| [views](views.md) | Account views and combined inbox | Alt+1..4 isolation, account send, Alt+I order, Sort views, restart |
| [hub](hub.md) | Unified hub transport (IGSH-531) | Source network identity, list/history, SSE replay, send retry, read/archive, media and DPAPI |
| [whatsapp-hub](whatsapp-hub.md) | WhatsApp hub transport | Chats, history, live SSE replay, idempotent retry, reads, archive, pending media and DPAPI |
| [appearance](appearance.md) | Theme and saved text size | Choose Green through the palette, check persistence |
| [archive](archive.md) | Archive and Keep archived | Ctrl+E, keep via palette, incoming provider event, Archive presence/unread and inbox absence |

Harness name in each map: `PowerShell UI Automation`. Dispatch with `gh workflow run verify.yml -f feature=<ID>`, watch with `--interval 60`, download `verify-wazig-<ID>` and inspect the images. PRs automatically prove search and the authenticated fake-hub journey; a map entry is not proof that every listed sub-feature was exercised. The automated recipe column is the exact coverage, not a claim to cover all entry points.

The source of truth for commands is `src/main.zig:buildPaletteItems`, for keyboard handling `src/main.zig:handleKeyboard`, and for discoverable help `src/shortcuts.zig`. Every feature file has precisely four H2 sections. Capture the input, resulting UI and durable side effects; preserve proof after cleanup. Only archive adds a synthetic incoming message at the fixture provider boundary; search, navigation, drafts, palette and appearance stay empty. No live send, account login, media, voice playback or transcription claim can be made from these local chats.

The hub journey uses a loopback fake bridge with synthetic rows instead of the offline chat seed. Its real app worker and WinHTTP reader run in the same isolated profile. It proves transport behavior against the frozen contract, not a live account or service deployment.

The `hub` journey uses the unified `/v1/wazig` contract and synthetic Slack/Telegram rows; `whatsapp-hub` continues to prove the separate legacy bridge. Both run automatically on matching PRs. Unit switch/fallback checks are part of the normal Zig test roots.

The `slack-sort` journey verifies Slack last message ordering and incoming/sent promotion through the unified fake hub, and runs on matching PRs.

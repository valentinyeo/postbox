# Wazig Messages verification map

Start with [the skill](../SKILL.md). These five core desktop features use the real native window, not the existing headless smoke modes. Each run creates a separate profile and synthetic cached chats `Verification Alpha` and `Verification Beta`, with no messages or provider login. The baseline is the AMOLED theme, saved-scale default of 82%, All networks, Alpha selected and an empty composer. Never change the product's default font or scale to suit the harness.

| ID / workflow input | User-facing feature | Automated recipe |
| --- | --- | --- |
| [search](search.md) | Chat search | Ctrl+F, match, clear, no-match, restore |
| [navigation](navigation.md) | Keyboard chat navigation | Next chat, previous chat |
| [drafts](drafts.md) | Composer and per-chat drafts | Type, switch away/back, check disk |
| [palette](palette.md) | Command palette and shortcut discovery | Filter a command, activate the help overlay |
| [appearance](appearance.md) | Theme and saved text size | Choose Green through the palette, check persistence |

Harness name in each map: `PowerShell UI Automation`. Dispatch with `gh workflow run verify.yml -f feature=<ID>`, watch with `--interval 60`, download `verify-wazig-<ID>` and inspect the images. PRs automatically prove the default search journey; a map entry is not proof that every listed sub-feature was exercised. The automated recipe column is the exact coverage, not a claim to cover all entry points.

The source of truth for commands is `src/main.zig:buildPaletteItems`, for keyboard handling `src/main.zig:handleKeyboard`, and for discoverable help `src/shortcuts.zig`. Every feature file has precisely four H2 sections. Capture the input, resulting UI and durable side effects; preserve proof after cleanup. No send, account login, media, voice playback or transcription claim can be made from these empty local chats.

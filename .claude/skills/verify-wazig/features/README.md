# Wazig verification map

Start with [the skill](../SKILL.md). The eight offline desktop journeys use the real native window, not the existing headless smoke modes. Each run creates a separate profile and synthetic cached chats `Verification Alpha` and `Verification Beta`, without provider login. Menus seeds one synthetic cached message to reach both message menus; text-comparison loads its synthetic paragraph from `src/verify_text.json`. The baseline is the AMOLED theme, saved-scale default of 82%, All networks, Alpha selected and an empty composer. Never change the product's default font or scale to suit the harness.

| ID / workflow input | User-facing feature | Automated recipe |
| --- | --- | --- |
| [paste-image](paste-image.md) | Clipboard images and multiple attachments | Ctrl+V, Enter, full-screen RGBA and 4K on every provider; WhatsApp/Slack + picker, two previews, ordered captioned sends and remove-first |
| [search](search.md) | Chat search | Ctrl+F, match, clear, no-match, restore |
| [navigation](navigation.md) | Keyboard chat navigation | Next chat, previous chat |
| [drafts](drafts.md) | Composer and per-chat drafts | Type, switch away/back, check disk |
| [palette](palette.md) | Command palette and shortcut discovery | Positive shortcut row, no Status result/sidebar entry, activate help |
| [appearance](appearance.md) | Theme and saved text size | Choose Green, save larger text, reset scale to 82% |
| [passage-copy](passage-copy.md) | Cross-message text selection | Real drags on WhatsApp and Slack, partial stamped clipboard, day change and held-edge scrolling |
| [reactions](reactions.md) | Right-click message reactions | Real mouse laughing-face selection on WhatsApp and Slack; exact hub request and visible chip |
| [menus](menus.md) | Native menus and custom popups | Measure AMOLED darkness and text contrast, then Green native-menu lightness |
| [whatsapp-hub](whatsapp-hub.md) | WhatsApp hub transport | Chats, history, live SSE replay, idempotent retry, reads, archive, pending media and DPAPI |
| [hub-archive](hub-archive.md) | Legacy WhatsApp Keep archived | Seed legacy flag, require hub re-archive and keep state, restart with newer incoming message |
| [palette-archived](palette-archived.md) | Ctrl+K finds archived chats on every account | Archived WhatsApp, Telegram and Slack names from every view, inbox names from every view, Enter opens without unarchiving |
| [hub](hub.md) | Unified hub transport (IGSH-531) | Source network identity, list/history, SSE replay, send retry, read/archive, media and DPAPI |
| [slack-sort](slack-sort.md) | Slack last message order | Newest first, unknown last, incoming and sent promotion with keyboard order |
| [slack-archive](slack-archive.md) | Local Slack archive | Ctrl+E, three incoming messages, inbox absence, Archive presence, restart and unarchive without hub archive writes |
| [slack-emoji](slack-emoji.md) | Slack emoji and animated Giphy | Generated standard aliases/tones, custom message/reaction pixels, differing GIF frame pixels and hub cache |
| [link-previews](link-previews.md) | Slack labels, linked images and page previews | Real hub messages on four providers, inline image and OG card pixels, image viewer and cache reuse |
| [slack-threads](slack-threads.md) | Slack threads | Replies line, side panel, threaded send, per-account toggle and restart |
| [telegram](telegram.md) | Telegram hub account | Prelinked hub chats, Saved Messages, text/file/reply, reactions, reads, live SSE and terminal rate limits |
| [signal](signal.md) | Signal hub account | Prelinked hub history, text/file, reactions, reads, live events, terminal 429/403 failures |
| [notrap](notrap.md) | No empty sign-in traps | Saved Signal startup fallback, Esc and every Alt view key from every view, per-view screenshots |
| [views](views.md) | Account views and combined inbox | Alt+1..4 isolation, inbox titles, drained fixed slots, account send, Alt+I order, Sort views, restart |
| [workspace-icons](workspace-icons.md) | Slack workspace icon, WhatsApp and Signal mark badges | Two synthetic team icon colours, missing-icon S, green handset, blue Signal mark and persistent avatar cache |
| [repaint](repaint.md) | Change-driven redraw | 60 seconds without input, baseline refreshes, non-selected incoming messages and full-paint deltas |
| [voice](voice.md) | Voice message bubbles | Five downloaded voice notes with cached transcripts, wheel scroll, Show more, playback-style partial repaints matching full repaints |
| [archive](archive.md) | Archive and Keep archived | Ctrl+E, keep via palette, incoming provider event, Archive presence/unread and inbox absence |
| [text-comparison](appearance.md) | DirectWrite beside Chrome | Exact text/font/metric parity, paired screenshots and 3x paragraph crops |
| [window](window.md) | Maximized startup and saved normal placement | Unforced launch, keyboard restore/resize, Alt+F4, same-profile reopen and --update-relaunch |

Harness name in each map: `PowerShell UI Automation`. Dispatch with `gh workflow run verify.yml -f feature=<ID>`, watch with `--interval 60`, download `verify-wazig-<ID>` and inspect the images. Matching PRs run `paste-image`, `passage-copy`, `reactions`, `menus`, `search`, `drafts`, `whatsapp-hub`, `hub`, `hub-archive`, `palette-archived`, `slack-sort`, `slack-archive`, `slack-threads`, `slack-emoji`, `views`, `workspace-icons`, `signal`, `telegram`, `notrap`, `repaint`, `text-comparison`, `window` and `voice`; the other journeys require dispatch; a map entry is not proof that every listed sub-feature was exercised. The automated recipe column is the exact coverage, not a claim to cover all entry points.

The source of truth for commands is `src/main.zig:buildPaletteItems`, for keyboard handling `src/main.zig:handleKeyboard`, and for discoverable help `src/shortcuts.zig`. Every feature file has precisely four H2 sections. Capture the input, resulting UI and durable side effects; preserve proof after cleanup. Only archive adds a synthetic incoming message at the fixture provider boundary; search, navigation, drafts, palette and appearance stay empty. No live send, account login, media, voice playback or transcription claim can be made from these local chats.

The hub journey uses a loopback fake bridge with synthetic rows instead of the offline chat seed. Its real app worker and WinHTTP reader run in the same isolated profile. It proves transport behavior against the frozen contract, not a live account or service deployment.

The `hub` journey uses the unified `/v1/wazig` contract and synthetic Slack/WhatsApp rows; `whatsapp-hub` continues to prove the separate legacy bridge. Both run automatically on matching PRs. Unit switch/fallback checks are part of the normal Zig test roots.

The `slack-sort` journey verifies Slack last message ordering and incoming/sent promotion through the unified fake hub, and runs on matching PRs.

The `workspace-icons` journey verifies rounded Slack workspace icon badges, the missing-icon S fallback and the green WhatsApp handset through screenshot pixel checks, authenticated synthetic endpoints and retained disk caches. It runs on matching PRs.

## Recent changes coverage

- IGSH-647: local Slack archive -> `slack-archive` (asserts real Ctrl+E, three archived=false incoming hub rows, Archive-only presence, same-profile restart, unarchive and absence of archive endpoint requests; direct Slack remains Zig coverage)

These are source changes in the bounded history window, not claims of live verification. A journey citation names only its actual assertions; unreachable entries identify the missing fixture, hardware, provider or measurement prerequisite. Named CI checks are existing coverage, not checks run during this maintenance pass.

- IGSH-461: AMOLED controls and popup inputs -> `menus` (requires default AMOLED and measures dark readable popup/edit surfaces; focus-transition state combinations remain in tools/test_theme_runtime.py)
- IGSH-462: native text beside Chrome -> `text-comparison` (asserts exact fixture, bundled font hashes, sizes, weights, line heights and surviving paired crops, not pixel equality)
- IGSH-463: double-click received text toggles thumbs up -> unreachable: an acknowledging reaction transport is absent from the offline fixture; covered by src/message_double_click_test.zig and src/message_double_click.zig in CI
- IGSH-464: unified inbox and Slack workspace sign-in -> `hub` (asserts synthetic Slack/WhatsApp identity, provider-pure CLI/sidebar views and Slack history/send; real OAuth requires provider login and is covered by tools/test_slack_integration.py)
- IGSH-465: Telegram through the triage hub -> `telegram` (asserts QR/password linking, provider-only view and saved row, text/file/reply, reactions, reads, media, live SSE, visible rate limits and unsupported archive; real account linking requires the live hub)
- IGSH-466: DirectWrite composer, search and palette editors -> `drafts` (asserts selection replacement, undo/redo, word deletion, guarded paste and newline via native text/UIA parity; ARM64 compilation is CI-only)
- IGSH-470: encrypted Deepgram key seeding and refresh -> unreachable: real speech-provider credentials and an authenticated transcription response; covered by src/deepgram_key.zig and tools/check_voice_transcription_regression.py
- IGSH-482: recording strip avoids full-window flicker -> unreachable: microphone capture plus a recording-state paint oracle; covered by tools/test_recording_paint.py and src/recording_paint.zig
- IGSH-494: consistent pin icon geometry -> unreachable: pinned-row icon geometry measurement is not exposed by the fixture journeys; covered by pin-icon-tests, src/pin_icon_test.zig and tools/test_pin_icon.py
- IGSH-497: per-chat draft editing and persistence -> `drafts` (asserts empty Beta, restored Alpha and saved drafts.json; no process-restart claim)
- IGSH-500: update notice does not overlap its button -> unreachable: a pending update offer is suppressed by the fixture; covered by src/update_card_layout.zig in CI
- IGSH-505: dark native menus and custom popups -> `menus` (asserts closed/open PNG pairs, AMOLED darkness and text contrast, and Green native-menu lightness)
- IGSH-510: buffered painting and typing invalidation -> unreachable: paint-event/dirty-region instrumentation is not a journey read; covered by tools/test_repaint.py, tools/repaint_test.zig and src/drafts_ui_test.zig
- IGSH-515: keep-archived survives provider unarchiving -> `archive` (injects incoming archived=false, requires provider re-archive, inbox absence and unread Archive presence)
- IGSH-517: voice recognition fallback and rotated keys -> unreachable: stored voice audio and authenticated speech-provider responses; covered by tools/check_voice_transcription_regression.py, src/transcription_retry_test.zig and the isolated Windows environment_keys tests
- IGSH-526: desktop verification isolation -> unreachable: no user-facing change (Actions-only fixture guards, registry/path isolation and UI evidence tooling)
- IGSH-531: unified hub transport -> `hub` (asserts authenticated unified wire paths, source networks, history, live replay, stable send retries, reads, archive and media cache; not more-than-500-row pagination)
- IGSH-532: legacy bridge account identity and foreign outbox adoption -> `whatsapp-hub` (asserts preferred synthetic namespace despite reversed account order, startup adopted send/reply exactly once, old journal removal and stable retry client_id)
- IGSH-533: reaction chips do not overlap message text -> unreachable: a reaction-bearing rendered message plus chip/text geometry oracle is not seeded by menus; covered by tools/test_reaction_layout.py
- IGSH-534: Dictate uses an icon inside the composer -> unreachable: glyph-shape/state instrumentation is absent from the journey, which checks only control bounds; covered by src/composer_button_test.zig in CI
- IGSH-538: WhatsApp Status removed -> `palette` (asserts Status filter has zero real UIA rows and former sidebar control 1120 is absent, after a positive shortcut-row control)
- IGSH-542: one-box composer with bottom-anchored controls -> `drafts` (asserts box inset, icon/control alignment and one/three lines at wide/narrow sizes in both themes)
- IGSH-545: row-sized paint buffers and brush-failure handling -> unreachable: native buffer-allocation and brush-failure instrumentation; covered by unfurl-verification's ISSUE-545 smooth_shapes raster test
- IGSH-546: keep-archived verification fixture -> unreachable: no user-facing change (fixture provider reads/archive acknowledgements and retained archive transition evidence)
- IGSH-575: uncached chat switching clears previous messages -> `hub` (asserts Beta identity with zero messages within one second, then delayed Beta-only history and restored Alpha; does not simulate an unbounded event storm)
- IGSH-592: unified provider views filter by row identity -> `hub` (asserts nonempty pure Slack/WhatsApp views, exact All partition and Alt-key sidebar parity; Telegram rows remain unit-test coverage)
- IGSH-604: Slack workspace icons and green WhatsApp badges -> `workspace-icons` (asserts screenshot badge colours and letter/handset pixels, authenticated per-team fetches, missing-icon fallback and retained avatar cache bytes; restart reuse and scaling remain source/unit review)
- IGSH-607: Signal account view and linking -> `signal` (asserts QR before linked chats, Signal-only account identity, history, text and multipart file bytes, reactions, author/timestamp read receipts, media cache, live events, unsupported archive and visible terminal rate-limit/captcha failures; real device linking and upstream delivery require a live provider)
- IGSH-605: newest-first Slack chat sorting -> `slack-sort` (asserts exact before/incoming/sent orders, descending known times with unknown last, cyclic keyboard order, retained Gamma selection on incoming reorder, authenticated SSE delivery and acknowledged Gamma send; equal-time/name ties and cached timestamp fallback remain CI coverage)
- WAZI-100: durable send queues and full-queue retention -> unreachable: process restart with pending offline sends and a saturated worker queue are not fixture journeys; covered by tools/test_outbox_runtime.py and src/outbox.zig
- WAZI-101: pasted files route by provider -> unreachable: staged file plus configured direct Slack/Telegram provider; covered by tools/test_outbox_runtime.py and lint-repeats rule D1
- WAZI-115: discoverable chat archive/keep menu -> `menus` (opens the real chat context menu and asserts its pixels; archive/keep action semantics are exercised by archive via keyboard/palette, not this menu)
- WAZI-116: read watermarks survive reload and sync -> unreachable: stale provider unread replay after persisted viewing is not supplied by these journeys; covered by src/read_state_test.zig and src/read_state.zig
- WAZI-117: automatic attachments, verified cache reuse and background prefetch -> `whatsapp-hub` (asserts automatic media 202-to-200 polling and matching durable cache bytes; background/reopen cases remain src/background_media_test.zig and src/media_drain.zig coverage)
- WAZI-118: image gallery navigation -> unreachable: a multi-image fixture with decodable cached images is not seeded; covered by src/image_gallery.zig and src/image_viewer_test.zig in CI
- WAZI-119: cached voice summaries before first paint -> unreachable: a voice-message fixture and persisted summary cache are not seeded; covered by src/format_pipeline_test.zig and src/format_cache.zig
- WAZI-130: f4v preview and inline playback -> unreachable: cached f4v media and Windows playback are absent from the fixture; covered by src/video_alias.zig and unfurl-verification's --unfurl-smoke video playback
- WAZI-133: deterministic video smoke fixture -> unreachable: no user-facing change (repo clip and smoke failure enforcement); covered by unfurl-verification's --unfurl-smoke
- WAZI-135: terminal attachment download failure -> unreachable: an expired-media failure response is absent from the fake bridge; covered by src/media_failure_test.zig and src/media_drain.zig
- WAZI-137: encrypted formatting-provider keys -> unreachable: saved formatting-provider credentials and DPAPI migration state are not seeded; covered by lint-repeats rule C1 for plaintext registry reads
- WAZI-141: bulk archive queue progress -> unreachable: a bulk-selected chat fixture and delayed archive acknowledgements are not driven; covered by src/archive_actions_test.zig and src/archive_rules.zig
- WAZI-143: archived/contact search and background selection reconciliation -> unreachable: a provider-populated archived/contact people index is absent from the offline fixture job set; covered by src/people_index.zig, src/chat_reconcile_test.zig and tools/test-people-index-speed.sh
- WAZI-144: plain archives resurface on incoming messages -> unreachable: archive seeds keep-archived, not a plain-archive incoming case; covered by src/archive_actions_test.zig and src/archive_rules.zig
- WAZI-145: encrypted Telegram API hash -> unreachable: Telegram credential setup and DPAPI migration state require a TDLib-enabled build; covered by lint-repeats rule C1 for plaintext registry reads
- WAZI-146: archive source logging and unarchive on send -> `archive` (asserts the kept-source archive log for the synthetic identity; unarchive-on-send requires a separate provider send scenario and remains src/archive_actions_test.zig coverage)
- WAZI-147: former WhatsApp Status browser removed -> `palette` (asserts its Status command and old sidebar control are absent, not the removed viewer behavior)
- WAZI-148: former Status seen receipts/control entry removed -> `palette` (asserts no Status UI entry; removed CLI/pipe commands are covered by src/control.zig and tools/test_no_stories.py)
- WAZI-149: Slack retry and restart-safe image sharing -> unreachable: a direct Slack upload/share transport and restart with its journal are absent from the hub text fixture; covered by src/slack_send_test.zig and tools/test_outbox_runtime.py
- WAZI-150: provider/account-scoped identities -> `hub` (asserts selected provider/account/id agrees with displayed history across switches and provider views; same-id multi-account collisions remain src/chat_key.zig coverage)
- WAZI-152: no-code-comments enforcement -> unreachable: no user-facing change (comment removal and required source policy check); covered by tools/test_no_comments.py and the No new code comments CI step
- WAZI-153: Ctrl+E archives from composer -> `archive` (starts with the composer focused, sends Ctrl+E and requires Alpha archive acknowledgement and Beta selection)
- WAZI-154: Material dark surfaces and unread-dot size -> unreachable: unread-dot geometry measurement is not exposed by the journey; covered by src/theme.zig unread-dot and contrast tests
- WAZI-155: rounded search/composer pills -> unreachable: corner-edge raster measurement is not part of the bounds-only composer oracle; covered by src/field_pill.zig and tools/test_theme_runtime.py
- WAZI-156: silent dictation skipped and speech clips sent once -> unreachable: microphone/synthetic WAV capture and speech-provider request observation are absent from journeys; covered by src/dictation_policy.zig
- WAZI-157: people-search CPU-time performance measurement -> unreachable: no user-facing change (speed-test timing oracle); covered by tools/test-people-index-speed.sh
- WAZI-159: antialiased curves/avatars and GDI fallback -> unreachable: edge-alpha and forced-renderer-fallback measurements are absent from the fixture journeys; covered by src/smooth_geometry.zig and lint-repeats rule F1 for raw rounded calls
- WAZI-160: selectable AMOLED theme -> `menus` (requires default AMOLED, measures dark popups, then switches to Green and verifies saved preference and light native chat menu)
- WAZI-161: DirectWrite IBM Plex Medium body text -> `text-comparison` (requires active DirectWrite, exact bundled Medium/SemiBold font hashes and body/heading metric parity with Chrome)

- IGSH-645: right-click reaction chooses the clicked emoji -> `reactions` (real SendInput selection of laughing face on WhatsApp and Slack, exact hub payload and visible chip)

- IGSH-668: legacy WhatsApp keep flags survive unified hub adoption -> `hub-archive` (seeds only the legacy flag, requires hub archive requests and durable keep state on initial launch and same-profile restart with newer archived=false delivery)

- IGSH-698: plain archived chat came back after his own reaction -> `hub-archive` (plain Ctrl+E archive of two direct chats, then a hub row moved by his own reaction must stay archived while a newer incoming message brings the other chat back)
- IGSH-669: maximize every startup on the saved monitor -> `window` (requires native zoomed state without harness maximization, real restore/resize and Alt+F4, same-profile reopen and --update-relaunch; multi-monitor hardware movement remains outside the hosted fixture)

- IGSH-671: Idle and background-message flicker -> `repaint` (60-second full-paint counter and arrival evidence)
- IGSH-692: voice bubbles drawn misplaced after partial repaints -> `voice` (five voice notes with cached long transcripts, wheel scroll and Show more; partial voice-bubble repaints must match full repaints, with time stamps, player circles and text inside their own bubbles)
- IGSH-683: WhatsApp phone chat page mixing @lid rows -> `hub` (asserts all four texts of a page that mixes phone and same-account @lid ChatJIDs reach the pane and the launch log has no WrongChat; other mismatches stay unit-test coverage in src/hub_test.zig)
- IGSH-681: WhatsApp chats load older hub messages on scroll-up -> `hub` (real PageUp keystrokes page a 250-row synthetic chat through cursor requests `before=<id>:<timestamp>`; asserts all 250 rows once each, oldest first, an empty last page and no request after it; the legacy `whatsapp-hub` bridge is not paged)
- IGSH-679: clipboard screenshot paste and Enter send -> `paste-image` (full-screen and 4K RGBA, V5/PNG and bitmap formats, decoded upload dimensions, alpha and orientation on four synthetic provider chats)
- IGSH-688: attach two or more images -> `paste-image` (WhatsApp and Slack Ctrl+V plus real + picker, two screenshot-measured previews, ordered per-image sends with first-only caption and distinct client IDs, remove-first keeps the second image)
- IGSH-700: Ctrl+K finds archived chats on every account -> `palette-archived` (archived WhatsApp, Telegram and Slack names from the combined inbox and every account view, inbox names from every view, Enter opens the chat without a hub archive write)

- IGSH-667: drag across full chat passages -> `passage-copy` (exact stamped partial clipboard and held-edge scrolling on WhatsApp and Slack)
- IGSH-670: Slack shortcodes, custom emoji and missing Giphy -> `slack-emoji` (exact Unicode and unknown fallback, custom message/reaction image pixels, two different GIF frame crops and account-scoped hub fetch/cache proof)

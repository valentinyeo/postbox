# Postbox verification map

Start with [the skill](../SKILL.md). The offline desktop journeys use the real native window, not the existing headless smoke modes. Each run creates a separate profile and synthetic cached chats `Verification Alpha` and `Verification Beta`, without provider login. Menus seeds one synthetic cached message to reach both message menus; text-comparison loads its synthetic paragraph from `src/verify_text.json`. The baseline is the Graphite theme (internal name `amoled`), saved-scale default of 100%, combined inbox, Alpha selected and an empty composer. Never change the product's default font or scale to suit the harness.

Journey IDs, automatic PR coverage and fixture modes are defined in [journeys.json](../../../../tools/verify-wazig/journeys.json). Read `features/<name>.md` for each registered journey's user-facing recipe. Three long journeys keep their one guide in [FEATURE-MAP.md](../../../../tools/verify-wazig/FEATURE-MAP.md): `real-size` (#journey-real-size), `deep-links` (#journey-deep-links) and `dictation-live` (#journey-dictation-live). Add a journey through one registry entry and its own files; do not maintain another catalog here.

Harness name in each map: `PowerShell UI Automation`. Dispatch with `gh workflow run verify.yml -f feature=<ID>`, watch with `--interval 60`, download `verify-wazig-<ID>` and inspect the images. Other than registered automatic PR coverage, journeys remain dispatchable; never claim skipped coverage as verification.

The source of truth for commands is `src/main.zig:buildPaletteItems`, for keyboard handling `src/main.zig:handleKeyboard`, and for discoverable help `src/shortcuts.zig`. Every feature file has precisely four H2 sections. Capture the input, resulting UI and durable side effects; preserve proof after cleanup. Fixture modes and initial rows differ by journey; search uses synthetic hub histories and appearance replays recorded dictation. Navigation, drafts and palette use offline cached chats. Synthetic hub sends, media and recorded transcription do not prove provider delivery, account login or acoustic recognition.

The hub journey uses a loopback fake bridge with synthetic rows instead of the offline chat seed. Its real app worker and WinHTTP reader run in the same isolated profile. It proves transport behavior against the frozen contract, not a live account or service deployment.

The `hub` journey uses the unified `/v1/wazig` contract and synthetic Slack/WhatsApp rows; `whatsapp-hub` continues to prove the separate legacy bridge. Both run automatically on matching PRs. Unit switch/fallback checks are part of the normal Zig test roots.

The `slack-sort` journey verifies Slack last message ordering and incoming/sent promotion through the unified fake hub, and runs on matching PRs.

The `workspace-icons` journey verifies rounded Slack workspace icon badges, the missing-icon S fallback and the green WhatsApp handset through screenshot pixel checks, authenticated synthetic endpoints and retained disk caches. It runs on matching PRs.

## Thirty-day source sweep

Window: 2026-10-25 through 2026-11-26, ending at `36122c5`. These are source dispositions, not live-pass results.

| Recent change | Source | Journey or missing prerequisite |
|---|---|---|
| `3c6a341`: Postbox links open WhatsApp and Slack chats | `src/deep_link.zig:isPostboxUrl`, `src/main.zig` | `deep-links` registers the isolated protocol, opens a WhatsApp business link distinct from a personal chat with the same number, a Slack channel/timestamp message and a cold start on an older message, and keeps the draft and selection on a missing chat. |
| `f08c582`, `4e9ac99`: the inbox says when it is up to date and catches up after sleep | `src/sync_line.zig:classify`, `src/sync_gate.zig:hubWakeUnixStale`, `src/main.zig:updateSyncLine` | `hub-wake-refresh` reads the label through UI Automation, requires `Up to date` plus its `HH:MM` sync time, the first three reconnect waits 1000, 2000 and 4000 ms logged once each, and a real resume notification refreshed within fifteen seconds. |
| `61e9158`: the next start reports why Postbox closed | `src/exit_record.zig:closeRequestLine`, `src/main.zig:reportPreviousExit` | `exit-record` closes the window from outside the process and asserts the close-request line, the clean-exit line, the record file and its consumption on restart. |
| `61dfa72`: dictation shows the words while you speak | `src/dictation_live.zig:apply`, `src/main.zig:updateLiveDictation` | `dictation-live` requires a fragmented interim and its revision in the composer before CloseStream and one final consumption; the guide is the `Journey: dictation-live` section of FEATURE-MAP.md. |
| `fb9a7e9`: dictation accepts only English and German tags | `src/dictation_policy.zig:parseResponse` | `dictation-shortcuts` asserts the three saved modes; rejecting every other language tag stays `src/dictation_policy.zig` unit coverage. |
| `b0815f5`: Slack chats use Slack reply style by default | `src/main.zig:localSlackStyle` | `slack-threads` seeds the legacy account switch off, then requires a fresh Slack chat folded under `2 replies` with no inline replies and a WhatsApp chat still inline. |
| `e360ea7`: Slack autocomplete | `src/main.zig:updateMentionPopup`, `src/mention_index.zig:search` | `slack-mentions` requires the visible popup, exact token and sent payload; the duplicate hub text-change probe is retired. |
| `6f3db97`: per-chat Slack Replies choice | `src/main.zig:localSlackStyle`, `src/slack.zig:repliesFold` | `slack-threads` checks both saved chat styles against the account default. |
| `febf904`, `2995401`: Read mark and chat isolation | `src/main.zig:drawReadTicks`, `src/read_receipt.zig:status` | `read-ticks`; the older-read/newest-unread case caught the newest-own-only selection bug, which #561 fixed. The journey keeps that case: the newest own message stays delivered while the older one shows blue. |
| `528e4e7`: loaded page thumbnail | `src/main.zig:unfurlCardVisible`, `src/unfurl.zig` | `link-previews` checks card-image pixels. |
| `eda5db7`: voice pill, message grouping and link-card redesign | `src/chat_screen.zig:VoicePill`, `src/chat_screen.zig:ChatRow`, `src/chat_screen.zig:Day` | Existing voice and link journeys cover their original assertions; the title-adjacent pill, Today line and one timestamp per sender group still need dedicated screenshot measurements. |
| `ee076a1`: native new-message toasts, no tray | `src/toast.zig:show`, `src/main.zig:finishNotificationGapIfReady` | Unreachable in the current recipes: need a hosted notification-center capture and real activation input tied to a synthetic incoming message. An accepted notification API call alone is not visible proof. |
| `16e332e`: redesigned update card | `src/main.zig:paintUpdateCard` | `quiet-status` exercises sync errors only; update-ready, downloading, staged and restart states need a pending-release fixture and screenshot assertions. Ordinary fixture startup suppresses update checks. |
| `afac62f`: caret after emoji | `src/directwrite_edit.zig:create` | `caret` currently types ASCII; emoji caret alignment needs a mixed-text fixture and a measured glyph-edge oracle. |
| `c12336f`, `180e120`: colour emoji in sidebar and reply preview | `src/emoji_draw.zig:draw`, `src/main.zig` | Picker glyph coverage is not sidebar/reply colour proof; need screenshot crops containing known colour glyphs. |
| `643cc56`: stalled media download and retry | `src/media_drain.zig:selectNext`, `src/media_drain.zig:backgroundReadExhausted` | `media-speed` covers gone and server-error responses, not a never-answering download followed by a manual retry. Need a held media response and visible failure/retry capture. |
| `907bf17`, `c8fe402`: sent image shown while upload is pending | `src/main.zig`, `src/staged_images.zig` | `paste-image` proves staged and acknowledged images, not the interval before acknowledgement; need a held upload and pending-bubble pixel assertion. |
| `e06be2d`, `7b593ed`, `a96e074`: thread broadcast, panel and orphan replies | `src/main.zig:toggleSlackThreads`, `src/slack.zig` | `slack-thread-broadcast` and `slack-threads` use quoted-message-only hub rows and check sent payloads, folding and restart. |
| `d506159`, `52bc120`: deletion and manual resend | `src/main.zig:applyHubDelete`, `src/main.zig:resendFailedMessage` | `hub` and `hub-fault` check exact request identities and restored failed bubbles. |
| `500ddc4`, `460e2a0`: archive return and retained intent | `src/main.zig`, `src/archive_rules.zig:archiveState` | `archive-return`, `slack-archive`, `hub-archive` and `archive-inbox` retain their separate provider/local contracts. |
| `b11fd97`, `521b4ab`, `727d046`: composer reveal, keyboard reply and chat-number keys | `src/main.zig:composeRevealTop`, `src/main.zig:startReply`, `src/shortcuts.zig` | `drafts`, `reply`, `ctrl-badges` and `notrap`; keyboard reply now checks the exact focused-message first line rather than nonempty text. |
| `e4faa39`, `f1c00f9`, `4f396eb`: own messages carry WhatsApp ticks and a receipt no longer moves the chat | `src/main.zig:drawReadTicks`, `src/read_receipt.zig:status`, `src/message_layout.zig` | `read-ticks` requires the blue mark on an older read message while the newest stays delivered, the second grey tick on delivered, no ticks on Slack or a Signal group, and a scrolled-up hold chat whose top message moves at most two pixels when the receipt arrives. |
| `d8f8d79`: the update check reads a published release file instead of the GitHub API | `src/update.zig:update_file_path`, `src/main.zig:checkForUpdate` | Unreachable in the desktop fixture, which suppresses update offers. `postbox-upgrade.yml` drives `tools/verify-wazig/fake-github-updates.py`; no registered journey covers the update card. |
| `5df4dac`: a brief reconnect keeps the sync line it already shows | `src/sync_line.zig:step`, `src/main.zig:invalidateSyncLine` | `hub-wake-refresh` reads the label through a real dropped stream and requires the three retry waits; the reconnect window and the reduced repaint rectangle are not measured by a journey. |
| `b657ed8`, `36122c5`: an expired media link is not retried, so its not-available note lands at once | `src/media_drain.zig:finish`, `src/main.zig:noteMediaFailureStatus` | `media-speed` asserts one 410 request and the note within 15 s. The 30 second refresh that `b657ed8` added left the row spinning for 28.83 s on the default-branch nightly; `36122c5` made the first 410 final, and the journey is green on the default branch again in the 2026-11-26 nightly. |

## Recent changes coverage

- SOFT-3165: a file that expires on WhatsApp says so at once -> `media-speed` (asserts one 410 request for the gone file, its not-available note and one `gone-media.txt` line within 15 s, and no 30 second refresh retry)
- SOFT-1936: open WhatsApp and Slack chats from Postbox links -> `deep-links` (asserts the isolated protocol registration, the business-versus-personal WhatsApp identity, the Slack message scrolled into the visible canvas, an unchanged draft and selection for a missing chat, and a cold start on an older message; the guide is the `Journey: deep-links` section of FEATURE-MAP.md)
- SOFT-3112: the next start reports why Postbox closed -> `exit-record` (asserts a real window close, both shutdown log lines, the exit record file and its consumption by the restart)
- SOFT-3122: dictation shows words while you speak -> `dictation-live` (asserts the interim fragment and its revision in the composer before CloseStream and one final consumption; the guide is the `Journey: dictation-live` section of FEATURE-MAP.md)
- SOFT-3041: sync catches up after sleep and polls each minute -> `hub-wake-refresh` (asserts a real resume notification refreshed within fifteen seconds, the `Up to date` label with its sync time, and the first three reconnect waits 1000, 2000 and 4000 ms logged once each)
- SOFT-3154: the inbox says when it is up to date -> `hub-wake-refresh` (asserts the label text and its `HH:MM` sync time through UI Automation after the poll row arrives)
- SOFT-3109: Slack chats use Slack reply style by default -> `slack-threads` (seeds the legacy account switch off and requires a fresh Slack chat folded under `2 replies` with no inline replies)
- IGSH-1267: dictation finish and cancel -> `dictation-shortcuts` (asserts native keys, scoped durable sends, cancellation races, navigation disarming and Unicode multiline drafts)
- IGSH-1268: icon hints and voice shortcut -> `icon-hints` (native popup and isolated synthetic voice evidence)

- IGSH-745: unresolved Slack mentions -> `slack-mentions` (asserts hub-named and labelled mentions, @someone fallback, no raw user ids, report link cleanup, real keyboard selection and before/after screenshots)

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
- IGSH-538: WhatsApp Status removed -> `palette` (asserts no row labelled `Status`, former sidebar control 1120 absent, after a positive shortcut-row control)
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
- WAZI-160: Graphite theme (internal name `amoled`) -> `menus` (requires the default theme, measures dark popups, then reapplies `Theme: Graphite` and verifies the saved preference and a dark native chat menu)
- WAZI-161: DirectWrite IBM Plex Medium body text -> `text-comparison` (requires active DirectWrite, exact bundled Medium/SemiBold font hashes and body/heading metric parity with Chrome)

- IGSH-645: right-click reaction chooses the clicked emoji -> `reactions` (real SendInput selection of laughing face on WhatsApp and Slack, exact hub payload and visible chip)

- IGSH-668: legacy WhatsApp keep flags survive unified hub adoption -> `hub-archive` (seeds only the legacy flag, requires durable keep state and zero hub archive requests on initial launch and same-profile restart)

- IGSH-698: plain archived chat came back after his own reaction -> `hub-archive` (plain Ctrl+E archive of two direct chats with zero hub archive requests, then a hub row moved by his own reaction must stay archived while a newer incoming message brings the other chat back; IGSH-902)
- IGSH-669: maximize every startup on the saved monitor -> `window` (requires native zoomed state without harness maximization, real restore/resize and Alt+F4, same-profile reopen and --update-relaunch; multi-monitor hardware movement remains outside the hosted fixture)

- IGSH-671: Idle and background-message flicker -> `repaint` (60-second full-paint counter and arrival evidence)
- IGSH-692: voice bubbles drawn misplaced after partial repaints -> `voice` (five voice notes with cached long transcripts, wheel scroll and Show more; partial voice-bubble repaints must match full repaints, with time stamps, player circles and text inside their own bubbles)
- IGSH-683: WhatsApp phone chat page mixing @lid rows -> `hub` (asserts all four texts of a page that mixes phone and same-account @lid ChatJIDs reach the pane and the launch log has no WrongChat; other mismatches stay unit-test coverage in src/hub_test.zig)
- IGSH-681: WhatsApp chats load older hub messages on scroll-up -> `hub` (real PageUp keystrokes page a 250-row synthetic chat through cursor requests `before=<id>:<timestamp>`; asserts all 250 rows once each, oldest first, an empty last page and no request after it; the legacy `whatsapp-hub` bridge is not paged)
- IGSH-679: clipboard screenshot paste and Enter send -> `paste-image` (full-screen and 4K RGBA, V5/PNG and bitmap formats, decoded upload dimensions, alpha and orientation on four synthetic provider chats)
- IGSH-688: attach two or more images -> `paste-image` (WhatsApp and Slack Ctrl+V plus real + picker, two screenshot-measured previews, ordered per-image sends with first-only caption and distinct client IDs, remove-first keeps the second image)
- IGSH-700: Ctrl+K finds archived chats on every account -> `palette-archived` (archived WhatsApp, Telegram and Slack names from the combined inbox and every account view, inbox names from every view, Enter opens the chat without a hub archive write)
- IGSH-1329: holding Ctrl numbers the top nine chat rows -> `ctrl-badges` (real Ctrl key-down shows six numbered badges, Ctrl+3 opens the third row with badges kept, key-up clears them; pixel measures per badge)

- IGSH-667: drag across full chat passages -> `passage-copy` (exact stamped partial clipboard and held-edge scrolling on WhatsApp and Slack)
- IGSH-701: Ctrl+A from an empty composer -> `archive-bulk` (two visible chats selected, Ctrl+E archives both, empty inbox and text select-all preserved)
- IGSH-670: Slack shortcodes, custom emoji and missing Giphy -> `slack-emoji` (exact Unicode and unknown fallback, custom message/reaction image pixels, two different GIF frame crops and account-scoped hub fetch/cache proof)

- IGSH-737: include archived chats per account and inbox -> `show-archived` (Alt+A, marked mixed rows, local archive actions, tooltip and same-profile restart)

- IGSH-777: bulk archive sends one WhatsApp batch and preserves every result -> `archive-inbox` (fixed 264-chat timing, one batch, no single archive requests, durable state and restart)
- IGSH-824: remove the sidebar status strip, retain exact version discovery and visible sync failures -> `quiet-status` (native absence, list geometry, real click, version row and forced HTTP 503 in the existing sidebar update card without a modal dialog)


- IGSH-829: regular message bodies and hanging list indentation -> `chat-lists` (six long bullets and two nested levels, actual font weight and screenshot text-edge alignment at two saved sizes)

- IGSH-1123: reply preview and quoted-message navigation -> `reply` (two-provider native preview, both cancellation paths, send target and fading original highlight)
- IGSH-1602: a sent message shows once and no bubble keeps "(sending)" -> `send-once` (normal chat and archived chat, one bubble by text, no waiting bubble, empty outbox)
- IGSH-1603: a reply in an archived chat returns it to Combined and its messenger inbox, Keep archived stays archived -> `reply-unarchive` (archive, reply, inbox and Combined, restart, keep archived reply)
- IGSH-1595: the first search after a fresh start finds archived chats -> `archived-search` (fresh app start, Ctrl+F, archived test chat listed on the first try)
- IGSH-1689: gone media is unavailable at once, server errors back off from 5 s, hub downloads run three at once -> `media-speed` (ten images and voice notes with slow replies, one server error and one gone file; all ten show within 15 seconds)
- IGSH-1242: GIF picker -> `gif-picker` (Ctrl+K Send a GIF against a loopback GIPHY look-alike: missing-key notice, protected storage, search and download retry, Escape keeps draft and reply, staged original sent once with the reply and caption)

# Gates: WAZI-150 account-scoped chat identity

OWNS: GATES.md, src/main.zig, src/chat_key.zig, src/chat_cache.zig, src/outbox.zig, src/transport.zig, src/*_test.zig, src/media_drain.zig, tools/outbox_runtime_test.zig, build.zig, tools/test_outbox_runtime.py, tools/lint-repeats.sh, tools/test-lint-repeats.sh, CLAUDE.md

Scope: Account-scoped chats, jobs, caches and durable queued sends with lossless legacy migration and regression enforcement. Checks use Bash on Linux and Zig 0.16.0.

- [x] G0: Ledger has valid, testable gate definitions
  CHECK: node ~/.agents/skills/unlazy/scripts/gate-lint.mjs GATES.md
  EXPECT: LINT OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=2770f040a7cc8da49fa1524d3a3fe5b65db289d5d3f753f22af30412dee16138; exit=0; EXPECT=matched; output-sha256=48630b7361dd44ee870917b12c3d19b9d7bdea738aaca16bb04d4cab83b772d2; output-bytes=8; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

- [x] G1: Zig source formatting is clean
  CHECK: ~/.local/zig-0.16.0/zig fmt --check src build.zig && printf 'FORMAT_OK\n'
  EXPECT: FORMAT_OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=d5d7f7e1a40635c4ddd7e36a8ffc0d8a063f856b54c4db18bc9dc9eb1e6f5902; exit=0; EXPECT=matched; output-sha256=2e80be8b8767d5f21912dcc361bab93340f72f82495eee2f102383038a040c74; output-bytes=10; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

- [x] G2: Unit tests pass including required account isolation and legacy outbox tests
  CHECK: rg -F 'test "two WhatsApp accounts that share a contact keep their chats apart"' src/chat_key.zig && rg -F 'test "old line without account parses and keeps the send"' src/outbox.zig && ~/.local/zig-0.16.0/zig build test && printf 'UNIT_TESTS_OK\n'
  EXPECT: UNIT_TESTS_OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=d2487456bdd1fdfd88b4c629e3e86e3c33154dad06bdda18f50d997a62f9d5ee; exit=0; EXPECT=matched; output-sha256=aaa8cb49a8f9bcf7bffc84dd677683451f3439ef772e49c2f7239cba76fdf668; output-bytes=149; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

- [x] G3: Actual outbox runtime and negative controls preserve sends through migration
  CHECK: python3 tools/test_outbox_runtime.py --zig ~/.local/zig-0.16.0/zig --negative-controls
  EXPECT: OUTBOX_RUNTIME_VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=0b656e4c631260741d6af2102015827210bcb765ad7737a16a0cbc3b42ae4b23; exit=0; EXPECT=matched; output-sha256=ed9239d01dd5de73baa67246d2295e02836e25e92af950c8f079bb72b6b9957c; output-bytes=6605; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

- [x] G4: Windows release-small binary builds
  CHECK: ~/.local/zig-0.16.0/zig build -Dtarget=x86_64-windows-gnu --release=small && printf 'WINDOWS_BUILD_OK\n'
  EXPECT: WINDOWS_BUILD_OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=ddbb6be170d96d6c734b05654d0d64408624723f5ef1c59dcc9f748e12f77621; exit=0; EXPECT=matched; output-sha256=186a613d48782bab26d3dd09e5857f05652ffda7a6610578647b5856c36adc95; output-bytes=17; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

- [x] G5: Repeat lint passes and rejects historical raw jid comparisons
  CHECK: bash tools/lint-repeats.sh . && bash tools/test-lint-repeats.sh
  EXPECT: test-lint-repeats: PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=3dd0b2d1c9e80510f71c5fcaf39b1af12b06a3a6f9cf596e47adc9ace23622a4; exit=0; EXPECT=matched; output-sha256=cb38dc537f6a57b679cde1557233f49f3d2cf447c02c7db516220640d437efc9; output-bytes=4821; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

- [x] G6: No new code comments are introduced
  CHECK: python3 tools/check_new_comments.py origin/main && python3 -c 'import subprocess; from tools.check_new_comments import find_new_comments; hits = find_new_comments(subprocess.check_output(["git", "diff", "--unified=0", "origin/main"], text=True)); print("Working-tree added comments:", len(hits)); assert not hits, hits'
  EXPECT: Working-tree added comments: 0
  EVIDENCE: automatic-evidence=v1; definition-sha256=abd602ba5b0d42aff3e73965d45c0303e34edd2547679e3aebac7bae18cb5b9f; exit=0; EXPECT=matched; output-sha256=65290744b3ea7162a851d593753c83655923d6f199c41ccbcf4f4bf3df3ce98e; output-bytes=53; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

- [x] G7: All five runtime identity structures have an account field
  CHECK: count=$(grep -cE '^\s+account: ' src/main.zig) && printf 'account fields: %s\n' "$count" && test "$count" -ge 5 && printf 'ACCOUNT_FIELDS_OK\n'
  EXPECT: ACCOUNT_FIELDS_OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=9258daffc2b52f866e89e7e34f57d1d3ccfb913113aaba1f2590aa001dae27ef; exit=0; EXPECT=matched; output-sha256=5011c3f39951939c2523e2fb7ef38ff0aacd0773bbc5b294ef4c652ff05e8e17; output-bytes=36; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

- [x] G8: Full project preflight passes
  CHECK: bash tools/preflight.sh && printf 'PREFLIGHT_OK\n'
  EXPECT: PREFLIGHT_OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=c380d4e2ffb9024413c979fadf898327aa15112ad9404d950b9814809e7cd7ee; exit=0; EXPECT=matched; output-sha256=5b25c8b0448c7972216775b5f30845de6762305326100fa1f12df6a78b88f2a9; output-bytes=14011; shell=/bin/sh; cwd=.; path=fd84e4e63686/12 entries

## Changed production functions

- `src/chat_key.zig`: `Key.eql`, `of`, `displayed`, `indexOf`.
- `src/chat_cache.zig`: `envelope`, `payloadFor`.
- `src/outbox.zig`: `writeLine`, `parseLine`.
- `src/main.zig`: `wacliRunJob`, `msgCacheGet`, `msgCacheStore`, `refreshGroups`, `refreshContactsIndex`, `peopleChat`.
- `src/main.zig`: `refreshChats`, `applyChats`, `queueUnreadProbe`, `appendTelegramChats`, `refreshTelegramMessages`, `slackChatById`.
- `src/main.zig`: `noteSlackActivity`, `applySlackWorkspace`, `applySlackUsers`, `refreshSlackWorkspace`, `refreshSlackHistory`, `applySlackHistory`.
- `src/main.zig`: `appendWhatsAppPending`, `appendWhatsAppFailed`, `rememberFailedSend`, `forgetFailedSend`, `pruneFailedSends`, `restoreFailedSendText`.
- `src/main.zig`: `resendFailedMessage`, `resolveSlackSend`, `persistOutbox`, `loadOutbox`, `bindOutboxAccount`, `enqueueSlackOutbox`.
- `src/main.zig`: `requestSlackDownload`, `loadSlackTokens`, `markChatRead`, `slackMarkViewMatches`, `fireSlackMark`, `messagesAreCurrent`.
- `src/main.zig`: `downloadMedia`, `autoDownloadNextMedia`, `loadMsgCacheDisk`, `pollFormatting`, `refreshMessages`, `reconcileOpenChat`.
- `src/main.zig`: `applyMessageData`, `enqueueCacheTagProbe`, `sentMessageExists`, `startNextSend`, `stageImageFromClipboard`, `queueVoiceNote`.
- `src/main.zig`: `sendMessage`, `reactToMessage`, `enqueueReactionJob`, `tickArchivedScan`, `enqueueResurfaceProbe`, `visibleChatIndex`.
- `src/main.zig`: `chatProvider`, `archiveChat`, `unarchiveSentChat`, `archiveSelectedChat`, `controlWhatsAppChats`, `controlSelect`.
- `src/main.zig`: `controlMessages`, `refreshStatuses`, `enqueueStatusSeen`, `replyToStatus`, `mainProc`, `applyStartupProbe`.
- `build.zig`: `build`; generated host-test fixtures and lint/runtime regression cases updated alongside their production call sites.

# Gates: IGSH-464 Slack session sign-in

Scope: Add protected session credentials, one-time import, shared Slack operations and RTM, fake-server coverage and a verification journey without changing OAuth mode.

PR note: An external actor created PR #298 during this session and closed it without merging. This session issued no PR creation commands and did not change that PR.

- [x] G0: This ledger has valid, outcome-oriented checks
  CHECK: node $HOME/.agents/skills/unlazy/scripts/gate-lint.mjs GATES.md
  EXPECT: LINT OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=66b2e0ae2a41eecbc187b178d77d63771a8aacd2c54ddb8feaaee9f7082da580; exit=0; EXPECT=matched; output-sha256=b0acab2df97d4db8bb9e00b1ac602ad8b9b9784b314fb6b1a9f18e39e834f2c3; output-bytes=387; shell=/bin/sh; cwd=/home/valentin/projects/wz-IGSH-464; path=b7c9797232e1/20 entries

- [x] G1: Session credentials and import use DPAPI, consume invalid files, and preserve OAuth compatibility
  EVIDENCE: Run 39863969039 on 58c522b passed all eight named Zig session tests. The import test checks two isolated session records, DPAPI REG_BINARY ciphertext without credential substrings, deleted valid/invalid/empty import files, absent-file handling and OAuth-default records. Reviewed src/slack_win.zig:218-325 and src/main.zig:17440; startup uses the existing Messages local directory, with fixed token-free import logs and no new UI. The real journey's final-data contains no import file; cleanup and protected-value-kind checks passed.

- [x] G2: Shared API operations authenticate session requests and RTM upgrades with the cookie, and rejected sessions become signed out
  EVIDENCE: Run 39863969039 records authenticated form API calls, Cookie-bearing RTM upgrade, text opcode 1 and raw incoming RTM delivery. Server state measures one app send and zero envelope acknowledgements. Native tests cover rejected auth and not_authed; reviewed requireSlackSignIn/socketThreadMain for the existing needs_signin state and immediate rejection return without refresh/retry. History, sent and after screenshots were visually inspected: Slack badge and all three synthetic messages are visible. Shared runJob paths retain files, replies and mark-read; existing OAuth fake-server/PKCE/refresh checks passed in GitHub CI on the same production code.

- [x] G3: Native session tests and the real app journey have surviving fake-server evidence
  CHECK: python3 tools/verify-wazig/check-evidence.py /tmp/igsh464-evidence-final
  EXPECT: EVIDENCE VERIFIED: Slack session
  EVIDENCE: automatic-evidence=v1; definition-sha256=2e8fc29ce57c2f64e0821a8d2e0777740eb853c938e130d753a385c9e16cd6fc; exit=0; EXPECT=matched; output-sha256=af12e8a5b80b14c06e01709f477314795b7211baa003bb55250000ac6c8f43c1; output-bytes=99; shell=/bin/sh; cwd=/home/valentin/projects/wz-IGSH-464; path=b7c9797232e1/20 entries

- [x] G4: The Slack session verification journey is in the workflow matrix and feature map
  CHECK: python3 tools/verify-wazig/check-map.py
  EXPECT: MAP VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=717f2c91da49a1efac95c3c818e852624787739971ba85a92b6578b43a0a4183; exit=0; EXPECT=matched; output-sha256=29f2b4b343d008f6f242272008dbb49672316aab2ee8bca63ab4c17eb9e0a646; output-bytes=108; shell=/bin/sh; cwd=/home/valentin/projects/wz-IGSH-464; path=b7c9797232e1/20 entries

- [x] G5: Changed production Zig files and native session tests pass formatting and AST syntax checks
  CHECK: set -e; for file in build.zig src/main.zig src/slack.zig src/slack_win.zig src/slack_session.zig src/slack_session_test.zig; do "$HOME/.local/zig-0.16.0/zig" fmt --check "$file"; "$HOME/.local/zig-0.16.0/zig" ast-check "$file"; done; "$HOME/.local/zig-0.16.0/zig" fmt --check src/slack_send_test.zig tools/outbox_runtime_test.zig; printf 'ZIG SYNTAX VERIFIED\n'
  EXPECT: ZIG SYNTAX VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=753db3e5f23ed591e83836d0485c56ba7fa95c0871cf6a71e6f74390b85486d7; exit=0; EXPECT=matched; output-sha256=3fb3fe6c1abd76adf6e3227d49f4540dac4d37222db371429aaf9d720c6763b5; output-bytes=20; shell=/bin/sh; cwd=/home/valentin/projects/wz-IGSH-464; path=b7c9797232e1/20 entries

- [x] G6: Fake Slack tooling tests pass locally, including rejected cookie and bearer-only controls
  CHECK: python3 tools/test_slack_session.py
  EXPECT: /(?:^|\n)OK\r?\n/
  EVIDENCE: automatic-evidence=v1; definition-sha256=7ab18aacd20cd05f787d409b2969004cf910c2b831d225e9d204ae30b910c764; exit=0; EXPECT=matched; output-sha256=481d0799e27c1f5cd55ca4fcbbc7b3880f104ce1d2bf1e73898b0de6c5f6cf0f; output-bytes=102; shell=/bin/sh; cwd=/home/valentin/projects/wz-IGSH-464; path=b7c9797232e1/20 entries

- [x] G7: Repository comment policy passes
  CHECK: node tools/strip-comments.mjs --check
  EXPECT: No code comments found.
  EVIDENCE: automatic-evidence=v1; definition-sha256=cd5bd956f38c93d1655fd41ff1510256fd5e63a749f3a2451a2ca1d60307dc61; exit=0; EXPECT=matched; output-sha256=33ad9c77b5aaa9b59009bc21cbb061083aebe1abb6a656c7c02af72264a20ded; output-bytes=24; shell=/bin/sh; cwd=/home/valentin/projects/wz-IGSH-464; path=b7c9797232e1/20 entries

- [x] G10: Changelog, public-safe diff and unchanged APP_VERSION are reviewed
  EVIDENCE: CHANGELOG.md Unreleased entry and README/feature map reviewed against the request. GitHub private-markers run 39863975567 succeeded on 58c522b; pre-commit secret scanners passed. All added identities/content are explicit fakes, and added logs contain fixed messages or auth booleans only. Version embedding and build default match baseline 6434e68; planted version-change and APP_VERSION filename controls were detected. No local build, Zig test, Wine, desktop run, stash or PR creation command was issued.

- [x] G8: Ticket commits are pushed to the requested branch and no PR remains open
  CHECK: test "$(git branch --show-current)" = ceo/IGSH-464-session && test "$(git rev-parse HEAD)" = "$(git rev-parse origin/ceo/IGSH-464-session)" && test "$(gh pr list --head ceo/IGSH-464-session --state open --json number --jq length)" = 0 && git log --format=%s 6434e68..HEAD | python3 -c 'import sys; lines=sys.stdin.read().splitlines(); assert lines and all(line.startswith("IGSH-464:") for line in lines); print("PUSH VERIFIED")'
  EXPECT: PUSH VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=2897ae5d04ed707a69220341a46bd1a988239f9d33959241b197b4abb5e94af0; exit=0; EXPECT=matched; output-sha256=23b03a4ce2954d9fa3106592568b3c7a6d2c2c736bf933aa1b4a008453550fca; output-bytes=14; shell=/bin/sh; cwd=/home/valentin/projects/wz-IGSH-464; path=b7c9797232e1/20 entries

- [x] G9: GitHub builds and fake-session journey pass for the pushed commit
  CHECK: gh run view 39863972679 --json conclusion,headSha | jq -e --arg sha "$(git rev-parse HEAD)" 'select(.headSha == $sha and .conclusion == "success") | "CI VERIFIED"' && gh run view 39863969039 --json conclusion,headSha | jq -e --arg sha "$(git rev-parse HEAD)" 'select(.headSha == $sha and .conclusion == "success") | "GITHUB RUNTIME VERIFIED"'
  EXPECT: GITHUB RUNTIME VERIFIED
  EVIDENCE: automatic-evidence=v1; definition-sha256=801359fe7cb54330cd1822ad5a83709b0b4bbad927e26c678f70206024e2e874; exit=0; EXPECT=matched; output-sha256=09d3f536466698d11b02923164c652633fd1b081f9e2c5805c6cd3f55a66942f; output-bytes=40; shell=/bin/sh; cwd=/home/valentin/projects/wz-IGSH-464; path=b7c9797232e1/20 entries

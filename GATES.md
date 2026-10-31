# Gates: IGSH-681 missing WhatsApp chat list

Scope: Trace every applyChats rejection for combined and WhatsApp views, make the smallest fix and regression, preserve the three existing commits, and record proof without local project execution, board writes, merge, or laptop access.

Manual gates are intentional: the user prohibits project tests and builds on this VPS; source review is not represented as runtime proof. This session's report is DIAGNOSIS3.md; the concurrent helper's DIAGNOSIS2.md is retained.

- [ ] G1: Diagnosis identifies the exact failing condition and values for WhatsApp/Slack versus Telegram, covering account matching, view keys, unresolved names, archived state, pending archives, kept archives, and account registration.
  EVIDENCE: Source trace in /tmp/r5-IGSH-681/DIAGNOSIS3.md proves the supplied row passes provider/account matching in both stated views, but cannot identify which runtime filter rejects it. Missing search, unread_only, show_archived, pending archive, and read-state values prevent exact diagnosis.

- [ ] G2: The smallest fix restores combined and own-account lists without new limits, waits, features, comments, or unrelated changes.
  EVIDENCE: No production edits made; modifying a predicate without identifying a failed value would be speculative.

- [ ] G3: A regression test or verify-wazig journey exercises the actual rejection path, with a source-grounded explanation of why main fails and the fix passes.
  EVIDENCE: Existing tools/verify-wazig/views.ps1 exercises combined and prefixed own-account rows, but is not established to reproduce this incident. No false red/green claim made.

- [x] G4: The existing commits 9308e20, bd20ab5, and 83a31d3 remain intact; edits stay in the requested worktree; no board write, merge, laptop access, local project build, test, Gradle, or Wine execution occurs.
  EVIDENCE: git merge-base --is-ancestor succeeded individually for all three commits; HEAD remains 83a31d3 on ceo/IGSH-681. git status lists only untracked ledgers. Command history contains source/metadata inspection and skill ledger lint/status only, with no project execution, board, laptop, commit, push, merge, or branch changes. Report stored alongside the worktree in /tmp/r5-IGSH-681 as required by the inherited report gate; the concurrent helper's report was restored and this session uses DIAGNOSIS3.md.

- [ ] G5: GitHub checks demonstrate the regression is red on main and green with the fix.
  EVIDENCE: Not executed. No failing fixture or justified fix exists yet; no commit/push authorization requested or used.

- [x] G6: /tmp/r5-IGSH-681/DIAGNOSIS3.md records cause, fix, regression, and exact proof/handoff status without private chat data.
  EVIDENCE: Read back DIAGNOSIS3.md: exact row-value trace, all requested filters, current-main differences, missing-state handoff, no-code/no-regression status, and gate counts included. Synthetic identifier replaces supplied private contact data. DIAGNOSIS2.md belongs to the earlier concurrent helper and was retained.

ABANDON: G1 Exact rejecting condition cannot be established from row fields and view alone; Runner 5 must provide sanitized current filter-state snapshots in both views.
ABANDON: G2 No safe minimal fix can be selected until G1 identifies a failing predicate; do not bypass archive, unread, search, or account semantics speculatively.
ABANDON: G3 No honestly red-on-main incident fixture is available; create the regression after the missing runtime state establishes reproduction.
ABANDON: G5 GitHub red/green proof requires that reproduction and an authorized published change; neither exists in this helper session.

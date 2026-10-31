# Gates: IGSH-681 missing WhatsApp chat list

Scope: Diagnose the unified chat omission, make the smallest compatible fix and regression journey, preserve paging commits, and document evidence without running project code on the VPS or touching the laptop.

- [x] G1: Diagnosis traces chat listing and message fetching to the divergent source with file:line evidence.
  EVIDENCE: Manual source and aggregate HTTP review: DIAGNOSIS2.md File:line trace; chat-archive-counts1.txt records zero inbox versus 433 all-archived personal rows. handlers.go:86-89 applies --no-archived, while handlers.go:123-153 fetches messages without an archive predicate. Later snapshots demonstrate externally changed archive state, not a helper fix. Origin of the mass archival remains unproven.

- [ ] G2: The fix preserves the hub/client contract and restores WhatsApp chat rows without new limits, waits, caps, features, or code comments.
  EVIDENCE: No product-code change made. Initial omission was correct filtering of archived data; later unchanged unified inbox returned 414 WhatsApp rows. Altering archive semantics or changing owner archive state is not a justified authorized code fix.

- [ ] G3: A regression journey exercises the omitted chat list and messages, with a main-versus-fix failure explanation grounded in source.
  EVIDENCE: Existing paging journey preserved at tools/verify-wazig/harness.ps1:388-422, mode hub, with evidence oracle check-evidence.py:373-394. It targets paging, not upstream mass archival. Current origin/main bd0c952 already contains paging merge 6090893 (#336), so claiming red on current main would be false.

- [x] G4: Existing paging commits remain ancestors and all edits stay in allowed worktrees; no board, merge, laptop, project build, test, or app execution occurs.
  EVIDENCE: Manual review of command history and git metadata: merge-base --is-ancestor succeeds for 9308e20, bd20ab5, 83a31d3; HEAD remains 83a31d35d32b88138aac5b716828c488a9ffd376. No tracked edits; this helper's ledger is isolated under .unlazy/igsh-681-helper2/GATES.md and the concurrently replaced root GATES.md is retained. Main checkouts read only. No local project code executed; remote research only inspected source/metadata/binary contents and performed read-only GETs to already-running services. No HTTP writes, laptop, board writes or merge.

- [ ] G5: GitHub checks demonstrate the regression is red on main and green with the fix.
  EVIDENCE: Not executed. No new code fix is justified by the measured archive state; current main already includes the original paging journey and implementation. No local project checks ran.

- [x] G6: /tmp/r5-IGSH-681/DIAGNOSIS2.md records cause, fix, journey and exact proof/handoff status.
  EVIDENCE: Manual reread of DIAGNOSIS2.md: immediate archive-filter cause, two distinct archive-state snapshots, no-code decision, original paging baseline versus current main, three preserved commits, 3 met and 3 abandoned gates, and explicit CI/owner-state handoffs.

ABANDON: G2 Runner 5 must reconcile externally changed archive state and authorize further investigation of its writer; no archive-contract bypass or owner-data mutation is justified.
ABANDON: G3 No valid archived-inbox regression can require incorrect archive behavior; preserve existing paging journey and do not claim it reproduces the archive-state incident.
ABANDON: G5 GitHub execution remains with Runner 5; current main already contains the original paging fix, so the requested current-main red premise no longer holds.

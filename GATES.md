# Gates: IGSH-824 quiet sidebar

OWNS: GATES.md, src/main.zig, tools/preflight-light.sh, tools/test_status_line.py, tools/verify-wazig/**, .claude/skills/verify-wazig/**

Scope: Evidence-first removal of the sidebar status control and reserved space, exact version discovery in Ctrl+K, retained sync failure delivery and unchanged update card; two local commits and an evidence-only red branch based on ceo/IGSH-823.

Authorization: No local builds, Zig, Wine, Gradle, suites, gate checker or linter. Only python3 tools/test_repaint.py and the directly changed single Python test file may execute locally. Gates use direct authorized output and source/history inspection. Actual Windows journeys are a runner handoff, not claimed as locally executed proof.

- [x] G1: Evidence asserts native status window and label absence, reclaimed list bounds, inert former click point, and the exact version palette row, with positive controls and rejecting negative controls.
  EVIDENCE: The registered quiet-status Windows journey reads both native GetDlgItem(1048) and UIA, checks labels and list bounds, drives real hover/click and Ctrl+K with a readable Keyboard shortcuts positive control, then requires the exact version row. The changed-file test accepts synthetic surviving proof and rejects status windows, labels, tooltips, old list bounds, changed selection, missing/stale version rows and missing positive controls. Direct pre-fix run: 10 tests, 3 expected app-contract/layout failures, no errors; evidence negative controls pass. Windows execution is not claimed.

- [x] G2: A forced provider sync-read failure requires a real existing native problem dialog and exact failure text; surviving evidence validates the input, problem surface and isolation.
  EVIDENCE: Authenticated fixture endpoint forces real /v1/wazig/chats HTTP 503; Refresh is driven through the real palette. The journey requires an owned #32770 native dialog and exact existing sync-read failure text, logs the actual 503 request and recovers before keyboard dismissal. The validator rejects absent/wrong dialog, process, failure text and request proof. Direct changed-file fixture test proves baseline 200, unauthenticated 401, forced 503 and recovered 200. Actual Windows dialog capture is reserved for the runner.

- [ ] G3: App removes status creation, identifier, field, font, colour handling and layout slot; only the chat list grows, the version row is searchable, and update card geometry, rendering and interaction remain unchanged.
  EVIDENCE: pending

- [ ] G4: Authorized changed-file tests and unchanged repaint checks pass, while the new source assertions reject the parent app and deliberately broken behavior/evidence.
  EVIDENCE: pending

- [ ] G5: Exactly two commits follow ceo/IGSH-823: assertions-only A then app B; ceo/IGSH-824-red contains only cherry-picked A on ceo/IGSH-823; clean trees, no push or PR, and exact dispatch handoff recorded.
  EVIDENCE: pending

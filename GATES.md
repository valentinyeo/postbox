# Gates: IGSH-824 quiet sidebar correction

OWNS: GATES.md, src/main.zig, tools/test_status_line.py, tools/verify-wazig/journey-quiet-status.ps1, tools/verify-wazig/evidence-quiet-status.py, .claude/skills/verify-wazig/**

Scope: Correct failure delivery to the existing sidebar update card without changing its look, dismissal, palette version row, commit A or the red branch; amend only commit B.

Authorization: Only python3 tools/test_status_line.py, python3 tools/test_no_stories.py and python3 tools/test_repaint.py may execute locally. No builds, Zig, Wine, Gradle, suites, gate checker or linter. Gates record direct authorized output and source/history inspection rather than checker-generated evidence. Windows journeys and screenshot review are runner work, not locally executed proof.

- [x] G1: showProblem logs via setStatus, stores persistent update_card_error and refreshes the existing card; it never opens a dialog and only the already-running warning retains MessageBoxW.
  EVIDENCE: python3 tools/test_status_line.py: 13 tests OK. showProblem copies bounded text into update_card_error, sets its persistent length and calls updateCardRefresh after setStatus/appendLaunchLog. Source guards reject missing storage, missing refresh, log-side clearing and modal regression, and require exactly one MessageBoxW call: the unchanged already-running instance warning. No timer or replacement indicator was added.

- [x] G2: A sync failure can reveal and paint the existing card without a pending update; only pending-update suppression changes, with identical card geometry, drawing styles, existing update behavior and Esc/dismiss paths.
  EVIDENCE: python3 tools/test_status_line.py compares update-card geometry, refresh, failure handling, click, dismiss and handleKeyboard byte-for-byte with base 162b5d1. Exact normalized comparisons permit only moving the error visibility check before the pending-update guard and replacing the painter pending-update early return with empty tag/notes fallbacks. The existing error line, colours, fonts, labels, controls, success clearing and dismissal code are unchanged. The existing layout refresh invalidates the main window and reserves only visible-card clearance.

- [x] G3: Quiet-status evidence requires the exact failure in the existing visible card, retained across ordinary input/repaint, with no modal dialog and a real authenticated provider 503; positive and rejecting controls cover the corrected contract.
  EVIDENCE: python3 tools/test_status_line.py accepts synthetic surviving card evidence and rejects wrong surface/PID/text, a modal handle, hidden card, lost persistence, missing card in screenshot state, missing list clearance and absent HTTP 503 proof. The real fake-hub endpoint test proves authenticated baseline 200, unauthorized mutation 401, forced read 503 and recovery 200. The Windows journey uses real Refresh and palette input, read-only card state, native list bounds, no-dialog assertions and matching sync-problem/after screenshot state. Actual Windows execution and visible-pixel inspection are not claimed.

- [x] G4: All three authorized test files pass; source guards still reject the parent and deliberately broken status, palette, problem routing, visibility, painting and evidence.
  EVIDENCE: Final authorized direct runs: python3 tools/test_status_line.py: 13 tests OK; python3 tools/test_no_stories.py: 4 tests OK; python3 tools/test_repaint.py: 6 tests OK. Parent-source rejection and deliberately broken source/evidence controls pass within the status test. No build, Zig, Wine, Gradle, suite, gate checker or linter was run.

- [x] G5: Only B is amended, exactly two commits follow the base, A and ceo/IGSH-824-red remain unchanged, and the final tree is clean with no push or PR.
  EVIDENCE: Amended B retains parent A df614c42a134c1a2a8a24cc8de56545e428fb3aa and exactly two commits over base 162b5d1435c41d026f29532af01ed8b6ab0ed7e2. Red remains 88ee692ef899028fe209cbb642db9637a4d43d1b; its tree and A both remain 6b83dc11148bdd9f86f5c863e6cc0db780527c94. Final history, refs and clean-tree inspection are required immediately after amend before reporting. No push, PR, branch modification or workflow dispatch.

## Runner handoff

After the runner pushes the two local branches, dispatch and inspect the quiet-status/version/sync-problem screenshots and validator result. Red must fail on the existing native status control; green must show the exact failure in the existing sidebar update card without a dialog. The red branch intentionally retains the original assertion commit unchanged.

```sh
gh workflow run verify.yml -R valentinyeo/wazig --ref ceo/IGSH-824-red -f feature=quiet-status
gh workflow run verify.yml -R valentinyeo/wazig --ref ceo/IGSH-824 -f feature=quiet-status
```

Local deliverable ledger: 5 met, 0 unmet, 0 abandoned. Windows execution and visual inspection remain required runner work.

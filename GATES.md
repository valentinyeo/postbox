# Gates: sidebar surface and single-pixel divider

OWNS: GATES.md, src/theme.zig, src/main.zig, tools/verify-wazig/*sidebar*, tools/verify-wazig/journeys.json, tools/verify-wazig/check-map.py, .github/workflows/verify.yml, .claude/skills/verify-wazig/features/sidebar-surface.md

Scope: Only lift the sidebar surface and add its faint right-edge divider, with screenshot measurements, unchanged-chat baseline comparison, and separate local red and green commits.

Authorization: Only directly changed single Python validators/test files may run locally. Builds and Windows execution belong to the runner. The unlazy Node gate checker/linter cannot run under that restriction; direct command transcripts below are not checker-generated certification.

- [x] G1: Screenshot validator rejects the old surface, missing or wide divider, unreadable text, and changed chat pixels while accepting valid dark and light captures
  CHECK: python3 tools/verify-wazig/test-sidebar-surface.py
  EXPECT: SIDEBAR VALIDATOR CONTROLS PASSED
  EVIDENCE: Direct authorized run exited zero and printed SIDEBAR VALIDATOR CONTROLS PASSED. PNG round trips and measured controls cover AMOLED, Green and an inverted-light synthetic palette; old black/absent-divider pixels and 14 other raster/geometry defects are rejected. These are synthetic controls, not Windows screenshot evidence.

- [x] G2: Journey registration, retained screenshots, baseline build provenance and theme coverage are consistent
  CHECK: python3 tools/verify-wazig/check-map.py
  EXPECT: verification skill map passed
  EVIDENCE: Direct authorized run exited zero: 36 feature entries and verification skill map passed. The registered PR journey includes both dark themes, real paragraph messages, full desktop captures, historical baseline build/hash binding, exact full-chat comparison, cleanup evidence and a surviving screenshot validator.

- [ ] G3: Only sidebar surface and divider rendering change; chat, text, bubbles, geometry, and hit areas remain untouched
  EVIDENCE: pending

- [ ] G4: Commit A contains proof only; commit B contains app changes; the red branch contains A cherry-picked onto the requested base
  EVIDENCE: pending

- [ ] G5: Isolated Windows screenshot evidence fails on the red branch and passes on the app branch, with measured colour, text contrast, divider luminance, and unchanged-chat pixels
  EVIDENCE: Not executed. No remote branch publication or local Windows/build execution is authorized. Runtime colour values and screenshot review are not claimed.

ABANDON: G5 Required runner handoff: publish both local branches, dispatch the two commands below, download both artifacts, confirm commit/hash provenance, inspect both theme pairs and require red failure plus green success. This gate is not met.

- [ ] G6: No prohibited local builds, Zig, Wine, Gradle, suites, pushes, PRs, or code comments are introduced
  EVIDENCE: pending

## Runner commands

```sh
gh workflow run verify.yml -R valentinyeo/wazig --ref ceo/IGSH-827-red -f feature=sidebar-surface
gh workflow run verify.yml -R valentinyeo/wazig --ref ceo/IGSH-827 -f feature=sidebar-surface
```

Both runs retain the real historical-build baseline under baseline/ and measured values in sidebar-pixels.json. The entire chat must match with zero channel tolerance, not just its mean background. No workflow was dispatched in this helper session.

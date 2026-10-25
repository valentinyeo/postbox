# Gates: IGSH-823 buffered archive colour correction

OWNS: GATES.md, src/main.zig, src/theme.zig, tools/test_show_archived.py, tools/verify-wazig/check-archive-presentation.py, tools/verify-wazig/archive-presentation.ps1, .claude/skills/verify-wazig/features/show-archived.md

Scope: Replace commit B's archive overlay with theme colour mixing, preserve full-strength interactions and all list/theme coverage, update evidence oracles, run only the two authorized light tests, and amend B without touching red or pushing.

Authorization: Only `python3 tools/test_repaint.py` and `python3 tools/test_show_archived.py` may run as local checks. No gate checker, linter, Zig, Wine, build or full preflight will run. Gates below record direct test-output and source/history review rather than claiming checker-generated evidence. Windows screenshot execution remains a runner handoff from the earlier ledger, outside this correction's authorized scope; no app pixel measurements are claimed locally.

- [x] G1: Shared drawChat uses theme-derived text and muted colour mixing in its existing paint_buffer, with no extra DC, bitmap or AlphaBlend; hover, selection and bulk selection retain their original full-strength colours.
  EVIDENCE: Reviewed src/main.zig:13682 drawChat and src/theme.zig:101-113. RGB channel = floor((foreground * 180 + surface_container_low * 75) / 255). row_text, row_muted and row_primary mix only when archived and not selected, bulk-selected or hovered; draft prefix and avatar initial also choose mixed colours under that guard. Full-strength branches and selection fills are unchanged. The overlay is removed; source negative controls reject all three forbidden GDI calls and disabled/missing dimming or interaction exclusions.

- [x] G2: Authorized repaint-test output proves the buffered painting contract passes.
  EVIDENCE: Direct python3 tools/test_repaint.py exited 0; final lines: Ran 6 tests in 0.035s; OK. Existing dirty-buffer guards, including drawChat's no-compatible-bitmap assertion, pass unchanged.

- [x] G3: Authorized archive-test output proves colour-mix evidence accepts both polarities across sidebar, inbox and search and rejects undimmed rows, still-dim interactions and the returning footer.
  EVIDENCE: Direct python3 tools/test_show_archived.py exited 0; final lines: Ran 13 tests in 43.184s; OK (skipped=1). Existing optional shortcut-history control skips because HEAD~1 already contains Alt+A. Positive synthetic scenes cover both polarities and all three lists/modes. Direct capture=True negative controls prove rejection before stale saved-metric comparison for undimmed and still-dim hover/selection pixels; wrong-colour mix and model/weight mutations also fail. Existing UIA footer, drawn-label and active-click mutations remain rejected. These are synthetic oracle checks, not Windows app screenshot measurements.

- [x] G4: Evidence capture, pixel oracle, source expectations and feature documentation consistently describe colour mixing rather than a row-surface alpha model; existing palette, identities, archive writes and footer contracts remain intact.
  EVIDENCE: archive-presentation.ps1 records theme-foreground-mix and the source theme weight. check-archive-presentation.py independently derives expected RGB text from measured live text/background, bounds channel error by 8, requires unchanged background and reduced contrast for dim rows, and requires original text/readable contrast on hover/selection. Metrics retain expected_dim_text, foreground_weight, colour_mix_error and contrast_excess_ratio instead of dim_ratio. Feature documentation matches the formula. Reviewed full diff: no archive filtering/write, palette, footer-removal or view-path changes. Local archive suite's complete evidence and negative controls pass; comment scan included in that authorized suite passes.

- [x] G5: Green remains exactly evidence A plus amended B, red remains f31c4146a5401750415079e7be4642f61d4a907a, and no third commit, push or PR is created.
  EVIDENCE: Post-code-amend audit: git log -3 shows amended B, parent evidence A c82479c0d30ba17b747b04576e87f89f52f236fe, and base 4a1b5d00d4bbc4a317061ebd741232740575f2ec; git rev-list --count origin/main..HEAD prints 2; git rev-parse ceo/IGSH-823-red prints unchanged f31c4146a5401750415079e7be4642f61d4a907a; git status --short is empty. Only the seven correction files were staged. This evidence-only ledger update is also folded into B using --amend --no-edit, followed by the same final history/red/clean audit. No push, PR or runner action was performed.

Final ledger: 5 met, 0 unmet, 0 abandoned within the authorized correction scope. Windows app execution remains explicitly unperformed and handed off, not silently certified.

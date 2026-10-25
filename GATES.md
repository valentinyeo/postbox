# Gates: IGSH-823 archive presentation

OWNS: GATES.md, src/**, build.zig, tools/verify-wazig/**, tools/test_show_archived.py, tools/test_theme_runtime.py, .github/workflows/verify.yml, .claude/skills/verify-wazig/features/show-archived.md

Scope: Remove the sidebar archive toggle, retain palette state and drawing-only semantics, dim archived rows using theme colours, and deliver deterministic Windows evidence in a separate red commit.

- [x] G1: Evidence observes the missing footer label and inert old click point, palette state and toggling, and unchanged archive identities in the isolated fixture.
  EVIDENCE: Source review: archive-presentation.ps1 drives real archive query/Enter and the old footer point; check-archive-presentation.py independently rejects label pixels/UIA, switch changes and archived identity changes. tools/test_show_archived.py adds old-footer, drawn-label and active-click negative controls; execution is GitHub-only.

- [x] G2: Evidence measures light and dark archived/live text-background contrast and dim ratio, with full-strength hovered and selected archived rows across sidebar, inbox and search.
  EVIDENCE: Source review: nine screenshot scenes per palette measure text/background contrast, archived/live contrast-excess ratio, and full-strength text colour; verify-archive-light.ps1 repeats the production renderer with only inverted AMOLED tokens, and --both requires dark and light evidence. Negative pixel mutations cover dim/hover/selected in all three lists. These are authored assertions, not claimed runtime measurements.

- [ ] G3: App has no footer drawing, layout reservation or hit target; shared row rendering uses theme-derived dimming except for hover or selection; archive writes are unchanged.
  EVIDENCE: pending

- [ ] G4: Local branches contain origin/main plus evidence A (red), and origin/main plus A plus app B (green), with no push or PR and no local builds or tests.
  EVIDENCE: pending

- [ ] G5: GitHub Windows red and green runs prove failure and success, with measured screenshot contrast numbers and visual review.
  EVIDENCE: pending

ABANDON: G5 Local-only authorization forbids pushing these new commits or opening a PR, so GitHub cannot run their contents in this session. Runner must push both branches, dispatch verify.yml with feature=show-archived, confirm red fails for the footer and green passes both palette builds, then inspect screenshots and report .contrast.json measurements. No measured app contrast numbers are available locally.

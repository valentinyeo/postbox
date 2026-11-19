# Sidebar surface

## Sub-features

- Graphite sidebar, chat background and divider means, measured from a full-desktop PNG.
- Unselected list name ink measured against the sidebar: 242 within one channel unit, contrast at least 4.5:1. Secondary-label ink and the 85%-of-baseline rule belong to the synthetic control only.
- A divider column of 46 at the sidebar edge. The one-pixel-wide and shadow-band checks belong to the synthetic control only.
- The fixture paragraph bubble is at most px(660) wide and lighter at the top than at the bottom. The zero-tolerance chat comparison with the pre-change build belongs to the synthetic control only.

## How to get to it (user POV)

Open Messages. Use Ctrl+K → Theme: Graphite. The left chat list remains distinct from the chat area without changing its layout or settings.

## Driving it with PowerShell UI Automation

Dispatch `feature=sidebar-surface`. The workflow builds the parent of the commit that introduced `journey-sidebar-surface.ps1` in a separate detached checkout. This selects the same pre-app-change baseline on the proof-only red branch and the app branch, including after rebasing. It builds both binaries with the same Zig, target, release mode and pinned version. The baseline runs the same current journey scripts against its own isolated fixture; no assertion is disabled in either build. Candidate evidence validation requires both captures and both cleanups.

The existing `--verify-text-comparison` fixture supplies a real deterministic cached paragraph. Each build is maximized, passes doctor, applies Theme: Graphite through the real palette, focuses Search chats to keep the blinking caret out of the chat, then records `sidebar-amoled.png` (the file keeps the internal theme name), UIA/state/message snapshots and `sidebar-layout.json`. The layout uses the actual canvas edge, list UIA bounds, client origin and DPI. No app control command changes state.

`check-sidebar-surface.py` decodes the PNG bytes with the existing standard-library PNG reader. It measures the mean sidebar in the blank list region below both rows, the chat background in its empty left margin, the divider column and the name text in the unselected Beta row. The live check asserts exact Graphite values, each within one channel unit: sidebar 24, chat 16, divider 46. The sidebar is exactly px(300) wide, the paragraph bubble at most px(660) wide, and the name ink is 242 with contrast at least 4.5:1. The bubble is lighter at the top (34 to 38) than at the bottom (30 to 34). The ratio, luminance and divider thresholds of the synthetic control (1.08–1.6:1 surface contrast, 0.005–0.04 divider delta, 99.5% uniform edge columns, zero-tolerance chat comparison) live in `measure_pair` and `validate` and are exercised only by `test-sidebar-surface.py`.

`sidebar-builds.json` binds candidate and baseline commits, binary hashes, assertion parent and fixture hash to both sessions. `baseline/` retains all historical-build screenshots and isolation evidence. `sidebar-pixels.json` records the measured values only after the pixel assertions pass; on failure the validator writes `journey-check-failed.txt` and no pixel file. The direct Python control file accepts synthetic dark, green and inverted-light captures and rejects old-main pixels, missing/wide/interrupted/heavy dividers, shadow bands, black sidebar, unreadable/changed text, blank screenshots, changed layout and a single changed chat channel.

## Gotchas

- The app has one theme, Graphite, which is dark. Do not add a light theme. The synthetic green and light-control captures in `test-sidebar-surface.py` exercise the control checker only, not the app.
- Synthetic controls are not real app screenshot evidence. Windows red/green runs and visual inspection of both theme pairs remain mandatory; report no runtime pixel values until artifacts exist.
- The red branch must fail the real screenshot assertions because the AMOLED sidebar is black and the separator is absent. The baseline capture itself intentionally only captures; the final surviving-evidence validator decides the result for both branches.
- Keep later app commits out of the journey script. If the journey itself changes after the proof commit, the baseline-selection rule must be updated rather than silently accepting a post-change baseline.

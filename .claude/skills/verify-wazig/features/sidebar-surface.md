# Sidebar surface

## Sub-features

- AMOLED and Green sidebar/background means and their WCAG relative-luminance contrast, measured from full-desktop PNGs.
- Unselected list name and secondary-label ink measured against the new sidebar, preserving ink RGB within one channel unit, contrast at least 4.5:1 and at least 85% of baseline.
- A continuous faint divider exactly one physical pixel wide, including the immediately adjacent columns to reject shadow bands.
- The entire chat rectangle, including the fixture paragraph bubble and composer, pixel-identical to the pre-change build: zero channel tolerance and zero changed pixels.

## How to get to it (user POV)

Open Messages. Use Ctrl+K → Theme: AMOLED black or Theme: Green. The left chat list remains distinct from the chat area without changing its layout or settings.

## Driving it with PowerShell UI Automation

Dispatch `feature=sidebar-surface`. The workflow builds the parent of the commit that introduced `journey-sidebar-surface.ps1` in a separate detached checkout. This selects the same pre-app-change baseline on the proof-only red branch and the app branch, including after rebasing. It builds both binaries with the same Zig, target, release mode and pinned version. The baseline runs the same current journey scripts against its own isolated fixture; no assertion is disabled in either build. Candidate evidence validation requires both captures and both cleanups.

The existing `--verify-text-comparison` fixture supplies a real deterministic cached paragraph. Each build is maximized, passes doctor, switches themes through the real palette, focuses Search chats to keep the blinking caret out of the chat, then records `sidebar-amoled.png`, `sidebar-green.png`, UIA/state/message snapshots and `sidebar-layout.json`. The layout uses the actual canvas edge, list UIA bounds, client origin and DPI. No app control command changes state.

`check-sidebar-surface.py` decodes the PNG bytes with the existing standard-library PNG reader. It measures the mean sidebar in the blank list region below both rows and the chat background in its empty left margin. Surface contrast must be 1.08–1.6:1, with a dark sidebar luminance lift above 0.004 and an average RGB separation of 8–40. It measures name and kind text in the unselected Beta row. Divider/sidebar luminance difference must be 0.005–0.04 and divider/chat difference 0.009–0.06. At least 99.5% of pixels in each of the edge and immediately adjacent columns must match their respective measured surface within one channel unit. The full chat comparison has no such tolerance: every channel must match exactly.

`sidebar-builds.json` binds candidate and baseline commits, binary hashes, assertion parent and fixture hash to both sessions. `baseline/` retains all historical-build screenshots and isolation evidence. `sidebar-pixels.json` records all measured values before the pixel assertions, including on the expected red failure. The direct Python control file accepts synthetic dark, green and inverted-light captures and rejects old-main pixels, missing/wide/interrupted/heavy dividers, shadow bands, black sidebar, unreadable/changed text, blank screenshots, changed layout and a single changed chat channel.

## Gotchas

- The app has only AMOLED and Green, both dark. Do not add a light theme. The validator's synthetic light control proves the inverted treatment; its divider/chat upper luminance bound is 0.22 for the higher-luminance scale.
- Synthetic controls are not real app screenshot evidence. Windows red/green runs and visual inspection of both theme pairs remain mandatory; report no runtime pixel values until artifacts exist.
- The red branch must fail the real screenshot assertions because the AMOLED sidebar is black and the separator is absent. The baseline capture itself intentionally only captures; the final surviving-evidence validator decides the result for both branches.
- Keep later app commits out of the journey script. If the journey itself changes after the proof commit, the baseline-selection rule must be updated rather than silently accepting a post-change baseline.

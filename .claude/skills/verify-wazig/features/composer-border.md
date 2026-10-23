# Composer border

## Sub-features

- Equal top, bottom, left and right border thickness at one-third width on the top/bottom edges and the midpoint of the left/right edges.
- Screenshot evidence at exact saved app text scales 100%, 125% and 150%.
- A synthetic pixel control accepts an even border and rejects a one-row bottom border.

## How to get to it (user POV)

Open a chat and focus the bottom message entry box with Ctrl+K → Compose message. Text size commands live in the same palette; Ctrl++ and Ctrl+- change the saved scale in ten-point steps, and Ctrl+0 restores the existing 82% default.

## Driving it with PowerShell UI Automation

Dispatch `feature=composer-border`; matching pull requests also run it. The normal isolated offline fixture launch and doctor run first. `Invoke-ComposerBorderJourney` closes the owned fixture with Alt+F4, writes exact `FontScale` values 100, 125 and 150 only into its GUID-isolated registry subtree and relaunches that same fixture with the existing guarded restart opt-in. Each restart updates the recorded PID/start time, passes doctor and verifies the actual UIA TextPattern font size with synthetic text before clearing it.

UI Automation finds edit `1032` and checks its screen bounds against the read-only composer layout. The box comes from `status.composer.box`, converted from client to screenshot coordinates using ClientToScreen and VirtualScreen. Capture `composer-border-<scale>.png`, UIA/state snapshots and `composer-border-<scale>-box.png`. Scan top/bottom edges at `left + floor((right - left) / 3)` and left/right edges at their vertical midpoint, including pixels outside the exclusive box bounds. For each scan, sample adjacent outside/inside backgrounds six pixels away; count pixels more than eight channel levels brighter than both backgrounds. This separates the border from both the dark window and the lighter field fill.

Write all four widths, probe positions, edit/box bounds, measured window DPI, font points and scale method to `composer-border.json` before asserting. All three cases are captured before comparing: each border must exist, be at most four pixels wide, and satisfy top = bottom = left = right. Failure contains `border`. Retain the normal side-effect and cleanup proof too. Inspect the full screenshots and box crops, not just the exit code.

## Gotchas

- These percentages are saved app text scale, not Windows display scale. Hosted runners provide no reliable supported per-monitor DPI switch without desktop/session reconfiguration. `px()` follows window DPI only; app zoom changes fonts/content height, not stroke width or layout margins. GetDpiForWindow records the unchanged monitor DPI. This journey does not claim 125%/150% monitor-DPI coverage.
- Registry seeding is required because ten-point keyboard steps from 82% cannot reach these exact values. Production preferences and the default font/scale are never changed.
- The baseline is AMOLED with no messages. Top/bottom probes sit at one-third box width to avoid the small grey bar above the centre; left/right probes stay at mid-height, away from glyphs and corner arcs; a blank or missing border fails rather than passing as four zeros.
- The verification-only commit is expected to fail on the old composer paint: its centred stroke uses an exclusive bottom minus one, and the child edit clips the inner bottom row. Windows execution is required to prove the actual red/green pixels; source review alone is not a runtime pass.

# Media fit

## Sub-features

- Opening a synthetic WhatsApp group automatically downloads landscape and portrait PNG attachments through the hub media route.
- Every media hit rectangle stays inside its bubble content padding, never wider than the bubble or taller than the scaled 250 px design cap.
- Matching screenshot colours stay inside the corresponding media and bubble rectangles.
- Own single-line text reaching the time box has its timestamp below the text pixels, not painted over the last word.
- Wide and narrow windows repeat all assertions; narrow bubble content must be narrower than the landscape decoded at the wide window, so raw-size painting cannot pass. An oversize MP4 is included when ffmpeg is already installed.

## How to get to it (user POV)

Open Ctrl+K, type Verification Media and press Enter. Inspect the group attachments and own long line, then restore and resize the window to a narrow canvas. Dispatch `feature=media-fit`.

## Driving it with PowerShell UI Automation

PowerShell UI Automation runs `Invoke-MediaFitJourney` with the registry fake-hub mode `media-fit`. The fixture generates 1600x1000 landscape and 700x1400 portrait PNG bytes with Python struct and zlib, without external dependencies. If ffmpeg is on PATH, it generates a 1512x1100 MP4 without downloading any executable. The app downloads these attachments normally through `/v1/wazig/media/`.

The journey opens the group through the palette, waits for local media and captures the maximized window. Native ShowWindow restore and SetWindowPos size the owned window to a measured 320 px canvas without clicking the canvas. Each bounded correction uses the measured outer-minus-canvas width, so sidebar clamps and window borders do not depend on keyboard resize increments or cursor position. The 300–340 px assertion remains mandatory. Real mouse-wheel input brings each attachment fully into view. Eight rendered M glyphs calibrate the native text advance; a fixture-only text update and palette Refresh produce one near-full own text line at each window width.

`media-fit-resize.json` retains the target, measured canvas width and each requested correction; the evidence validator checks the correction arithmetic and narrow screenshot widths. `media-fit-checks.json` retains each named bubble/media rectangle, DPI, canvas origin and pixel measurements; `<wide|narrow>-<message>.messages.json`, screenshots and UIA/state snapshots retain independent evidence. C# assertions check containment, the scaled cap, fixture-colour pixels and timestamp/text vertical separation. `check-media-fit-evidence.py` independently decodes the screenshots with the existing stdlib PNG reader and repeats the geometry and pixel assertions, checks authenticated hub download records and requires narrower bubbles. `failure.txt` starts `media-fit:` on a failed journey.

## Gotchas

Only GitHub-hosted Windows may launch this journey. The red journey commit must fail before the layout fix; both exact-commit runs and visual screenshot inspection remain required evidence. Optional video coverage is recorded in `media-fit-fixture.json`; missing ffmpeg is not video coverage. No real provider account, media content or speech service is used. The journey does not change the saved font scale or the viewer/player opened on click.

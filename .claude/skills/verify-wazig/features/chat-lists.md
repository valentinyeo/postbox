# Chat list indentation and regular body text

## Sub-features

- Ordinary message bodies use IBM Plex Sans Regular (400).
- Six long bullets support `• `, `- `, `* ` and numbered markers, including multi-digit numbers.
- Two nested levels retain their own marker columns and hanging text edges.
- Measurement and painting agree at baseline and larger saved text sizes.

## How to get to it (user POV)

Open a Slack chat with a long list. Resize the window or choose Ctrl+K → `Make text larger`. Wrapped lines must start under the first line's text, not under its marker or at the bubble edge. Quotes, code and sidebar styles are outside this change.

## Driving it with PowerShell UI Automation

Dispatch `feature=chat-lists`; the registry also enables it for matching PRs in `verify.yml`. The isolated hub serves one synthetic Slack message with six long bullets and two nested list levels. Each item repeats the same word so its first glyph has the same ink bearing on every line.

The journey opens Slack with Alt+1 and Ctrl+Tab, then captures baseline and larger-size screenshots. Fixture-only control snapshots expose the actual body HFONT weight and painted word rectangles with original UTF-16 ranges. Require weight 400, all 168 marker/word spans, and a bubble fully inside the canvas. Every continuation rectangle starts at that item's first text x and to the right of its marker x. Nested text x values strictly increase.

For each item, scan the screenshot's bright foreground pixels inside the first word rectangle and the first word rectangle of every continuation. Require their leftmost ink x positions to differ by at most one pixel. Retain `baseline.png`, `larger.png`, their message snapshots, and `list-alignment.json`. The journey resets text size and the standard cleanup checks isolated state and no sends, archives or reactions.

## Gotchas

- Pixel comparison uses repeated identical words, not marker ink bearings. It measures real foreground ink, not only layout coordinates.
- The Zig unit tests use deterministic font metrics; this Windows journey exercises production DirectWrite/GDI metrics and painting.
- The workflow must run on Windows; do not build or launch the app on the shared VPS.
- Native text comparison separately pairs the Regular body font with Chrome. No screenshot equality with Slack is claimed.

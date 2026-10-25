# Native text comparison

Compare the guarded native paragraph with installed Chrome using identical IBM Plex text and metrics.

## Sub-features

- Exact fixture text and bundled font hashes, sizes, weights and line heights.
- Paired native/Chrome full-window PNGs and 1x/3x paragraph crops.

## How to get to it (user POV)

Text comparison is a verification fixture, not a product command or alternate renderer. Normal chats render with DirectWrite and the private font files beside Messages.exe.

## Driving it with PowerShell UI Automation

Dispatch `feature=text-comparison`. The helper adds `--verify-text-comparison`, loads the exact `src/verify_text.json` paragraph through the guarded production parser and waits for painted metrics to match the maximized UIA canvas.

`compare-text.ps1` captures the native window, then `chrome-text.cjs` opens installed headed Chrome at device scale 1. Require DirectWrite at 96 DPI, body weight 400, heading weight 600, identical text/sizes/line heights and font hashes.

Retain `text-metrics.json`, `native-capture.json`, `chrome.json`, `chrome.html`, bundled fonts/license, `wazig.png`, `chrome.png`, `text-comparison.png` and `*-paragraph{,-3x}.png`. `check-text-comparison.cjs` rechecks source/fixture contracts, exact font hashes, PNG dimensions/crop scaling, isolated side effects and cleanup.

- **Chat lists:** dispatch `feature=chat-lists` for six long bullets and two nested levels through the real Slack bubble renderer. At baseline and larger text size, the journey checks Regular body weight, measured marker/text columns, full bubble height, and screenshot foreground left edges within one pixel between the first text line and each continuation. See `features/chat-lists.md`.

## Gotchas

- Inspect the screenshots; the validator does not assert Chrome/DirectWrite pixel equality, every glyph or every DPI.
- The workflow pins `0.0.526`, not the current product release, and the screenshot driver is runner-only infrastructure.
- Do not alter the default font, default scale or production preferences for screenshots.

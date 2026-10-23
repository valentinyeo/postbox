# Chat passage copy

## Sub-features

Cross-message word selection, partial endpoints, sender/time stamps, You for outgoing messages, intervening date lines and held-edge auto-scroll on WhatsApp and Slack.

## How to get to it (user POV)

Drag from text in one message into another. Hold at the top or bottom of the message canvas to extend through offscreen messages. Ctrl+C or the existing right-click Copy selection copies plain text. Single-message selection remains unstamped.

## Driving it with PowerShell UI Automation

Run `feature=passage-copy` on GitHub-hosted Windows. The unified fake hub seeds seven synthetic messages per provider, alternating senders and one outgoing message, with a day change between messages three and four. Message six has forty lines so message seven starts below the fold when viewing the first five.

Use Ctrl+F to open each chat, real PageUp to reach the start, UIA canvas 1024 bounds, read-only bubble rectangles and screenshot body pixels to locate the middle word of messages two and five. Real SendInput mouse down, move and up followed by Send-Keys Ctrl+C must yield the exact fixture-derived stamped passage, including both partial endpoints and the intervening date line. Current single-message-only selection must fail that clipboard assertion.

Repeat from message two and hold the pointer beyond the canvas bottom until message seven appears. Require changed bubble positions and exact clipboard text through message seven. Retain passage-fixture.json, clipboard.json, provider before/after/edge-after screenshots and state/UIA companions, actions.log, result.json, side-effects.json and cleanup.txt. check-evidence.py independently reconstructs the clipboard expectations. Inspect screenshots after downloading the artifact.

## Gotchas

The first commit deliberately contains no app fix and must fail the partial passage assertion on GitHub. No local app or suite runs are permitted. Pixel targeting requires a fully visible single-line endpoint; fixture setup failures do not count as the expected red result. This proves the synthetic hub providers, not live provider delivery. Top-edge, reverse selection, right-click copying and single-message behavior also require unit/source review; this journey exercises bottom-edge scrolling and Ctrl+C.

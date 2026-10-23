# Link previews

## Sub-features

- Hub Slack mrkdwn displays clean clickable labels and decoded query ampersands.
- Direct PNG, JPG, JPEG, GIF and WebP links use the existing inline image and large viewer.
- HTTP(S) pages with Open Graph images show image, title, site and a short description; pages without an image remain links.
- URL-scoped memory and disk caches avoid repeated network fetches across repaints and chats on all four providers.

## How to get to it (user POV)

- Open any account chat containing a shared image or page URL.
- Images download automatically; click the inline image to open the large viewer, then Escape to return.
- Click a clean link or page card to open its original URL.

## Driving it with PowerShell UI Automation

- Run feature=link-previews on GitHub Actions only. The fake-hub.py --link-previews mode serves synthetic Slack, WhatsApp, Telegram and Signal chats and loopback PNG/HTML responses.
- Search for each chat through Ctrl+F. Require four real history rows, no raw markup or ampersand entities, linked image media bounds, preview image/title/site and a clean image-free link.
- Save per-provider screenshots, UIA trees, read-only messages and state. Measure amber inline-image and cobalt card-image pixels from the actual screenshots within their reported bounds.
- Click the Slack inline image with foreground-checked SendInput and require the existing image viewer window; retain viewer.png and Escape back.
- Reopen the Slack chat and require unchanged page/image request counts. Retain bridge-requests.jsonl and final disk caches; check-link-previews-evidence.py validates surviving proof after cleanup.

## Gotchas

- The fixture uses the existing isolated Actions fake-hub origin. Any loopback fetch allowance must be restricted to this configured verification origin, never ordinary app sessions.
- The journey-only commit must fail on unconverted hub Slack text before accepting renderer observations.
- No production account or external site is used. Screenshots must be inspected in addition to the read-only validator.
- Source: src/main.zig renders and fetches cards; src/unfurl.zig classifies links and reads Open Graph metadata; src/slack.zig converts mrkdwn.

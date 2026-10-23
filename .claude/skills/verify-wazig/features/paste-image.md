# Clipboard images

## Sub-features

- `screenshot-paste`: paste full-screen 1920x1032 and 3840x2160 RGBA screenshots with both CF_DIBV5 and registered PNG clipboard streams.
- `image-formats`: preserve alpha, colour channels and row orientation for V5 BI_BITFIELDS, top-down rows and PNG-only data; retain opaque 24-bit DIB, 32-bit BI_RGB and bitmap behavior.
- `account-send`: Enter sends the staged image through the selected WhatsApp, Slack, Signal or Telegram chat, not another account.

## How to get to it (user POV)

- Copy a screenshot or image to the clipboard.
- Select a chat, focus the message box, press Ctrl+V, then Enter. No caption is required.
- Escape discards a staged image; normal text clipboard behavior is unchanged.

## Driving it with PowerShell UI Automation

- Dispatch feature=paste-image on GitHub Actions, or use run.ps1 -Feature paste-image. Matching pull requests run the same journey.
- The unified fake hub exposes four synthetic chats, one per provider. paste-image.ps1 selects each through the palette and focuses Compose message.
- System.Windows.Forms.Clipboard receives a DataObject with a 124-byte BITMAPV5HEADER, 32-bit BI_BITFIELDS, explicit RGBA masks and a registered PNG stream for each screenshot size on each provider. Additional cases exercise V5-only top-down, PNG-only, bottom-up 24-bit DIB, top-down 32-bit BI_RGB and CF_BITMAP.
- The harness keyboard helper sends Ctrl+V and Enter. For each case require exactly one accepted multipart image upload, no pending sends, and acknowledged image history in the same chat.
- Decode the received PNG bytes with System.Drawing.Bitmap, compare width and height to the source, and sample opposite corners for alpha, channels and orientation. Both screenshot sizes must preserve half-transparent pixels; Windows synthesized legacy DIB fallback must not hide alpha loss.
- Keep paste-N-staged.png, paste-N-sent.png, state/UIA snapshots, paste-N.messages.json, bridge-requests.jsonl, paste-uploads/*.png, sizes.json and hub-proof.log. Failure writes failure.txt beginning paste-image: with the failed assertion.
- check-paste-image-evidence.py validates surviving upload hashes, PNG chunks and decompression, dimensions, decoded pixel samples, per-provider histories, exact send count, keyboard actions and cleanup isolation.

## Gotchas

- Commit A is deliberately red against the old clipboard implementation: V5/PNG are not selected, and any Windows-synthesized legacy DIB fallback reaches a PNG writer that requires unsupported 32bppBGR rather than native PNG 32bppBGRA. The decoder also discards alpha. PNG-only is independently unreachable there.
- Runtime proof, PowerShell parsing, Zig builds/tests and screenshot inspection belong to GitHub Windows. Local light checks do not prove a successful paste or send.
- Synthetic hub acceptance is not upstream provider delivery or authentication. One account per provider is covered; direct-provider transport and multiple same-provider account isolation retain their existing coverage.
- The image path retains source dimensions; screenshot evidence shows the preview, not an intentionally downscaled upload. No new paste size policy, retry delay or timeout is introduced.

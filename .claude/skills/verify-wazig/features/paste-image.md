# Clipboard images

## Sub-features

- `screenshot-paste`: paste full-screen 1920x1032 and 3840x2160 RGBA screenshots with both CF_DIBV5 and registered PNG clipboard streams.
- `image-formats`: preserve alpha, colour channels and row orientation for V5 BI_BITFIELDS, top-down rows and PNG-only data; retain opaque 24-bit DIB, 32-bit BI_RGB and bitmap behavior.
- `account-send`: Enter sends staged images through the selected WhatsApp, Slack, Signal or Telegram chat, not another account.
- `multiple-images`: paste one image, add another with the existing + picker, see separate previews, then Enter sends both in order with the caption on the first only. Each preview has its own remove x.

## How to get to it (user POV)

- Copy a screenshot or image to the clipboard.
- Select a chat, focus the message box, press Ctrl+V, then Enter. No caption is required.
- Paste more images, choose another through +, or drop files into the window to append attachments. Click a preview's x to remove only that image; Escape discards all staged images. Normal text clipboard behavior is unchanged.

## Driving it with PowerShell UI Automation

- Dispatch feature=paste-image on GitHub Actions, or use run.ps1 -Feature paste-image. Matching pull requests run the same journey.
- The unified fake hub exposes four synthetic chats, one per provider. paste-image.ps1 selects each through the palette and focuses Compose message.
- System.Windows.Forms.Clipboard receives a DataObject with a 124-byte BITMAPV5HEADER, 32-bit BI_BITFIELDS, explicit RGBA masks and a registered PNG stream for each screenshot size on each provider. Additional cases exercise V5-only top-down, PNG-only, bottom-up 24-bit DIB, top-down 32-bit BI_RGB and CF_BITMAP.
- The harness keyboard helper sends Ctrl+V and Enter. For each case require exactly one accepted multipart image upload, no pending sends, and acknowledged image history in the same chat.
- Decode the received PNG bytes with System.Drawing.Bitmap, compare width and height to the source, and sample opposite corners for alpha, channels and orientation. Both screenshot sizes must preserve half-transparent pixels; Windows synthesized legacy DIB fallback must not hide alpha loss.
- Keep paste-N-staged.png, paste-N-sent.png, state/UIA snapshots, paste-N.messages.json, bridge-requests.jsonl, paste-uploads/*.png, sizes.json and hub-proof.log. Failure writes failure.txt beginning paste-image: with the failed assertion.
- On WhatsApp and Slack, paste an opaque synthetic image with Ctrl+V, then use SendInput to click + and UI Automation plus keyboard to choose a distinct synthetic PNG in the isolated profile. Screenshot pixel assertions require both separate previews. Type a caption and Enter; require two ordered distinct uploads, text on the first only and independent client IDs. Repeat, click the first preview's x with SendInput and require only the second image.
- Keep whatsapp/ and slack/ multi-before.png, multi-staged.png, multi-sent.png, remove-staged.png, remove-one.png, remove-sent.png and state/UIA snapshots, plus multi-sent.json and remove.json. These assertions deliberately use screenshots and hub requests, not a new staging status field.
- check-paste-image-evidence.py validates surviving upload hashes, PNG chunks and decompression, dimensions, decoded pixel samples, per-provider histories, exact send count, two-preview measurements, ordered captions, remove-first identity, keyboard/mouse actions and cleanup isolation.

## Gotchas

- IGSH-688 commit A is deliberately red against single-attachment staging: the WhatsApp + control is disabled, and adding a picker image replaces the pasted image instead of preserving two previews and two ordered sends. Its journey and evidence assertions require both images, not just a successful exit.
- Runtime proof, PowerShell parsing, Zig builds/tests and screenshot inspection belong to GitHub Windows. Local light checks do not prove a successful paste or send.
- Synthetic hub acceptance is not upstream provider delivery or authentication. One account per provider is covered; direct-provider transport and multiple same-provider account isolation retain their existing coverage.
- The image path retains source dimensions; screenshot evidence shows the preview, not an intentionally downscaled upload. No new paste size policy, retry delay or timeout is introduced.

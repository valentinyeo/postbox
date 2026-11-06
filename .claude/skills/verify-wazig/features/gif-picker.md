# GIF picker

## Sub-features

- `gif-search`: Ctrl+K "Send a GIF" opens the emoji-style picker with trending GIFs, previews load as small tiles, typing a query and Enter searches, and Left, Right, Up, Down move the selection.
- `gif-stage`: Enter on a tile downloads the original and stages it as an attachment in the composer, like a pasted file. Enter in the composer sends it with the draft as its caption.
- `gif-keep`: Escape closes the picker, keeps the draft and any reply, and stages nothing. The chat is fixed when the picker opens.
- `gif-retry`: a failed search or failed download shows a short notice and Enter retries.
- `gif-key`: the GIPHY key lives only in the encrypted preferences. Without one the command shows "GIF search needs a GIPHY key" and opens nothing.

## How to get to it (user POV)

- Select a chat, optionally start a reply and type a caption, press Ctrl+K and run Send a GIF.
- Type to search, arrow to a tile, press Enter, then Enter again in the message box to send.

## Driving it with PowerShell UI Automation

- Dispatch feature=gif-picker on GitHub Actions, or use run.ps1 -Feature gif-picker. Matching pull requests run the same journey.
- The unified fake hub (GifPickerHandler in fake-hub.py) serves the paste chats plus a GIPHY look-alike on the same loopback port. run.ps1 passes the port to the app as POSTBOX_GIPHY_PORT, which the app honours only in verification fixture mode. The real GIPHY service is never contacted.
- The journey generates a random fixture secret, writes it as plain text into the fixture's isolated preferences, and the app migrates it to encrypted storage on first use. The journey fails if the value is plain in the registry or appears in any evidence file. The hub logs only a SHA-256 of what it received and strips the query credential from logged paths.
- Sequence: missing-key notice, store the secret, start a reply on GIF-ORIGINAL, type a draft, open the picker (trending), Escape keeps draft and reply, reopen, search boom (first call fails, Enter retries), search cats, arrow to the second tile, Enter (first original download fails, Enter retries and stages), Enter in the composer sends once.
- Require one accepted multipart upload with the draft as text, reply_to GIF-ORIGINAL, a .gif name, bytes equal to the served original, decoded 64x48 with the picked GIF's left and right pixels, and a sent history row quoting the original.
- Keep no-key, trending, escaped, search-failed, cats, download-failed, staged and sent screenshots with state and UIA snapshots, bridge-requests.jsonl, paste-uploads/*.gif, sent.messages.json, gif-picker.json and hub-proof.log. Failure writes failure.txt beginning gif-picker: with the failed assertion.
- check-gif-picker-evidence.py validates credential hashes, retry sequences, upload bytes, dimensions, send body, sent history and cleanup isolation.

## Gotchas

- This journey proves the picker against a look-alike service. The real GIPHY service stays unverified until a real key exists.
- A failed GIF send rides the existing outbox retry and is not exercised for GIFs here. Switching chats while a download runs is covered by unit tests in src/giphy_catalogue.zig, not by this journey.
- Keyboard focus decides whether Escape, Enter and arrows reach the picker; the journey fails with the state it saw rather than retrying keys blindly.

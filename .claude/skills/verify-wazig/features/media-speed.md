# Media speed

## Sub-features

- `media-speed-ten-files`: opening a WhatsApp chat downloads six images and four voice notes, newest first, and all ten show within 15 seconds.
- `media-speed-three-at-once`: the hub answers each file slowly (0.8 s) after a pending reply, so a one-at-a-time app cannot finish in time.
- `media-speed-server-error`: one image first fails with a server error and shows after the short 5 second wait.
- `media-speed-gone`: one file the server calls gone is asked for once, stops showing as a spinning download within 15 seconds and shows its not-available note instead of a download.

- `playback-speed-commands`: Ctrl+K sets playback speed to 1.5x, 2x and 1x, checked through the audio status.

## How to get to it (user POV)

Open a WhatsApp chat that has just received many images and voice notes. Each one shows its picture or player without a click. Dispatch `feature=media-speed` for the synthetic chat.

## Driving it with PowerShell UI Automation

PowerShell UI Automation runs `Invoke-MediaSpeedJourney` with the unified fake hub in `media-speed` mode: `Verification Speed` holds ten downloadable files and one gone file. Ctrl+K opens the chat with the palette. The journey polls the read-only `wazigctl messages` list and records the second each file first shows as local, then saves `media-speed.json`, `media-speed.messages.json`, `media-speed.requests.json` and `media-speed-done.png`. The fake hub writes `media-speed-server.jsonl`, one line per media request with its status and time. The validator needs all ten files within 15 seconds on the client and the server clock, the 502 then 200 order for the failing image, and exactly one 410 request for the gone file.

The journey also runs each playback speed command from Ctrl+K and saves the resulting values in `playback-speeds.json`.

## Gotchas

The files are synthetic bytes, not real photos or audio. The 15 second limit is measured from the client timer that starts when the journey opens the chat, and the validator also reads the server clock that starts at the first media request, so a slow history reply cannot hide a slow download. Look at `media-speed-done.png`, not only the exit status.

A 410 is final on its first answer. `b657ed8` (`SOFT-3158`) re-requested the link once after `gone_refresh_ms`, which left the row spinning for 28.83 s on the default-branch nightly, so `SOFT-3165` dropped that refresh: the first 410 marks the file unavailable, writes its hash to `gone-media.txt` once and repaints through the twenty second note throttle (`noteRepaintDue` in `src/media_drain.zig`, called by `flushMediaNote` in `src/main.zig`). The single-request and 15 second assertions hold that behaviour.

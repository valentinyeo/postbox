# Voice

## Sub-features

- `voice-download`: opening a WhatsApp chat downloads five voice notes automatically into the hub media cache.
- `voice-transcript-cache`: cached transcripts beside the downloaded files show in their bubbles, cut to the first part with Show more.
- `voice-scroll`: mouse-wheel scrolling up and down keeps every bubble, player and time stamp inside its own bubble.
- `voice-expand`: Show more expands one long transcript; scrolling again keeps the layout clean.
- `voice-bar`: with a note paused in the voice chat, the row keeps its last message; in the other chat the bar offers a 1x, 1.5x and 2x speed control, pause and resume, and the row still keeps its last message.
- `voice-partial-repaint`: repainting only the voice bubbles, as the playback timer does, draws exactly what a full repaint draws.
- `voice-copy-transcript`: the palette command Copy transcript copies the selected voice note words.

- `voice-commands`: Ctrl+Shift+M starts fixture recording; Ctrl+P pauses the selected playing voice note. The palette toggles the selected transcript and restores it.
- `transcript-selection`: Copy all transcripts copies the marked raw transcripts in chronological order; Escape clears the marks.

## How to get to it (user POV)

Open a WhatsApp chat with several voice messages. Scroll with the mouse wheel, click Show more under a long transcript, scroll again and play a voice note. Dispatch `feature=voice` for the synthetic chat.

## Driving it with PowerShell UI Automation

PowerShell UI Automation runs `Invoke-VoiceJourney` with the unified `Start-FakeBridge -Voice` fixture: `Verification Voice` holds five incoming `audio/ogg` voice notes served by the fake hub, `Verification Beta` one text message. Wait for the five automatic media downloads, reopen the chat with Ctrl+Tab and Ctrl+Shift+Tab, write one long cached transcript (`<voice file>.txt`) beside each downloaded `.ogg` and reopen again until all five show. Then probe, scroll up four notches and down two with real SendInput wheel input over the canvas, click Show more with a real SendInput click, and scroll up six and down three, probing after every step.

The journey starts and cancels fixture recording with Ctrl+Shift+M and Escape, selects a voice note with Alt+J, starts it with a click and pauses it with Ctrl+P. `voice-recording.json` and `playback.json` record the results.

Each probe reads the read-only `wazigctl messages` geometry (bubble, player and Show more rectangles), asks the canvas for a full repaint and saves `<step>-full.png`, then invalidates only the visible voice bubble rectangles, exactly what the playback timer does each tick, and saves `<step>.png`. The canvas pixels of both screenshots must match (at most 16 differing pixels). Both screenshots must have no drawn pixels outside every bubble, no overlapping bubbles, a filled bubble, a player circle with its play glyph inside its own bubble and visible time stamp ink. Results go to `voice-checks.json`; failures read `voice: <step>: <problem>`. `transcripts.json`, every screenshot pair, UIA trees and state snapshots are retained.

`Invoke-VoiceBar` then switches to Verification Beta, reads the bar rectangle and speed and pause zones from `wazigctl status`, and clicks them with real SendInput: resume, speed 1.5x, 2x, 1x and pause. `voice-bar.json` plus `voice-bar-paused.png` and `voice-bar-speed.png` are retained.

## Gotchas

Playback uses synthetic playable voice files. Recording uses a synthetic PCM fixture instead of a microphone. Transcription stays off (no speech key), so the transcripts come only from the local cache. Look at the screenshot pairs, not only the exit status.

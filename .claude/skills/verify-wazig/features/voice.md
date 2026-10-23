# Voice

## Sub-features

- `voice-download`: opening a WhatsApp chat downloads five voice notes automatically into the hub media cache.
- `voice-transcript-cache`: cached transcripts beside the downloaded files show in their bubbles, cut to the first part with Show more.
- `voice-scroll`: mouse-wheel scrolling up and down keeps every bubble, player and time stamp inside its own bubble.
- `voice-expand`: Show more expands one long transcript; scrolling again keeps the layout clean.
- `voice-partial-repaint`: repainting only the voice bubbles, as the playback timer does, draws exactly what a full repaint draws.

## How to get to it (user POV)

Open a WhatsApp chat with several voice messages. Scroll with the mouse wheel, click Show more under a long transcript, scroll again and play a voice note. Dispatch `feature=voice` for the synthetic chat.

## Driving it with PowerShell UI Automation

PowerShell UI Automation runs `Invoke-VoiceJourney` with the unified `Start-FakeBridge -Voice` fixture: `Verification Voice` holds five incoming `audio/ogg` voice notes served by the fake hub, `Verification Beta` one text message. Wait for the five automatic media downloads, reopen the chat with Ctrl+Tab and Ctrl+Shift+Tab, write one long cached transcript (`<voice file>.txt`) beside each downloaded `.ogg` and reopen again until all five show. Then probe, scroll up four notches and down two with real SendInput wheel input over the canvas, click Show more with a real SendInput click, and scroll up six and down three, probing after every step.

Each probe reads the read-only `wazigctl messages` geometry (bubble, player and Show more rectangles), asks the canvas for a full repaint and saves `<step>-full.png`, then invalidates only the visible voice bubble rectangles, exactly what the playback timer does each tick, and saves `<step>.png`. The canvas pixels of both screenshots must match (at most 16 differing pixels). Both screenshots must have no drawn pixels outside every bubble, no overlapping bubbles, a filled bubble, a player circle with its play glyph inside its own bubble and visible time stamp ink. Results go to `voice-checks.json`; failures read `voice: <step>: <problem>`. `transcripts.json`, every screenshot pair, UIA trees and state snapshots are retained.

## Gotchas

Hosted runners cannot be relied on to play audio, so the journey does not press play; it repeats the playback timer's own partial invalidation from the harness instead. The voice files are synthetic bytes, not playable audio. Transcription stays off (no speech key), so the transcripts come only from the local cache. Look at the screenshot pairs, not only the exit status.

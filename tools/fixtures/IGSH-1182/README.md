# Recorded dictation input

Unmodified PocketSphinx recording, 16000 Hz mono signed 16-bit PCM.
Original source and license accompany these bytes in source.json and LICENSE.pocketsphinx.
The recording says “go forward ten meters”; response.json is hand-authored provider-format JSON.

The GitHub-only isolated app fixture replaces microphone capture and provider I/O.
The production worker, audio meter, response parser, state transitions and native composer remain real.
This proves the shared dictation interface and transcript delivery, not microphone hardware or acoustic recognition.
The proof makes no network transcription request and needs no paid key.

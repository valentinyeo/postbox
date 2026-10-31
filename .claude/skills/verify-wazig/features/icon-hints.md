# Icon hints and voice shortcut

## Sub-features

- Native hover labels for composer, reply, staged attachments, message actions and chat avatar.
- Selected-message reaction and reply shortcuts appear only for the selected message.
- Ctrl+Shift+M starts or finishes a WhatsApp voice note.
- Missing or invalid verification PCM never reaches the microphone.

## How to get to it (user POV)

- Open a chat and hover its avatar or composer icons.
- Hover a message action, reply close or attachment remove icon.
- Press Ctrl+Shift+M to record; Escape cancels.
- Ctrl+D retains its existing dictation behavior.

## Driving it with PowerShell UI Automation

- Dispatch `feature=icon-hints` on hosted Windows.
- The synthetic hub supplies WhatsApp and Slack chats and scrollable messages.
- Real mouse input observes process-owned native tooltip text, tool identities and rectangles, and captures screenshots.
- Check every staged attachment slot, including wrapped rows, compaction and the sole attachment.
- Check selected and unselected actions, adjacent movement, leave, resize, scroll, chat changes, reply close and attachment compaction.
- Require prompt transitions before native auto-pop; retain current and registered tools before and after.
- Real keyboard input reaches the voice worker with synthetic PCM. Check held repeats, cancellation, draft, selection and zero microphone entries.
- Separate isolated processes check no chat, missing PCM and malformed PCM. Capture each executable, PID, start time and cleanup.
- Check unsupported provider, extra modifiers and fixture-backed Ctrl+D without sending or calling a service.
- The registered evidence checker requires the native screenshots, popup text, process identities and cleanup.

## Gotchas

- This journey uses synthetic audio and a local fixture. It does not prove microphone quality or external delivery.
- Source registration does not prove a hosted run succeeded.
- Physical desktop verification remains separate.

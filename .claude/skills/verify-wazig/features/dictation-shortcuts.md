# Dictation shortcuts

## Sub-features

- Finish dictation and send with Ctrl+Enter.
- Cancel with Escape and restore the original draft.
- Keep changed contexts as unsent origin drafts.
- Preserve ordinary keys and Ctrl+D insertion.

## How to get to it (user POV)

- Open a synthetic chat and focus its message box.
- Press Ctrl+D to start dictating.
- Press Ctrl+Enter to finish, or Escape to cancel.

## Driving it with PowerShell UI Automation

- Dispatch `feature=dictation-shortcuts` on GitHub Actions.
- The isolated fixture uses synthetic PCM and a Unicode, multiline response.
- Native keyboard events drive recording, finishing, cancellation and navigation.
- Named gates hold transcription, publication and result consumption.
- Capture native text, selections, screens, scoped sends and the durable ledger.
- Verify cancelled workers drain without late insertion or admission.
- Verify archive and search round trips disarm sending.
- Verify another chat retains its own draft.

## Gotchas

- The native editor normalizes paragraph markers to line feeds.
- Preserve every word and paragraph in comparisons.
- The response fixture retains CRLF to exercise normalization.
- Missing fixtures must never reach a microphone or service.
- This fixture proves local admission, not provider delivery.

# WhatsApp owns its archive (IGSH-949)

## Sub-features

Run `feature=hub-archive` on GitHub Windows Actions. The journey drives the real desktop with a synthetic hub, never a user's device.

- Ctrl+E archives and unarchives through WhatsApp, including bulk selections.
- Phone unarchive changes the provider row; Wazig follows it.
- Incoming messages return when WhatsApp returns them. No Wazig return write.
- Ctrl+Shift+E remains local: kept chats stay hidden even when WhatsApp returns them.
- Existing ordinary local entries migrate through acknowledged archive writes. Failed writes retain durable entries. Successful migration does not repeat after restart.
- Telegram archives remain local through bulk selection and restart. Slack and Signal retain their existing local archive tests.
- Legacy keep migration retains the original file and hub-scoped marker.

## How to get to it (user POV)

Ctrl+E archives in WhatsApp. Ctrl+K, Show archived chats opens Archive. Ctrl+Shift+E keeps a chat archived locally.

## Driving it with PowerShell UI Automation

`check-hub-archive-evidence.py` checks requests, provider rows, desktop lists, screenshots, migration state and isolation. CI first builds original main and requires the same journey to fail because WhatsApp never acknowledges an archive. Candidate evidence then proves all four requested behaviors and migration.

## Gotchas

This proves the client contract, not live WhatsApp delivery.

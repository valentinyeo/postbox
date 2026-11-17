# Postbox job entries

## Sub-features

<!-- entry: job|provider archived_scan|src/main.zig -->
- `src/main.zig:564`: archived_scan

<!-- entry: job|provider background_media|src/main.zig -->
- `src/main.zig:564`: background_media

<!-- entry: job|provider cache_tag|src/main.zig -->
- `src/main.zig:564`: cache_tag

<!-- entry: job|provider chats|src/main.zig -->
- `src/main.zig:564`: chats

<!-- entry: job|provider contacts_index|src/main.zig -->
- `src/main.zig:564`: contacts_index

<!-- entry: job|provider groups|src/main.zig -->
- `src/main.zig:564`: groups

<!-- entry: job|provider hub_archive|src/main.zig -->
- `src/main.zig:564`: hub_archive

<!-- entry: job|provider hub_avatar|src/main.zig -->
- `src/main.zig:564`: hub_avatar

<!-- entry: job|provider hub_delete|src/main.zig -->
- `src/main.zig:564`: hub_delete

<!-- entry: job|provider hub_media|src/main.zig -->
- `src/main.zig:564`: hub_media

<!-- entry: job|provider hub_older|src/main.zig -->
- `src/main.zig:564`: hub_older

<!-- entry: job|provider hub_read|src/main.zig -->
- `src/main.zig:564`: hub_read

<!-- entry: job|provider hub_send|src/main.zig -->
- `src/main.zig:564`: hub_send

<!-- entry: job|provider hub_thread|src/main.zig -->
- `src/main.zig:564`: hub_thread

<!-- entry: job|provider kept_check|src/main.zig -->
- `src/main.zig:564`: kept_check

<!-- entry: job|provider messages|src/main.zig -->
- `src/main.zig:564`: messages

<!-- entry: job|provider reaction|src/main.zig -->
- `src/main.zig:564`: reaction

<!-- entry: job|provider slack_attach|src/main.zig -->
- `src/main.zig:564`: slack_attach

<!-- entry: job|provider slack_auth|src/main.zig -->
- `src/main.zig:564`: slack_auth

<!-- entry: job|provider slack_download|src/main.zig -->
- `src/main.zig:564`: slack_download

<!-- entry: job|provider slack_history|src/main.zig -->
- `src/main.zig:564`: slack_history

<!-- entry: job|provider slack_mark|src/main.zig -->
- `src/main.zig:564`: slack_mark

<!-- entry: job|provider slack_replies|src/main.zig -->
- `src/main.zig:564`: slack_replies

<!-- entry: job|provider slack_send|src/main.zig -->
- `src/main.zig:564`: slack_send

<!-- entry: job|provider slack_share|src/main.zig -->
- `src/main.zig:564`: slack_share

<!-- entry: job|provider slack_users|src/main.zig -->
- `src/main.zig:564`: slack_users

<!-- entry: job|provider slack_workspace|src/main.zig -->
- `src/main.zig:564`: slack_workspace

<!-- entry: job|provider unread_probe|src/main.zig -->
- `src/main.zig:564`: unread_probe

<!-- entry: job|timer_slack_mark|src/main.zig -->
- `src/main.zig:6317`: timer_slack_mark

<!-- entry: job|timer_voice|src/main.zig -->
- `src/main.zig:10665`: timer_voice

<!-- entry: job|timer_reply_flash|src/main.zig -->
- `src/main.zig:11371`: timer_reply_flash

<!-- entry: job|timer_chat_select|src/main.zig -->
- `src/main.zig:12025`: timer_chat_select

<!-- entry: job|timer_passage_scroll|src/main.zig -->
- `src/main.zig:19414`: timer_passage_scroll

<!-- entry: job|timer_refresh|src/main.zig -->
- `src/main.zig:20065`: timer_refresh

<!-- entry: job|timer_animation|src/main.zig -->
- `src/main.zig:20066`: timer_animation

<!-- entry: job|timer_update_first_check|src/main.zig -->
- `src/main.zig:20067`: timer_update_first_check

<!-- entry: job|timer_update_check|src/main.zig -->
- `src/main.zig:20068`: timer_update_check

<!-- entry: job|timer_update_restart|src/main.zig -->
- `src/main.zig:20582`: timer_update_restart

<!-- entry: job|timer_update_card|src/main.zig -->
- `src/main.zig:22420`: timer_update_card

## How to get to it (user POV)

Launch Postbox. Use the listed control or command.
Conditional entries require their matching provider state.

## Driving it with PowerShell UI Automation

Use the real Windows harness, never internal setters.
Read [the skill](../SKILL.md) before driving.
Match the source label through keyboard or UIA.
Inspect resulting screenshots and persisted side effects.
CLI entries use the listed postboxctl command.
Jobs need their user action and resulting state.

## Gotchas

An inventory entry does not prove execution.
The shared gate cannot scan Zig yet.
These are bounded scanner results, not semantic completeness.
Existing journeys document narrower proof and gaps.

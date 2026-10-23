# Local Slack archive

## Sub-features

- `local-archive`: the existing archive action moves Slack channels, groups and DMs to Wazig Archive without closing them in Slack.
- `stay-archived`: incoming and synced messages never return a locally archived Slack chat to the inbox.
- `restart`: provider/account/chat identity and local archive state survive restarting the isolated profile.
- `unarchive`: Ctrl+E in Archive clears the local state and restores inbox presence.

## How to get to it (user POV)

Select a Slack chat and use Ctrl+E, bare E outside an editor, right-click Archive, or Ctrl+K → Archive selected chat. Open Archive through Ctrl+K → Show archived chats. Ctrl+E there unarchives. No Slack workspace archive call is made. No extra command, button or setting is added.

## Driving it with PowerShell UI Automation

Run `feature=slack-archive` on GitHub Actions. Matching PRs run `verify (slack-archive)` and upload `verify-wazig-slack-archive`. The real Messages.exe --verify-fixture uses the unified fake hub's `--slack-archive` mode and a fresh isolated profile.

Foreground-checked SendKeys selects synthetic Slack Alpha and sends Ctrl+E. Require inbox absence and Archive presence; retain `archived.png`. Deliver three distinct incoming messages through `/fixture/live` and normal SSE/Refresh. Each hub row explicitly says archived=false, with an increasing unread count. After each delivery require inbox absence and unread Archive presence; retain `incoming.png` after the third.

Stop only the identity-checked recorded app PID, then relaunch the same executable with the same isolated profile and registry. Retain `restart.json`, require inbox absence and Archive-only presence with three unread messages, and capture `restart.png`. Send real Ctrl+E in Archive, require Alpha back in the inbox and Archive empty, and capture `unarchived.png`.

Every stage retains read-only state/chats, UIA trees and screenshots. Keep `bridge-requests.jsonl` with every request's method/path and all three live deliveries, plus local archive-state evidence. Any archive endpoint path is a failure, including unsuccessful requests; archived query parameters are normal list reads, not archive endpoints. `result.json` is passed only after the complete journey and cleanup. `check-evidence.py` validates surviving evidence; Python negative controls reject archive writes, missing deliveries, resurfacing, lost restart state and missing images.

## Gotchas

This is synthetic unified-hub evidence, not a real Slack workspace or direct-connector runtime test. The common archive entry points and direct Slack merges have Zig regression coverage in CI. No Zig, Wine or Windows app runs locally. Inspect the required screenshots from the exact GitHub commit before claiming visible runtime success.

Source: `src/main.zig:archiveChat`, `src/main.zig:applyChats`, `src/main.zig:appendSlackChats`, `src/archive_rules.zig:State`; journey `tools/verify-wazig/slack-archive.ps1`, fixture `tools/verify-wazig/fake-hub.py:SlackArchiveHandler`, evidence `tools/verify-wazig/check-slack-archive-evidence.py`.

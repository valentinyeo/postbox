# Local Slack archive

## Sub-features

- `local-archive`: Ctrl+E writes an ordinary archive. Channels, groups, and DMs stay open in Slack. The label is `Archived`, never `Kept archived`.
- `incoming-return`: a newer message restores inbox presence automatically. Archive becomes empty.
- `restart`: rearchiving survives the isolated profile restart. Provider, account, and chat identity remain unchanged.
- `unarchive`: Ctrl+E in Archive restores inbox presence. Archive stays empty.

## How to get to it (user POV)

Select a Slack chat and use Ctrl+E. Other existing entry points use the same action. These include bare E outside an editor. Right-click Archive and Ctrl+K also work. Choose Archive selected chat in Ctrl+K. Open Archive through Ctrl+K → Show archived chats. Ctrl+E there unarchives. No Slack workspace archive call is made. No extra command, button, or setting is added.

## Driving it with PowerShell UI Automation

Run `feature=slack-archive` on GitHub Actions. Matching PRs run `verify (slack-archive)`. Download `verify-wazig-slack-archive` from that run. The real Messages.exe runs with `--verify-fixture`. Its unified fake hub uses `--slack-archive`. Each run uses a fresh isolated profile.

1. Select synthetic Slack Alpha through foreground-checked SendKeys. Send Ctrl+E. Require inbox absence and Archive presence. Require `archive_label` equal to `Archived`. Retain `archived.png` and `slack-archive-state.txt`. The saved Slack line has five tab-separated fields. Their order is provider, account, id, keep, ts. Require the matching Slack identity and `keep=0`. Require a non-empty timestamp.
2. Deliver one incoming message through `/fixture/live`. Keep the normal SSE and Refresh path. Fixture timestamps start one day ahead. The delivery timestamp advances another second. This keeps delivery newer than the archive baseline. Require the hub row's `archived=false` and `unread_count=1`. Require automatic inbox return, without manual unarchive. Capture `incoming-inbox.png` with those same flags. Require Archive empty. Capture `incoming-archive-empty.png`.
3. Select Alpha again and require it read. Send Ctrl+E again. Capture `rearchived-inbox.png` and `rearchived.png`. Save `slack-rearchive-state.txt` with matching identity. Require `keep=0` and the newer timestamp.
4. Stop only the identity-checked recorded app PID. Relaunch the same executable and isolated profile. Keep the same registry. Retain `restart.json`. Require inbox absence and Archive-only presence. Require `Archived` and zero unread messages. Capture `restart-inbox.png` and `restart.png`.
5. Send real Ctrl+E in Archive. Require Alpha back in the inbox. Require Archive empty. Capture `unarchived.png` and `unarchived-archive.png`.

Every stage retains read-only state/chats, UIA, and screenshots. Keep every request's method/path in `bridge-requests.jsonl`. Require exactly one live delivery and its SSE. Verify delivery and row timestamps exceed archive time. Preserve both local archive-state captures.

Any archive endpoint path fails, including unsuccessful requests. Archived query parameters remain normal list reads. Require zero `/v1/wazig/archive` requests throughout. `result.json` passes only after complete journey cleanup. `check-evidence.py` validates the surviving evidence.

## Gotchas

This proves synthetic unified-hub behavior only. Real workspaces and direct connectors need separate evidence. Shared archive actions have Zig coverage in CI. No local builds, tests, or app runs. Inspect screenshots from the exact GitHub commit. Only then claim visible runtime success.

Source: `src/main.zig:archiveChat`, `src/main.zig:applyChats`, `src/main.zig:appendSlackChats`, `src/archive_rules.zig:State`; journey `tools/verify-wazig/slack-archive.ps1`, fixture `tools/verify-wazig/fake-hub.py:SlackArchiveHandler`, evidence `tools/verify-wazig/check-slack-archive-evidence.py`.

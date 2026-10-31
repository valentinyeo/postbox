# Slack threads like Slack

## Sub-features

- Default-on Slack account setting groups replies under their parent with one replies line and last reply time.
- Enter on a selected parent opens the parent and all replies in a native side panel; Enter sends with the parent thread ID, Escape closes.
- The account-scoped palette toggle restores inline messages and survives restart. Other providers are unchanged.

## How to get to it (user POV)

- Open a Slack account with Alt+2, select a parent and press Enter, or click its replies line.
- Type in the panel and press Enter. Escape closes the panel.
- Ctrl+K → Slack threads like Slack for this account toggles the current Slack account.

## Driving it with PowerShell UI Automation

- Run `feature=slack-threads` on GitHub Actions only, using the unified fake hub in `--slack-threads` mode.
- The fixture has parent `1740000000.000100`, exactly thirty replies and two channel messages. Read-only `wazigctl status` must expose `slack_threads`; missing fields fail the journey before any feature action.
- Save threads-on.png/json, select the parent with real Ctrl+Up and Enter, and save thread-panel.png/json with thirty listed replies.
- Type Synthetic thread reply and Enter; retain thread-reply.png and the authenticated send POST body in bridge-requests.jsonl.
- Escape, toggle via Ctrl+K and retain threads-off.png/json. Quit normally and restart with the same isolated profile and registry; retain restart.json and threads-restart.png/json.
- Result status becomes passed only after all assertions and cleanup. The surviving validator cross-checks measurements against read-only state, input, screenshots, transport and isolation.

## Gotchas

- Hub message rows use `thread_ts` for the parent, `reply_count` and `latest_reply` for the summary; ordinary quoted-message fields remain separate.
- Synthetic data proves the client contract, not a live Slack service. Inspect screenshots before claiming rendered behavior.
- Only real foreground-checked SendKeys drives this recipe; UIA and wazigctl are read-only observers. Clicking the replies line, multiple accounts and direct Slack transport require source/unit coverage in addition to this keyboard journey.
- Source: `src/main.zig` handles grouping, panel and palette; `src/slack.zig` supplies direct Slack history metadata.
- Journey: `tools/verify-wazig/slack-threads.ps1`; evidence: `tools/verify-wazig/check-slack-threads-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

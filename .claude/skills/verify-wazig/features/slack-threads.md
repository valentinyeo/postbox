# Slack threads like Slack

## Sub-features

- Default-on Slack account setting groups replies under their parent with one replies line and last reply time.
- Enter on a selected parent opens the parent and all replies in a native side panel; Enter sends with the parent thread ID, Escape closes.
- The account-scoped palette toggle restores inline messages and survives restart. Other providers are unchanged.
- A Slack chat with its own saved Replies choice follows it: WhatsApp style shows the thread replies inline with a quote of the parent, Slack style folds them under N replies again. A Slack chat without a saved choice keeps following the account setting, and the palette labels show the current style for the chat.

## How to get to it (user POV)

- Open a Slack account with Alt+2, select a parent and press Enter, or click its replies line.
- Type in the panel and press Enter. Escape closes the panel.
- Ctrl+K → Slack threads like Slack for this account toggles the current Slack account.
- Ctrl+K → Replies: WhatsApp style shows this Slack chat's replies inline; Replies: Slack style folds this one chat again, whatever the account setting says.

## Driving it with PowerShell UI Automation

- Run `feature=slack-threads` on GitHub Actions only, using the unified fake hub in `--slack-threads` mode.
- The fixture has parent `1740000000.000100`, exactly thirty replies, two orphan replies whose parent is not in the chat, and two channel messages (so 32 inline replies with threads off). Read-only `wazigctl status` must expose `slack_threads`; missing fields fail the journey before any feature action.
- Save threads-on.png/json, select the parent with real Ctrl+Up and Enter, and save thread-panel.png/json with thirty listed replies.
- Type Synthetic thread reply and Enter; retain thread-reply.png and the authenticated send POST body in bridge-requests.jsonl.
- Escape, toggle via Ctrl+K and retain threads-off.png/json. Quit normally and restart with the same isolated profile and registry; retain restart.json and threads-restart.png/json.
- Toggle the account setting back on, then pick Ctrl+K → Replies: WhatsApp style in the chat and retain chat-whatsapp-style.png/json with 32 inline replies, the two orphans counted as loose and no replies line; pick Replies: Slack style and retain chat-slack-style.png/json with the thirty replies folded under `30 replies`. `slack_threads.replies_style` reports `whatsapp` or `slack` for the selected chat.
- Result status becomes passed only after all assertions and cleanup. The surviving validator cross-checks measurements against read-only state, input, screenshots, transport and isolation.

## Gotchas

- The live hub sends Slack thread replies with only `quoted_msg_id` (the parent) and no `thread_ts`, `reply_count` or `latest_reply`; the fixture does the same and the client groups replies by the quote chain. Rows that do carry `thread_ts`, `reply_count` and `latest_reply` still group by them.
- A saved per-chat Replies choice outranks the account threads setting, so the account toggle leaves that one chat alone until the user picks the style again.
- Synthetic data proves the client contract, not a live Slack service. Inspect screenshots before claiming rendered behavior.
- Only real foreground-checked SendKeys drives this recipe; UIA and wazigctl are read-only observers. Clicking the replies line, multiple accounts and direct Slack transport require source/unit coverage in addition to this keyboard journey.
- Source: `src/main.zig` handles grouping, panel and palette; `src/slack.zig` supplies direct Slack history metadata.
- Journey: `tools/verify-wazig/slack-threads.ps1`; evidence: `tools/verify-wazig/check-slack-threads-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

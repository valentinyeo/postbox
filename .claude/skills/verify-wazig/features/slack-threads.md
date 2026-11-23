# Slack threads like Slack

## Sub-features

- Slack chats use Slack reply style by default: replies fold under their parent with one replies line and last reply time, whatever the account threads setting says.
- WhatsApp chats keep WhatsApp style unless that chat saves a per-chat Replies choice of its own.
- Enter on a selected parent opens the parent and all replies in a native side panel; Enter sends with the parent thread ID, Escape closes.
- A Slack chat with its own saved Replies choice follows it: WhatsApp style shows the thread replies inline with a quote of the parent, Slack style folds them under N replies again.
- The account-scoped palette toggle applies its choice to every Slack chat in that account at the moment it is pressed. Chats without a saved choice always open in Slack style, so a Slack chat added after the toggle still folds. The palette labels show the current style for the chat.

## How to get to it (user POV)

- Open any Slack chat: its replies are folded under the parent, with or without a saved account setting.
- Select a parent and press Enter, or click its replies line, to open the panel.
- Type in the panel and press Enter. Escape closes the panel.
- Ctrl+K → Slack threads like Slack for this account applies the choice to the chats in the current Slack account.
- Ctrl+K → Replies: WhatsApp style shows this chat's replies inline; Replies: Slack style folds this one chat again.
- Open a new Slack chat with no Replies choice and it is folded; open a WhatsApp chat and its replies stay inline with their quotes.

## Driving it with PowerShell UI Automation

- Run `feature=slack-threads` on GitHub Actions only, using the unified fake hub in `--slack-threads` mode. `prepare-slack-threads.ps1` seeds the legacy account key `SlackThreads-fixture-fresh` as off before the app starts and records it in `legacy-account-threads.json`.
- The fixture serves three chats: parent `1740000000.000100` with exactly thirty replies, two orphan replies whose parent is not in the chat, and two channel messages (so 32 inline replies with threads off) in the threads channel; a fresh Slack chat `fixture-fresh` with a parent and two replies; and a WhatsApp chat `fixture-whatsapp` with a reply quoting its original.
- Read-only `wazigctl status` must expose `slack_threads`; missing fields fail the journey before any feature action. Chats are selected with Ctrl+F and their names.
- Save threads-on.png/json, select the parent with real Ctrl+Up and Enter, and save thread-panel.png/json with thirty listed replies. Type Synthetic thread reply and Enter; retain thread-reply.png and the authenticated send POST body in bridge-requests.jsonl.
- Escape, toggle the account setting via Ctrl+K and retain threads-off.png/json with 32 inline replies. Quit normally and restart with the same isolated profile and registry; retain restart.json and threads-restart.png/json.
- Toggle the account setting back on, pick Ctrl+K → Replies: WhatsApp style and retain chat-whatsapp-style.png/json with 32 inline replies, the two orphans counted as loose and no replies line; pick Replies: Slack style and retain chat-slack-style.png/json with the thirty replies folded under `30 replies`.
- Open the fresh Slack chat and retain fresh-slack-default.png/json: `replies_style` slack, `threads_option` on, `2 replies` under parent `1750000000.000100`, no inline or loose replies, while the legacy account key for that chat's account stays off.
- Open the WhatsApp chat and retain whatsapp-default.png/state.json with no `slack_threads` block at all, plus whatsapp-default.messages.json with the reply's quote painted above its bubble.
- Result status becomes passed only after all assertions and cleanup. The surviving validator cross-checks measurements against read-only state, input, screenshots, transport and isolation.

## Gotchas

- The live hub sends Slack thread replies with only `quoted_msg_id` (the parent) and no `thread_ts`, `reply_count` or `latest_reply`; the fixture does the same and the client groups replies by the quote chain. Rows that do carry `thread_ts`, `reply_count` and `latest_reply` still group by them.
- The account threads key no longer decides the style of a chat that has no saved Replies choice. A stored off value from an older build only shows up in the palette label and in the chats the toggle applies to. The seeded key makes the previous build open the fresh chat inline.
- The account toggle writes a per-chat Replies value for every Slack chat in that account, so it overrides a per-chat choice made earlier.
- Synthetic data proves the client contract, not a live Slack service. Inspect screenshots before claiming rendered behavior.
- Only real foreground-checked SendKeys drives this recipe; UIA and wazigctl are read-only observers. Clicking the replies line, multiple accounts and direct Slack transport require source/unit coverage in addition to this keyboard journey.
- Source: `src/main.zig` handles grouping, panel, palette and the per-chat replies resolution; `src/slack.zig` supplies direct Slack history metadata and the replies fold rule.
- Journey: `tools/verify-wazig/slack-threads.ps1`; evidence: `tools/verify-wazig/check-slack-threads-evidence.py`; fixture: `tools/verify-wazig/fake-hub.py`.

# Slack last message ordering

## Sub-features

- `last-message-order`: Slack chats use the last message sent or received, newest first, just like WhatsApp.
- `unknown-last`: a chat without a known last message time stays below timestamped chats; equal times sort by name.
- `incoming-promotion`: an incoming message moves the oldest chat to the top without changing the selected chat.
- `sent-promotion`: sending through the composer moves that Slack chat to the top.

## How to get to it (user POV)

- Open Messages with the unified hub configured and choose its Slack account with Alt+1 in this single-account fixture (Alt+N follows saved account order).
- Read the chat list from top to bottom; Ctrl+Tab and Ctrl+Shift+Tab follow the same order.
- Receive a message or compose and press Enter to send; the chat with the newest last message rises to the top. Existing pins keep the same precedence as WhatsApp.

## Driving it with PowerShell UI Automation

- Run `feature=slack-sort`, or `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature slack-sort`, on GitHub Actions only.
- The isolated real desktop uses the authenticated fake hub in `--slack-sort` mode. It returns four synthetic Slack chats in deliberately shuffled wire order: Alpha oldest, Gamma middle, Beta newest and Aardvark without a time.
- Drive Alt+1 and require Beta, Gamma, Alpha, Aardvark. Read-only `wazigctl chats` observes the current sidebar; real Ctrl+Tab navigation verifies all four selected identities in that order, including wraparound. The walk records four selected identities in cyclic sidebar order, starting at the current selection. At every stage require four Slack rows, descending nonempty times for the first three and an empty time for Aardvark.
- Keep Gamma selected, then deliver a synthetic upstream last message to Alpha through the fixture-only HTTP trigger and the production SSE reader. Require Alpha, Beta, Gamma, Aardvark while Gamma remains selected.
- Use keyboard navigation, Ctrl+K → Compose message and Enter to send Synthetic Slack outgoing to Gamma. Require Gamma, Alpha, Beta, Aardvark and an acknowledged hub send.
- Retain before/after/sent screenshots, UIA trees, state/chat snapshots, keyboard navigation arrays, bridge requests and hub-proof.log. `result.json` has status `passed` only after the journey and cleanup succeed; failures retain status `failed`. The surviving evidence validator checks orders, times, live delivery, send acknowledgement and isolation.

## Gotchas

- Hub rows carry `last_message_ts`; if absent, the app uses the newest message already cached for that chat, never channel creation or modification time. Unknown chats do not trigger new history fetches merely to sort.
- This proves the client contract against synthetic loopback data, not a real Slack account, delivery or deployed triage service. Inspect the screenshots before claiming visible behavior.
- Only real keyboard input drives the desktop. Read-only state and UI Automation supplement screenshots; no private window messages or control mutations are used.
- Equal-time/name ties, pin precedence and cached timestamp fallback are source/CI coverage, not assertions of this four-row journey. Comparator unit tests include equal timestamps with names deliberately opposite to ID order. No Zig, PowerShell or app execution is performed on the development host.
- Source: `src/main.zig:3891` fills missing Slack times from message cache; `src/main.zig:12392` and `src/chat_order.zig:3` order pinned rows, last message times, names and identity ties; `src/slack.zig:191` reads actual last-message time rather than channel creation/modification time.
- Journey and evidence: `tools/verify-wazig/run.ps1:143` drives the three stages, `tools/verify-wazig/fake-hub.py:99` supplies the synthetic hub, and `tools/verify-wazig/check-evidence.py:9` validates retained orders, times, keyboard walks, selection, delivery, send and isolation.

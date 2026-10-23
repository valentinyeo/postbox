# Account views and combined inbox

## Sub-features

- `account-views`: each account or workspace has one view, labelled WhatsApp <account>, or Slack <locally saved workspace name> (Slack <team id> when unknown).
- `view-keys`: Alt+1..9 selects the saved account position; Alt+I opens the combined inbox.
- `view-scope`: search, Ctrl+1..9, next/previous chat and sending stay in the account view. Routing identity includes provider, cache account and the full prefixed id; a separate view account controls membership.
- `view-order`: Ctrl+K → Sort views uses the existing palette list. Ctrl+Up/Down saves a move immediately, Enter switches to that view and Escape closes.
- `combined-inbox`: all account chats appear newest activity first, retaining existing app badges and hover tooltips with app/account labels.
- `view-status`: read-only status exposes current_view (provider, account, label, inbox) and view_order. Control view accepts a number, inbox and legacy provider aliases.

## How to get to it (user POV)

- Open Messages with hub accounts or configured local providers. Each WhatsApp account and Slack workspace is a separate view; Telegram accounts follow.
- Press Alt+1..9 or choose Show <view label> in Ctrl+K. Choose Show combined inbox or press Alt+I for all chats.
- Choose Sort views, move the selected row with Ctrl+Up/Down, then Enter to switch or Escape to close. ViewOrder persists provider:account entries in the existing settings store. Missing accounts remain saved but are skipped; new accounts append in provider and hub listing order.
- Hover a chat row for its app and account label. No toolbar or new controls are added.

## Driving it with PowerShell UI Automation

- Run feature=views on GitHub Actions only. run.ps1 starts fake-hub.py --views with two WhatsApp accounts (personal and business) and two Slack teams (T0ABC123 and T0DEF456), two chats each. Rows omit account and account_name, matching the real hub. WhatsApp JIDs are <account>:<contact>@s.whatsapp.net with the same synthetic contact in both accounts; Slack JIDs are slack:<team>:<channel>.
- Drive Alt+1..Alt+4. Assert account-only sidebar identities through current_view.account and each chat's view_account in read-only status and chats; capture view-1.png through view-4.png. Exercise Ctrl+1, next/previous and Shared search in each account, retaining search-1.png through search-4.png.
- Send Verification account send in the first account. Require one accepted fake-hub send with source_account personal and the selected opaque handle. Retain sent.messages.json and sent.png. Open the matching contact in business; require its own history without that message, with other.messages.json and isolated.png.
- Drive Alt+I and assert the complete catalog and descending activity timestamps in inbox.chats.json and inbox.png.
- Drive Ctrl+K, Sort views, Ctrl+Down, Enter. Retain sort-command.png, sort-before.png, sort-moved.png, sort-selected.png, view-order.txt and immediate read-only state. Open again and Escape, capturing sort-closed.png.
- Quit through the palette and restart the same executable with the same fixture root, registry id and preferences. Retain restart.json, restart-1.png through restart-4.png and corresponding state/chat snapshots proving swapped Alt+1/Alt+2 and unchanged Slack positions.
- check-evidence.py validates the surviving screenshots, keyboard log, account partitions, scoped send, combined ordering and restart evidence. Inspect the images too; source checks are not runtime proof.

## Gotchas

- This is a fake hub journey, not upstream account authentication or production delivery. Windows execution and screenshot inspection belong to GitHub Actions, never the development host.
- Hub conversation handles stay opaque and globally unique; an explicit account wins for view membership, otherwise WhatsApp account prefixes and Slack team IDs provide it. Chat.account stays in the existing cache namespace when account is absent; only Chat.view_account is derived. Sends retain the full JID and the existing chat/text/reply_to/client_id payload, with no account field. Outbox adoption, caches, read state, pending reads and archive routing are unchanged. The same contact display name does not imply the same chat identity.
- New fixture launches require a fresh isolated registry subtree. The harness explicitly opts into same-profile restart after the owned process exits; Actions and isolated-path guards remain required.
- Alt+0 and old provider control aliases remain compatible. Provider aliases select the first matching account in saved order; explicit messenger chat queries still list all accounts of that provider.

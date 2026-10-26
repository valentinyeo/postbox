# Account views and combined inbox

## Sub-features

- `account-views`: each account or workspace has one view, labelled WhatsApp <account>, or Slack <workspace name> for Slack (hub name or locally saved workspace name for direct sign-ins; Slack <team id> when unknown).
- `view-keys`: Ctrl+2..9 selects the saved account position, even when that account has zero visible chats; Ctrl+1 or Alt+I opens the combined inbox.
- `view-title`: the native window title is <view label> - Wazig v<version>, using the exact Show palette label; the combined view uses Combined inbox - Wazig v<version>.
- `view-scope`: search, Ctrl+Shift+Home, next/previous chat and sending stay in the account view. Routing identity includes provider, cache account and the full prefixed id; a separate view account controls membership.
- `view-order`: Ctrl+K → Sort views uses the existing palette list. Ctrl+Up/Down saves a move immediately, Enter switches to that view and Escape closes.
- `combined-inbox`: all account chats appear newest activity first, retaining existing app badges and hover tooltips with app/account labels.
- `empty-views`: unlinked Signal and Telegram are ordinary empty lists, with no sign-in screen. Saved empty provider startup falls back to the combined inbox; Esc leaves any empty account view and normal Ctrl view keys remain available. The [no-trap journey](notrap.md) covers these cases.
- `view-status`: read-only status exposes current_view (provider, account, label, inbox) and view_order. Control view accepts a number, inbox and legacy provider aliases.

## How to get to it (user POV)

- Open Messages with hub accounts or configured local providers. Each WhatsApp account and Slack workspace is a separate view; Telegram and Signal views follow; linking is done once through the triage CLI on the hub, never through Wazig.
- Press Ctrl+2..9 or choose Show <view label> in Ctrl+K. Choose Show combined inbox or press Ctrl+1 / Alt+I for all chats.
- Choose Sort views, move the selected row with Ctrl+Up/Down, then Enter to switch or Escape to close. ViewOrder persists provider:account entries in the existing settings store. Hub workspace names persist alongside the hub state and label cached startup rows without waiting on the hub. Saved account slots remain available as empty lists when their chats disappear; new accounts append in provider and hub listing order.
- Hover a chat row for its app and account label. No toolbar or new controls are added.

## Driving it with PowerShell UI Automation

- Run feature=views on GitHub Actions only. run.ps1 starts fake-hub.py --views with two WhatsApp accounts (personal and business) and two Slack teams (T0ABC123 and T0DEF456), two chats each, plus empty Telegram and Signal views after those four accounts. Rows omit account and account_name, matching the real hub; Slack rows carry team_name Alpha Workspace and Beta Workspace. WhatsApp JIDs are <account>:<contact>@s.whatsapp.net with the same synthetic contact in both accounts; Slack JIDs are slack:<team>:<channel>.
- First drive Ctrl+2..Ctrl+7, including empty Telegram and Signal, returning through Ctrl+1 after each account. Alt+0..9 must leave the selected account unchanged; Alt+I returns to the inbox. Retain view-shortcuts.json and shortcut-account-N, shortcut-inbox and shortcut-help captures.
- Drive Ctrl+2..Ctrl+5. Assert account-only sidebar identities through current_view.account and each chat's view_account in read-only status and chats; capture view-1.png through view-4.png. Exercise Ctrl+Shift+Home, next/previous and Shared search in each account, retaining search-1.png through search-4.png.
- Send Verification account send in the first account. Require one accepted fake-hub send with source_account personal and the selected opaque handle. Retain sent.messages.json and sent.png. Open the matching contact in business; require its own history without that message, with other.messages.json and isolated.png.
- Drive Alt+I and assert the complete catalog and descending activity timestamps in inbox.chats.json and inbox.png.
- Require exact native titles after Ctrl+2 and Ctrl+4 and Combined inbox after Alt+I, with the read-only build version. Retain title-view-1.png, title-inbox.png and title.json alongside UI Automation and state snapshots.
- Drain personal through Ctrl+Shift+Home and Ctrl+E twice; WhatsApp archives stay in Wazig and the fake hub must record zero archive requests (IGSH-902). Refresh, press Ctrl+2 and require current_view personal with zero chats and the unchanged view_order. Retain drained-alt1.png; Ctrl+3 must still select business with two chats, retaining drained-alt2.png. Restore both chats through Show archived chats and Ctrl+E before sorting and restarting.
- Drive Ctrl+K, Sort views, Ctrl+Down, Enter. Retain sort-command.png, sort-before.png, sort-moved.png, sort-selected.png, view-order.txt and immediate read-only state. Open again and Escape, capturing sort-closed.png.
- Quit through the palette and restart the same executable with the same fixture root, registry id and preferences. Retain restart.json, restart-1.png through restart-4.png and corresponding state/chat snapshots proving swapped Ctrl+2/Ctrl+3 and unchanged Slack positions.
- Require full labels Slack Alpha Workspace and Slack Beta Workspace (Show Slack Alpha Workspace and Show Slack Beta Workspace in the palette), while retaining exact names Alpha Workspace and Beta Workspace in evidence, under exact result check ids `view-label`, `sort-views`, `palette` and `inbox-tooltip`. Reject Slack T0ABC123 and Slack T0DEF456 labels for these named workspaces. Read current_view/view_order, the actual Sort views and Ctrl+K Show list rows, and each visible owned native tooltip after real mouse hover in the combined inbox. Retain workspace-names.json, result.json checks, hub-proof.log, workspace-palette.png, sort-before.png, view-3.png/view-4.png and inbox-tooltip-T0ABC123.png/inbox-tooltip-T0DEF456.png. The final-data hub workspace-names cache and restart labels must retain both names.
- check-evidence.py validates the surviving screenshots, keyboard log, account partitions, scoped send, combined ordering and restart evidence. Inspect the images too; source checks are not runtime proof.

## Gotchas

- This is a fake hub journey, not upstream account authentication or production delivery. Windows execution and screenshot inspection belong to GitHub Actions, never the development host.
- Hub conversation handles stay opaque and globally unique; an explicit account wins for view membership, otherwise WhatsApp account prefixes and Slack team IDs provide it. Chat.account stays in the existing cache namespace when account is absent; only Chat.view_account is derived. Sends retain the full JID and the existing chat/text/reply_to/client_id payload, with no account field. Outbox adoption, caches, read state, pending reads and archive routing are unchanged. The same contact display name does not imply the same chat identity.
- New fixture launches require a fresh isolated registry subtree. The harness explicitly opts into same-profile restart after the owned process exits; Actions and isolated-path guards remain required.
- Alt+0..9 no longer switches views. Existing provider control aliases remain compatible. Provider aliases select the first matching account in saved order; explicit messenger chat queries still list all accounts of that provider.

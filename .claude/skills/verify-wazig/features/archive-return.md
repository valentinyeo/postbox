# Archive return

Every archived chat returns to the inbox when a newer message arrives: WhatsApp, Slack, Signal and Telegram, muted chats included, and chats archived in bulk with Ctrl+A then Ctrl+E. Only chats kept with Ctrl+Shift+E stay archived.

## Sub-features

- `whatsapp-return`: a chat the provider reports as archived returns on a newer message.
- `slack-return`: a Slack channel returns the same way.
- `signal-return`: a Signal chat returns the same way.
- `telegram-return`: a Telegram chat returns the same way.
- `muted-return`: a muted archived chat returns too.
- `bulk-return`: Ctrl+A then Ctrl+E, then one incoming returns its chat.
- `kept-stays`: a chat kept with Ctrl+Shift+E stays archived.

## How to get to it (user POV)

- Archive a chat with Ctrl+E, or archive everything with Ctrl+A then Ctrl+E.
- Receive a message in one of those chats.
- The chat reappears in the inbox with its unread count.

## Driving it with PowerShell UI Automation

- Run `feature=archive-return` on GitHub Actions only.
- Archive the open chat, then deliver one live message through the fixture trigger.
- Require the chat back in the inbox. Require the kept chat to stay archived.

## Gotchas

- The archive time is kept per chat on every channel.
- A provider's own archived flag never vetoes a return.
- His own outgoing message never returns a chat.

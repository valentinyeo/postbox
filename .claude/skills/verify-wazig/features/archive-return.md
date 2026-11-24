# Archive return

The app returns every archived chat to the inbox when a newer message arrives, on every provider, muted chats and bulk-archived chats included. Only chats kept with Ctrl+Shift+E stay archived. The journey itself drives only the WhatsApp return and the kept chat, listed below.

## Sub-features

Driven by `journey-archive-return.ps1`: `whatsapp-return` and `kept-stays`. The Slack return is driven in the [slack-archive](slack-archive.md) journey. The others are source behavior with no return journey: `signal-return`, `telegram-return`, `muted-return` and `bulk-return`.

- `whatsapp-return`: a chat the provider reports as archived returns on a newer message.
- `slack-return`: a Slack channel returns the same way.
- `signal-return`: a Signal chat returns the same way.
- `telegram-return`: a Telegram chat returns the same way.
- `muted-return`: a muted archived chat returns too.
- `bulk-return`: Ctrl+A then Ctrl+E, then one incoming returns its chat.
- `kept-stays`: a chat kept with Ctrl+Shift+E stays archived, including when it receives a newer message of its own, and a newer archived message on another chat never releases it.

## How to get to it (user POV)

- Archive a chat with Ctrl+E, or archive everything with Ctrl+A then Ctrl+E.
- Receive a message in one of those chats.
- The chat reappears in the inbox with its unread count.

## Driving it with PowerShell UI Automation

- Run `feature=archive-return` on GitHub Actions only.
- Archive one WhatsApp chat (`business:notification-inbox@s.whatsapp.net`) with Ctrl+E, then deliver one incoming message through the fixture trigger.
- Require the chat back in the inbox and the return acknowledged. Then keep the same chat with Ctrl+Shift+E and deliver a newer archived message on `business:notification-archived@s.whatsapp.net`; that chat, which was never kept, must return to the inbox. Deliver one more message to the kept chat and require a fresh chats pull, the kept chat still listed as an archived row through `chats --archived`, and the chat absent from the inbox list. The pull count is taken before the notification, so the assertion cannot pass on a stale list.

## Gotchas

- The archive time is kept per chat on every channel.
- A provider's own archived flag never vetoes a return.
- His own outgoing message never returns a chat.

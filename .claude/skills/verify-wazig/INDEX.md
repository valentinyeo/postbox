# Verification index

The complete workflow-input index and bounded recent-change coverage live in [features/README.md](features/README.md). Launch and evidence rules live in [SKILL.md](SKILL.md); [RULE-MAP.md](RULE-MAP.md) links feature-specific acceptance rules.

- [Reactions](features/reactions.md): real right-click laughing-face selection on WhatsApp and Slack, exact hub requests and visible chips.
- [Telegram](features/telegram.md): hub-only account view, Saved Messages, replies and unified messaging evidence.
- [Signal](features/signal.md): account view, unified actions, visible terminal send failures and isolated Windows evidence.
- [No-trap navigation](features/notrap.md): saved empty startup fallback, Esc, and every Alt view shortcut from every view.
- [Account views](features/views.md): saved Alt-key ordering, account isolation, combined inbox and same-profile restart.
- [Slack ordering](features/slack-sort.md): last-message ordering and incoming/sent promotion.
- [Slack archive](features/slack-archive.md): local archive, incoming messages, restart and unarchive without workspace archive calls.
- [Workspace icons](features/workspace-icons.md): Slack workspace images, WhatsApp and Signal marks, fallback and persistent cache evidence.
- [Hub archive migration](features/hub-archive.md): legacy WhatsApp keep flags, hub re-archive, durable state and same-profile restart.
- [Palette archived](features/palette-archived.md): Ctrl+K finds archived and other-view chats on every account; Enter opens without unarchiving.
- [Unified hub](features/hub.md): existing transport and backend isolation.

IGSH-607 adds signal to workflow dispatch, the pull-request matrix and surviving-evidence validation. A registered journey is coverage intent, not proof of a successful run. Runtime evidence must come from the exact commit's GitHub Windows run.

- [Clipboard images](features/paste-image.md): native V5/PNG paste, Enter send, decoded full-screen/4K uploads and per-provider evidence.

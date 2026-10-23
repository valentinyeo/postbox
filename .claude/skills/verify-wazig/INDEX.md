# Verification index

The complete workflow-input index and bounded recent-change coverage live in [features/README.md](features/README.md). Launch and evidence rules live in [SKILL.md](SKILL.md); [RULE-MAP.md](RULE-MAP.md) links feature-specific acceptance rules.

- [Signal](features/signal.md): account view, QR linking, unified actions, visible terminal send failures and isolated Windows evidence.
- [Account views](features/views.md): saved Alt-key ordering, account isolation, combined inbox and same-profile restart.
- [Slack ordering](features/slack-sort.md): last-message ordering and incoming/sent promotion.
- [Unified hub](features/hub.md): existing transport and backend isolation.

IGSH-607 adds signal to workflow dispatch, the pull-request matrix and surviving-evidence validation. A registered journey is coverage intent, not proof of a successful run. Runtime evidence must come from the exact commit's GitHub Windows run.

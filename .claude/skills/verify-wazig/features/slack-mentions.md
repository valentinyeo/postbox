# Slack mention display

## Sub-features

- `cached-name`: unresolved mention markup uses the same hub-provided name as the sender line.
- `neutral-fallback`: an unresolved user mention displays `@someone`, never a raw Slack user id.
- `labelled-mention`: a supplied mention label displays as `@Outside Guest` without exposing its id.
- `external-members`: guest and Slack Connect names absent from the initial member list remain available through cached sender names; upstream-resolved text stays unchanged.
- `link-cleanup`: Slack link markup still displays its label and preserves the target URL.

## How to get to it (user POV)

- Open Messages with the unified hub configured and select the Slack account with Ctrl+2 in this single-account fixture.
- Use Ctrl+Tab to select Verification Mentions and read its five messages.
- Expect `@Fixture Peer hello`, `@someone joins later`, `@Outside Guest thanks report`, `@Guest Person joins @Fixture Peer` and `@Guest Person meets @Connect Person`.

## Driving it with PowerShell UI Automation

- Run `feature=slack-mentions` on GitHub Actions only. The registry includes the journey in the standard Windows PR evidence matrix, without a workflow exemption.
- `SlackMentionsHandler` in `tools/verify-wazig/fake-hub.py` serves `slack:fixture-mentions:channel` through the authenticated unified hub.
- The fixture's initial member map contains only `U4A59H6UT` with name `Fixture Peer`. Synthetic `users.info` results supply `UEXT00001` as `Guest Person` and `WCONNECT01` as `Connect Person`; these results populate the sender names, not a direct Slack installation. Retain the member map, lookup results and raw wire rows in `bridge-requests.jsonl`.
- Known, guest and Connect wire mentions deliberately retain markup so the client must use the hub sender-name lookup. The Connect row also contains upstream-resolved `@Guest Person` to assert preservation of mention-only names.
- `journey-slack-mentions.ps1` sends real Ctrl+2 and Ctrl+Tab keystrokes. Read-only `Read-Control messages` observes the selected chat's rendered text; nonempty bubble rectangles prove layout.
- Assert all five exact strings and the named sender lines. Require the `report` link's target to remain `https://example.org/report`.
- Retain `before.messages.json` and `after.messages.json` intact. Their `sender_id` fields are transport metadata, not rendered text. Separately retain `before.rendered.json` and `after.rendered.json` with the entire snapshot except that non-rendered `sender_id` metadata; reject the five fixture Slack ids by name and any `<@` or `<https://` markup in these rendered snapshots and both UI Automation trees, so ordinary uppercase UI words cannot trip the check.
- Keep `before.png`, `after.png`, their UI Automation trees and state snapshots, keyboard actions, authenticated requests and `hub-proof.log` after cleanup.
- The standard `check-evidence.py` registry dispatcher calls `check_slack_mentions` from `check-slack-mentions-evidence.py`, just as neighbouring archive journeys register their validator functions. It validates retained messages, rendered snapshots, screenshots, UIA title and search/composer controls, selected Slack identity, fixture lookup provenance, no sends/archive/reactions, isolated stores and successful cleanup.

## Gotchas

- In the companion hub, `messageRows` uses `slackTeam.userName` for both the sender and `mentionNames`. That IGSH-687 lookup checks the paginated member map, then the in-memory names cache, then cached `users.info`, including guests and Slack Connect members. Unknown mentions stay markup for the client label/`@someone` fallback.
- In the client, unified hub history, quotes and thread pages use `hub.SlackUserNames` over normalized `SenderJID`/`SenderName` rows. Direct Slack history uses `slackUserLookup` over the installation's member cache. Both feed `setSlackMessageText` and `slack.convertMrkdwnLinks`.
- This journey fails without the hub-name adapter because its known and external raw mentions become `@someone`; it fails before the neutral fallback because the unknown id leaks. GitHub Actions must establish the runtime result.
- The member and info maps are synthetic hub outputs, not an execution of the companion Go hub's Slack API resolver. Its `TestSlackMentionNames` covers a guest absent from both member pages, a mention-only guest, and cached `users.info` reuse. No companion files are changed here.
- Read-only state and UI Automation supplement screenshots; inspect them before claiming visible behavior. This is loopback coverage, not proof of live Slack or the deployed hub.
- No local builds, tests, Windows app or PowerShell journey execution. Zig unit tests cover normalized cached sender names, late guests, Connect members, labels, invalid names, unknown ids and link offsets in CI.

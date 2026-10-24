# Slack mention display

## Sub-features

- `hub-named`: names already resolved by the hub stay unchanged.
- `neutral-fallback`: an unresolved user mention displays `@someone`, never a raw Slack user id.
- `labelled-mention`: a supplied mention label displays as `@Outside Guest` without exposing its id.
- `link-cleanup`: Slack link markup still displays its label and preserves the target URL.

## How to get to it (user POV)

- Open Messages with the unified hub configured and select the Slack account with Alt+1 in this single-account fixture.
- Use Ctrl+Tab to select Verification Mentions and read its three messages.
- Expect `@Fixture Peer hello`, `@someone joins later` and `@Outside Guest thanks report`.

## Driving it with PowerShell UI Automation

- Run `feature=slack-mentions` on GitHub Actions only. The registry includes the journey in the same Windows PR matrix as slack-sort.
- `SlackMentionsHandler` in `tools/verify-wazig/fake-hub.py` serves the single chat `slack:fixture-mentions:channel` through the authenticated unified hub.
- The wire messages contain `@Fixture Peer hello`, `<@UUNKNOWN99> joins later` and `<@UHIDDEN01|Outside Guest> thanks <https://example.org/report|report>`. No Slack user table is seeded.
- `journey-slack-mentions.ps1` sends real Alt+1 and Ctrl+Tab keystrokes. The read-only `Read-Control messages` helper observes the selected chat's rendered text; nonempty message bubble rectangles prove the messages have been laid out.
- Assert all three exact displayed strings, reject `UUNKNOWN99`, `UHIDDEN01` and raw markup across the rendered message snapshot, and require the `report` link's target to remain `https://example.org/report`. Also reject raw ids in the after UI Automation tree.
- Keep `before.png`, `after.png`, their UI Automation trees and state snapshots, `after.messages.json`, keyboard actions, authenticated bridge requests and `hub-proof.log` after cleanup.
- `evidence-slack-mentions.py` validates those retained artifacts, selected Slack identity, expected text and link, screenshots, no sends/archive/reactions, isolated stores and successful cleanup. The registry dispatches it through `check-evidence.py`.

## Gotchas

- The hub normally resolves mentions upstream. This fixture deliberately sends unresolved markup to cover the client fallback in `src/slack.zig:renderMrkdwnToken`, reached through `src/main.zig:setSlackMessageText` and `slack.convertMrkdwnLinks`.
- This journey is designed to fail on the parent implementation because it displays `UUNKNOWN99`. Its first commit contains only journey assets; the second adds the fallback and unit coverage. That red/green runtime result must be established by GitHub Actions, not inferred from this recipe.
- Read-only state and UI Automation supplement the screenshots; inspect the screenshots before claiming visible behavior. This is synthetic loopback coverage, not proof of a live Slack account or the deployed hub.
- No local builds, unit tests, Windows app or PowerShell journey execution on the development host. Zig unit tests next to the existing convertMrkdwn cases cover lookup hits, misses, labels and the no-table path in CI.

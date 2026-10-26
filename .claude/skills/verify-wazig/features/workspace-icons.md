# Workspace icon provider badges

## Sub-features

- `workspace-icon`: each Slack chat shows its workspace icon in the existing rounded provider badge, not in place of the main contact avatar.
- `workspace-cache`: the avatar worker fetches once per team, saves the exact image bytes in the avatar cache, and reloads that cache on subsequent starts. Existing avatar expiry and negative-cache rules apply.
- `letter-fallback`: while loading, on a missing icon or a failed request, Slack keeps the existing S badge. Telegram keeps T.
- `signal-mark`: Signal shows a #3A76F0 circle with a white speech bubble and dashed outline through the same provider-mark renderer as WhatsApp; disabling the badge switch restores S.
- `whatsapp-mark`: WhatsApp shows a #25D366 circle with a smooth white phone handset. The default-on `igsh_604_workspace_icons` switch restores all previous letters when disabled.

## How to get to it (user POV)

- Open Messages with the unified hub configured and choose All networks with Ctrl+1.
- Look at the small badge at the bottom right of each contact avatar. Slack uses the team image returned by authenticated GET `/v1/wazig/workspace-icon/<team>`; a 404 means no workspace icon.
- No toolbar, extra command, click-to-load step, font change or contact-avatar change is introduced.

## Driving it with PowerShell UI Automation

- Run `feature=workspace-icons`, or `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature workspace-icons`, on GitHub Actions only. Matching pull requests include this journey.
- The authenticated fake hub in `--workspace-icons` mode returns five synthetic rows: Amber Slack, Cobalt Slack, Delta WhatsApp, Empty Slack and Signal. Amber and Cobalt have generated PNG icons with distinct orange/blue solid colours and white A/C letters; Empty returns 404. All three icon endpoints must return 401 without a token.
- Drive Ctrl+1 through real keyboard input. Read-only control snapshots require exactly those identities and providers in that order. UI Automation resolves chat list 1016; bounded read-only list queries obtain its row height and scroll offset, and native client-to-screen coordinates locate each existing badge at the actual DPI.
- Save `workspace-icons-list.png` with state, visible chats and UIA snapshots. `check-workspace-icons.py --capture` crops `badge-icon-amber.png`, `badge-icon-cobalt.png`, `badge-icon-empty.png`, `badge-icon-whatsapp.png` and `badge-icon-signal.png` directly from that screenshot.
- Decode the screenshot pixels without additional dependencies. Require distinct expected icon colours over 55% of each Slack icon crop and visible white letter pixels; require the missing-icon badge to be mostly the existing dark grey with white letter pixels and none of the icon colours. Require WhatsApp green within 12 RGB levels over 35% of its whole crop plus white handset pixels. Require Signal brand blue over 35% plus white speech-bubble pixels. Signal blue uses a four-level RGB tolerance; cross-colour rejection also uses four levels between Signal and the nearby Cobalt blue. Preserve measured bounds and fractions in `workspace-icons-pixels.json`.
- `result.json` has `feature: workspace-icons` and remains failed until all pixel checks, isolation assertions and cleanup succeed. The surviving evidence validator recomputes the pixel checks, verifies each crop against the full screenshot, requires exactly one authenticated fetch per team plus the explicit 401 probes, and matches both successful PNG response hashes to files retained under `final-data/avatars`.

## Gotchas

- This proves the client contract using synthetic loopback data, not production hub deployment or real Slack workspaces. Inspect the screenshot and crops before claiming visible behavior.
- No Zig, Windows desktop, fixture server or test suite runs on the development host. Unit tests and the desktop journey execute only in GitHub CI.
- The journey proves cold fetch, disk persistence, missing-icon fallback and visible badges at the runner DPI. Restart reuse, transport-error fallback, switch-off letters and 100–200% scaling also require source/unit review; the journey does not claim to exercise every scale or a second launch.

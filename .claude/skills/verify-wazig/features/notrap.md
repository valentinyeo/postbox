# No empty sign-in traps

## Sub-features

- `startup-fallback`: saved Signal or Telegram with no hub chats falls back to the combined inbox after the first successful chat response. Linking belongs to the triage CLI on the hub, never an in-app login, QR or password screen.
- `every-view-escape-alt`: empty providers use the ordinary chat list and keyboard path. Esc clears search, then leaves an empty account view. Alt+2..9 selects saved positions; Alt+1, Alt+I and G then I reach the combined inbox.
- `retained-evidence`: save a screenshot, UI Automation tree and control state/chats for every registered view, plus the full source-to-target shortcut matrix.

## How to get to it (user POV)

- Link Signal and Telegram once through the triage CLI on the hub. Wazig only shows chats already on that hub.
- Open a provider with no chats: it is an empty chat list, not a sign-in screen. Press Esc to leave, or any assigned Alt+number to switch directly.
- Restart with an empty Signal or Telegram view saved: Messages opens the combined inbox instead.

## Driving it with PowerShell UI Automation

- Run feature=notrap on GitHub Actions only. run.ps1 starts fake-hub.py --notrap: two WhatsApp accounts and two Slack workspaces, two chats each; Signal and Telegram have no rows.
- Before launch, seed the isolated registry with InboxView=4 and AccountView=signal, retaining startup-seed.json. The same-profile fixture opt-in permits this preseeded subtree; production preferences remain absent.
- Start Wazig and require eight chats, a combined current_view, and neither Signal nor Telegram as the active provider. Retain startup.png with state/chats. Old code retains the empty Signal view and fails the startup chat-count wait rather than passing this journey.
- Read every position in view_order, including both empty providers. Select it through Alt+number, assert the exact provider/account/label and chat count, then save view-N.png and its control/UI Automation artifacts.
- From every view, focus search, type no-trap-search and press Esc to clear it. Press Esc again, require a responsive status and populated view, and prove Alt+2 reaches position one. Retain esc-N.state.json and escape-to-first-N.state.json.
- For every source view, return to that source before pressing each assigned Alt+number and assert the exact target current_view. Also test Alt+1, Alt+I and G then I from every source. Retain all transitions in transitions.json; the checker requires the complete Cartesian matrix, not just one navigation cycle.
- check-evidence.py delegates to check-notrap-evidence.py for startup, screenshot, empty-list, Escape, shortcut-matrix, request allowlist and cleanup evidence. Inspect the per-view screenshots from the exact GitHub commit before claiming visible success.

## Gotchas

- No provider login is simulated. The fixture deliberately returns only WhatsApp and Slack rows; the ordinary registered Signal and Telegram views remain empty.
- The saved view is seeded before the process starts, not selected after launch. A test that switches away first cannot prove startup recovery.
- This journey exercises every assigned position in its fixture, not nonexistent Alt positions. Alt+1, Alt+I and G then I are inbox aliases.
- Windows builds, Zig tests, PowerShell parsing/execution, old-binary regression runs and screenshot inspection belong to GitHub Actions. Source review on the development host is not runtime proof.

- Verify Ctrl+1 leaves the account unchanged, typed gi remains in search, an intervening key cancels G then I, and composer gi remains typed after a focus change. Retain screenshots and exact current_view.

- Capture each shortcut destination with state and screenshot. Retain a bounded, silent fixture-window recording and timestamped key ledger. Without ffmpeg.exe, retain 100 timestamped PNG frames at 5 fps for later encoding.

- Open and dismiss the owned message menu after G. Require a live prefix at menu entry, its cancellation, and no inbox switch on I.

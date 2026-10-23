# Maximized window startup

## Sub-features

- Every start opens the main MessagesZig window maximized with the taskbar available, not borderless fullscreen.
- Normal placement survives a user close and same-profile restart; the window returns maximized on the same monitor.
- The updater's exact --update-relaunch argument follows the same startup rule.

## How to get to it (user POV)

- Start Messages, including after installation: the main window opens maximized.
- Restore and resize through the window system menu, then close with Alt+F4.
- Reopen Messages or let an update relaunch it: it opens maximized again on its saved monitor. Restore retains the normal size.

## Driving it with PowerShell UI Automation

- Run feature=window on GitHub Actions. Reuse run.ps1's isolated cached-chat profile, process-local registry redirect and recorded session. Unlike other journeys, the harness must not maximize this window for the app.
- Wait for the main window and run the read-only doctor. Read IsZoomed, GetWindowPlacement and MonitorFromWindow/GetMonitorInfo through user32 P/Invoke. Save start-1.png before requiring zoomed=true; current unmodified startup uses SW_SHOW and fails with Main window not zoomed at start 1.
- After foreground ownership checks, use SendKeys Alt+Space, R to restore, then Alt+Space, S and arrow keys to shrink both dimensions. Require zoomed=false and a smaller normal rect; save restored.png.
- Send Alt+F4, require process exit, and relaunch the same ProcessStartInfo with WAZIG_VERIFY_RESTART set to the fixture ID. Immediately replace the session manifest PID and start ticks before waiting for the new window and running doctor. Require zoomed=true, the saved monitor and normal rect; save start-2.png.
- Close again with Alt+F4, wait for exit, append --update-relaunch and repeat the same-profile launch, manifest update and doctor. Require zoomed=true, the saved monitor and normal rect; save start-3.png.
- Retain window.json even on assertion failure: ordered start-1, restored, start-2 and start-3 observations contain zoomed values, HWND, PID/start ticks, monitor handle/rect/work area, normal rect, isolated root/ID and update-relaunch flag. check-evidence.py validates these observations, images, user-input log and side-effect/cleanup evidence.

## Gotchas

- Never use ShowWindow to manufacture a successful startup or restore. Restore, resize and close are real foreground-checked keyboard input; only read-only native calls observe placement.
- No provider login, network transport, new setting or borderless fullscreen is introduced. The fixture retains the same isolated registry across both restarts; production HKCU preferences stay absent.
- Cleanup reads the current session manifest and only closes or kills the recorded PID after ownership checks. Each previous PID must exit before relaunch; never kill by process name.
- A single-monitor hosted runner proves retained monitor identity, not physically moving between multiple displays. Windows execution, PowerShell parsing, baseline failure and screenshots must be checked on GitHub Actions; local static checks are not runtime proof.

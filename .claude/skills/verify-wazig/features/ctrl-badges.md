# Holding Ctrl numbers the top chats

## Sub-features

- `ctrl-badges-show`: while Ctrl is held, the first nine chat rows show a round number badge 1 to 9 next to the avatar.
- `ctrl-badges-jump`: Ctrl plus a number opens that row, and the badges stay while Ctrl is still held.
- `ctrl-badges-hide`: releasing Ctrl, or losing the window, removes every badge.

## How to get to it (user POV)

Hold Ctrl in the chat list. Numbers 1 to 9 appear on the first nine rows. Press Ctrl plus that number to open the chat. Let go of Ctrl and the numbers disappear.

## Driving it with PowerShell UI Automation

Run `feature=ctrl-badges` on GitHub Windows Actions. Matching pull requests also run it. `run.ps1` starts the unified fake hub in `ctrl-badges` mode with the search fixture, which gives six chat rows.

- **Idle:** `wazigctl status` reports `ctrl_badges.held` false with no badges, and `ctrl-before.png` is saved.
- **Held:** the journey sends a real Ctrl key-down behind the foreground-process guard and waits until `ctrl_badges` lists six numbered badge rectangles. `ctrl-held.png` is saved and each badge rectangle is compared with the idle screenshot: most pixels must change, one fill colour must dominate, and digit ink must exist in the middle.
- **Jump:** while Ctrl is still down, a real `3` key press must select the third chat row, and all six badges must stay.
- **Release:** a real Ctrl key-up must clear the badges. After the first chat is selected again, each badge rectangle must match the idle screenshot within 2 percent.

`check-ctrl-badges-evidence.py`, dispatched by `check-evidence.py`, requires the passed result, six numbered badges in row order in one column, the pixel measures, the four screenshots, the action log and isolation. Runtime and screenshot inspection are GitHub-only.

## Gotchas

- Badge rectangles are screen coordinates from `ctrl_badges.badges[].rect`; subtract the virtual screen origin before reading pixels.
- Ctrl is released in a `finally`, so a failed step cannot leave the key stuck on the runner.
- Synthetic client proof only. No `WM_COMMAND`, state setter or control-client mutation is used.

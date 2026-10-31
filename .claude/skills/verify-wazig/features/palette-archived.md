# Ctrl+K finds archived chats on every account

## Sub-features

- `palette-archived-all`: from the combined inbox, Ctrl+K finds archived WhatsApp, Telegram and Slack chats by full name.
- `palette-archived-views`: the same three archived names, plus every inbox chat, are found from every account view.
- `palette-archived-open`: Enter on an archived result selects that chat, loads its history and never unarchives it.
- `palette-archived-mark`: archived results keep the existing `  ·  Archived` label suffix.

## How to get to it (user POV)

Press Ctrl+K and type part of a contact or channel name. Chats on any connected account (WhatsApp, Slack, Signal, Telegram) appear, archived ones marked Archived, whichever view is on screen. Enter opens the chat; it stays archived.

## Driving it with PowerShell UI Automation

Run `feature=palette-archived` on GitHub Windows Actions. Matching pull requests also run it. `run.ps1` starts the unified fake hub with `--palette-archived`: the inbox has `Inbox WhatsApp Epsilon`, `Inbox WhatsApp Zeta` and Slack `Inbox Slack Delta`; the archived list has WhatsApp `Archived Person Alpha`, Telegram `Archived Telegram Beta` (`telegram:user:7001001`) and Slack `Archived Slack Gamma`. Every name is synthetic and unique, so a full-name query has one target row.

- **Wait signal:** the journey waits for the app's own `GET /v1/wazig/chats?archived=true` (the `archived_scan` job, about 20 timer ticks after start) in the hub request log, then allows the first query up to 30 seconds for the row; no fixed sleep proves anything.
- **a (combined inbox):** `Alt+I`, then Ctrl+K and the full name. `Read-ListLabels` reads the native `LB_GETTEXT` rows; each target row `<name>  ·  Archived` must appear exactly once at an index below `palette_max_rows` (10). `Inbox Slack Delta` is the positive control. A crowded `Archived` query is saved as informational evidence only.
- **b (every account view):** for each entry of `view_order` (`Alt+2`..`Alt+9`), the three archived names and the three inbox names must give a row. Screenshots, `.palette.json` row lists and state/UIA snapshots are saved per archived query.
- **c (Enter):** from the combined inbox and again from the chat's own view, Enter on each archived result must make `wazigctl status` report that chat as `selected` and archived, the hub must receive `GET /v1/wazig/messages?chat=<id>` after the keystroke, and no `POST /v1/wazig/archive` may mention it.
- **Failures:** the journey keeps going after a failed step and ends with one `failure.txt` listing every failed step with its suspected cause: `1` view gate, `2` people index drops ids without `@`, `3` below the fold, `4` identity mismatch, plus `unarchived by Enter`. `palette-archived.json` holds the full matrix.

`check-palette-archived-evidence.py`, dispatched by `check-evidence.py`, requires the passed result, the whole matrix, screenshots, the request ledger and isolation. Runtime and screenshot inspection are GitHub-only.

## Gotchas

- Palette labels are limited to 63 characters by `Read-ListLabels`; keep fixture names short.
- Never type into the palette without the foreground check in `Send-Keys`; Escape closes it between queries.
- The journey-only commit failed on the app before the fix (hub rows are now indexed with provider, account and view account, searched in every view and scored with the commands): expect steps `a-all-telegram`, `a-all-slack`, every non-WhatsApp view and the `c-*` steps to fail.
- This is synthetic client-contract proof, not live provider delivery. No `WM_COMMAND`, state setter or control-client mutation is used.

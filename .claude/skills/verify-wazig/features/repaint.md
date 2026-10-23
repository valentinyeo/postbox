# Repaint

## Sub-features

Cumulative window, message canvas and chat-list paint counts, including full-client updates. Idle redraw and non-selected incoming messages must not erase or fully repaint unchanged surfaces.

## How to get to it (user POV)

Open a chat and leave the app untouched while incoming messages reach another chat. Dispatch `feature=repaint` for synthetic provider traffic.

## Driving it with PowerShell UI Automation

PowerShell UI Automation runs `Invoke-RepaintJourney` with the unified `Start-FakeBridge -Repaint` fixture. Wait for Alpha history and selection, save before screenshots and `wazigctl status` paints, then observe 60 seconds with no input. The hub publishes an unchanged baseline every two seconds and one incoming Beta message every ten seconds. Read status again and retain `paints.json`, `before.chats.json`, `after.chats.json`, screenshots and UIA/state snapshots. Require Beta's incoming unread count to increase by at least five and Alpha to remain selected. Sum window_full, canvas_full and list_full deltas; fail above three with `repaint: <N> full repaints in 60 s, limit 3` in failure.txt.

## Gotchas

Counters are cumulative since process start; minute logging must not reset them. Partial row paints do not count as full list paints. No keys or mouse actions occur during the measurement. Windows Actions owns runtime proof; static map validation alone cannot prove absence of visible flicker. Inspect the screenshots and arrival snapshots, not only the exit status.

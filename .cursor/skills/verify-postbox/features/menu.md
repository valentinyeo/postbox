# Postbox menu entries

## Sub-features

<!-- entry: menu|contextMenu@437:43|src/directwrite_edit.zig -->
- `src/directwrite_edit.zig:437`: menu, @intCast(if (item[2]) win.MF_STRING | win.MF_ENABLED else win.MF_STRING | win.MF_GRAYED), item[1], item[0]

<!-- entry: menu|appendMessageMenuItem@13821:13|src/main.zig -->
- `src/main.zig:13821`: menu, flags, command, label

<!-- entry: menu|addReactionItems@13825:13|src/main.zig -->
- `src/main.zig:13825`: menu, win.MF_OWNERDRAW, reaction_row, null

<!-- entry: menu|addReactionItems@13827:5|src/main.zig -->
- `src/main.zig:13827`: Remove reaction

<!-- entry: menu|addReactionItems@13829:5|src/main.zig -->
- `src/main.zig:13829`: Copy text

<!-- entry: menu|addReactionItems@13830:5|src/main.zig -->
- `src/main.zig:13830`: Copy link address

<!-- entry: menu|openReactionMenu@13884:5|src/main.zig -->
- `src/main.zig:13884`: Reply Ctrl+Shift+R

<!-- entry: menu|openReactionMenu@13887:9|src/main.zig -->
- `src/main.zig:13887`: Send again

<!-- entry: menu|openReactionMenu@13888:9|src/main.zig -->
- `src/main.zig:13888`: Delete unsent message

<!-- entry: menu|openReactionMenu@13891:37|src/main.zig -->
- `src/main.zig:13891`: Delete for everyone

<!-- entry: menu|openQuickReactions@14034:13|src/main.zig -->
- `src/main.zig:14034`: menu, win.MF_OWNERDRAW, reaction_row, null

<!-- entry: menu|canvasProc@19552:33|src/main.zig -->
- `src/main.zig:19552`: Reply

<!-- entry: menu|canvasProc@19554:33|src/main.zig -->
- `src/main.zig:19554`: Copy selection

<!-- entry: menu|canvasProc@19555:33|src/main.zig -->
- `src/main.zig:19555`: Copy message text

<!-- entry: menu|canvasProc@19556:62|src/main.zig -->
- `src/main.zig:19556`: Copy transcript

<!-- entry: menu|canvasProc@19557:58|src/main.zig -->
- `src/main.zig:19557`: Copy link address

<!-- entry: menu|openChatMenu@19637:35|src/main.zig -->
- `src/main.zig:19637`: popup, win.MF_STRING, item.command, item.label.ptr

<!-- entry: menu|openChatMenu@19644:25|src/main.zig -->
- `src/main.zig:19644`: popup, win.MF_STRING, command_archive, wide.ptr

<!-- entry: menu|openChatMenu@19646:21|src/main.zig -->
- `src/main.zig:19646`: Cancel selection

## How to get to it (user POV)

Launch Postbox. Use the listed control or command.
Conditional entries require their matching provider state.

## Driving it with PowerShell UI Automation

Use the real Windows harness, never internal setters.
Read [the skill](../SKILL.md) before driving.
Match the source label through keyboard or UIA.
Inspect resulting screenshots and persisted side effects.
CLI entries use the listed postboxctl command.
Jobs need their user action and resulting state.

## Gotchas

An inventory entry does not prove execution.
The shared gate cannot scan Zig yet.
These are bounded scanner results, not semantic completeness.
Existing journeys document narrower proof and gaps.

# Postbox screen entries

## Sub-features

<!-- entry: screen|create@28:22|src/directwrite_edit.zig -->
- `src/directwrite_edit.zig:28`: 0, class_name, null, style, x, y, width, height, parent, id, instance, null

<!-- entry: screen|open@196:22|src/image_viewer.zig -->
- `src/image_viewer.zig:196`: MessagesImageViewer / Messages · Image

<!-- entry: screen|createTooltips@1647:20|src/main.zig -->
- `src/main.zig:1647`: tooltips_class32

<!-- entry: screen|openPlayerWindow@8447:22|src/main.zig -->
- `src/main.zig:8447`: MessagesVideoPlayer / Postbox · Video

<!-- entry: screen|showMentionPopup@11305:24|src/main.zig -->
- `src/main.zig:11305`: MessagesShortcodePopup

<!-- entry: screen|shortcodeUpdate@12786:24|src/main.zig -->
- `src/main.zig:12786`: MessagesShortcodePopup

<!-- entry: screen|showEmojiPickerWindow@13155:24|src/main.zig -->
- `src/main.zig:13155`: MessagesEmojiPicker

<!-- entry: screen|showEmojiPickerWindow@13181:24|src/main.zig -->
- `src/main.zig:13181`: LISTBOX

<!-- entry: screen|showPaletteWindow@16217:25|src/main.zig -->
- `src/main.zig:16217`: MessagesPalette

<!-- entry: screen|showPaletteWindow@16246:26|src/main.zig -->
- `src/main.zig:16246`: LISTBOX

<!-- entry: screen|openShortcutHelp@16590:22|src/main.zig -->
- `src/main.zig:16590`: MessagesShortcutHelp

<!-- entry: screen|mainProc@20039:32|src/main.zig -->
- `src/main.zig:20039`: LISTBOX

<!-- entry: screen|mainProc@20041:28|src/main.zig -->
- `src/main.zig:20041`: WacliMessageCanvas

<!-- entry: screen|main@22229:22|src/main.zig -->
- `src/main.zig:22229`: MessagesZig / Postbox v

<!-- entry: screen|openSlackThread@24971:25|src/main.zig -->
- `src/main.zig:24971`: MessagesThreadPane

<!-- entry: screen|openSlackThread@24981:59|src/main.zig -->
- `src/main.zig:24981`: MessagesThreadCheck

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

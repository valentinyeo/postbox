# Postbox endpoint entries

## Sub-features

<!-- entry: endpoint|control-pipe theme|src/control.zig -->
- `src/control.zig:52`: Local named pipe: theme <amoled>

<!-- entry: endpoint|control-pipe font|src/control.zig -->
- `src/control.zig:53`: Local named pipe: font <percent>

<!-- entry: endpoint|control-pipe status|src/control.zig -->
- `src/control.zig:54`: Local named pipe: status

<!-- entry: endpoint|control-pipe chats|src/control.zig -->
- `src/control.zig:55`: Local named pipe: chats [--json] [--messenger all|whatsapp|slack|telegram|signal] [--archived] [--all] [--limit N]

<!-- entry: endpoint|control-pipe search|src/control.zig -->
- `src/control.zig:56`: Local named pipe: search <text>

<!-- entry: endpoint|control-pipe view|src/control.zig -->
- `src/control.zig:57`: Local named pipe: view <N|inbox|all|whatsapp|slack|telegram|signal>

<!-- entry: endpoint|control-pipe select|src/control.zig -->
- `src/control.zig:58`: Local named pipe: select <id> [--provider whatsapp|slack|telegram|signal --account ID]

<!-- entry: endpoint|control-pipe messages|src/control.zig -->
- `src/control.zig:59`: Local named pipe: messages [<id>] [--limit N]

<!-- entry: endpoint|control-pipe archive|src/control.zig -->
- `src/control.zig:60`: Local named pipe: archive <id>

<!-- entry: endpoint|control-pipe unarchive|src/control.zig -->
- `src/control.zig:61`: Local named pipe: unarchive <id>

<!-- entry: endpoint|control-pipe archive-many|src/control.zig -->
- `src/control.zig:62`: Local named pipe: archive-many <id>...

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

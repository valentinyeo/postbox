# Postbox command entries

## Sub-features

<!-- entry: command|postboxctl theme|src/control.zig -->
- `src/control.zig:52`: postboxctl theme <amoled>

<!-- entry: command|postboxctl font|src/control.zig -->
- `src/control.zig:53`: postboxctl font <percent>

<!-- entry: command|postboxctl status|src/control.zig -->
- `src/control.zig:54`: postboxctl status

<!-- entry: command|postboxctl chats|src/control.zig -->
- `src/control.zig:55`: postboxctl chats [--json] [--messenger all|whatsapp|slack|telegram|signal] [--archived] [--all] [--limit N]

<!-- entry: command|postboxctl search|src/control.zig -->
- `src/control.zig:56`: postboxctl search <text>

<!-- entry: command|postboxctl view|src/control.zig -->
- `src/control.zig:57`: postboxctl view <N|inbox|all|whatsapp|slack|telegram|signal>

<!-- entry: command|postboxctl select|src/control.zig -->
- `src/control.zig:58`: postboxctl select <id> [--provider whatsapp|slack|telegram|signal --account ID]

<!-- entry: command|postboxctl messages|src/control.zig -->
- `src/control.zig:59`: postboxctl messages [<id>] [--limit N]

<!-- entry: command|postboxctl archive|src/control.zig -->
- `src/control.zig:60`: postboxctl archive <id>

<!-- entry: command|postboxctl unarchive|src/control.zig -->
- `src/control.zig:61`: postboxctl unarchive <id>

<!-- entry: command|postboxctl archive-many|src/control.zig -->
- `src/control.zig:62`: postboxctl archive-many <id>...

<!-- entry: command|appendMicrophones@15542:5|src/main.zig -->
- `src/main.zig:15542`: Microphone: System default (in use) / Microphone: System default

<!-- entry: command|appendMicrophones@15547:9|src/main.zig -->
- `src/main.zig:15547`: a, text, "", @intCast(command_mic_default + 1 + index)

<!-- entry: command|buildPaletteItems@15557:5|src/main.zig -->
- `src/main.zig:15557`: Search chats / Ctrl+F

<!-- entry: command|buildPaletteItems@15558:5|src/main.zig -->
- `src/main.zig:15558`: Compose message / C

<!-- entry: command|buildPaletteItems@15559:41|src/main.zig -->
- `src/main.zig:15559`: Slack threads like Slack for this account / On / Off

<!-- entry: command|buildPaletteItems@15560:5|src/main.zig -->
- `src/main.zig:15560`: Keyboard shortcuts / F1

<!-- entry: command|buildPaletteItems@15562:5|src/main.zig -->
- `src/main.zig:15562`: Dictate / Ctrl+D

<!-- entry: command|buildPaletteItems@15563:5|src/main.zig -->
- `src/main.zig:15563`: Record a voice note / Ctrl+Shift+M

<!-- entry: command|buildPaletteItems@15564:5|src/main.zig -->
- `src/main.zig:15564`: Dictation language: Automatic

<!-- entry: command|buildPaletteItems@15565:5|src/main.zig -->
- `src/main.zig:15565`: Dictation language: English

<!-- entry: command|buildPaletteItems@15566:5|src/main.zig -->
- `src/main.zig:15566`: Dictation language: German

<!-- entry: command|buildPaletteItems@15568:5|src/main.zig -->
- `src/main.zig:15568`: Playback speed: 1x

<!-- entry: command|buildPaletteItems@15569:5|src/main.zig -->
- `src/main.zig:15569`: Playback speed: 1.5x

<!-- entry: command|buildPaletteItems@15570:5|src/main.zig -->
- `src/main.zig:15570`: Playback speed: 2x

<!-- entry: command|buildPaletteItems@15571:5|src/main.zig -->
- `src/main.zig:15571`: Make text smaller / Ctrl+-

<!-- entry: command|buildPaletteItems@15572:5|src/main.zig -->
- `src/main.zig:15572`: Make text larger / Ctrl++

<!-- entry: command|buildPaletteItems@15573:5|src/main.zig -->
- `src/main.zig:15573`: Reset text size / Ctrl+0

<!-- entry: command|buildPaletteItems@15574:5|src/main.zig -->
- `src/main.zig:15574`: Text size: Small / 80%

<!-- entry: command|buildPaletteItems@15575:5|src/main.zig -->
- `src/main.zig:15575`: Text size: Default / 100%

<!-- entry: command|buildPaletteItems@15576:5|src/main.zig -->
- `src/main.zig:15576`: Text size: Large / 125%

<!-- entry: command|buildPaletteItems@15577:5|src/main.zig -->
- `src/main.zig:15577`: Text size: Larger / 150%

<!-- entry: command|buildPaletteItems@15578:5|src/main.zig -->
- `src/main.zig:15578`: Theme: Graphite

<!-- entry: command|buildPaletteItems@15579:5|src/main.zig -->
- `src/main.zig:15579`: Toggle unread chats / U

<!-- entry: command|buildPaletteItems@15580:5|src/main.zig -->
- `src/main.zig:15580`: Show combined inbox / Alt+1 / Alt+I

<!-- entry: command|buildPaletteItems@15581:5|src/main.zig -->
- `src/main.zig:15581`: Sort views

<!-- entry: command|buildPaletteItems@15586:9|src/main.zig -->
- `src/main.zig:15586`: Show {s} / Alt+{d}

<!-- entry: command|buildPaletteItems@15589:5|src/main.zig -->
- `src/main.zig:15589`: Unpin selected chat / Pin chat to top

<!-- entry: command|buildPaletteItems@15590:5|src/main.zig -->
- `src/main.zig:15590`: Toggle archived chats in this view: On / Toggle archived chats in this view: Off / Alt+A

<!-- entry: command|buildPaletteItems@15593:9|src/main.zig -->
- `src/main.zig:15593`: Archive {d} selected chats / Archive selected chats

<!-- entry: command|buildPaletteItems@15594:9|src/main.zig -->
- `src/main.zig:15594`: Cancel selection / Esc

<!-- entry: command|buildPaletteItems@15596:5|src/main.zig -->
- `src/main.zig:15596`: Pick the mention

<!-- entry: command|buildPaletteItems@15598:5|src/main.zig -->
- `src/main.zig:15598`: Replies: Slack style / Replies: WhatsApp style

<!-- entry: command|buildPaletteItems@15599:5|src/main.zig -->
- `src/main.zig:15599`: Replies: WhatsApp style / Replies: Slack style

<!-- entry: command|buildPaletteItems@15600:5|src/main.zig -->
- `src/main.zig:15600`: Show inbox chats / Show archived chats

<!-- entry: command|buildPaletteItems@15601:5|src/main.zig -->
- `src/main.zig:15601`: Unarchive selected chat / Archive selected chat / Ctrl+E

<!-- entry: command|buildPaletteItems@15602:5|src/main.zig -->
- `src/main.zig:15602`: Reply to selected message / Ctrl+Shift+R

<!-- entry: command|buildPaletteItems@15603:5|src/main.zig -->
- `src/main.zig:15603`: Resend failed message

<!-- entry: command|buildPaletteItems@15604:55|src/main.zig -->
- `src/main.zig:15604`: Delete message for everyone

<!-- entry: command|buildPaletteItems@15605:5|src/main.zig -->
- `src/main.zig:15605`: React to selected message / Ctrl+R

<!-- entry: command|buildPaletteItems@15606:5|src/main.zig -->
- `src/main.zig:15606`: Copy message text / Ctrl+C

<!-- entry: command|buildPaletteItems@15607:5|src/main.zig -->
- `src/main.zig:15607`: Copy message link

<!-- entry: command|buildPaletteItems@15608:5|src/main.zig -->
- `src/main.zig:15608`: Copy transcript

<!-- entry: command|buildPaletteItems@15609:42|src/main.zig -->
- `src/main.zig:15609`: Copy all transcripts

<!-- entry: command|buildPaletteItems@15610:5|src/main.zig -->
- `src/main.zig:15610`: Play or pause voice message / Ctrl+P

<!-- entry: command|buildPaletteItems@15611:5|src/main.zig -->
- `src/main.zig:15611`: Show or hide transcript / Ctrl+T

<!-- entry: command|buildPaletteItems@15612:5|src/main.zig -->
- `src/main.zig:15612`: Select next message / Alt+J

<!-- entry: command|buildPaletteItems@15613:5|src/main.zig -->
- `src/main.zig:15613`: Select previous message / Alt+K

<!-- entry: command|buildPaletteItems@15614:5|src/main.zig -->
- `src/main.zig:15614`: Jump to latest message / Alt+G

<!-- entry: command|buildPaletteItems@15615:5|src/main.zig -->
- `src/main.zig:15615`: Open links in message / Ctrl+O

<!-- entry: command|buildPaletteItems@15616:5|src/main.zig -->
- `src/main.zig:15616`: Next chat / Ctrl+Tab

<!-- entry: command|buildPaletteItems@15617:5|src/main.zig -->
- `src/main.zig:15617`: Previous chat / Ctrl+Shift+Tab

<!-- entry: command|buildPaletteItems@15618:5|src/main.zig -->
- `src/main.zig:15618`: Insert emoji

<!-- entry: command|buildPaletteItems@15619:5|src/main.zig -->
- `src/main.zig:15619`: Send a GIF

<!-- entry: command|buildPaletteItems@15620:45|src/main.zig -->
- `src/main.zig:15620`: Why are emoji black and white?

<!-- entry: command|buildPaletteItems@15621:5|src/main.zig -->
- `src/main.zig:15621`: Send message / Enter

<!-- entry: command|buildPaletteItems@15622:5|src/main.zig -->
- `src/main.zig:15622`: React to message: 👍 Like

<!-- entry: command|buildPaletteItems@15623:5|src/main.zig -->
- `src/main.zig:15623`: React to message: ❤️ Love

<!-- entry: command|buildPaletteItems@15624:5|src/main.zig -->
- `src/main.zig:15624`: React to message: 😂 Laugh

<!-- entry: command|buildPaletteItems@15625:5|src/main.zig -->
- `src/main.zig:15625`: React to message: 😮 Surprised

<!-- entry: command|buildPaletteItems@15626:5|src/main.zig -->
- `src/main.zig:15626`: React to message: 😢 Sad

<!-- entry: command|buildPaletteItems@15627:5|src/main.zig -->
- `src/main.zig:15627`: React to message: 🙏 Thanks

<!-- entry: command|buildPaletteItems@15628:5|src/main.zig -->
- `src/main.zig:15628`: Remove reaction

<!-- entry: command|buildPaletteItems@15629:5|src/main.zig -->
- `src/main.zig:15629`: Refresh / R

<!-- entry: command|buildPaletteItems@15630:5|src/main.zig -->
- `src/main.zig:15630`: Restart live sync / S

<!-- entry: command|buildPaletteItems@15631:5|src/main.zig -->
- `src/main.zig:15631`: Manage accounts

<!-- entry: command|buildPaletteItems@15632:5|src/main.zig -->
- `src/main.zig:15632`: Open video in external player

<!-- entry: command|buildPaletteItems@15633:5|src/main.zig -->
- `src/main.zig:15633`: Open image in Windows viewer

<!-- entry: command|buildPaletteItems@15634:5|src/main.zig -->
- `src/main.zig:15634`: Attach photo or file

<!-- entry: command|buildPaletteItems@15635:5|src/main.zig -->
- `src/main.zig:15635`: Connect Slack workspace

<!-- entry: command|buildPaletteItems@15636:5|src/main.zig -->
- `src/main.zig:15636`: Slack sign-in settings

<!-- entry: command|buildPaletteItems@15640:9|src/main.zig -->
- `src/main.zig:15640`: Disconnect Slack workspace: {s} / Disconnect Slack workspace

<!-- entry: command|buildPaletteItems@15642:5|src/main.zig -->
- `src/main.zig:15642`: Check for updates now

<!-- entry: command|buildPaletteItems@15643:35|src/main.zig -->
- `src/main.zig:15643`: Restart now to install update

<!-- entry: command|buildPaletteItems@15644:5|src/main.zig -->
- `src/main.zig:15644`: Quit Postbox / Q

<!-- entry: command|appendPalettePeople@15740:9|src/main.zig -->
- `src/main.zig:15740`: a, label, "", 0

<!-- entry: command|buildSortViewsItems@16129:9|src/main.zig -->
- `src/main.zig:16129`: Alt+{d}

<!-- entry: command|buildAccountsItems@16190:9|src/main.zig -->
- `src/main.zig:16190`: Add WhatsApp account (opens the pairing window)

<!-- entry: command|buildAccountsItems@16192:9|src/main.zig -->
- `src/main.zig:16192`: Reconnect WhatsApp

<!-- entry: command|buildAccountsItems@16194:13|src/main.zig -->
- `src/main.zig:16194`: Confirm: remove the WhatsApp account from this PC

<!-- entry: command|buildAccountsItems@16196:13|src/main.zig -->
- `src/main.zig:16196`: Remove WhatsApp account...

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

# Postbox setting entries

## Sub-features

<!-- entry: setting|PinnedChats|src/main.zig -->
- `src/main.zig:1890`: PinnedChats

<!-- entry: setting|DictationLanguage|src/main.zig -->
- `src/main.zig:1938`: DictationLanguage

<!-- entry: setting|InboxView|src/main.zig -->
- `src/main.zig:1955`: InboxView

<!-- entry: setting|EmojiRecents|src/main.zig -->
- `src/main.zig:1974`: EmojiRecents

<!-- entry: setting|Theme|src/main.zig -->
- `src/main.zig:1983`: Theme

<!-- entry: setting|FontScale|src/main.zig -->
- `src/main.zig:2072`: FontScale

<!-- entry: setting|GiphyApiKey|src/main.zig -->
- `src/main.zig:13410`: GiphyApiKey

<!-- entry: setting|HubToken|src/main.zig -->
- `src/main.zig:24483`: HubToken

<!-- entry: setting|WaBridgeKey|src/main.zig -->
- `src/main.zig:24536`: WaBridgeKey

<!-- entry: setting|WaBridgeUrl|src/main.zig -->
- `src/main.zig:24543`: WaBridgeUrl

<!-- entry: setting|Microphone|src/mic_choice.zig -->
- `src/mic_choice.zig:66`: Microphone

<!-- entry: setting|DisplayName|src/toast.zig -->
- `src/toast.zig:209`: DisplayName

<!-- entry: setting|IconUri|src/toast.zig -->
- `src/toast.zig:212`: IconUri

<!-- entry: setting|DeepgramApiKey|src/winhttp.zig -->
- `src/winhttp.zig:184`: DeepgramApiKey

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

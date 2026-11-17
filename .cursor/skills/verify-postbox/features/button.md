# Postbox button entries

## Sub-features

<!-- entry: button|handleAudioClick@6644:5|src/main.zig -->
- `src/main.zig:6644`: x < hit.left + px(a, 48)

<!-- entry: button|handleAudioClick@6648:5|src/main.zig -->
- `src/main.zig:6648`: x < hit.left + px(a, 96)

<!-- entry: button|advanceGifs@9138:9|src/main.zig -->
- `src/main.zig:9138`: hit.right <= hit.left or hit.bottom <= hit.top

<!-- entry: button|controlMessages@15418:17|src/main.zig -->
- `src/main.zig:15418`: hit.message_index != a.message_count - count + index

<!-- entry: button|layoutQuoteBody@18163:13|src/main.zig -->
- `src/main.zig:18163`: hit.left < hit.right and hit.top < hit.bottom

<!-- entry: button|chatsProc@18530:9|src/main.zig -->
- `src/main.zig:18530`: hiword(hit) != 0 or loword(hit) >= a.chat_count or win.SendMessageW(hwnd, win.LB_GETITEMRECT, loword(hit), @intCast(@intFromPtr(&rect))) == win.LB_ERR or win.PtInRect(&rect, point) == 0

<!-- entry: button|visibleLinkAt@18700:9|src/main.zig -->
- `src/main.zig:18700`: hit.message_index >= a.message_count or x < hit.rect.left or x >= hit.rect.right or y < hit.rect.top or y >= hit.rect.bottom

<!-- entry: button|visibleLinkAt@18702:9|src/main.zig -->
- `src/main.zig:18702`: hit.end <= message.quote.len and quoteFingerprint(message, hit.start, hit.end) == hit.fingerprint

<!-- entry: button|drawCompactQuote@18761:13|src/main.zig -->
- `src/main.zig:18761`: hit.left < hit.right and hit.top < hit.bottom

<!-- entry: button|canvasProc@19394:17|src/main.zig -->
- `src/main.zig:19394`: hit.right > hit.left and x >= hit.left and x < hit.right and y >= hit.top and y < hit.bottom

<!-- entry: button|canvasProc@19483:29|src/main.zig -->
- `src/main.zig:19483`: hit.message_index == down.message_index and hit.start == down.start and hit.end == down.end and hit.fingerprint == down.fingerprint and hit.message_index < a.message_count

<!-- entry: button|canvasProc@19486:33|src/main.zig -->
- `src/main.zig:19486`: hit.end <= quote.len and quoteFingerprint(quoted_message, hit.start, hit.end) == down.fingerprint and wordIsUrl(quote[hit.start..hit.end])

<!-- entry: button|mainProc@20042:32|src/main.zig -->
- `src/main.zig:20042`: BUTTON / Attach photo or file

<!-- entry: button|mainProc@20050:31|src/main.zig -->
- `src/main.zig:20050`: BUTTON / Voice

<!-- entry: button|mainProc@20051:29|src/main.zig -->
- `src/main.zig:20051`: BUTTON / Dictate

<!-- entry: button|mainProc@20052:31|src/main.zig -->
- `src/main.zig:20052`: BUTTON / 😊

<!-- entry: button|mainProc@20053:26|src/main.zig -->
- `src/main.zig:20053`: BUTTON / Send

<!-- entry: button|mainProc@20272:17|src/main.zig -->
- `src/main.zig:20272`: win.PtInRect(&close_rect, .{ .x = x, .y = y }) != 0

<!-- entry: button|mainProc@20303:17|src/main.zig -->
- `src/main.zig:20303`: win.PtInRect(&a.compose_pill, point) != 0

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

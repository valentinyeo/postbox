# Theme, saved text size and text comparison

Switch the app's colour scheme and control saved text scaling while retaining privately loaded IBM Plex Sans.

## Sub-features

- `appearance-theme`: Graphite uses the shared native design and persists the choice.
- `appearance-scale`: smaller/larger text follows the saved scale.
- `appearance-reset`: reset text size to the existing 100% default.
- `text-comparison`: compare the guarded native paragraph with installed Chrome using identical IBM Plex text and metrics; preserve paired full-window PNGs and 1x/3x paragraph crops.

## How to get to it (user POV)

- Ctrl+K → `Theme: Graphite`.
- Ctrl+K → `Make text smaller`, `Make text larger`, `Reset text size`.
- Ctrl+K → `Text size: Small`, `Text size: Default`, `Text size: Large`, or `Text size: Larger`.
- Ctrl+- / Ctrl++ / Ctrl+0 are the corresponding text-size shortcuts.
- Normal chats render with DirectWrite and the private font files beside Messages.exe. Text comparison is a separate verification fixture, not a product command or alternate renderer.

## Driving it with PowerShell UI Automation

Preconditions: doctor passes, baseline Graphite and IBM Plex Sans loaded from files beside Messages.exe.

- **Run:** dispatch `feature=appearance`; GitHub helper: `pwsh -NoProfile -File tools/verify-wazig/run.ps1 -Feature appearance`.
- **Before:** `before.png` captures Graphite without changing scale.
- **Choose:** `Invoke-PaletteCommand $session 'Theme: Graphite' action` opens Ctrl+K, waits for the owned `MessagesPalette` below the app window with the session PID, and checks the query in DirectWrite RichEdit `1064`; `action.png` shows the actual palette command before Enter.
- **Apply:** the helper presses Enter; wait for read-only status `theme=amoled`. The GUID-isolated registry's `Software/Messages/Theme` must be DWORD `1`. The final `after.png` shows Graphite at the restored scale.
- **Persistence:** cleanup captures `preferences.txt` before deleting only the temporary registry subtree. No provider state changes are permitted. After the theme check, type a synthetic `Scale probe` and read its UIA TextPattern font size. Choose `Make text larger` through the palette, require saved `FontScale=110`, and capture `text-larger.png`. Press Ctrl+0, require `FontScale=100`, and retain `text-scale.json` with the observed larger/reset values. Require the UIA font size to increase and then return exactly to baseline, retain those readings in `text-scale.json`, and clear the probe without sending. `after.png` is captured at the restored default scale; no registry setter drives the app.

- **Comparison run:** dispatch `feature=text-comparison`; matching PRs also run it. The helper adds `--verify-text-comparison`, loads the exact `src/verify_text.json` paragraph through the guarded production parser and waits for painted metrics to match the maximized UIA canvas. `compare-text.ps1` captures the native window, then `chrome-text.cjs` opens installed headed Chrome at device scale 1. Require DirectWrite at 96 DPI, body weight 400, heading weight 600, identical text/sizes/line heights and both fonts loaded.
- **Comparison evidence:** retain `text-metrics.json`, `native-capture.json`, `chrome.json`, `chrome.html`, bundled fonts/license, `wazig.png`, `chrome.png`, `text-comparison.png` and `*-paragraph{,-3x}.png`. `check-text-comparison.cjs` rechecks source/fixture contracts, exact font hashes, PNG dimensions/crop scaling, isolated side effects and cleanup.

- **Chat lists:** dispatch `feature=chat-lists` for six long bullets and two nested levels through the real Slack bubble renderer. At baseline and larger text size, the journey checks Regular body weight, measured marker/text columns, full bubble height, and screenshot foreground left edges within one pixel between the first text line and each continuation. See `features/chat-lists.md`.

- **Shared dictation:** the appearance journey replays checked-in recorded PCM in the isolated GitHub fixture. Real Ctrl+D expands the production pill to 116 logical pixels; screenshots require white foreground ink and raised grey fill. The production response parser must deliver the exact recorded transcript into the native composer. No paid request, microphone hardware, or acoustic recognition is claimed. `shared-design.png` is the actual 1920×1032 app region; `shared-design-mic.png` crops its active pill.

- **Presets:** choose all four palette rows. Capture each hosted viewport. Require scales 80, 100, 125, and 150. Measure composer text through UI Automation. Measure painted chat and list fonts. Check list geometry and chat bubble bounds. Restart the owned fixture at 150%. Verify its saved size and binary identity. Reset with Ctrl+0.

## Gotchas

- Graphite is enum value 1. Legacy choices migrate to Graphite.
- Composer `1032` and palette edit `1064` are native `RICHEDIT50W` DirectWrite hosts, not standard `EDIT` controls. Composer UIA TextPattern reads the real character font size; `recreateFonts` updates it through `WM_SETFONT`, and the host applies `EM_SETCHARFORMAT` to all existing text. Both theme and larger-text commands use the shared owner-descendant palette lookup, not desktop root children.
- Do not alter default font, default scale or production preferences for screenshots.
- Status plus persisted preference proves the selected setting; inspect the screenshot to prove repainting. The fixture does not prove every DPI. Screenshots require visual inspection. The actual laptop remains untested.

- Comparison screenshots require visual inspection; the validator does not assert Chrome/DirectWrite pixel equality, every glyph or every DPI. The workflow pins `0.0.526`, not the current product release, and the screenshot driver is runner-only infrastructure.
- Comparison source: `src/main.zig:15122` writes paragraph metrics and `src/main.zig:15874` loads the guarded fixture; `tools/verify-wazig/chrome-text.cjs:27` validates metrics.
- Source: `src/main.zig:1433` loads/clamps the saved scale, `src/main.zig:1739` changes it in ten-point steps, and `src/main.zig:13573` resets to 100%; theme commands are registered at `src/main.zig:12613`. `src/main.zig:15855` creates composer `1032`; `src/directwrite_edit.zig:25` creates the RichEdit host and `src/directwrite_edit.zig:117` updates its font.

# Caret

## Sub-features

- The message box shows a text caret that blinks while it has focus, with typed text in it.
- Checked on the AMOLED theme (pure black surround) and on the Green theme.
- A synthetic frame series control accepts a blinking series and rejects a steady one.

## How to get to it (user POV)

Open a chat and focus the bottom message entry box with Ctrl+K → Compose message, then type. The caret sits after the typed text and blinks at the Windows caret rate.

## Driving it with PowerShell UI Automation

Dispatch `feature=caret`; matching pull requests also run it. `Invoke-CaretJourney` opens the composer with the palette, types `abc` through SendKeys, waits for UI Automation to read the text back and settles for 900 ms. It then reads the system caret from outside the process with `GetGUIThreadInfo` (owner window, rectangle, focus) and `GetCaretBlinkTime`, and captures 24 screenshots of the composer text area about 130 ms apart with `CopyFromScreen`. Per frame it counts pixels clearly brighter than the field fill. Constant text pixels cancel out; the caret adds a fixed block of pixels on its on phases. The series is split at half the spread into on and off phases and the runs are counted. The same runs happen after `Theme: Green`.

`caret.json` keeps both themes with the caret owner, rectangle, blink time, per frame ink counts, timestamps and phase counts; `caret-<theme>-first.png`, `caret-<theme>-brightest.png` and a full screenshot are kept next to it. Each theme must show at least two on phases and two off phases. Failure contains `caret`.

## Gotchas

- The oracle needs a spread of at least eight pixels between the darkest and brightest frame, so a missing caret reads as zero phases rather than noise.
- The reading and the frames answer different questions: the reading says whether the system caret exists and where, the frames say whether a person would see it blink. Look at both when the journey fails.
- Typing resets the blink phase, so sampling starts only after the settle delay.

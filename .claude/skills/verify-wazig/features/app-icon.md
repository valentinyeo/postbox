# Postbox app icon

## Sub-features

- Approved red flag at 16, 24, 32, 48, 64, 128 and 256 pixels.
- Executable resources, window class large/small icons, taskbar and Alt+Tab.

## How to get to it (user POV)

- Launch Postbox and inspect its window, taskbar and Alt+Tab entry.

## Driving it with PowerShell UI Automation

- Run feature=app-icon on GitHub Actions, optionally with a published release tag.
- Extract resource 1 from the actual executable through LoadImageW at every ICO size.
- Draw actual class HICON handles and require red flag and grey pole pixels.
- Capture the taskbar and Alt+Tab; retain native icon PNGs and executable digest.
- Send WM_DPICHANGED at 144 DPI and capture the application's transition.
- Run the pixel regression against the original chat bubble as a red control.

## Gotchas

- Hosted shell DPI remains unchanged. The 144-DPI transition is synthetic; resource-24.png separately proves the 150% small icon. Do not describe this as a physical high-DPI monitor test.
- Launch only through the isolated fixture harness. Input belongs only to the hosted test desktop.
- Resource 1 also supplies the notification icon. Installer shortcuts resolve the executable icon; the update feed has no separate icon asset.

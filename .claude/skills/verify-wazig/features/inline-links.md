# Inline links

## Sub-features

- Body URLs open through Windows on the first and last wrapped fragments.
- Plain text does not launch a URL; Ctrl+O retains the body URL.
- A compact quoted-reply URL opens its complete stored target.

## How to get to it (user POV)

- Open the synthetic inline-links chat and click its wrapped URL.
- Click ordinary text, then open the body URL with Ctrl+O.
- Click the URL in the reply preview.

## Driving it with PowerShell UI Automation

- Run feature=inline-links on GitHub Actions. The fixture serves synthetic loopback URLs and never contacts a provider.
- SendInput uses the body's painted link rectangles and the compact reply line. The fixture-only receipt records the real ShellExecuteW result after the call.
- Capture each stage's messages, geometry, status, local requests, receipt history and screenshot before assertions. The baseline may fail at quoted-reply dispatch; earlier failures identify setup, body dispatch or browser availability instead.
- The evidence checker validates successful candidate runs. A Windows-accepted dispatch does not prove a browser page loaded. Loopback GETs may also come from previews and are not treated as browser proof.

## Gotchas

- No browser association, protocol, certificate or system registry is changed. A missing default browser makes dispatch inconclusive, not a quoted-link reproduction.
- The baseline covers the compact reply line, not the separate fallback quote block. The later feature must cover both presentations.
- Only synthetic fixture data and the owned verification profile are used. Inspect the screenshots and retained failure evidence before drawing conclusions.

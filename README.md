# Postbox

Postbox is a small native Windows messaging client written in Zig. WhatsApp through `wacli` is the first provider. Slack, Signal, and Telegram can be added behind the same interface later.

The interface uses Win32, Windows Imaging Component, and Windows shell thumbnail APIs. It does not embed Electron, WebView, .NET, Node, Java, or a browser engine.

## Existing installations

Existing installs keep messages, settings, and update support. The executable and storage paths stay unchanged. New installers and shortcuts use Postbox. Download from https://github.com/valentinyeo/postbox/releases/latest.

## Current features

- WhatsApp chats, messages, search, sending, archive, and unarchive through `wacli`
- Official WhatsApp group names from the local group metadata store
- Automatic image downloads, inline images, animated GIFs, and video thumbnails after download
- Colour emoji in chat names and message text; if the Windows text engine cannot draw them, messages fall back to monochrome emoji instead of stopping
- Click-to-download videos and click-to-open local attachments
- Per-message WhatsApp reactions from the message context menu
- Shared graphite theme, with saved-choice migration. Ctrl+K: **Theme: Graphite**; `postboxctl theme amoled`
- IBM Plex Sans bundled as a private application font
- Deepgram dictation uses a DPAPI-encrypted key, seeded from the user's saved environment variable `DEEPGRAM_API_KEY` and refreshed when it changes; the variable can then be removed

## Keyboard

| Key | Action |
| --- | --- |
| `Up` / `Down`, `J` / `K` | Move between chats |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Select next / previous message |
| `Enter`, `C` | Focus the composer |
| `Enter` | Send from the composer |
| `Shift+Enter` | Insert a new line |
| `Ctrl+F`, `/` | Search chats |
| `Up` / `Down` in search | Move through results |
| `Enter` in search | Open the selected chat and compose |
| `E` | Archive or unarchive the selected chat |
| `U` | Toggle unread chats |
| `Ctrl+D` | Dictation control |
| `R` | Refresh |
| `Ctrl+K` | Command menu |
| `Esc` | Return to the chat list |
| `Q` | Quit |

Use `Win+.` in the composer for the Windows emoji picker. Right-click a message bubble to react.

## Build

Install Zig 0.16, then run:

```powershell
zig build --release=small
```

## Shipping

Pull requests from the repository owner merge themselves once every check on
the head commit is green, and a successful `ci` run on `main` publishes the
release. No release pull request, no manual merge.

## Slack

Use Ctrl+K > **Connect Slack workspace** to sign in with Slack in your browser.
On first use, enter your Slack app's Client ID and its `xapp-` app-level token
with `connections:write` for Socket Mode. Existing saved app tokens are reused.
Change either value through Ctrl+K > **Slack sign-in settings**.

Create your app at https://api.slack.com/apps using `slack-app-manifest.yml`,
enable PKCE (this makes the app a public client and is not freely reversible),
Socket Mode and distribution for multiple workspaces, and register exactly
`http://localhost:53682/slack/oauth/callback` as an OAuth redirect URL. Approve
the requested user scopes in each workspace; administrator approval may be
needed. No client secret is used. Postbox listens only on `127.0.0.1:53682`
for one callback, for up to five minutes; a busy port fails without opening a
browser. The Client ID is saved per-user; tokens are DPAPI-encrypted in the
registry. Rotating user tokens refresh before expiry. If refresh fails, use
**Connect Slack workspace** to sign in again.

Ctrl+K > **Disconnect Slack workspace: <name>** removes that workspace and its
saved credentials without disconnecting other workspaces. The Client ID and
shared Socket Mode token remain available for the next connection.

Slack uses the native Web API and Socket Mode websocket, without a bundled
runtime. Channels and DMs appear in the sidebar, messages arrive live, text
replies (threads inline) and image attachments send, and file attachments
download to `%LOCALAPPDATA%\Messages\slack`.

The executable and IBM Plex font files are written to `zig-out\bin`. The app expects the official `wacli.exe` at `%LOCALAPPDATA%\Programs\wacli\wacli.exe`.

To enable Deepgram dictation without committing a key, seed it from the user's saved environment variable:

```powershell
[Environment]::SetEnvironmentVariable('DEEPGRAM_API_KEY', 'your-key', 'User')
```

At startup, Postbox reads the user's saved variable from `HKCU\Environment`, not the inherited process environment. It trims whitespace, stores the key encrypted with Windows DPAPI, and refreshes the stored key whenever the saved variable changes. The launch log confirms `startup: deepgram key saved to encrypted storage from environment` for a new key or `startup: deepgram key updated from environment` for a replacement. The variable can then be removed; later starts use the stored key.

param(
    [ValidateSet('search', 'navigation', 'drafts', 'palette', 'appearance', 'menus', 'passage-copy', 'reactions', 'paste-image', 'whatsapp-hub', 'hub', 'hub-archive', 'palette-archived', 'slack-sort', 'slack-archive', 'slack-threads', 'link-previews', 'views', 'workspace-icons', 'signal', 'telegram', 'notrap', 'repaint', 'archive', 'text-comparison', 'window', 'voice')][string]$Feature = 'search',
    [string]$Bin = 'zig-out/bin',
    [string]$Evidence = 'verification-evidence'
)
. "$PSScriptRoot/harness.ps1"
. "$PSScriptRoot/signal.ps1"
. "$PSScriptRoot/telegram.ps1"
. "$PSScriptRoot/notrap.ps1"
. "$PSScriptRoot/hub-archive.ps1"
. "$PSScriptRoot/palette-archived.ps1"
. "$PSScriptRoot/window.ps1"
. "$PSScriptRoot/repaint.ps1"
Assert-That ($env:GITHUB_ACTIONS -eq 'true') 'Verification runs only on GitHub Actions'
New-Item $Evidence -ItemType Directory -Force | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
@{ feature = $Feature; status = 'failed' } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'result.json')
Start-Transcript (Join-Path $Evidence 'run.log') | Out-Null
Assert-That (-not (Test-Path 'HKCU:\Software\Messages')) 'Hosted runner already has production app preferences'
$id = [Guid]::NewGuid().ToString()
$root = Join-Path $env:RUNNER_TEMP "wazig-verify-$id"
$local = Join-Path $root 'local'
$profile = Join-Path $root 'profile'
$messages = Join-Path $local 'Messages'
New-Item $messages, $profile -ItemType Directory -Force | Out-Null
$tag = '0000000000000526'
if ($Feature -notin @('whatsapp-hub', 'hub', 'hub-archive', 'palette-archived', 'slack-sort', 'slack-archive', 'slack-threads', 'link-previews', 'views', 'workspace-icons', 'signal', 'telegram', 'notrap', 'passage-copy', 'reactions', 'repaint', 'paste-image', 'voice')) {
    Set-Content (Join-Path $messages 'account-tag.txt') $tag -NoNewline
    @{ data = @(
        @{ jid = 'verify-alpha'; name = 'Verification Alpha'; kind = 'direct'; last_message_ts = '' },
        @{ jid = 'verify-beta'; name = 'Verification Beta'; kind = 'direct'; last_message_ts = '' }
    ) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $messages "chats-$tag.json")
}
if ($Feature -eq 'menus') {
    $cache = Join-Path $messages "msg-cache-$tag"
    New-Item $cache -ItemType Directory -Force | Out-Null
    $payload = @{ data = @{ messages = @(@{ MsgID = 'verify-menu-message'; Text = 'Synthetic menu verification'; SenderName = 'Verification Alpha'; FromMe = $false; Timestamp = '2026-01-01T12:00:00Z' }) } } | ConvertTo-Json -Depth 6 -Compress
    "wazig-msg-cache v2`n$tag`nverify-alpha`n$payload" | Set-Content (Join-Path $cache '82d67c3e0292bfc0.msg') -NoNewline
}
if ($Feature -eq 'hub-archive') {
    "120363000000000001@g.us`t1`t2026-10-10T10:00:00Z" | Set-Content (Join-Path $messages 'archive-state.txt')
    Copy-Item (Join-Path $messages 'archive-state.txt') (Join-Path $Evidence 'legacy-archive-state.txt')
}
if ($Feature -eq 'archive') {
    $provider = Join-Path $messages 'verification-provider.json'
    $seed = @{ data = @(
        @{ jid = 'verify-alpha@s.whatsapp.net'; name = 'Verification Alpha'; kind = 'direct'; last_message_ts = ''; archived = $false; unread = $false; unread_count = 0 },
        @{ jid = 'verify-beta@s.whatsapp.net'; name = 'Verification Beta'; kind = 'direct'; last_message_ts = ''; archived = $false; unread = $false; unread_count = 0 }
    ); messages = @{} }
    $seed | ConvertTo-Json -Depth 8 | Set-Content $provider
    $seed | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $messages "chats-$tag.json")
}
$exe = (Resolve-Path (Join-Path $Bin 'Messages.exe')).Path
foreach ($case in @('not-actions', 'not-isolated')) {
    $rejected = [Diagnostics.ProcessStartInfo]::new($exe)
    $rejected.UseShellExecute = $false
    $rejected.ArgumentList.Add('--verify-fixture')
    if ($case -eq 'not-actions') { $rejected.Environment['GITHUB_ACTIONS'] = 'false' }
    $null = $rejected.Environment.Remove('WAZIG_VERIFY_ROOT')
    $child = [Diagnostics.Process]::Start($rejected)
    try {
        Assert-That ($child.WaitForExit(10000)) "Unsafe fixture launch did not reject: $case"
        Assert-That ($child.ExitCode -ne 0) "Unsafe fixture launch succeeded: $case"
    } finally {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
    }
    Add-Content (Join-Path $Evidence 'launch-guards.log') "REJECTED: $case"
}
$ctl = (Resolve-Path (Join-Path $Bin 'wazigctl.exe')).Path
$start = [Diagnostics.ProcessStartInfo]::new($exe)
$start.UseShellExecute = $false
$start.RedirectStandardError = $true
$start.ArgumentList.Add('--verify-fixture')
if ($Feature -eq 'text-comparison') { $start.ArgumentList.Add('--verify-text-comparison') }
$start.Environment['WAZIG_VERIFY_ROOT'] = $root
$start.Environment['WAZIG_VERIFY_ID'] = $id
$start.Environment['LOCALAPPDATA'] = $local
$start.Environment['APPDATA'] = $local
$start.Environment['USERPROFILE'] = $profile
$start.Environment['USERNAME'] = "verify-$id"
foreach ($name in @('DEEPGRAM_API_KEY', 'OPENROUTER_API_KEY', 'OPENROUTER_MODEL', 'WAZIG_FAKE_VERSION', 'WA_BRIDGE_KEY', 'WAZIG_VERIFY_HUB_URL', 'WAZIG_VERIFY_HUB_KEY', 'WAZIG_HUB_URL', 'WAZIG_HUB_TOKEN', 'WAZIG_VERIFY_RESTART')) { $null = $start.Environment.Remove($name) }
$bridge = $null
if ($Feature -eq 'whatsapp-hub') {
    @{ id = '53200000000000000000000000000001'; provider = 'whatsapp'; account = '1111111111111111'; jid = 'personal:15550000001@s.whatsapp.net'; text = 'Synthetic adopted send'; file = ''; reply_to = 'personal:BASELINE'; state = 'queued'; queued_unix = 1 } | ConvertTo-Json -Compress | Set-Content (Join-Path $messages 'hub-1111111111111111-outbox.jsonl')
    $bridge = Start-FakeBridge $Evidence $root
    $start.Environment['WAZIG_VERIFY_HUB_URL'] = $bridge.url
    $start.Environment['WAZIG_VERIFY_HUB_KEY'] = 'fixture-key-not-a-secret'
}
if ($Feature -in @('hub', 'hub-archive', 'palette-archived', 'slack-sort', 'slack-archive', 'slack-threads', 'link-previews', 'views', 'workspace-icons', 'signal', 'telegram', 'notrap', 'passage-copy', 'reactions', 'repaint', 'paste-image', 'voice')) {
    $bridge = Start-FakeBridge $Evidence $root -Unified -SlackSort:($Feature -eq 'slack-sort') -SlackArchive:($Feature -eq 'slack-archive') -SlackThreads:($Feature -eq 'slack-threads') -LinkPreviews:($Feature -eq 'link-previews') -Views:($Feature -eq 'views') -WorkspaceIcons:($Feature -eq 'workspace-icons') -Signal:($Feature -eq 'signal') -Telegram:($Feature -eq 'telegram') -Notrap:($Feature -eq 'notrap') -PassageCopy:($Feature -eq 'passage-copy') -Reactions:($Feature -eq 'reactions') -HubArchive:($Feature -eq 'hub-archive') -PaletteArchived:($Feature -eq 'palette-archived') -MixedLid:($Feature -eq 'hub') -Repaint:($Feature -eq 'repaint') -PasteImage:($Feature -eq 'paste-image') -Voice:($Feature -eq 'voice')
    $start.Environment['WAZIG_HUB_URL'] = $bridge.url
    $start.Environment['WAZIG_HUB_TOKEN'] = (Get-Content (Join-Path $PSScriptRoot 'fake-wa-bridge.py') | Where-Object { $_.StartsWith('KEY = ') }).Split("'")[1]
}
if ($Feature -eq 'notrap') {
    $preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
    New-Item $preferences -Force | Out-Null
    New-ItemProperty $preferences -Name InboxView -Value 4 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $preferences -Name AccountView -Value 'signal' -PropertyType String -Force | Out-Null
    $saved = Get-ItemProperty $preferences
    @{ view = $saved.InboxView; account = $saved.AccountView; providers_without_rows = @('signal', 'telegram') } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'startup-seed.json')
    $start.Environment['WAZIG_VERIFY_RESTART'] = $id
}
try {
    $app = [Diagnostics.Process]::Start($start)
} catch {
    if ($null -ne $bridge) { $bridge.process.Kill(); $bridge.process.WaitForExit() }
    throw
}
$session = [ordered]@{
    id = $id; pid = $app.Id; startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    root = $root; evidence = $Evidence; exe = $exe; ctl = $ctl; username = "verify-$id"
    sha256 = (Get-FileHash $exe).Hash; commit = $env:GITHUB_SHA; feature = $Feature
}
if ($null -ne $bridge) {
    $session['bridge_pid'] = $bridge.process.Id
    $session['bridge_start_ticks'] = $bridge.process.StartTime.ToUniversalTime().Ticks.ToString()
    $session['bridge_exe'] = (Get-Process -Id $bridge.process.Id).Path
    $session['bridge_url'] = $bridge.url
}
$session | ConvertTo-Json | Set-Content (Join-Path $Evidence 'session.json')
$session = Read-Session $Evidence
try {
    $null = Wait-Until { $app.Refresh(); if ($app.HasExited) { throw "App exited: $($app.ExitCode)" }; $app.MainWindowHandle -ne [IntPtr]::Zero } 'main window'
    if ($Feature -ne 'window') { [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null }
    if ($Feature -in @('whatsapp-hub', 'hub', 'palette-archived', 'slack-sort', 'slack-archive', 'slack-threads', 'link-previews', 'views', 'workspace-icons', 'signal', 'telegram', 'notrap', 'passage-copy', 'reactions', 'repaint', 'paste-image', 'voice')) {
        $null = Wait-Until { (Read-Control $session status).chat_count -eq $(if ($Feature -eq 'signal') { 4 } elseif ($Feature -eq 'telegram') { 5 } elseif ($Feature -eq 'paste-image') { 4 } elseif ($Feature -in @('views', 'notrap')) { 8 } elseif ($Feature -eq 'workspace-icons') { 5 } elseif ($Feature -eq 'slack-sort') { 4 } elseif ($Feature -eq 'slack-threads') { 1 } elseif ($Feature -eq 'link-previews') { 4 } elseif ($Feature -eq 'palette-archived') { 3 } elseif ($Feature -eq 'hub') { 3 } else { 2 }) } 'hub chat list'
    }
    if ($Feature -eq 'whatsapp-hub') {
        $null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'adopted outbox acknowledged'
    }
    if ($Feature -eq 'hub-archive') {
        Wait-HubArchive $session $messages 1
    }
    Invoke-Doctor $session
    if ($Feature -eq 'search') {
        $launch = Get-Content (Join-Path $messages 'launch-log.txt') -Raw
        Assert-That ($launch.Contains('whatsapp backend: wacli (URL not configured)') -and -not $launch.Contains('message backend: hub')) 'Unconfigured hub did not select direct fallback'
        Add-Content (Join-Path $Evidence 'fallback-proof.log') 'hub no-url-direct-fallback PASS'
    }
    $window = Get-Window $session
    $compose = Get-Edit $window '1032'
    $search = Get-Edit $window '1008'
    Save-Screen $session before
    switch ($Feature) {
        window {
            $app = Invoke-WindowJourney $session $start $app
        }
        text-comparison {
            $metrics = Join-Path $messages 'text-metrics.json'
            $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'WacliMessageCanvas')
            $canvas = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
            Assert-That ($null -ne $canvas) 'Message canvas missing'
            $null = Wait-Until {
                if (-not (Test-Path $metrics)) { return $false }
                $painted = Get-Content $metrics -Raw | ConvertFrom-Json
                $bounds = $canvas.Current.BoundingRectangle
                $painted.canvas.width -eq [int]$bounds.Width -and $painted.canvas.height -eq [int]$bounds.Height
            } 'fixture paragraph painted at final window size'
            Copy-Item $metrics (Join-Path $Evidence 'text-metrics.json')
            Save-Screen $session after
            & "$PSScriptRoot/compare-text.ps1" -Session $session -Bin $Bin
        }
        whatsapp-hub {
            Invoke-WhatsAppHubJourney $session $messages
        }
        hub-archive {
            $app = Invoke-HubArchiveJourney $session $messages $start
        }
        palette-archived {
            Invoke-PaletteArchivedJourney $session
        }
        repaint {
            Invoke-RepaintJourney $session
        }
        voice {
            . "$PSScriptRoot/voice.ps1"
            Invoke-VoiceJourney $session $messages
        }
        hub {
            Invoke-WhatsAppHubJourney $session $messages
        }
        notrap {
            Invoke-NotrapJourney $session
        }
        telegram {
            Invoke-TelegramJourney $session $messages
        }
        paste-image {
            . "$PSScriptRoot/paste-image.ps1"
            Invoke-PasteImageJourney $session
        }
        signal {
            Invoke-SignalJourney $session $messages
        }
        slack-sort {
            Send-Keys $session '%1'
            $null = Wait-Until { (Read-Control $session status).view -eq 'slack' } 'Slack sidebar'
            $orders = [ordered]@{
                before = @('fixture-beta', 'fixture-gamma', 'fixture-alpha', 'fixture-unknown')
                after = @('fixture-alpha', 'fixture-beta', 'fixture-gamma', 'fixture-unknown')
                sent = @('fixture-gamma', 'fixture-alpha', 'fixture-beta', 'fixture-unknown')
            }
            foreach ($stage in $orders.Keys) {
                if ($stage -eq 'after') {
                    Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/live" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' | Out-Null
                    Add-Content (Join-Path $Evidence 'actions.log') 'provider: new Slack last message to fixture-alpha'
                } elseif ($stage -eq 'sent') {
                    Send-Keys $session '^{TAB}'
                    $null = Wait-Until { (Read-Control $session status).selected.id -eq 'fixture-gamma' } 'select Slack send target'
                    Invoke-PaletteCommand $session 'Compose message'
                    Send-Keys $session 'Synthetic Slack outgoing'
                    Send-Keys $session '{ENTER}'
                    $null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'Slack send acknowledged'
                }
                $expected = $orders[$stage]
                $null = Wait-Until {
                    $rows = (Read-Control $session chats).chats
                    ($rows.id -join ',') -eq ($expected -join ',')
                } "Slack $stage last message order"
                $rows = (Read-Control $session chats).chats
                Assert-That ($rows.Count -eq 4 -and @($rows | Where-Object provider -ne 'slack').Count -eq 0) 'Slack list identity changed'
                Assert-That ($rows[3].last_message_time -eq '') 'Unknown Slack time did not stay last'
                Save-Screen $session $stage
                $walk = @()
                $first = (Read-Control $session status).selected.id
                foreach ($step in 1..4) {
                    $selected = (Read-Control $session status).selected
                    $walk += $selected.id
                    if ($step -lt 4) { Send-Keys $session '^{TAB}' }
                }
                $offset = [Array]::IndexOf($expected, $first)
                Assert-That ($offset -ge 0) 'Selected chat is outside the Slack list'
                $visible = @(0..3 | ForEach-Object { $expected[($offset + $_) % 4] })
                Assert-That (($walk -join ',') -eq ($visible -join ',')) 'Keyboard navigation disagrees with visible Slack list order'
                $walk | ConvertTo-Json | Set-Content (Join-Path $Evidence "$stage.navigation.json")
                if ($stage -eq 'before') {
                    Send-Keys $session '^+{TAB}'
                    Send-Keys $session '^+{TAB}'
                    $null = Wait-Until { (Read-Control $session status).selected.id -eq 'fixture-gamma' } 'retain selection during incoming reorder'
                } elseif ($stage -eq 'after') {
                    Assert-That ($first -eq 'fixture-gamma') 'Incoming message changed selected Slack chat'
                }
                Hub-Pass $session "$stage-last-message-order"
            }
        }
        slack-archive {
            . "$PSScriptRoot/slack-archive.ps1"
            $restarted = @(Invoke-SlackArchiveJourney $session $messages $start)
            Assert-That ($restarted.Count -eq 1 -and $restarted[0] -is [Diagnostics.Process] -and
                $restarted[0].Id -eq $session.pid) 'Slack archive journey did not return the restarted process'
            $app = $restarted[0]
        }
        link-previews {
            . "$PSScriptRoot/link-previews.ps1"
            Invoke-LinkPreviewsJourney $session
        }
        slack-threads {
            . "$PSScriptRoot/slack-threads.ps1"
            $app = Invoke-SlackThreadsJourney $session $start
        }
        views {
            . "$PSScriptRoot/views.ps1"
            $app = Invoke-ViewsJourney $session $messages $start
        }
        workspace-icons {
            Invoke-WorkspaceIconsJourney $session
        }
        search {
            function Save-SearchPill([string]$Name) {
                $bounds = $search.Current.BoundingRectangle
                $dpi = [VerifyWindow]::GetDpiForWindow([IntPtr]$search.Current.NativeWindowHandle)
                Assert-That ($dpi -gt 0) 'Cannot measure search DPI'
                $height = [int]$bounds.Height + 2
                $diameter = [Math]::Min([Math]::Floor((56 * $dpi + 48) / 96), $height)
                $inset = [int][Math]::Ceiling($diameter / 2)
                $left = [int]$bounds.Left - $inset
                $top = [int]$bounds.Top - 1
                $width = [int]$bounds.Width + 2 * $inset
                $image = [Drawing.Bitmap]::new($width, $height)
                $graphics = [Drawing.Graphics]::FromImage($image)
                try {
                    $graphics.CopyFromScreen($left, $top, 0, 0, $image.Size)
                    $image.Save((Join-Path $Evidence "search-center-$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
                } finally {
                    $graphics.Dispose()
                    $image.Dispose()
                }
                return @{
                    pill = @(0, 0, $width, $height)
                    edit = @($inset, 1, ($width - $inset), ($height - 1))
                    screen_pill = @($left, $top, ($left + $width), ($top + $height))
                    uia_edit = @($bounds.Left, $bounds.Top, $bounds.Right, $bounds.Bottom)
                    dpi = $dpi; focused = $search.Current.HasKeyboardFocus; text = (Read-Edit $search)
                }
            }
            Invoke-PaletteCommand $session 'Compose message'
            $null = Wait-Until { -not $search.Current.HasKeyboardFocus -and (Read-Edit $search) -eq '' } 'empty unfocused search'
            $centerLayout = @{ placeholder = (Save-SearchPill placeholder) }
            Send-Keys $session '^f'
            Send-Keys $session 'Beta'
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 1 } 'one filtered chat'
            $state = Read-Control $session status
            Assert-That ($state.search -eq 'Beta' -and $state.selected.name -eq 'Verification Beta') 'Search did not select the matching fixture'
            Save-Screen $session after
            $null = Wait-Until { $search.Current.HasKeyboardFocus -and (Read-Edit $search) -eq 'Beta' } 'focused Beta search'
            $centerLayout['typed'] = Save-SearchPill typed
            $centerLayout | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Evidence 'search-center-layout.json')
            Send-Keys $session '{ESC}'
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 2 } 'search cleared'
            Send-Keys $session '^f'
            Send-Keys $session 'NoSuchFixture'
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 0 } 'empty search result'
            Save-Screen $session empty
            Send-Keys $session '{ESC}'
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 2 } 'baseline restored'
        }
        archive {
            Assert-That ((Read-Control $session status).selected.name -eq 'Verification Alpha') 'Archive fixture did not start on Alpha'
            Send-Keys $session '^e'
            $null = Wait-Until {
                $state = Read-Control $session status
                $row = (Get-Content $provider -Raw | ConvertFrom-Json).data | Where-Object name -eq 'Verification Alpha'
                $row.archived -and $state.pending_archives -eq 0 -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta'
            } 'Alpha archived through Ctrl+E'
            Invoke-PaletteCommand $session 'Show archived chats'
            $null = Wait-Until { $state = Read-Control $session status; $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Alpha' } 'Alpha in Archive'
            Invoke-PaletteCommand $session 'Archive and keep archived' action
            $keep = Join-Path $messages 'archive-state.txt'
            $null = Wait-Until {
                (Read-Control $session status).pending_archives -eq 0 -and (Get-Content $keep -Raw).Contains("verify-alpha@s.whatsapp.net`t1`t")
            } 'Keep archived persisted through palette'
            Copy-Item $keep (Join-Path $Evidence 'kept-archive-state.txt')
            Save-Screen $session kept
            Invoke-PaletteCommand $session 'Show inbox chats'
            $null = Wait-Until { $state = Read-Control $session status; -not $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta' } 'inbox before incoming delivery'
            $incoming = Get-Content $provider -Raw | ConvertFrom-Json
            $alpha = $incoming.data | Where-Object name -eq 'Verification Alpha'
            Assert-That ($alpha.archived -and $alpha.unread_count -eq 0) 'Unexpected pre-delivery provider state'
            $alpha.archived = $false
            $alpha.unread = $true
            $alpha.unread_count = 1
            $alpha.last_message_ts = '2026-10-10T11:00:00Z'
            $incoming.messages | Add-Member -NotePropertyName 'verify-alpha@s.whatsapp.net' -NotePropertyValue @{ data = @{ messages = @(
                @{ MsgID = 'verify-incoming-1'; ChatJID = 'verify-alpha@s.whatsapp.net'; FromMe = $false; SenderName = 'Verification Alpha'; Text = 'Verification incoming message'; Timestamp = $alpha.last_message_ts }
            ) } }
            $incoming | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'incoming-provider.json')
            Copy-Item (Join-Path $Evidence 'incoming-provider.json') "$provider.next"
            $null = Wait-Until {
                try { [IO.File]::Move("$provider.next", $provider, $true); return $true } catch [IO.IOException] { return $false }
            } 'atomic incoming provider delivery'
            Add-Content (Join-Path $Evidence 'actions.log') 'provider: incoming verify-incoming-1; archived=false; unread_count=1'
            $null = Wait-Until {
                $row = (Get-Content $provider -Raw | ConvertFrom-Json).data | Where-Object name -eq 'Verification Alpha'
                $state = Read-Control $session status
                $row.archived -and $row.unread_count -eq 1 -and $state.pending_archives -eq 0 -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Beta'
            } 'production merge re-archives kept Alpha after provider unarchive'
            Save-Screen $session inbox
            $chats = Read-Control $session chats
            Assert-That ($chats.total -eq 1 -and $chats.chats[0].name -eq 'Verification Beta') 'Alpha resurfaced in the main list'
            Invoke-PaletteCommand $session 'Show archived chats'
            $null = Wait-Until {
                $state = Read-Control $session status
                $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.name -eq 'Verification Alpha' -and $state.selected.archived -and $state.selected.unread -and $state.selected.unread_count -eq 1
            } 'kept Alpha remains in Archive with updated unread count'
            Save-Screen $session after
        }
        navigation {
            Send-Keys $session '^{TAB}'
            $null = Wait-Until { (Read-Control $session status).selected.name -eq 'Verification Beta' } 'next chat'
            Save-Screen $session after
            Send-Keys $session '^+{TAB}'
            $null = Wait-Until { (Read-Control $session status).selected.name -eq 'Verification Alpha' } 'previous chat'
        }
        drafts {
            Send-Keys $session 'Verification draft'
            Send-Keys $session '{HOME}{RIGHT 12}+{END}'
            Send-Keys $session 'text'
            $null = Wait-Until { (Read-Edit $compose) -eq 'Verificationtext' } 'Shift-arrow selection replacement'
            Send-Keys $session '^z'
            $null = Wait-Until { (Read-Edit $compose) -eq 'Verification draft' } 'native undo'
            Send-Keys $session '^y'
            $null = Wait-Until { (Read-Edit $compose) -eq 'Verificationtext' } 'native redo'
            Send-Keys $session '^a'
            Send-Keys $session 'Verification draft'
            Send-Keys $session '^{BACKSPACE}'
            $null = Wait-Until { (Read-Edit $compose) -eq 'Verification ' } 'Ctrl-Backspace word deletion'
            Send-Keys $session 'draft'
            Send-Keys $session '^a'
            Send-Keys $session '^c'
            Send-Keys $session '^v'
            $null = Wait-Until { (Read-Edit $compose) -eq 'Verification draft' } 'Ctrl-V pastes exactly once'
            Send-Keys $session '^a'
            Send-Keys $session '+{INSERT}'
            $null = Wait-Until { (Read-Edit $compose) -eq 'Verification draft' } 'Shift-Insert uses the guarded paste path'
            Save-Screen $session paste
            Send-Keys $session '{END}'
            Send-Keys $session '+{ENTER}'
            Send-Keys $session 'second'
            $null = Wait-Until { (Read-Edit $compose) -eq "Verification draft`nsecond" } 'Shift-Enter multiline input'
            Send-Keys $session '^a'
            Send-Keys $session 'Verification draft'
            Send-Keys $session '^{TAB}'
            Assert-That ((Read-Edit $compose) -eq '') 'Draft leaked to the next chat'
            Send-Keys $session '^+{TAB}'
            $null = Wait-Until { (Read-Edit $compose) -eq 'Verification draft' } 'restored per-chat draft'
            $draft = Join-Path $messages 'drafts.json'
            $null = Wait-Until { (Test-Path $draft) -and (Get-Content $draft -Raw).Contains('Verification draft') } 'persisted draft'
            Copy-Item $draft (Join-Path $Evidence 'drafts.json')
            Save-Screen $session after
            foreach ($theme in @('AMOLED black', 'Green')) {
                Send-Keys $session '^k'
                Send-Keys $session "Theme: $theme"
                Send-Keys $session '{ENTER}'
                $themeId = if ($theme -eq 'Green') { 'green' } else { 'amoled' }
                $null = Wait-Until { (Read-Control $session status).theme -eq $themeId } 'composer theme applied'
                foreach ($windowSize in @('wide', 'narrow')) {
                    if ($windowSize -eq 'wide') {
                        [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
                    } else {
                        [VerifyWindow]::ShowWindow($app.MainWindowHandle, 9) | Out-Null
                        $dpi = [VerifyWindow]::GetDpiForWindow($app.MainWindowHandle)
                        $width = [int][Math]::Floor((600 * $dpi + 48) / 96)
                        $height = [int][Math]::Floor((700 * $dpi + 48) / 96)
                        Assert-That ([VerifyWindow]::SetWindowPos($app.MainWindowHandle, [IntPtr]::Zero, 0, 0, $width, $height, 6)) 'Cannot resize narrow verification window'
                        $null = Wait-Until { [Math]::Abs((Get-Window $session).Current.BoundingRectangle.Width - $width) -le 1 } 'narrow native window'
                        $narrowBox = (Read-Control $session status).composer.box
                        Assert-That (($narrowBox.right - $narrowBox.left) -lt 360 * $dpi / 96) 'Composer did not reach narrow width'
                    }
                    Send-Keys $session '^a'
                    Send-Keys $session 'One'
                    $null = Wait-Until { (Read-Control $session status).composer.lines -eq 1 } 'one composer line'
                    $baseline = Assert-ComposerLayout $session "composer-$themeId-$windowSize-one" 1
                    Send-Keys $session '+{ENTER}'
                    Send-Keys $session 'Two'
                    Send-Keys $session '+{ENTER}'
                    Send-Keys $session 'Three'
                    $null = Wait-Until { (Read-Control $session status).composer.lines -eq 3 } 'three composer lines'
                    $null = Assert-ComposerLayout $session "composer-$themeId-$windowSize-multiline" 3 $baseline
                }
            }
        }
        palette {
            Send-Keys $session '^k'
            $palette = Get-PaletteWindow $session
            Send-Keys $session 'Keyboard shortcuts'
            $edit = Get-Edit $palette '1064'
            $list = Get-Edit $palette '1072'
            $null = Wait-Until { (Read-Edit $edit) -eq 'Keyboard shortcuts' -and (Read-ListCount $list) -eq 1 } 'positive palette row control'
            $positiveRows = @(Read-ListLabels $list)
            Assert-That ($positiveRows.Count -eq 1 -and $positiveRows[0] -eq 'Keyboard shortcuts') 'Positive palette row label is not readable'
            $positiveCount = $positiveRows.Count
            Send-Keys $session '^a'
            Send-Keys $session 'Status'
            $settled = @{ signature = $null; since = [DateTime]::UtcNow; rows = @() }
            $null = Wait-Until {
                if ((Read-Edit $edit) -ne 'Status') { return $false }
                $settled.rows = @(Read-ListLabels $list)
                $signature = ConvertTo-Json -InputObject $settled.rows -Compress
                if ($signature -cne $settled.signature) {
                    $settled.signature = $signature
                    $settled.since = [DateTime]::UtcNow
                    return $false
                }
                return ([DateTime]::UtcNow - $settled.since).TotalMilliseconds -ge 200
            } 'removed Status query and settled palette rows'
            $rows = $settled.rows
            $statusCount = @($rows | Where-Object { $_.Trim() -ieq 'Status' }).Count
            $removedCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, '1120')
            $sidebarCount = $window.FindAll([Windows.Automation.TreeScope]::Descendants, $removedCondition).Count
            @{ query = Read-Edit $edit; status_rows = $statusCount; rows = $rows; positive_query = 'Keyboard shortcuts'; positive_matches = $positiveCount; sidebar_status_controls = $sidebarCount } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'removed-status.json')
            Save-Screen $session removed-status
            Assert-That ($statusCount -eq 0 -and $sidebarCount -eq 0) 'Removed WhatsApp Status entry is still reachable'
            Send-Keys $session '^a'
            Send-Keys $session 'Keyboard shortcuts'
            $null = Wait-Until { (Read-Edit $edit) -eq 'Keyboard shortcuts' -and (Read-ListCount $list) -eq 1 } 'shortcut command restored'
            Save-Screen $session action
            Send-Keys $session '{ENTER}'
            $owner = Get-Window $session
            $null = Wait-Until {
                $condition = [Windows.Automation.AndCondition]::new(
                    [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesShortcutHelp'),
                    [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty, [int]$session.pid)
                )
                $owner.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
            } 'keyboard shortcut overlay'
            Save-Screen $session after
            Send-Keys $session '{ESC}'
        }
        passage-copy {
            . "$PSScriptRoot/passage-copy.ps1"
            Invoke-PassageCopyJourney $session
        }
        reactions {
            . "$PSScriptRoot/reactions.ps1"
            Invoke-ReactionsJourney $session
        }
        menus {
            . "$PSScriptRoot/menus.ps1"
            Invoke-Menus $session
        }
        appearance {
            Invoke-PaletteCommand $session 'Theme: Green' action
            $null = Wait-Until { (Read-Control $session status).theme -eq 'green' } 'green theme'
            $preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
            Assert-That ((Get-ItemProperty $preferences).Theme -eq 0) 'Theme preference was not saved'
            Assert-That ($null -eq (Get-ItemProperty $preferences).FontScale) 'Fresh fixture already has a saved scale'
            Send-Keys $session 'Scale probe'
            $textPattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
            $baselinePoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
            Assert-That ($baselinePoints -gt 0) 'Composer font size is not readable through UI Automation'
            Invoke-PaletteCommand $session 'Make text larger'
            $null = Wait-Until { (Get-ItemProperty $preferences).FontScale -eq 92 } 'larger text scale persisted'
            $larger = (Get-ItemProperty $preferences).FontScale
            $largerPoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
            Assert-That ($largerPoints -gt $baselinePoints) 'Larger text did not increase the UI Automation font size'
            Save-Screen $session text-larger
            Send-Keys $session '^0'
            $null = Wait-Until { (Get-ItemProperty $preferences).FontScale -eq 82 } 'default text scale restored'
            $resetPoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
            Assert-That ($resetPoints -eq $baselinePoints) 'Reset did not restore the UI Automation font size'
            @{ initial_saved = $false; larger = $larger; reset = (Get-ItemProperty $preferences).FontScale; baseline_points = $baselinePoints; larger_points = $largerPoints; reset_points = $resetPoints } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'text-scale.json')
            Send-Keys $session '^a{BACKSPACE}'
            $null = Wait-Until { (Read-Edit $compose) -eq '' } 'scale probe cleared'
            Save-Screen $session after
        }
    }
    $final = Read-Control $session status
    Assert-That ($final.pending_sends -eq 0 -and $final.pending_archives -eq 0 -and $final.sync -eq 'stopped') 'Unexpected transport side effect'
    Assert-That (-not (Test-Path (Join-Path $profile '.wacli'))) 'Provider store was created'
    Assert-That (-not (Test-Path (Join-Path $messages 'telegram'))) 'Telegram store was created'
    if ($Feature -eq 'archive') {
        Assert-That ((Get-Content $provider -Raw | ConvertFrom-Json).data.Count -eq 2) 'Fixture provider chat storage changed'
    } elseif ($Feature -notin @('whatsapp-hub', 'hub', 'hub-archive', 'palette-archived', 'slack-sort', 'slack-archive', 'slack-threads', 'link-previews', 'views', 'workspace-icons', 'signal', 'telegram', 'notrap', 'passage-copy', 'reactions', 'repaint', 'paste-image', 'voice')) {
        Assert-That ((Get-Content (Join-Path $messages "chats-$tag.json") -Raw | ConvertFrom-Json).data.Count -eq 2) 'Fixture chat storage changed'
    }
    $final | Add-Member -NotePropertyName production_preferences_absent -NotePropertyValue (-not (Test-Path 'HKCU:\Software\Messages'))
    $final | Add-Member -NotePropertyName whatsapp_store_absent -NotePropertyValue (-not (Test-Path (Join-Path $profile '.wacli')))
    $final | Add-Member -NotePropertyName telegram_store_absent -NotePropertyValue (-not (Test-Path (Join-Path $messages 'telegram')))
    Assert-That $final.production_preferences_absent 'Production app preferences were touched'
    $final | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'side-effects.json')
    "JOURNEY PASSED: $Feature" | Set-Content (Join-Path $Evidence 'result.txt')
} catch {
    "${Feature}: $($_.Exception.Message)" | Set-Content (Join-Path $Evidence 'failure.txt')
    try { Save-Screen $session failure } catch { $_ | Out-String | Add-Content (Join-Path $Evidence 'failure.txt') }
    throw
} finally {
    & "$PSScriptRoot/cleanup.ps1" -Evidence $Evidence
    $app.StandardError.ReadToEnd() | Set-Content (Join-Path $Evidence 'app.stderr.log')
    Stop-Transcript | Out-Null
}
$result = @{ feature = $Feature; status = 'passed' }
if ($Feature -eq 'views') {
    $result.checks = Get-Content (Join-Path $Evidence 'workspace-names.json') -Raw | ConvertFrom-Json -AsHashtable
}
$result | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'result.json')

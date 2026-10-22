param(
    [ValidateSet('search', 'navigation', 'drafts', 'palette', 'appearance', 'menus', 'whatsapp-hub', 'text-comparison')][string]$Feature = 'search',
    [string]$Bin = 'zig-out/bin',
    [string]$Evidence = 'verification-evidence'
)
. "$PSScriptRoot/harness.ps1"
Assert-That ($env:GITHUB_ACTIONS -eq 'true') 'Verification runs only on GitHub Actions'
New-Item $Evidence -ItemType Directory -Force | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
Start-Transcript (Join-Path $Evidence 'run.log') | Out-Null
Assert-That (-not (Test-Path 'HKCU:\Software\Messages')) 'Hosted runner already has production app preferences'
$id = [Guid]::NewGuid().ToString()
$root = Join-Path $env:RUNNER_TEMP "wazig-verify-$id"
$local = Join-Path $root 'local'
$profile = Join-Path $root 'profile'
$messages = Join-Path $local 'Messages'
New-Item $messages, $profile -ItemType Directory -Force | Out-Null
$tag = '0000000000000526'
if ($Feature -ne 'whatsapp-hub') {
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
foreach ($name in @('DEEPGRAM_API_KEY', 'OPENROUTER_API_KEY', 'OPENROUTER_MODEL', 'WAZIG_FAKE_VERSION', 'WA_BRIDGE_KEY', 'WAZIG_VERIFY_HUB_URL', 'WAZIG_VERIFY_HUB_KEY')) { $null = $start.Environment.Remove($name) }
$bridge = $null
if ($Feature -eq 'whatsapp-hub') {
    $bridge = Start-FakeBridge $Evidence $root
    $start.Environment['WAZIG_VERIFY_HUB_URL'] = $bridge.url
    $start.Environment['WAZIG_VERIFY_HUB_KEY'] = 'fixture-key-not-a-secret'
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
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    if ($Feature -eq 'whatsapp-hub') {
        $null = Wait-Until { (Read-Control $session status).chat_count -eq 2 } 'hub chat list'
    }
    Invoke-Doctor $session
    $window = Get-Window $session
    $compose = Get-Edit $window '1032'
    $search = Get-Edit $window '1008'
    Save-Screen $session before
    switch ($Feature) {
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
        search {
            Send-Keys $session '^f'
            Send-Keys $session 'Beta'
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 1 } 'one filtered chat'
            $state = Read-Control $session status
            Assert-That ($state.search -eq 'Beta' -and $state.selected.name -eq 'Verification Beta') 'Search did not select the matching fixture'
            Save-Screen $session after
            Send-Keys $session '{ESC}'
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 2 } 'search cleared'
            Send-Keys $session '^f'
            Send-Keys $session 'NoSuchFixture'
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 0 } 'empty search result'
            Save-Screen $session empty
            Send-Keys $session '{ESC}'
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 2 } 'baseline restored'
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
            Send-Keys $session 'Keyboard shortcuts'
            Save-Screen $session action
            Send-Keys $session '{ENTER}'
            $null = Wait-Until {
                $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesShortcutHelp')
                [Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children, $condition)
            } 'keyboard shortcut overlay'
            Save-Screen $session after
            Send-Keys $session '{ESC}'
        }
        menus {
            . "$PSScriptRoot/menus.ps1"
            Invoke-Menus $session
        }
        appearance {
            Send-Keys $session '^k'
            Send-Keys $session 'Theme: Green'
            Save-Screen $session action
            Send-Keys $session '{ENTER}'
            $null = Wait-Until { (Read-Control $session status).theme -eq 'green' } 'green theme'
            $preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
            Assert-That ((Get-ItemProperty $preferences).Theme -eq 0) 'Theme preference was not saved'
            Save-Screen $session after
        }
    }
    $final = Read-Control $session status
    Assert-That ($final.pending_sends -eq 0 -and $final.pending_archives -eq 0 -and $final.sync -eq 'stopped') 'Unexpected transport side effect'
    Assert-That (-not (Test-Path (Join-Path $profile '.wacli'))) 'Provider store was created'
    Assert-That (-not (Test-Path (Join-Path $messages 'telegram'))) 'Telegram store was created'
    if ($Feature -ne 'whatsapp-hub') {
        Assert-That ((Get-Content (Join-Path $messages "chats-$tag.json") -Raw | ConvertFrom-Json).data.Count -eq 2) 'Fixture chat storage changed'
    }
    $final | Add-Member -NotePropertyName production_preferences_absent -NotePropertyValue (-not (Test-Path 'HKCU:\Software\Messages'))
    $final | Add-Member -NotePropertyName whatsapp_store_absent -NotePropertyValue (-not (Test-Path (Join-Path $profile '.wacli')))
    $final | Add-Member -NotePropertyName telegram_store_absent -NotePropertyValue (-not (Test-Path (Join-Path $messages 'telegram')))
    Assert-That $final.production_preferences_absent 'Production app preferences were touched'
    $final | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'side-effects.json')
    "JOURNEY PASSED: $Feature" | Set-Content (Join-Path $Evidence 'result.txt')
} catch {
    $_ | Out-String | Set-Content (Join-Path $Evidence 'failure.txt')
    try { Save-Screen $session failure } catch { $_ | Out-String | Add-Content (Join-Path $Evidence 'failure.txt') }
    throw
} finally {
    & "$PSScriptRoot/cleanup.ps1" -Evidence $Evidence
    $app.StandardError.ReadToEnd() | Set-Content (Join-Path $Evidence 'app.stderr.log')
    Stop-Transcript | Out-Null
}

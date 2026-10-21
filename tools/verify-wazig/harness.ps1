$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class VerifyWindow {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)]
    public static extern IntPtr ReadText(IntPtr window, uint message, UIntPtr capacity, StringBuilder text, uint flags, uint timeout, out UIntPtr length);
}
'@

function Assert-That($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Wait-Until([scriptblock]$Check, [string]$Description) {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $value = & $Check
        if ($value) { return $value }
        [System.Threading.Thread]::Sleep(100)
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out: $Description"
}

function Read-Session([string]$Evidence) {
    Get-Content (Join-Path $Evidence 'session.json') -Raw | ConvertFrom-Json
}

function Get-App($Session) {
    $app = Get-Process -Id $Session.pid -ErrorAction Stop
    Assert-That ($app.StartTime.ToUniversalTime().Ticks.ToString() -eq $Session.startTicks) 'PID was reused'
    Assert-That ($app.Path -eq $Session.exe) 'Wrong executable path'
    Assert-That ((Get-FileHash $app.Path).Hash -eq $Session.sha256) 'Executable changed after launch'
    return $app
}

function Read-Control($Session, [string]$Command, [string[]]$Arguments = @()) {
    $start = [Diagnostics.ProcessStartInfo]::new($Session.ctl)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add($Command)
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $start.Environment['USERNAME'] = $Session.username
    $child = [Diagnostics.Process]::Start($start)
    $text = $child.StandardOutput.ReadToEnd()
    $errors = $child.StandardError.ReadToEnd()
    Assert-That ($child.WaitForExit(15000)) 'Read-only control client timed out'
    Assert-That ($child.ExitCode -eq 0) "Read-only control failed: $errors"
    $response = $text | ConvertFrom-Json
    Assert-That $response.ok 'Control response is not OK'
    return $response.result
}

function Get-Window($Session) {
    $null = Get-App $Session
    $condition = [Windows.Automation.AndCondition]::new(
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty, [int]$Session.pid),
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesZig')
    )
    $window = [Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children, $condition)
    Assert-That ($null -ne $window) 'App window is not up'
    Assert-That ($window.Current.ProcessId -eq $Session.pid) 'UI Automation found another process'
    Assert-That ($window.Current.ClassName -eq 'MessagesZig') 'Wrong window class'
    Assert-That ($window.Current.Name -eq 'Wazig Messages v0.0.526') 'Wrong build title'
    return $window
}

function Get-Edit($Window, [string]$Id) {
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $edit = $Window.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
    Assert-That ($null -ne $edit) "Missing stable edit AutomationId=$Id"
    return $edit
}

function Read-Edit($Edit) {
    $handle = [IntPtr]$Edit.Current.NativeWindowHandle
    Assert-That ($handle -ne [IntPtr]::Zero -and $Edit.Current.ClassName -eq 'Edit') 'Expected a native edit control'
    $text = [Text.StringBuilder]::new(65537)
    $length = [UIntPtr]::Zero
    $ok = [VerifyWindow]::ReadText($handle, 13, [UIntPtr]65537, $text, 2, 2000, [ref]$length)
    Assert-That ($ok -ne [IntPtr]::Zero) 'Read-only WM_GETTEXT timed out'
    return $text.ToString()
}

function Send-Keys($Session, [string]$Keys) {
    $app = Get-App $Session
    $foreground = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())
    if ($foreground.Current.ProcessId -ne $Session.pid) {
        [VerifyWindow]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
        $foreground = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetForegroundWindow())
    }
    Assert-That ($foreground.Current.ProcessId -eq $Session.pid) 'Refusing keyboard input to another app'
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Add-Content (Join-Path $Session.evidence 'actions.log') "keys: $Keys"
}

function Invoke-PaletteCommand($Session, [string]$Command, [string]$Capture = '') {
    Send-Keys $Session '^k'
    $palette = Wait-Until {
        $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'MessagesPalette')
        $windows = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children, $condition)
        foreach ($window in $windows) { if ($window.Current.ProcessId -eq $Session.pid) { return $window } }
    } 'owned command palette'
    $edit = Get-Edit $palette '1064'
    Send-Keys $Session $Command
    $null = Wait-Until { (Read-Edit $edit) -eq $Command } 'palette query'
    if ($Capture) {
        Save-Screen $Session $Capture
        "MessagesPalette | $($palette.Current.ProcessId) | $(Read-Edit $edit)" | Set-Content (Join-Path $Session.evidence "$Capture.palette.uia.txt")
    }
    Send-Keys $Session '{ENTER}'
}

function Save-Screen($Session, [string]$Name) {
    $window = Get-Window $Session
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $image = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($image)
    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $image.Save((Join-Path $Session.evidence "$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $image.Dispose()
    }
    $elements = $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
    $tree = @("$($window.Current.ClassName) | $($window.Current.Name)")
    foreach ($element in $elements) {
        $tree += "$($element.Current.AutomationId) | $($element.Current.ClassName) | $($element.Current.Name)"
    }
    $tree | Set-Content (Join-Path $Session.evidence "$Name.uia.txt")
    $state = Read-Control $Session status
    $state | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.state.json")
    if ($Session.feature -eq 'archive') {
        $arguments = if ($state.show_archived) { @('--archived') } else { @() }
        Read-Control $Session chats -Arguments $arguments | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.chats.json")
    }
}

function Invoke-Doctor($Session) {
    $window = Get-Window $Session
    $search = Get-Edit $window '1008'
    $compose = Get-Edit $window '1032'
    Assert-That $compose.Current.IsEnabled 'Fixture chat is not usable'
    $null = Read-Edit $search
    if ($Session.feature -eq 'whatsapp-hub') {
        $null = Wait-Until { (Read-Control $Session status).chat_count -eq 2 } 'hub baseline'
    }
    $status = Read-Control $Session status
    Assert-That ($status.version -eq '0.0.526') 'Wrong control build'
    Assert-That ($status.sync -eq 'stopped' -and -not $status.slack_connected) 'Provider unexpectedly connected'
    Assert-That ($status.pending_sends -eq 0 -and $status.pending_archives -eq 0) 'Unexpected pending writes'
    $status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'doctor.json')
    Write-Output 'DOCTOR PASSED: build, owned window, usable fixture and readable UI Automation edits'
}

function Start-FakeBridge([string]$Evidence, [string]$Root) {
    $portFile = Join-Path $Root 'bridge-port.txt'
    $start = [Diagnostics.ProcessStartInfo]::new((Get-Command python).Source)
    $start.UseShellExecute = $false
    $start.ArgumentList.Add((Join-Path $PSScriptRoot 'fake-wa-bridge.py'))
    $start.ArgumentList.Add('--port-file')
    $start.ArgumentList.Add($portFile)
    $start.ArgumentList.Add('--log')
    $start.ArgumentList.Add((Join-Path $Evidence 'bridge-requests.jsonl'))
    $process = [Diagnostics.Process]::Start($start)
    try {
        $null = Wait-Until { if ($process.HasExited) { throw 'Fake bridge exited' }; (Test-Path $portFile) -and (Get-Item $portFile).Length -gt 0 } 'fake bridge listening'
        $port = [int](Get-Content $portFile -Raw)
        return @{ process = $process; url = "http://127.0.0.1:$port" }
    } catch {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        throw
    }
}

function Read-BridgeRequests($Session) {
    $path = Join-Path $Session.evidence 'bridge-requests.jsonl'
    if (-not (Test-Path $path)) { return @() }
    return @(Get-Content $path | Where-Object { $_.EndsWith('}') } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Hub-Pass($Session, [string]$Gate) {
    $line = "whatsapp-hub $Gate PASS"
    Write-Output $line
    Add-Content (Join-Path $Session.evidence 'hub-proof.log') $line
}

function Invoke-WhatsAppHubJourney($Session, [string]$Messages) {
    $state = Read-Control $Session status
    Assert-That ($state.chat_count -eq 2 -and $state.selected.name -eq 'Verification Alpha' -and $state.selected.id -eq '15550000001@s.whatsapp.net' -and $state.selected.provider -eq 'whatsapp') 'Hub chats did not reach the sidebar'
    $requests = @(Read-BridgeRequests $Session)
    foreach ($path in @('/v1/accounts', '/v1/chats?')) {
        Assert-That (@($requests | Where-Object { $_.path.StartsWith($path) -and $_.status -eq 200 }).Count -gt 0) "Missing hub list request: $path"
    }
    Hub-Pass $Session chats
    Send-Keys $Session '^{TAB}'
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq '15550000002@s.whatsapp.net' } 'hub Beta selected'
    Send-Keys $Session '^+{TAB}'
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq '15550000001@s.whatsapp.net' } 'hub Alpha selected'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object id -eq 'BASELINE').Count -eq 1 } 'hub history visible'
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'history.messages.json')
    Save-Screen $Session history
    Hub-Pass $Session history
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/mark-read' -and $_.body.chat -eq '15550000001@s.whatsapp.net' -and $_.status -eq 200 }).Count -gt 0 } 'hub mark-read'
    Hub-Pass $Session mark-read
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/events' -and $_.last_event_id -eq '1' }).Count -gt 0 } 'SSE baseline resume'
    $headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
    Invoke-RestMethod "$($Session.bridge_url)/fixture/live" -Method Post -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object id -eq 'LIVE').Count -eq 1 } 'live SSE message visible'
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'live.messages.json')
    Save-Screen $Session live
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/events' -and $_.last_event_id -eq '2' }).Count -gt 0 } 'SSE live resume'
    Hub-Pass $Session live-sse-replay
    Send-Keys $Session '^k'
    Send-Keys $Session 'Compose message'
    Send-Keys $Session '{ENTER}'
    Send-Keys $Session 'Fixture outgoing'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/send' -and $_.duplicate -eq $true -and $_.status -eq 200 }).Count -eq 1 } 'deduplicated hub retry'
    $sends = @(Read-BridgeRequests $Session | Where-Object path -eq '/v1/send')
    Assert-That ($sends.Count -ge 2 -and @($sends.body.client_id | Select-Object -Unique).Count -eq 1) 'Send retry changed client_id'
    Assert-That (@($sends | Where-Object accepted -eq $true).Count -eq 1) 'Send delivered more than once'
    Assert-That ($sends[0].body.client_id -match '^[a-f0-9]{32}$') 'Send did not use the outbox id'
    $null = Wait-Until { (Read-Control $Session status).pending_sends -eq 0 } 'outbox acknowledged'
    Hub-Pass $Session send-client-id-dedupe
    $null = Wait-Until {
        $media = @(Read-BridgeRequests $Session | Where-Object { $_.path.StartsWith('/v1/media/') })
        @($media | Where-Object status -eq 202).Count -gt 0 -and @($media | Where-Object status -eq 200).Count -gt 0
    } 'pending then ready media'
    $null = Wait-Until { @(Get-ChildItem (Join-Path $Messages 'hub-media') -Filter '*.bin' | Where-Object Length -gt 0).Count -gt 0 } 'durable media cache'
    $ready = @(Read-BridgeRequests $Session | Where-Object { $_.path.StartsWith('/v1/media/') -and $_.status -eq 200 })[0]
    $cached = @(Get-ChildItem (Join-Path $Messages 'hub-media') -Filter '*.bin' | Where-Object { (Get-FileHash $_.FullName).Hash.ToLowerInvariant() -eq $ready.sha256 })
    Assert-That ($cached.Count -gt 0) 'Downloaded media bytes differ from bridge response'
    Hub-Pass $Session media-202-ready-cache
    Save-Screen $Session sent
    Send-Keys $Session '^k'
    Send-Keys $Session 'Archive selected chat'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/archive' -and $_.body.archived -eq $true -and $_.body.chat -eq '15550000001@s.whatsapp.net' -and $_.status -eq 200 }).Count -gt 0 } 'hub archive'
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 1 -and (Read-Control $Session status).pending_archives -eq 0 } 'archived chat removed'
    Hub-Pass $Session archive
    Save-Screen $Session after
    $requests = @(Read-BridgeRequests $Session | Where-Object { $_.method -ne 'SSE' })
    Assert-That (@($requests | Where-Object authorized -ne $true).Count -eq 0) 'Unauthenticated hub request'
    $launch = Get-Content (Join-Path $Messages 'launch-log.txt')
    Assert-That (@($launch | Where-Object { $_ -match 'whatsapp backend:' }).Count -eq 1) 'Backend was logged more than once'
    Assert-That (@($launch | Where-Object { $_ -match 'whatsapp backend: hub$' }).Count -eq 1) 'Hub was not selected'
    Assert-That (-not (($launch -join "`n").Contains('fixture-key-not-a-secret'))) 'Launch log leaked key'
    $preferences = "HKCU:\Software\MessagesVerification\$($Session.id)\Software\Messages"
    $registry = Get-Item $preferences
    Assert-That ($registry.GetValueKind('WaBridgeKey') -eq [Microsoft.Win32.RegistryValueKind]::Binary) 'Bridge key is not DPAPI storage'
    Hub-Pass $Session auth-dpapi-backend
}

function Assert-ComposerLayout($Session, [string]$Name, [int]$Lines, $Baseline = $null) {
    $state = Read-Control $Session status
    $layout = $state.composer
    Assert-That ($null -ne $layout -and $layout.lines -eq $Lines) "composer-one-box $Name wrong line count"
    $box = $layout.box
    Assert-That ($box.right -gt $box.left -and $box.bottom -gt $box.top) "composer-one-box $Name empty box"
    $names = @('attach', 'text', 'mic', 'dictate', 'emoji', 'send')
    $ids = @('1136', '1032', '1104', '1056', '1080', '1040')
    Assert-That ($layout.controls.Count -eq $names.Count) "composer-one-box $Name missing controls"
    $window = Get-Window $Session
    $handle = [IntPtr]$window.Current.NativeWindowHandle
    $client = [VerifyWindow+Rect]::new()
    $origin = [VerifyWindow+Point]::new()
    Assert-That ([VerifyWindow]::GetClientRect($handle, [ref]$client)) 'Cannot measure native client area'
    Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot measure native client origin'
    $dpi = [VerifyWindow]::GetDpiForWindow($handle)
    Assert-That ($dpi -gt 0) 'Cannot measure window DPI'
    $bottomInset = [Math]::Floor((11 * $dpi + 48) / 96)
    $iconInset = [Math]::Floor((4 * $dpi + 48) / 96)
    $boxBottom = $client.Bottom - $bottomInset
    Assert-That ($box.bottom -eq $boxBottom) "composer-one-box $Name box not anchored to native client bottom"
    $offsetX = $origin.X
    $offsetY = $origin.Y
    for ($i = 0; $i -lt $names.Count; $i++) {
        $rect = $layout.controls[$i]
        Assert-That ($rect.name -eq $names[$i]) "composer-one-box $Name unexpected control order"
        Assert-That ($rect.right -gt $rect.left -and $rect.bottom -gt $rect.top) "composer-one-box $Name empty $($rect.name)"
        Assert-That ($rect.left -ge $box.left -and $rect.right -le $box.right -and $rect.top -ge $box.top -and $rect.bottom -le $box.bottom) "composer-one-box $Name $($rect.name) outside box"
        $element = Get-Edit $window $ids[$i]
        Assert-That (-not $element.Current.IsOffscreen) "composer-one-box $Name hidden $($rect.name)"
        if ($rect.name -ne 'text') {
            Assert-That (-not [string]::IsNullOrWhiteSpace($element.Current.Name)) "composer-one-box $Name unnamed icon"
            Assert-That ($rect.bottom -eq $box.bottom - $iconInset) "composer-one-box $Name icon not anchored to box bottom"
        }
        $bounds = $element.Current.BoundingRectangle
        if ($rect.name -ne 'text') {
            Assert-That ([Math]::Abs($bounds.Bottom - ($origin.Y + $boxBottom - $iconInset)) -le 1) "composer-one-box $Name UIA icon not anchored to native bottom"
        }
        Assert-That ([Math]::Abs($bounds.Left - $offsetX - $rect.left) -le 1 -and [Math]::Abs($bounds.Top - $offsetY - $rect.top) -le 1 -and [Math]::Abs($bounds.Right - $offsetX - $rect.right) -le 1 -and [Math]::Abs($bounds.Bottom - $offsetY - $rect.bottom) -le 1) "composer-one-box $Name UIA mismatch $($rect.name)"
        for ($j = $i + 1; $j -lt $names.Count; $j++) {
            $other = $layout.controls[$j]
            Assert-That ($rect.right -le $other.left -or $other.right -le $rect.left -or $rect.bottom -le $other.top -or $other.bottom -le $rect.top) "composer-one-box $Name overlapping controls"
        }
        if ($null -ne $Baseline -and $rect.name -ne 'text') {
            $initial = $Baseline.controls[$i]
            Assert-That ($rect.left -eq $initial.left -and $rect.right -eq $initial.right -and $rect.top -eq $initial.top -and $rect.bottom -eq $initial.bottom) "composer-one-box $Name icon moved while growing"
        }
    }
    if ($null -ne $Baseline) {
        Assert-That ($box.bottom -eq $Baseline.box.bottom -and $box.top -lt $Baseline.box.top) "composer-one-box $Name box did not grow upwards"
    }
    $layout | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.layout.json")
    Save-Screen $Session $Name
    $message = "composer-one-box $Name lines=$Lines theme=$($state.theme) PASS"
    Add-Content (Join-Path $Session.evidence 'composer-one-box.log') $message
    Write-Host $message
    return $layout
}

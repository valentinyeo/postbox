. "$PSScriptRoot/paste-image.ps1"
Add-Type -Path "$PSScriptRoot/inbox-tooltip.cs"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class IconHintKeys {
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT { public uint message; public ushort low, high; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT mouse;
        [FieldOffset(0)] public KEYBDINPUT keyboard;
        [FieldOffset(0)] public HARDWAREINPUT hardware;
    }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION data; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr window);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    public static extern IntPtr Selection(IntPtr window, uint message, ref uint start, ref uint end, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    public static bool Key(ushort key, bool up) {
        INPUT input = new INPUT { type = 1, data = new INPUTUNION { keyboard = new KEYBDINPUT { vk = key, flags = up ? 2u : 0u } } };
        return SendInput(1, new INPUT[] { input }, Marshal.SizeOf<INPUT>()) == 1;
    }
    public static bool Wheel(int delta) {
        INPUT input = new INPUT { type = 0, data = new INPUTUNION { mouse = new MOUSEINPUT { mouseData = unchecked((uint)delta), flags = 0x0800 } } };
        return SendInput(1, new INPUT[] { input }, Marshal.SizeOf<INPUT>()) == 1;
    }
}
'@

function Icon-Key([int]$Key, [bool]$Up) {
    $process = Get-App $session
    $foreground = [VerifyWindow]::GetForegroundWindow()
    Assert-That ($foreground -eq $process.MainWindowHandle) 'Keyboard target is not the foreground app'
    Assert-That ([IconHintKeys]::Key([uint16]$Key, $Up)) 'SendInput failed'
    Add-Content (Join-Path $session.evidence 'actions.log') "icon-key: $Key up=$Up"
}

function Icon-Selection {
    $first = [uint32]0
    $last = [uint32]0
    $result = [UIntPtr]::Zero
    $handle = [IntPtr]$compose.Current.NativeWindowHandle
    $ok = [IconHintKeys]::Selection($handle, 0x00B0, [ref]$first, [ref]$last, 2, 2000, [ref]$result)
    Assert-That ($ok -ne [IntPtr]::Zero) 'Composer selection read timed out'
    return @{ start = $first; end = $last }
}

function Icon-Snapshot([string]$Name) {
    $process = Get-App $session
    $state = Read-Control $session status
    Assert-That ($state.version -ceq $session.expected_version) 'Version differs'
    Assert-That ($state.voice_recording.microphone_entries -eq 0) 'Voice capture reached microphone'
    Assert-That ($state.dictation.microphone_entries -eq 0 -and $state.dictation.transcription_attempts -eq 0) 'Dictation reached microphone or service'
    @{ pid = $process.Id; start_ticks = $session.startTicks; exe = $process.Path; sha256 = $session.sha256; commit = $session.commit; state = $state; draft = (Read-Edit $compose); selection = (Icon-Selection) } |
        ConvertTo-Json -Depth 16 | Set-Content (Join-Path $session.evidence "$Name.icon.json")
    Save-Screen $session $Name
    $requests = @(Read-BridgeRequests $session)
    ConvertTo-Json -InputObject $requests -Depth 16 | Set-Content (Join-Path $session.evidence "$Name.requests.json")
    return $state
}

function Icon-Popup {
    $begin = [Diagnostics.Stopwatch]::GetTimestamp()
    $first = @([VerifyInboxTooltip]::Tools($session.pid))
    Assert-That ($first.Count -eq 1) 'Tooltip window count changed'
    $tip = [VerifyMenus]::Find($session.pid, 'tooltips_class32')
    $text = ''
    $bounds = $null
    if ($tip -ne [IntPtr]::Zero) {
        $bounds = [VerifyMenus]::Bounds($tip)
        $text = Read-EditText $tip
    }
    $last = @([VerifyInboxTooltip]::Tools($session.pid))
    $endTip = [VerifyMenus]::Find($session.pid, 'tooltips_class32')
    $endText = if ($endTip -ne [IntPtr]::Zero) { Read-EditText $endTip } else { '' }
    $end = [Diagnostics.Stopwatch]::GetTimestamp()
    Assert-That ($last.Count -eq 1 -and $first[0].hwnd -eq $last[0].hwnd -and $first[0].visible -eq $last[0].visible -and $tip -eq $endTip -and $text -ceq $endText -and $first[0].visible -eq ($tip -ne [IntPtr]::Zero)) 'Tooltip observation changed during native reads'
    if ($tip -ne [IntPtr]::Zero) {
        Assert-That (($first[0].current | ConvertTo-Json -Compress) -ceq ($last[0].current | ConvertTo-Json -Compress)) 'Tooltip target changed during native reads'
    }
    return @{ visible = ($tip -ne [IntPtr]::Zero); hwnd = $tip.ToInt64(); text = $text; bounds = if ($null -eq $bounds) { @() } else { @($bounds.Left, $bounds.Top, $bounds.Right, $bounds.Bottom) }; ticks = $end; begin_ticks = $begin; end_ticks = $end; frequency = [Diagnostics.Stopwatch]::Frequency; tooltips = $last; first_tools = $first }
}

$script:hoverSequence = 0
function Icon-FreshHover([string]$Id, [int]$AnchorX = 0, [int]$AnchorY = 0) {
    $evidence = Get-Content (Join-Path $session.evidence "hover-$Id.json") -Raw | ConvertFrom-Json
    $tool = $evidence.tooltips[0].current
    $screen = @($evidence.owner_rect)
    $clientOrigin = @()
    if (($tool.flags -band 1) -eq 0) {
        $client = [VerifyWindow+Point]::new()
        Assert-That ([VerifyWindow]::ClientToScreen([IntPtr][long]$tool.owner, [ref]$client)) 'Tool owner origin unavailable'
        $clientOrigin = @($client.X, $client.Y)
        $screen = @(($client.X + $tool.rect[0]), ($client.Y + $tool.rect[1]), ($client.X + $tool.rect[2]), ($client.Y + $tool.rect[3]))
    }
    $neutral = [VerifyWindow+Point]::new()
    $neutral.X = 4; $neutral.Y = 4
    Assert-That ([VerifyWindow]::ClientToScreen([IntPtr](Get-App $session).MainWindowHandle, [ref]$neutral)) 'Neutral origin unavailable'
    [VerifyMenus]::Hover($session.pid, $neutral.X, $neutral.Y)
    if ($AnchorX -ne 0 -or $AnchorY -ne 0) { [VerifyMenus]::Hover($session.pid, $AnchorX, $AnchorY) }
    $reset = Wait-Until { $value = Icon-Popup; if (-not $value.visible) { return ,$value } } 'hidden tooltip reset'
    $cursor = [IconHintKeys+POINT]::new()
    Assert-That ([IconHintKeys]::GetCursorPos([ref]$cursor)) 'Cursor position unavailable'
    $cursorWindow = [IconHintKeys]::WindowFromPoint($cursor)
    $cursorPid = [uint32]0
    [VerifyWindow]::GetWindowThreadProcessId($cursorWindow, [ref]$cursorPid) | Out-Null
    Assert-That ($cursorPid -eq $session.pid -and -not ($cursor.x -ge $screen[0] -and $cursor.x -lt $screen[2] -and $cursor.y -ge $screen[1] -and $cursor.y -lt $screen[3])) 'Reset cursor still hits target'
    $entryBegin = [long]0; $entryEnd = [long]0
    [VerifyMenus]::Hover($session.pid, [int]$evidence.x, [int]$evidence.y, [ref]$entryBegin, [ref]$entryEnd)
    $entered = [IconHintKeys+POINT]::new()
    Assert-That ([IconHintKeys]::GetCursorPos([ref]$entered)) 'Target cursor position unavailable'
    $enteredWindow = [IconHintKeys]::WindowFromPoint($entered)
    $enteredPid = [uint32]0
    [VerifyWindow]::GetWindowThreadProcessId($enteredWindow, [ref]$enteredPid) | Out-Null
    Assert-That ($enteredPid -eq $session.pid -and $enteredWindow.ToInt64() -eq $evidence.owner -and $entered.x -ge $screen[0] -and $entered.x -lt $screen[2] -and $entered.y -ge $screen[1] -and $entered.y -lt $screen[3]) 'Target cursor hit changed'
    $first = Wait-Until {
        $value = Icon-Popup
        if ($value.visible -and $value.text -ceq $evidence.expected -and ($value.tooltips[0].current | ConvertTo-Json -Compress) -ceq ($tool | ConvertTo-Json -Compress)) { return ,$value }
    } "fresh tooltip $Id"
    $script:hoverSequence++
    return @{ hover_id = $Id; sequence = $script:hoverSequence; pid = $session.pid; start_ticks = $session.startTicks; exe = $session.exe; sha256 = $session.sha256; commit = $session.commit; frequency = [Diagnostics.Stopwatch]::Frequency; tooltip_hwnd = $first.hwnd; autopop_ms = $first.tooltips[0].autopop_ms; text = $first.text; tool = $tool; target_hwnd = $evidence.owner; target_screen_rect = $screen; client_origin = $clientOrigin; reset = $reset; reset_cursor = @{ x = $cursor.x; y = $cursor.y; owner_hwnd = $cursorWindow.ToInt64(); owner_pid = $cursorPid }; target_move = @{ x = $entered.x; y = $entered.y; requested_x = $evidence.x; requested_y = $evidence.y; owner_hwnd = $enteredWindow.ToInt64(); owner_pid = $enteredPid; input_begin_ticks = $entryBegin; input_end_ticks = $entryEnd }; first_visible = $first }
}

function Icon-Transition([string]$Name, [string]$Id, [scriptblock]$Action, [string]$AfterText = '', [int]$AnchorX = 0, [int]$AnchorY = 0) {
    $generation = $null; $before = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $generation = Icon-FreshHover $Id $AnchorX $AnchorY
        $before = Icon-Popup
        $now = [Diagnostics.Stopwatch]::GetTimestamp()
        $f = [bigint]$generation.frequency; $a = [bigint]$generation.autopop_ms
        $reserve = [bigint]::Min([bigint]500 * $f, [bigint]::Min([bigint]3000 * $f, $a * $f))
        if ($before.visible -and ($before.tooltips[0].current | ConvertTo-Json -Compress) -ceq ($generation.tool | ConvertTo-Json -Compress) -and 2000 * ([bigint]$now - $generation.target_move.input_begin_ticks) + $reserve -lt $a * $f) { break }
        $generation = $null
    }
    Assert-That ($null -ne $generation) "$Name could not establish fresh hover"
    $transition = [Diagnostics.Stopwatch]::GetTimestamp()
    Assert-That (2000 * ([bigint]$transition - $generation.target_move.input_begin_ticks) + $reserve -lt $a * $f) "$Name hover became too old"
    $actionBegin = [Diagnostics.Stopwatch]::GetTimestamp()
    & $Action
    $actionEnd = [Diagnostics.Stopwatch]::GetTimestamp()
    $after = Wait-Until {
        $value = Icon-Popup
        $elapsedTicks = [bigint]$value.end_ticks - $transition
        $ageTicks = [bigint]$value.end_ticks - $generation.target_move.input_begin_ticks
        Assert-That (1000 * $elapsedTicks -lt 1500 * $f -and 2000 * $elapsedTicks -lt $a * $f -and 2000 * $ageTicks -lt $a * $f) "$Name native tooltip deadline missed"
        if (($AfterText -eq '' -and -not $value.visible) -or ($AfterText -ne '' -and $value.visible -and $value.text -ceq $AfterText)) { return ,$value }
    } "$Name native tooltip transition"
    $prompt = [bigint]$after.end_ticks - $transition
    $age = [bigint]$after.end_ticks - $generation.target_move.input_begin_ticks
    Assert-That (1000 * $prompt -lt 1500 * $f -and 2000 * $prompt -lt $a * $f -and 2000 * $age -lt $a * $f) "$Name native tooltip deadline missed"
    $screenshot = "transition-$Name"
    Save-Screen $session $screenshot
    $script:iconTransitions[$Name] = @{ generation = $generation; before = $before; after = $after; transition_ticks = $transition; action_begin_ticks = $actionBegin; action_end_ticks = $actionEnd; pid = $session.pid; start_ticks = $session.startTicks; exe = $session.exe; sha256 = $session.sha256; commit = $session.commit; screenshot = "$screenshot.png" }
}

function Icon-Hover([string]$Id, [string]$Expected, [int]$X, [int]$Y, [int]$AnchorX = 0, [int]$AnchorY = 0) {
    $process = Get-App $session
    Assert-That ([VerifyWindow]::GetForegroundWindow() -eq $process.MainWindowHandle) 'Hover target is not foreground'
    $outside = [VerifyWindow+Point]::new()
    $outside.X = 4
    $outside.Y = 4
    Assert-That ([VerifyWindow]::ClientToScreen([IntPtr]$process.MainWindowHandle, [ref]$outside)) 'Window origin unavailable'
    [VerifyMenus]::Hover($session.pid, $outside.X, $outside.Y)
    if ($AnchorX -ne 0 -or $AnchorY -ne 0) { [VerifyMenus]::Hover($session.pid, $AnchorX, $AnchorY) }
    [VerifyMenus]::Hover($session.pid, $X, $Y)
    $point = [IconHintKeys+POINT]::new()
    $point.x = $X
    $point.y = $Y
    $owner = [IconHintKeys]::WindowFromPoint($point)
    $ownerPid = [uint32]0
    [VerifyWindow]::GetWindowThreadProcessId($owner, [ref]$ownerPid) | Out-Null
    Assert-That ($owner -ne [IntPtr]::Zero -and $ownerPid -eq $session.pid) 'Hover owner is not the app'
    $ownerBounds = [VerifyMenus]::Bounds($owner)
    $popup = Wait-Until {
        $tip = [VerifyMenus]::Find($session.pid, 'tooltips_class32')
        if ($tip -ne [IntPtr]::Zero -and (Read-EditText $tip) -ceq $Expected) { $tip }
    } "native tooltip $Id"
    $bounds = [VerifyMenus]::Bounds($popup)
    $actual = Read-EditText $popup
    $tooltips = @([VerifyInboxTooltip]::Tools($session.pid))
    Assert-That ($tooltips.Count -eq 1 -and $tooltips[0].hwnd -eq $popup.ToInt64() -and $null -ne $tooltips[0].current) 'Native tooltip identity unavailable or duplicated'
    @{ id = $Id; expected = $Expected; actual = $actual; popup = $popup.ToInt64(); pid = $session.pid; owner = $owner.ToInt64(); parent = ([IconHintKeys]::GetParent($owner)).ToInt64(); owner_pid = $ownerPid; owner_rect = @($ownerBounds.Left, $ownerBounds.Top, $ownerBounds.Right, $ownerBounds.Bottom); x = $X; y = $Y; bounds = @($bounds.Left, $bounds.Top, $bounds.Right, $bounds.Bottom); tooltips = $tooltips } |
        ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence "hover-$Id.json")
    Save-Screen $session "hover-$Id"
    if ($null -ne (Read-Control $session status).selected) {
        Read-Control $session messages | ConvertTo-Json -Depth 16 | Set-Content (Join-Path $session.evidence "hover-$Id.messages.json")
    }
}

function Invoke-IconIsolated([string]$Name, [bool]$UseHub) {
    $caseId = [Guid]::NewGuid().ToString()
    $caseRoot = Join-Path $env:RUNNER_TEMP "postbox-icon-$caseId"
    $caseLocal = Join-Path $caseRoot 'local'
    $caseProfile = Join-Path $caseRoot 'profile'
    $caseMessages = Join-Path $caseLocal 'Messages'
    $caseEvidence = Join-Path $session.evidence $Name
    $bridgeLog = Join-Path $session.evidence 'bridge-requests.jsonl'
    New-Item $caseMessages, $caseProfile, $caseEvidence -ItemType Directory -Force | Out-Null
    if (Test-Path $bridgeLog) { Copy-Item $bridgeLog (Join-Path $caseEvidence 'bridge-before.jsonl') }
    if ($Name -ceq 'voice-invalid-fixture') { [IO.File]::WriteAllBytes((Join-Path $caseMessages 'voice.pcm'), [byte[]](1, 2, 3)) }
    if (-not $UseHub) {
        Set-Content (Join-Path $caseMessages 'account-tag.txt') '0000000000000526' -NoNewline
        '{"data":[],"messages":{}}' | Set-Content (Join-Path $caseMessages 'verification-provider.json')
        '{"data":[]}' | Set-Content (Join-Path $caseMessages 'chats-0000000000000526.json')
    }
    $caseStart = [Diagnostics.ProcessStartInfo]::new($session.exe)
    $caseStart.UseShellExecute = $false
    $caseStart.ArgumentList.Add('--verify-fixture')
    $caseStart.Environment['WAZIG_VERIFY_ROOT'] = $caseRoot
    $caseStart.Environment['WAZIG_VERIFY_ID'] = $caseId
    $caseStart.Environment['LOCALAPPDATA'] = $caseLocal
    $caseStart.Environment['APPDATA'] = $caseLocal
    $caseStart.Environment['USERPROFILE'] = $caseProfile
    $caseStart.Environment['USERNAME'] = "verify-$caseId"
    foreach ($key in @('DEEPGRAM_API_KEY', 'OPENROUTER_API_KEY', 'WA_BRIDGE_KEY', 'WAZIG_VERIFY_HUB_URL', 'WAZIG_VERIFY_HUB_KEY', 'WAZIG_HUB_URL', 'WAZIG_HUB_TOKEN', 'WAZIG_VERIFY_RESTART')) { $null = $caseStart.Environment.Remove($key) }
    if ($UseHub) {
        $caseStart.Environment['WAZIG_HUB_URL'] = $start.Environment['WAZIG_HUB_URL']
        $caseStart.Environment['WAZIG_HUB_TOKEN'] = $start.Environment['WAZIG_HUB_TOKEN']
    }
    $child = [Diagnostics.Process]::Start($caseStart)
    $caseSession = [pscustomobject]@{ id = $caseId; pid = $child.Id; startTicks = $child.StartTime.ToUniversalTime().Ticks.ToString(); root = $caseRoot; evidence = $caseEvidence; exe = $session.exe; ctl = $session.ctl; username = "verify-$caseId"; sha256 = $session.sha256; commit = $session.commit; feature = $session.feature; expected_version = $session.expected_version; expected_product = $session.expected_product }
    $caseSession | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $caseEvidence 'session.json')
    try {
        $null = Wait-Until { $child.Refresh(); if ($child.HasExited) { throw 'Isolated app exited' }; $child.MainWindowHandle -ne [IntPtr]::Zero } "$Name window"
        [VerifyWindow]::ShowWindow($child.MainWindowHandle, 3) | Out-Null
        [VerifyWindow]::SetForegroundWindow($child.MainWindowHandle) | Out-Null
        $session = $caseSession
        $compose = Get-Edit (Get-Window $session) '1032'
        if ($UseHub) {
            $null = Wait-Until { (Read-Control $session status).chat_count -eq 2 } 'isolated fixture chats'
            for ($attempt = 0; $attempt -lt 5; $attempt++) {
                if ((Read-Control $session status).selected.provider -ceq 'whatsapp') { break }
                Send-Keys $session '^{TAB}'
            }
            Assert-That ((Read-Control $session status).selected.provider -ceq 'whatsapp') 'Missing fixture WhatsApp chat'
            $compose.SetFocus()
        } else {
            $null = Wait-Until { $value = Read-Control $session status; if ($value.chat_count -eq 0 -and $null -eq $value.selected) { return ,$value } } 'isolated empty chat list'
            $list = Get-Edit (Get-Window $session) '1016'
            $list.SetFocus()
            $state = Read-Control $session status
            $attach = @($state.composer.controls | Where-Object name -ceq 'attach')[0]
            $point = [VerifyWindow+Point]::new()
            Assert-That ([VerifyWindow]::ClientToScreen($child.MainWindowHandle, [ref]$point)) 'Isolated window origin unavailable'
            Icon-Hover 'attach-disabled' 'Select a chat first' ($point.X + [int](($attach.left + $attach.right) / 2)) ($point.Y + [int](($attach.top + $attach.bottom) / 2))
        }
        $before = Icon-Snapshot "$Name-before"
        try {
            Icon-Key 17 $false
            Icon-Key 16 $false
            Icon-Key 77 $false
        } finally {
            Icon-Key 77 $true
            Icon-Key 16 $true
            Icon-Key 17 $true
        }
        $after = Icon-Snapshot $Name
        Assert-That (-not $after.voice_recording.active -and $after.voice_recording.microphone_entries -eq 0 -and $after.voice_recording.fixture_entries -eq 0) 'Isolated voice gate failed'
        Assert-That ($after.pending_sends -eq $before.pending_sends) 'Isolated voice gate sent a message'
    } finally {
        & "$PSScriptRoot/cleanup.ps1" -Evidence $caseEvidence
        if (Test-Path $bridgeLog) { Copy-Item $bridgeLog (Join-Path $caseEvidence 'bridge-after.jsonl') }
        foreach ($file in @("$Name-before.icon.json", "$Name-before.png", "$Name.icon.json", "$Name.png", 'session.json', 'cleanup.txt', 'actions.log')) {
            $destination = if ($file -eq 'session.json') { "$Name.session.json" } elseif ($file -eq 'cleanup.txt') { "$Name.cleanup.txt" } elseif ($file -eq 'actions.log') { "$Name.actions.log" } else { $file }
            if (Test-Path (Join-Path $caseEvidence $file)) { Copy-Item (Join-Path $caseEvidence $file) (Join-Path $caseEvidence '..' $destination) }
        }
        if (-not $UseHub) {
            foreach ($extension in @('json', 'png')) { Copy-Item (Join-Path $caseEvidence "hover-attach-disabled.$extension") (Join-Path $caseEvidence "../hover-attach-disabled.$extension") }
        }
    }
}

$script:iconTransitions = @{}
for ($attempt = 0; $attempt -lt 5; $attempt++) {
    $state = Read-Control $session status
    if ($state.selected.provider -ceq 'whatsapp') { break }
    Send-Keys $session '^{TAB}'
}
$state = Read-Control $session status
Assert-That ($state.selected.provider -ceq 'whatsapp') 'WhatsApp fixture chat not selected'
$null = Wait-Until { $compose.Current.IsEnabled } 'composer enabled'
$main = [IntPtr](Get-Window $session).Current.NativeWindowHandle
$origin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($main, [ref]$origin)) 'Main origin unavailable'
$labels = @{ attach = 'Attach photo or file'; mic = 'Record a voice note  Ctrl+Shift+M'; dictate = 'Dictate  Ctrl+D'; emoji = 'Emoji menu'; send = 'Send message  Enter' }
foreach ($control in $state.composer.controls) {
    if (-not $labels.ContainsKey($control.name)) { continue }
    $x = $origin.X + [int](($control.left + $control.right) / 2)
    $y = $origin.Y + [int](($control.top + $control.bottom) / 2)
    Icon-Hover $control.name $labels[$control.name] $x $y
}
Icon-Transition 'leave' 'send' { [VerifyMenus]::Hover($session.pid, $origin.X + 4, $origin.Y + 4) }
$canvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
$canvasOrigin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$canvasOrigin)) 'Canvas origin unavailable'
$header = Wait-Until { $value = (Read-Control $session status).header_avatar; if ($value[2] -gt $value[0] -and $value[3] -gt $value[1]) { return ,$value } } 'header avatar painted'
Icon-Hover 'header-avatar' 'Current chat' ($canvasOrigin.X + [int](($header[0] + $header[2]) / 2)) ($canvasOrigin.Y + [int](($header[1] + $header[3]) / 2))
$originalBounds = [VerifyMenus]::Bounds($main)
[VerifyWindow]::ShowWindow($main, 9) | Out-Null
$null = Wait-Until { $value = [VerifyMenus]::Bounds($main); ($value.Right - $value.Left) -ne ($originalBounds.Right - $originalBounds.Left) } 'restored window settled'
$restoredBounds = [VerifyMenus]::Bounds($main)
$canvasOrigin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$canvasOrigin)) 'Restored canvas origin unavailable'
$header = Wait-Until { $value = (Read-Control $session status).header_avatar; if ($value[2] -gt $value[0]) { return ,$value } } 'restored header painted'
Icon-Hover 'header-resize' 'Current chat' ($canvasOrigin.X + [int](($header[0] + $header[2]) / 2)) ($canvasOrigin.Y + [int](($header[1] + $header[3]) / 2))
$resizeWidth = [Math]::Max(400, $restoredBounds.Right - $restoredBounds.Left - 80)
$resizeHeight = [Math]::Max(300, $restoredBounds.Bottom - $restoredBounds.Top - 40)
Icon-Transition 'resize' 'header-resize' { Assert-That ([VerifyWindow]::SetWindowPos($main, [IntPtr]::Zero, 0, 0, $resizeWidth, $resizeHeight, 0x16)) 'Resize failed' }
$resizedBounds = Wait-Until {
    $value = [VerifyMenus]::Bounds($main)
    if (($value.Right - $value.Left) -ne ($originalBounds.Right - $originalBounds.Left) -or ($value.Bottom - $value.Top) -ne ($originalBounds.Bottom - $originalBounds.Top)) { return ,$value }
} 'window resized'
$script:iconTransitions['resize']['before_window'] = @($restoredBounds.Left, $restoredBounds.Top, $restoredBounds.Right, $restoredBounds.Bottom)
$script:iconTransitions['resize']['after_window'] = @($resizedBounds.Left, $resizedBounds.Top, $resizedBounds.Right, $resizedBounds.Bottom)
[VerifyWindow]::ShowWindow($main, 3) | Out-Null
$null = Wait-Until { $bounds = [VerifyMenus]::Bounds($main); ($bounds.Right - $bounds.Left) -eq ($originalBounds.Right - $originalBounds.Left) } 'window maximized again'
$origin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($main, [ref]$origin)) 'Restored origin unavailable'
$compose.SetFocus()
Send-Keys $session 'Synthetic draft'
Send-Keys $session '+{LEFT 5}'
$selection = Icon-Selection
Assert-That ($selection.start -eq 10 -and $selection.end -eq 15) 'Draft selection differs'
$before = Icon-Snapshot 'voice-before'
Assert-That ($before.pending_sends -eq 0) 'Unexpected pending send'
try {
    Icon-Key 17 $false
    Icon-Key 16 $false
    Icon-Key 77 $false
    $recording = Wait-Until {
        $value = Read-Control $session status
        if ($value.voice_recording.active -and $value.voice_recording.samples -gt 0) { $value }
    } 'fixture voice worker recording'
    $voiceControl = @($recording.composer.controls | Where-Object name -ceq 'mic')[0]
    $voiceX = $origin.X + [int](($voiceControl.left + $voiceControl.right) / 2)
    $voiceY = $origin.Y + [int](($voiceControl.top + $voiceControl.bottom) / 2)
    Icon-Hover 'mic-recording' 'Finish voice note  Ctrl+Shift+M · Enter sends · Esc cancels' $voiceX $voiceY
    Icon-Key 77 $false
    Icon-Key 77 $false
    $held = Icon-Snapshot 'voice-held'
    Assert-That ($held.voice_recording.active -and -not $held.voice_recording.finishing -and $held.voice_recording.fixture_entries -eq 1) 'Repeated key changed capture'
} finally {
    Icon-Key 77 $true
    Icon-Key 16 $true
    Icon-Key 17 $true
}
Icon-Key 27 $false
Icon-Key 27 $true
$null = Wait-Until { -not (Read-Control $session status).voice_recording.active } 'voice cancelled'
$after = Icon-Snapshot 'voice-cancelled'
Assert-That ((Read-Edit $compose) -ceq 'Synthetic draft' -and $after.pending_sends -eq 0 -and $after.voice_recording.microphone_entries -eq 0) 'Cancellation changed the draft or sent a message'
Icon-Key 27 $false
Icon-Key 27 $true
$inactive = Icon-Snapshot 'voice-inactive'
Assert-That (-not $inactive.voice_recording.active -and $inactive.voice_recording.fixture_entries -eq $after.voice_recording.fixture_entries -and (Read-Edit $compose) -ceq 'Synthetic draft') 'Inactive Escape changed voice or draft'
try {
    Icon-Key 17 $false
    Icon-Key 16 $false
    Icon-Key 18 $false
    Icon-Key 77 $false
} finally {
    Icon-Key 77 $true
    Icon-Key 18 $true
    Icon-Key 16 $true
    Icon-Key 17 $true
}
$modifiers = Icon-Snapshot 'voice-modifiers'
Assert-That (-not $modifiers.voice_recording.active -and $modifiers.voice_recording.fixture_entries -eq $after.voice_recording.fixture_entries) 'Extra modifier started voice'
Send-Keys $session '%j'
$selected = Wait-Until {
    $rows = (Read-Control $session messages).messages
    $match = @($rows | Where-Object { $_.selected -and $_.bubble[3] -gt 72 })
    if ($match.Count -eq 1) { $match[0] }
} 'selected visible message'
$rows = (Read-Control $session messages).messages
$other = @($rows | Where-Object { -not $_.selected -and $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt 72 })
Assert-That ($other.Count -gt 0) 'Second visible message unavailable'
$canvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
$canvasOrigin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$canvasOrigin)) 'Canvas origin unavailable'
foreach ($case in @(@{ name = 'selected'; message = $selected }, @{ name = 'unselected'; message = $other[0] })) {
    $row = $case.message
    $anchorX = $canvasOrigin.X + [int](($row.bubble[0] + $row.bubble[2]) / 2)
    $anchorY = $canvasOrigin.Y + [int](($row.bubble[1] + $row.bubble[3]) / 2)
    $wanted = if ($case.name -eq 'selected') { @('React  Ctrl+R', 'Reply  Ctrl+Shift+R', 'Message actions') } else { @('React', 'Reply', 'Message actions') }
    $ids = @('react', 'reply', 'more')
    for ($cell = 0; $cell -lt 3; $cell++) {
        $rect = $row.action_cells[$cell]
        $x = $canvasOrigin.X + [int](($rect[0] + $rect[2]) / 2)
        $y = $canvasOrigin.Y + [int](($rect[1] + $rect[3]) / 2)
        Icon-Hover "$($ids[$cell])-$($case.name)" $wanted[$cell] $x $y $anchorX $anchorY
        if ($case.name -eq 'selected' -and $cell -eq 0) {
            $next = $row.action_cells[1]
            $nextX = $canvasOrigin.X + [int](($next[0] + $next[2]) / 2)
            $nextY = $canvasOrigin.Y + [int](($next[1] + $next[3]) / 2)
            Icon-Transition 'adjacent' 'react-selected' { [VerifyMenus]::Hover($session.pid, $nextX, $nextY) } 'Reply  Ctrl+Shift+R' $anchorX $anchorY
        }
    }
}
$scrollBefore = Read-Control $session messages
Icon-Transition 'scroll' 'more-unselected' { Assert-That ([IconHintKeys]::Wheel(120)) 'Mouse wheel SendInput failed' } '' $anchorX $anchorY
$scrollAfter = Read-Control $session messages
$script:iconTransitions['scroll']['before_messages'] = $scrollBefore.messages
$script:iconTransitions['scroll']['after_messages'] = $scrollAfter.messages
Add-Content (Join-Path $session.evidence 'actions.log') 'icon-wheel: 120'
Send-Keys $session '^+r'
$reply = Wait-Until { $value = Read-Control $session status; if ($value.reply.id -ceq $selected.id) { $value.reply } } 'selected message reply'
$rect = $reply.close
$x = $origin.X + [int](($rect[0] + $rect[2]) / 2)
$y = $origin.Y + [int](($rect[1] + $rect[3]) / 2)
Icon-Hover 'reply-close' 'Cancel reply  Esc in message box' $x $y
Icon-Transition 'reply-close' 'reply-close' { [VerifyMenus]::Click($session.pid, $x, $y, $false) }
$closedReply = Wait-Until { $value = Read-Control $session status; if ($value.reply.id -ceq '') { return ,$value } } 'reply closed'
$script:iconTransitions['reply-close']['before_reply'] = $reply.id
$script:iconTransitions['reply-close']['after_reply'] = $closedReply.reply.id
$fixture = Join-Path (Join-Path $session.root 'profile') 'icon-fixture.png'
[VerifyPasteImage]::Fixture($fixture)
$capacity = (Read-Control $session status).staged_capacity
Assert-That ($capacity -gt 1) 'Staged attachment capacity unavailable'
for ($index = 0; $index -lt $capacity; $index++) {
    Add-PickerImage $session $fixture
    $wanted = $index + 1
    $null = Wait-Until { (Read-Control $session status).staged_attachment_count -eq $wanted } "attachment $wanted staged"
}
$staged = Read-Control $session status
Assert-That (@($staged.staged_remove_rects | ForEach-Object { $_[1] } | Sort-Object -Unique).Count -gt 1) 'Staged attachments did not wrap'
for ($index = 0; $index -lt $capacity; $index++) {
    $rect = $staged.staged_remove_rects[$index]
    $x = $origin.X + [int](($rect[0] + $rect[2]) / 2)
    $y = $origin.Y + [int](($rect[1] + $rect[3]) / 2)
    Icon-Hover "staged-$index" 'Remove attachment' $x $y
}
$rect = $staged.staged_remove_rects[0]
$x = $origin.X + [int](($rect[0] + $rect[2]) / 2)
$y = $origin.Y + [int](($rect[1] + $rect[3]) / 2)
Icon-Hover 'staged-before-compaction' 'Remove attachment' $x $y
Icon-Transition 'staged-compaction' 'staged-before-compaction' { [VerifyMenus]::Click($session.pid, $x, $y, $false) }
$staged = Wait-Until { $value = Read-Control $session status; if ($value.staged_attachment_count -eq ($capacity - 1)) { $value } } 'attachment compacted'
$script:iconTransitions['staged-compaction']['before_count'] = $capacity
$script:iconTransitions['staged-compaction']['after_count'] = $staged.staged_attachment_count
$rect = $staged.staged_remove_rects[0]
$x = $origin.X + [int](($rect[0] + $rect[2]) / 2)
$y = $origin.Y + [int](($rect[1] + $rect[3]) / 2)
Icon-Hover 'staged-compacted' 'Remove attachment' $x $y
while ($staged.staged_attachment_count -gt 1) {
    $rect = $staged.staged_remove_rects[0]
    $x = $origin.X + [int](($rect[0] + $rect[2]) / 2)
    $y = $origin.Y + [int](($rect[1] + $rect[3]) / 2)
    $wanted = $staged.staged_attachment_count - 1
    [VerifyMenus]::Click($session.pid, $x, $y, $false)
    $staged = Wait-Until { $value = Read-Control $session status; if ($value.staged_attachment_count -eq $wanted) { $value } } 'attachment removed'
}
$rect = $staged.staged_remove_rects[0]
$x = $origin.X + [int](($rect[0] + $rect[2]) / 2)
$y = $origin.Y + [int](($rect[1] + $rect[3]) / 2)
Icon-Hover 'staged-sole' 'Remove attachment  Esc in message box' $x $y
[VerifyMenus]::Click($session.pid, $x, $y, $false)
$null = Wait-Until { (Read-Control $session status).staged_attachment_count -eq 0 } 'attachments cleared'
$canvasOrigin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$canvasOrigin)) 'Canvas origin unavailable after attachments'
$chatBefore = Read-Control $session status
$header = Wait-Until { $value = (Read-Control $session status).header_avatar; if ($value[2] -gt $value[0] -and $value[3] -gt $value[1]) { return ,$value } } 'header restored'
Icon-Hover 'header-before-chat' 'Current chat' ($canvasOrigin.X + [int](($header[0] + $header[2]) / 2)) ($canvasOrigin.Y + [int](($header[1] + $header[3]) / 2))
Assert-That ([VerifyWindow]::GetForegroundWindow() -eq $main) 'Chat window is not foreground'
Icon-Transition 'chat' 'header-before-chat' {
    Assert-That ([VerifyWindow]::GetForegroundWindow() -eq $main) 'Chat window lost foreground'
    try {
        Assert-That ([IconHintKeys]::Key(17, $false)) 'Ctrl down failed'
        Assert-That ([IconHintKeys]::Key(9, $false)) 'Tab down failed'
    } finally {
        Assert-That ([IconHintKeys]::Key(9, $true)) 'Tab up failed'
        Assert-That ([IconHintKeys]::Key(17, $true)) 'Ctrl up failed'
    }
    Assert-That ([VerifyWindow]::GetForegroundWindow() -eq $main) 'Chat window lost foreground'
}
$chatAfter = Wait-Until { $value = Read-Control $session status; if ($null -ne $value.selected -and $value.selected.id -cne $chatBefore.selected.id) { $value } } 'different chat selected'
$script:iconTransitions['chat']['before_selected'] = $chatBefore.selected
$script:iconTransitions['chat']['after_selected'] = $chatAfter.selected
for ($attempt = 0; $attempt -lt 5; $attempt++) {
    if ((Read-Control $session status).selected.provider -ceq 'slack') { break }
    Send-Keys $session '^{TAB}'
}
$unsupportedBefore = Icon-Snapshot 'voice-unsupported-before'
Assert-That ($unsupportedBefore.selected.provider -ceq 'slack') 'Unsupported provider fixture unavailable'
try {
    Icon-Key 17 $false
    Icon-Key 16 $false
    Icon-Key 77 $false
} finally {
    Icon-Key 77 $true
    Icon-Key 16 $true
    Icon-Key 17 $true
}
$unsupportedAfter = Icon-Snapshot 'voice-unsupported'
Assert-That (-not $unsupportedAfter.voice_recording.active -and $unsupportedAfter.voice_recording.fixture_entries -eq $unsupportedBefore.voice_recording.fixture_entries) 'Unsupported provider started capture'
$dictationBefore = Read-Control $session status
Send-Keys $session '^d'
$dictationRecording = Wait-Until { $value = Read-Control $session status; if ($value.dictation.phase -ceq 'recording') { $value } } 'Ctrl+D starts fixture dictation'
Send-Keys $session '{ESC}'
$dictationCancelled = Wait-Until { $value = Read-Control $session status; if ($value.dictation.phase -ceq 'idle' -and -not $value.dictation.draining) { $value } } 'fixture dictation cancelled'
Assert-That ($dictationRecording.dictation.microphone_entries -eq 0 -and $dictationRecording.dictation.transcription_attempts -eq 0) 'Dictation fixture escaped isolation'
@{ before = $dictationBefore; recording = $dictationRecording; cancelled = $dictationCancelled } | ConvertTo-Json -Depth 16 | Set-Content (Join-Path $session.evidence 'dictation-ctrl-d.json')
Invoke-IconIsolated 'voice-no-chat' $false
Invoke-IconIsolated 'voice-bad-fixture' $true
Invoke-IconIsolated 'voice-invalid-fixture' $true
[VerifyWindow]::SetForegroundWindow((Get-App $session).MainWindowHandle) | Out-Null
$script:iconTransitions | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'icon-transitions.json')

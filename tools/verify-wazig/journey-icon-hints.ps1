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
    $tools = @([VerifyInboxTooltip]::Tools($session.pid))
    Assert-That ($tools.Count -eq 1) 'Tooltip window count changed'
    $tip = [VerifyMenus]::Find($session.pid, 'tooltips_class32')
    if ($tip -eq [IntPtr]::Zero) { return @{ visible = $false; hwnd = 0; text = ''; ticks = [Diagnostics.Stopwatch]::GetTimestamp(); frequency = [Diagnostics.Stopwatch]::Frequency; tooltips = $tools } }
    $bounds = [VerifyMenus]::Bounds($tip)
    $text = Read-EditText $tip
    return @{ visible = $true; hwnd = $tip.ToInt64(); text = $text; bounds = @($bounds.Left, $bounds.Top, $bounds.Right, $bounds.Bottom); ticks = [Diagnostics.Stopwatch]::GetTimestamp(); frequency = [Diagnostics.Stopwatch]::Frequency; tooltips = $tools }
}

function Icon-Transition([string]$Name, $Before, [string]$OldText) {
    $after = Wait-Until {
        $value = Icon-Popup
        if (-not $value.visible -or $value.text -cne $OldText) { return ,$value }
    } "$Name old tooltip disappears"
    $elapsed = 1000.0 * ($after.ticks - $Before.ticks) / $Before.frequency
    $autopop = $Before.tooltips[0].autopop_ms
    Assert-That ($autopop -gt 0 -and $elapsed -ge 0 -and $elapsed -lt [Math]::Min(1500, $autopop / 2)) "$Name tooltip stayed visible too long"
    $screenshot = "transition-$Name"
    Save-Screen $session $screenshot
    $script:iconTransitions[$Name] = @{ before = $Before; after = $after; elapsed_ms = $elapsed; screenshot = "$screenshot.png" }
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
$oldPopup = Icon-Popup
Assert-That ($oldPopup.visible -and $oldPopup.text -ceq 'Send message  Enter') 'Send tooltip was not visible'
[VerifyMenus]::Hover($session.pid, $origin.X + 4, $origin.Y + 4)
Icon-Transition 'leave' $oldPopup 'Send message  Enter'
$canvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
$canvasOrigin = [VerifyWindow+Point]::new()
Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$canvasOrigin)) 'Canvas origin unavailable'
$header = Wait-Until { $value = (Read-Control $session status).header_avatar; if ($value[2] -gt $value[0] -and $value[3] -gt $value[1]) { return ,$value } } 'header avatar painted'
Icon-Hover 'header-avatar' 'Current chat' ($canvasOrigin.X + [int](($header[0] + $header[2]) / 2)) ($canvasOrigin.Y + [int](($header[1] + $header[3]) / 2))
$beforeResize = Icon-Popup
$originalBounds = [VerifyMenus]::Bounds($main)
[VerifyWindow]::ShowWindow($main, 9) | Out-Null
Assert-That ([VerifyWindow]::SetWindowPos($main, [IntPtr]::Zero, 0, 0, 1100, 700, 0x16)) 'Resize failed'
$resizedBounds = Wait-Until {
    $value = [VerifyMenus]::Bounds($main)
    if (($value.Right - $value.Left) -ne ($originalBounds.Right - $originalBounds.Left) -or ($value.Bottom - $value.Top) -ne ($originalBounds.Bottom - $originalBounds.Top)) { return ,$value }
} 'window resized'
Icon-Transition 'resize' $beforeResize 'Current chat'
$script:iconTransitions['resize']['before_window'] = @($originalBounds.Left, $originalBounds.Top, $originalBounds.Right, $originalBounds.Bottom)
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
            $beforePopup = Icon-Popup
            $next = $row.action_cells[1]
            $nextX = $canvasOrigin.X + [int](($next[0] + $next[2]) / 2)
            $nextY = $canvasOrigin.Y + [int](($next[1] + $next[3]) / 2)
            [VerifyMenus]::Hover($session.pid, $nextX, $nextY)
            $afterPopup = Wait-Until { $value = Icon-Popup; if ($value.visible -and $value.text -ceq 'Reply  Ctrl+Shift+R') { return ,$value } } 'adjacent action tooltip'
            $elapsed = 1000.0 * ($afterPopup.ticks - $beforePopup.ticks) / $beforePopup.frequency
            Assert-That ($elapsed -ge 0 -and $elapsed -lt [Math]::Min(1500, $beforePopup.tooltips[0].autopop_ms / 2)) 'Adjacent tooltip update was too slow'
            Save-Screen $session 'transition-adjacent'
            $script:iconTransitions['adjacent'] = @{ before = $beforePopup; after = $afterPopup; elapsed_ms = $elapsed; screenshot = 'transition-adjacent.png' }
        }
    }
}
$beforeScroll = Icon-Popup
Assert-That ($beforeScroll.visible -and $beforeScroll.text -ceq 'Message actions') 'Scroll tooltip unavailable'
Assert-That ([IconHintKeys]::Wheel(120)) 'Mouse wheel SendInput failed'
Add-Content (Join-Path $session.evidence 'actions.log') 'icon-wheel: 120'
Icon-Transition 'scroll' $beforeScroll 'Message actions'
Send-Keys $session '^+r'
$reply = Wait-Until { $value = Read-Control $session status; if ($value.reply.id -ceq $selected.id) { $value.reply } } 'selected message reply'
$rect = $reply.close
$x = $origin.X + [int](($rect[0] + $rect[2]) / 2)
$y = $origin.Y + [int](($rect[1] + $rect[3]) / 2)
Icon-Hover 'reply-close' 'Cancel reply  Esc in message box' $x $y
$oldPopup = Icon-Popup
[VerifyMenus]::Click($session.pid, $x, $y, $false)
$null = Wait-Until { (Read-Control $session status).reply.id -ceq '' } 'reply closed'
Icon-Transition 'reply-close' $oldPopup 'Cancel reply  Esc in message box'
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
$oldPopup = Icon-Popup
[VerifyMenus]::Click($session.pid, $x, $y, $false)
$staged = Wait-Until { $value = Read-Control $session status; if ($value.staged_attachment_count -eq ($capacity - 1)) { $value } } 'attachment compacted'
Icon-Transition 'staged-compaction' $oldPopup 'Remove attachment'
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
$oldPopup = Icon-Popup
Send-Keys $session '^{TAB}'
$chatAfter = Wait-Until { $value = Read-Control $session status; if ($null -ne $value.selected -and $value.selected.id -cne $chatBefore.selected.id) { $value } } 'different chat selected'
Icon-Transition 'chat' $oldPopup 'Current chat'
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

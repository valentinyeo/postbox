. "$PSScriptRoot/menus.ps1"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CtrlBadgeKeys {
    [DllImport("user32.dll")] static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    public static void Down(byte key) { keybd_event(key, 0, 0, UIntPtr.Zero); }
    public static void Up(byte key) { keybd_event(key, 0, 2, UIntPtr.Zero); }
}
'@

function Assert-AppForeground {
    $app = Get-App $session
    $null = Wait-Until {
        $foreground = [VerifyWindow]::GetForegroundWindow()
        $ownerPid = [uint32]0
        if ($foreground -ne [IntPtr]::Zero) { [VerifyWindow]::GetWindowThreadProcessId($foreground, [ref]$ownerPid) | Out-Null }
        if ($foreground -eq [IntPtr]::Zero -or $ownerPid -ne $session.pid) {
            $app.Refresh()
            [VerifyWindow]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
            return $false
        }
        return $true
    } 'app foreground window before keyboard input'
}

function Send-CtrlKey([bool]$Down, [string]$Note) {
    Assert-AppForeground
    if ($Down) { [CtrlBadgeKeys]::Down(0x11) } else { [CtrlBadgeKeys]::Up(0x11) }
    Add-Content (Join-Path $session.evidence 'actions.log') "SendInput: ctrl $Note"
}

function Send-DigitWhileCtrl([byte]$Key, [string]$Note) {
    Assert-AppForeground
    [CtrlBadgeKeys]::Down($Key)
    [CtrlBadgeKeys]::Up($Key)
    Add-Content (Join-Path $session.evidence 'actions.log') "SendInput: digit $Note"
}

function Read-Badges { (Read-Control $session status).ctrl_badges }

function Measure-Badge($Before, $Other, $Rect, [int]$OriginX, [int]$OriginY) {
    $left = $Rect[0] - $OriginX; $top = $Rect[1] - $OriginY; $right = $Rect[2] - $OriginX; $bottom = $Rect[3] - $OriginY
    $colors = @{}
    $changed = 0; $area = 0; $ink = 0
    for ($y = $top; $y -lt $bottom; $y++) {
        for ($x = $left; $x -lt $right; $x++) {
            Assert-That ($x -ge 0 -and $x -lt $Before.width -and $y -ge 0 -and $y -lt $Before.height) 'Badge is outside the screenshot'
            $at = $y * $Before.stride + $x * 4
            $area++
            $delta = [Math]::Abs([int]$Before.bytes[$at] - [int]$Other.bytes[$at]) + [Math]::Abs([int]$Before.bytes[$at + 1] - [int]$Other.bytes[$at + 1]) + [Math]::Abs([int]$Before.bytes[$at + 2] - [int]$Other.bytes[$at + 2])
            if ($delta -gt 48) { $changed++ }
            $key = "$($Other.bytes[$at]),$($Other.bytes[$at + 1]),$($Other.bytes[$at + 2])"
            if ($colors.ContainsKey($key)) { $colors[$key]++ } else { $colors[$key] = 1 }
        }
    }
    $fill = ($colors.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
    $fillParts = $fill.Key.Split(',') | ForEach-Object { [int]$_ }
    $insetX = [int](($right - $left) * 0.2); $insetY = [int](($bottom - $top) * 0.2)
    for ($y = $top + $insetY; $y -lt $bottom - $insetY; $y++) {
        for ($x = $left + $insetX; $x -lt $right - $insetX; $x++) {
            $at = $y * $Before.stride + $x * 4
            $distance = [Math]::Abs([int]$Other.bytes[$at] - $fillParts[0]) + [Math]::Abs([int]$Other.bytes[$at + 1] - $fillParts[1]) + [Math]::Abs([int]$Other.bytes[$at + 2] - $fillParts[2])
            if ($distance -gt 150) { $ink++ }
        }
    }
    @{ area = $area; changed = $changed; fill_pixels = [int]$fill.Value; ink_pixels = $ink }
}

$state = Read-Control $session status
Assert-That ($state.chat_count -eq 6) 'Ctrl badges need six chats'
$rows = (Read-Control $session chats).chats
$idle = $state.ctrl_badges
Assert-That (-not $idle.held -and @($idle.badges).Count -eq 0) 'Badges must be hidden before Ctrl is held'
Assert-That (@($rows).Count -eq 6) 'Ctrl badges need six chat rows'
$initial = (Read-Control $session status).selected.id
$initialRow = [Array]::IndexOf(@($rows | ForEach-Object { $_.id }), $initial)
Assert-That ($initialRow -ge 0 -and $initialRow -lt 9) 'Initial chat must be one of the numbered rows'
Save-Screen $session ctrl-before
$before = Read-ScreenshotPixels (Join-Path $Evidence 'ctrl-before.png')

$held = $null
Send-CtrlKey $true 'down'
try {
    $held = Wait-Until {
        $badges = Read-Badges
        if ($badges.held -and @($badges.badges).Count -eq 6) { $badges }
    } 'six numbered badges while Ctrl is held'
    Save-Screen $session ctrl-held
    $heldImage = Read-ScreenshotPixels (Join-Path $Evidence 'ctrl-held.png')

    Send-DigitWhileCtrl 0x33 '3'
    $null = Wait-Until { (Read-Control $session status).selected.id -eq $rows[2].id } 'Ctrl+3 opens the third chat'
    $stillHeld = Wait-Until {
        $badges = Read-Badges
        if ($badges.held -and @($badges.badges).Count -eq 6) { $badges }
    } 'badges stay while Ctrl is still held after the jump'
    Save-Screen $session ctrl-jump
} finally {
    Send-CtrlKey $false 'up'
}
$released = Wait-Until {
    $badges = Read-Badges
    if (-not $badges.held -and @($badges.badges).Count -eq 0) { $badges }
} 'badges disappear when Ctrl is released'
Send-Keys $session "^$($initialRow + 1)"
$null = Wait-Until { (Read-Control $session status).selected.id -eq $initial } 'initial chat reselected'
$null = Wait-Until {
    $badges = Read-Badges
    if (-not $badges.held -and @($badges.badges).Count -eq 0) { $badges }
} 'badges hidden again after reselecting'
Save-Screen $session ctrl-after

$screen = [Windows.Forms.SystemInformation]::VirtualScreen
$after = Read-ScreenshotPixels (Join-Path $Evidence 'ctrl-after.png')
$measures = @()
foreach ($badge in @($held.badges)) {
    $heldMeasure = Measure-Badge $before $heldImage $badge.rect $screen.Left $screen.Top
    $afterMeasure = Measure-Badge $before $after $badge.rect $screen.Left $screen.Top
    $measures += @{ number = [int]$badge.number; rect = @($badge.rect); held = $heldMeasure; after = $afterMeasure }
}
@{
    schema = 1
    rows = @($rows | ForEach-Object { @{ id = $_.id; name = $_.name } })
    idle = $idle
    held = $held
    jumped = $stillHeld
    released = $released
    measures = $measures
    selected_after_jump = $rows[2].id
} | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'ctrl-badges.json')
Hub-Pass $session ctrl-badges

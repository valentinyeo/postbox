Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class VerifyCaret {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct ThreadInfo {
        public int Size, Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public Rect CaretRect;
    }
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread, ref ThreadInfo info);
    [DllImport("user32.dll")] public static extern uint GetCaretBlinkTime();
}
'@

function Get-CaretOnOff([int[]]$Ink) {
    $low = ($Ink | Measure-Object -Minimum).Minimum
    $high = ($Ink | Measure-Object -Maximum).Maximum
    $spread = $high - $low
    $phases = @()
    if ($spread -ge 8) {
        foreach ($count in $Ink) {
            $state = if ($count - $low -ge $spread / 2) { 1 } else { 0 }
            if ($phases.Count -eq 0 -or $phases[-1] -ne $state) { $phases += $state }
        }
    }
    return @{ low = $low; high = $high; on = @($phases | Where-Object { $_ -eq 1 }).Count; off = @($phases | Where-Object { $_ -eq 0 }).Count; phases = $phases }
}

function Test-CaretOracle {
    $steady = Get-CaretOnOff @(40, 40, 40, 40, 40, 40)
    Assert-That ($steady.on -eq 0 -and $steady.off -eq 0) 'caret oracle counted phases in a steady frame series'
    $blinking = Get-CaretOnOff @(40, 40, 58, 58, 40, 40, 58, 58, 40, 58)
    Assert-That ($blinking.on -ge 2 -and $blinking.off -ge 2) 'caret oracle missed a blinking series'
}

function Measure-CaretTheme($Session, [string]$Theme) {
    Invoke-PaletteCommand $Session 'Compose message'
    $window = Get-Window $Session
    $edit = Get-Edit $window '1032'
    Send-Keys $Session 'abc'
    $null = Wait-Until { (Read-Edit $edit) -eq 'abc' } "caret $Theme typed text"
    [System.Threading.Thread]::Sleep(900)
    $handle = [IntPtr]$window.Current.NativeWindowHandle
    $processId = 0
    $thread = [VerifyWindow]::GetWindowThreadProcessId($handle, [ref]$processId)
    $info = [VerifyCaret+ThreadInfo]::new()
    $info.Size = [Runtime.InteropServices.Marshal]::SizeOf([type][VerifyCaret+ThreadInfo])
    $reading = [VerifyCaret]::GetGUIThreadInfo($thread, [ref]$info)
    $bounds = $edit.Current.BoundingRectangle
    $desktop = [Windows.Forms.SystemInformation]::VirtualScreen
    $left = [int]($bounds.Left - $desktop.Left)
    $top = [int]($bounds.Top - $desktop.Top)
    $width = [Math]::Min(260, [int]$bounds.Width)
    $height = [int]$bounds.Height
    $frames = @()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt 24; $i++) {
        $image = [Drawing.Bitmap]::new($width, $height)
        $graphics = [Drawing.Graphics]::FromImage($image)
        try {
            $graphics.CopyFromScreen($left + $desktop.Left, $top + $desktop.Top, 0, 0, [Drawing.Size]::new($width, $height))
        } finally { $graphics.Dispose() }
        $frames += @{ at = $clock.ElapsedMilliseconds; image = $image }
        [System.Threading.Thread]::Sleep(130)
    }
    $fill = $frames[0].image.GetPixel(2, 2)
    $fillMax = [Math]::Max($fill.R, [Math]::Max($fill.G, $fill.B))
    $ink = @()
    $stamps = @()
    foreach ($frame in $frames) {
        $count = 0
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $pixel = $frame.image.GetPixel($x, $y)
                if ([Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B)) -gt $fillMax + 40) { $count++ }
            }
        }
        $ink += $count
        $stamps += $frame.at
    }
    $frames[0].image.Save((Join-Path $Session.evidence "caret-$Theme-first.png"), [Drawing.Imaging.ImageFormat]::Png)
    $best = 0
    for ($i = 1; $i -lt $ink.Count; $i++) { if ($ink[$i] -gt $ink[$best]) { $best = $i } }
    $frames[$best].image.Save((Join-Path $Session.evidence "caret-$Theme-brightest.png"), [Drawing.Imaging.ImageFormat]::Png)
    foreach ($frame in $frames) { $frame.image.Dispose() }
    $phases = Get-CaretOnOff $ink
    Save-Screen $Session "caret-$Theme"
    Send-Keys $Session '^a{BACKSPACE}'
    $null = Wait-Until { (Read-Edit $edit) -eq '' } "caret $Theme empty edit"
    $caretOwner = if ($info.Caret -eq [IntPtr]::Zero) { 'none' } elseif ($info.Caret -eq [IntPtr]$edit.Current.NativeWindowHandle) { 'composer' } else { 'other' }
    return [ordered]@{
        theme = $Theme; thread_reading = $reading; caret_owner = $caretOwner
        caret_rect = @{ left = $info.CaretRect.Left; top = $info.CaretRect.Top; right = $info.CaretRect.Right; bottom = $info.CaretRect.Bottom }
        focus_is_composer = ($info.Focus -eq [IntPtr]$edit.Current.NativeWindowHandle)
        blink_time_ms = [VerifyCaret]::GetCaretBlinkTime(); edit = @{ left = $bounds.Left; top = $bounds.Top; width = $bounds.Width; height = $bounds.Height }
        fill_max = $fillMax; ink_low = $phases.low; ink_high = $phases.high; on = $phases.on; off = $phases.off
        phases = $phases.phases; ink = $ink; frame_ms = $stamps
    }
}

function Invoke-CaretJourney($Session, $Start, $App) {
    Test-CaretOracle
    $themes = [ordered]@{}
    $themes['amoled'] = Measure-CaretTheme $Session 'amoled'
    Send-Keys $Session '^k'
    Send-Keys $Session 'Theme: Green'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { (Read-Control $Session status).theme -eq 'green' } 'caret green theme'
    $themes['green'] = Measure-CaretTheme $Session 'green'
    [ordered]@{ themes = $themes } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'caret.json')
    Save-Screen $Session after
    foreach ($name in $themes.Keys) {
        $theme = $themes[$name]
        Assert-That ($theme.on -ge 2 -and $theme.off -ge 2) "caret does not blink in $name composer: owner=$($theme.caret_owner) on=$($theme.on) off=$($theme.off) ink=$($theme.ink_low)..$($theme.ink_high)"
    }
    return $App
}

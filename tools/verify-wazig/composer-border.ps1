function Measure-ComposerBorder($Image, [int]$X, [int]$Y, [int]$Dx, [int]$Dy) {
    $samples = @(-6..6 | ForEach-Object {
        $pixel = $Image.GetPixel($X + $_ * $Dx, $Y + $_ * $Dy)
        [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B))
    })
    $background = [Math]::Max($samples[0], $samples[-1])
    $ink = @($samples | Where-Object { $_ -gt $background + 8 })
    return $ink.Count
}

function Assert-ComposerBorder($Measurement) {
    Assert-That ($Measurement.top -gt 0 -and $Measurement.top -le 4 -and $Measurement.top -eq $Measurement.bottom -and $Measurement.left -eq $Measurement.right -and $Measurement.top -eq $Measurement.left) "composer border unequal or missing: top=$($Measurement.top) bottom=$($Measurement.bottom) left=$($Measurement.left) right=$($Measurement.right)"
}

function Test-ComposerBorderOracle {
    $image = [Drawing.Bitmap]::new(64, 64)
    try {
        foreach ($bottomWidth in @(2, 1)) {
            for ($y = 0; $y -lt 64; $y++) {
                for ($x = 0; $x -lt 64; $x++) {
                    $border = (($x -ge 15 -and $x -le 16 -or $x -ge 47 -and $x -le 48) -and $y -ge 15 -and $y -le 48) -or (($y -ge 15 -and $y -le 16 -or $y -ge 49 - $bottomWidth -and $y -le 48) -and $x -ge 15 -and $x -le 48)
                    $image.SetPixel($x, $y, $(if ($border) { [Drawing.Color]::White } else { [Drawing.Color]::Black }))
                }
            }
            $measurement = @{
                top = Measure-ComposerBorder $image 32 16 0 1
                bottom = Measure-ComposerBorder $image 32 48 0 -1
                left = Measure-ComposerBorder $image 16 32 1 0
                right = Measure-ComposerBorder $image 48 32 -1 0
            }
            if ($bottomWidth -eq 2) { Assert-ComposerBorder $measurement } else {
                $rejected = $false
                try { Assert-ComposerBorder $measurement } catch { $rejected = $_.Exception.Message.Contains('border') }
                Assert-That $rejected 'composer border oracle accepted a one-row bottom defect'
            }
        }
    } finally { $image.Dispose() }
}

function Invoke-ComposerBorderJourney($Session, $Start, $App) {
    Test-ComposerBorderOracle
    $measurements = @()
    $tokens = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../src/design_tokens.zig'))
    $bodyMatch = [regex]::Match($tokens, 'pub const body_size: i32 = (\d+);')
    Assert-That $bodyMatch.Success 'Shared body font token missing'
    $bodySize = [int]$bodyMatch.Groups[1].Value
    $preferences = "HKCU:\Software\MessagesVerification\$($Session.id)\Software\Messages"
    foreach ($scale in @(100, 125, 150)) {
        $null = Get-App $Session
        Send-Keys $Session '%{F4}'
        Assert-That ($App.WaitForExit(10000)) 'composer border fixture did not close'
        $App.StandardError.ReadToEnd() | Set-Content (Join-Path $Session.evidence "composer-border-before-$scale.stderr.log")
        New-ItemProperty $preferences -Name FontScale -Value $scale -PropertyType DWord -Force | Out-Null
        $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
        $App = [Diagnostics.Process]::Start($Start)
        $Session.pid = $App.Id
        $Session.startTicks = $App.StartTime.ToUniversalTime().Ticks.ToString()
        $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
        $null = Wait-Until { $App.Refresh(); if ($App.HasExited) { throw 'composer border fixture exited' }; $App.MainWindowHandle -ne [IntPtr]::Zero } 'composer border restarted window'
        Invoke-Doctor $Session | Out-Null
        Invoke-PaletteCommand $Session 'Compose message'
        $window = Get-Window $Session
        $edit = Get-Edit $window '1032'
        Send-Keys $Session 'Border probe'
        $null = Wait-Until { (Read-Edit $edit) -eq 'Border probe' } 'composer border font probe'
        $pattern = $edit.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
        $points = [double]$pattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
        $dpi = [int][VerifyWindow]::GetDpiForWindow([IntPtr]$window.Current.NativeWindowHandle)
        $expectedPoints = [Math]::Floor(($bodySize * $scale * $dpi + 4800) / 9600) * 72 / $dpi
        Assert-That ([Math]::Abs($points - $expectedPoints) -lt 0.1) 'composer border saved text scale was not applied'
        Send-Keys $Session '^a{BACKSPACE}'
        $null = Wait-Until { (Read-Edit $edit) -eq '' } 'composer border empty edit'
        $state = Read-Control $Session status
        $box = $state.composer.box
        $origin = [VerifyWindow+Point]::new()
        Assert-That ([VerifyWindow]::ClientToScreen([IntPtr]$window.Current.NativeWindowHandle, [ref]$origin)) 'composer border client origin unavailable'
        $bounds = $edit.Current.BoundingRectangle
        $text = @($state.composer.controls | Where-Object name -eq 'text')[0]
        Assert-That ([Math]::Abs($bounds.Left - $origin.X - $text.left) -le 1 -and [Math]::Abs($bounds.Top - $origin.Y - $text.top) -le 1 -and [Math]::Abs($bounds.Right - $origin.X - $text.right) -le 1 -and [Math]::Abs($bounds.Bottom - $origin.Y - $text.bottom) -le 1) 'composer border UIA edit bounds mismatch'
        $name = "composer-border-$scale"
        [System.Threading.Thread]::Sleep(300)
        Save-Screen $Session $name
        $desktop = [Windows.Forms.SystemInformation]::VirtualScreen
        $left = [int]($origin.X + $box.left - $desktop.Left)
        $top = [int]($origin.Y + $box.top - $desktop.Top)
        $right = [int]($origin.X + $box.right - $desktop.Left)
        $bottom = [int]($origin.Y + $box.bottom - $desktop.Top)
        $probeX = $left + [int][Math]::Floor(($right - $left) / 3)
        $midY = [int][Math]::Floor(($top + $bottom) / 2)
        $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence "$name.png"))
        try {
            $record = [ordered]@{
                scale_method = 'saved app text scale'; scale = $scale; dpi = $dpi; font_points = $points
                screenshot = "$name.png"; box = $box
                edit = @{ left = $bounds.Left; top = $bounds.Top; right = $bounds.Right; bottom = $bounds.Bottom }
                probes = @{ top = @($probeX, $top); bottom = @($probeX, $bottom); left = @($left, $midY); right = @($right, $midY) }
                top = Measure-ComposerBorder $image $probeX $top 0 1
                bottom = Measure-ComposerBorder $image $probeX $bottom 0 -1
                left = Measure-ComposerBorder $image $left $midY 1 0
                right = Measure-ComposerBorder $image $right $midY -1 0
            }
            $crop = $image.Clone([Drawing.Rectangle]::new($left - 7, $top - 7, $right - $left + 14, $bottom - $top + 14), $image.PixelFormat)
            try { $crop.Save((Join-Path $Session.evidence "$name-box.png"), [Drawing.Imaging.ImageFormat]::Png) } finally { $crop.Dispose() }
        } finally { $image.Dispose() }
        $measurements += $record
        $measurements | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $Session.evidence 'composer-border.json')
    }
    Save-Screen $Session after
    foreach ($measurement in $measurements) { Assert-ComposerBorder $measurement }
    return $App
}

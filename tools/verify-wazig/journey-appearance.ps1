. "$PSScriptRoot/chat-design.ps1"
Add-Type -Path (Join-Path $PSScriptRoot 'layout-capture.cs')
[LayoutCapture]::Display()
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 9) | Out-Null
[LayoutCapture]::MoveWindow($app.MainWindowHandle, 0, 0, 1920, 1032, $true) | Out-Null
Invoke-PaletteCommand $session 'Theme: Graphite' action
$null = Wait-Until { (Read-Control $session status).theme -eq 'amoled' } 'green theme'
$preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
Assert-That ((Get-ItemProperty $preferences).Theme -eq 1) 'Theme preference was not saved'
Assert-That ($null -eq (Get-ItemProperty $preferences).FontScale) 'Fresh fixture already has a saved scale'
Send-Keys $session 'Scale probe'
$textPattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
$baselinePoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
Assert-That ($baselinePoints -gt 0) 'Composer font size is not readable through UI Automation'
Invoke-PaletteCommand $session 'Make text larger'
$null = Wait-Until { (Get-ItemProperty $preferences).FontScale -eq 110 } 'larger text scale persisted'
$larger = (Get-ItemProperty $preferences).FontScale
$largerPoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
Assert-That ($largerPoints -gt $baselinePoints) 'Larger text did not increase the UI Automation font size'
Save-Screen $session text-larger
Send-Keys $session '^0'
$null = Wait-Until { (Get-ItemProperty $preferences).FontScale -eq 100 } 'default text scale restored'
$resetPoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
Assert-That ($resetPoints -eq $baselinePoints) 'Reset did not restore the UI Automation font size'
@{ initial_saved = $false; larger = $larger; reset = (Get-ItemProperty $preferences).FontScale; baseline_points = $baselinePoints; larger_points = $largerPoints; reset_points = $resetPoints } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'text-scale.json')
Send-Keys $session '^a{BACKSPACE}'
$null = Wait-Until { (Read-Edit $compose) -eq '' } 'scale probe cleared'
Save-Screen $session after

Send-Keys $session 'Shared design check'
Send-Keys $session '^d'
$button = [Windows.Automation.AutomationElement]::FromHandle([VerifyWindow]::GetDlgItem($app.MainWindowHandle, 1056))
$null = Wait-Until { $button.Current.BoundingRectangle.Width -ge 116 } 'shared dictation pill expands'
$pill = $button.Current.BoundingRectangle
$null = Wait-Until {
    Save-Screen $session 'shared-design-screen'
    $image = [Drawing.Bitmap]::new((Join-Path $Evidence 'shared-design-screen.png'))
    try {
        $ink = 0; $fill = 0
        for ($y = [int]$pill.Top; $y -lt [int]$pill.Bottom; $y++) {
            for ($x = [int]$pill.Left; $x -lt [int]$pill.Right; $x++) {
                $pixel = $image.GetPixel($x, $y)
                if ($pixel.R -ge 227 -and $pixel.G -ge 227 -and $pixel.B -ge 227) { $ink++ }
                if ($pixel.R -eq 53 -and $pixel.G -eq 53 -and $pixel.B -eq 53) { $fill++ }
            }
        }
        $script:sharedInk = $ink; $script:sharedFill = $fill
        $ink -ge 10 -and $fill -gt ($pill.Width * $pill.Height / 2)
    } finally { $image.Dispose() }
} 'shared dictation paints white on raised grey'
$image = [Drawing.Bitmap]::new((Join-Path $Evidence 'shared-design-screen.png'))
try {
    $frame = $image.Clone([Drawing.Rectangle]::new(0, 0, 1920, 1032), $image.PixelFormat)
    try { $frame.Save((Join-Path $Evidence 'shared-design.png')) } finally { $frame.Dispose() }
    $crop = $image.Clone([Drawing.Rectangle]::new([int]$pill.Left, [int]$pill.Top, [int]$pill.Width, [int]$pill.Height), $image.PixelFormat)
    try { $crop.Save((Join-Path $Evidence 'shared-design-mic.png')) } finally { $crop.Dispose() }
} finally { $image.Dispose() }
@{ width = 1920; height = 1032; draft = (Read-Edit $compose); foreground_pixels = $script:sharedInk; raised_pixels = $script:sharedFill; pill = @{ left = $pill.Left; top = $pill.Top; width = $pill.Width; height = $pill.Height } } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Evidence 'shared-design.json')
Send-Keys $session '^d'
$null = Wait-Until { (Read-Edit $compose) -ceq 'Shared design check Go forward ten meters.' } 'recorded PCM reaches the production composer'
@{ expected = 'Shared design check Go forward ten meters.'; actual = (Read-Edit $compose) } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'dictation-transcript.json') -Encoding utf8
Send-Keys $session '^a{BACKSPACE}'
$null = Wait-Until { (Read-Edit $compose) -ceq '' } 'proof draft cleared'

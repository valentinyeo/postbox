. "$PSScriptRoot/chat-design.ps1"
Add-Type -Path (Join-Path $PSScriptRoot 'layout-capture.cs')
[LayoutCapture]::Display()
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 9) | Out-Null
[LayoutCapture]::MoveWindow($app.MainWindowHandle, 0, 0, 1920, 1032, $true) | Out-Null
$viewport = (Get-Window $session).Current.BoundingRectangle
Assert-That ($viewport.Width -eq 1920 -and $viewport.Height -eq 1032) 'Hosted viewport differs from reported working area'
@{ width = $viewport.Width; height = $viewport.Height; source = 'reported working area'; hosted_only = $true } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'font-viewport.json')
Invoke-PaletteCommand $session 'Theme: Graphite' action
$null = Wait-Until { (Read-Control $session status).theme -eq 'amoled' } 'green theme'
$preferences = "HKCU:\Software\MessagesVerification\$id\Software\Messages"
Assert-That ((Get-ItemProperty $preferences).Theme -eq 1) 'Theme preference was not saved'
Assert-That ($null -eq (Get-ItemProperty $preferences).FontScale) 'Fresh fixture already has a saved scale'
Send-Keys $session 'Scale probe'
$textPattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
$baselinePoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
Assert-That ($baselinePoints -gt 0) 'Composer font size is not readable through UI Automation'
Assert-That ((Read-Control $session status).font_layout.scale -eq 100) 'Fresh default is not 100 percent'
Save-Screen $session text-fresh-default
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
$presetPoints = @()
foreach ($preset in @(
    @{ label = 'Text size: Small'; scale = 80 },
    @{ label = 'Text size: Default'; scale = 100 },
    @{ label = 'Text size: Large'; scale = 125 },
    @{ label = 'Text size: Larger'; scale = 150 }
)) {
    Invoke-PaletteCommand $session $preset.label
    $null = Wait-Until { (Get-ItemProperty $preferences).FontScale -eq $preset.scale -and (Read-Control $session status).font_layout.scale -eq $preset.scale } "saved $($preset.label)"
    $points = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
    $state = Read-Control $session status
    $layout = $state.font_layout
    $shown = Read-Control $session messages
    $message = @($shown.messages | Where-Object id -eq 'GROUP-OWN')[0]
    Assert-That ($null -ne $message -and $message.font_height -lt 0 -and @($message.words).Count -gt 0) 'Painted chat font unavailable'
    $list = Get-Edit (Get-Window $session) '1016'
    $height = [UIntPtr]::Zero
    $ok = [VerifyWindow]::ReadListMetric([IntPtr]$list.Current.NativeWindowHandle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$height)
    Assert-That ($ok -ne [IntPtr]::Zero -and [int]$height.ToUInt64() -eq $layout.row_height) 'Listbox row height differs from painted geometry'
    Assert-That ($layout.preview_top - $layout.name_top -ge [Math]::Max($layout.name_line_height, $layout.time_line_height)) 'List name or time clips vertically'
    Assert-That ($layout.preview_bottom - $layout.preview_top -ge $layout.preview_line_height) 'List preview clips vertically'
    $editBounds = $compose.Current.BoundingRectangle
    Assert-That ($editBounds.Height -ge $layout.body_line_height) 'Composer clips its font vertically'
    foreach ($word in $message.words) {
        Assert-That ($word.rect[0] -ge $message.bubble[0] -and $word.rect[2] -le $message.bubble[2] -and $word.rect[1] -ge $message.bubble[1] -and $word.rect[3] -le $message.bubble[3]) 'Chat text clips outside its bubble'
    }
    if ($presetPoints.Count -gt 0) {
        $previous = $presetPoints[-1]
        Assert-That ($points -gt $previous.points -and $message.font_height -lt $previous.chat_font_height -and $layout.row_font_height -lt $previous.list_font_height) 'Preset did not increase all three fonts'
    }
    Assert-That ($points -gt 0 -and $layout.row_font_height -lt 0) 'Preset font measurements unavailable'
    Save-Screen $session "text-preset-$($preset.scale)"
    $presetPoints += @{ scale = $preset.scale; points = $points; chat_font_height = $message.font_height; list_font_height = $layout.row_font_height; list = $layout; list_uia_height = $list.Current.BoundingRectangle.Height; composer_uia_height = $editBounds.Height }
}
$presetPoints | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $Evidence 'text-presets.json')
Send-Keys $session '^k'
$palette = Get-PaletteWindow $session
$paletteEdit = Get-Edit $palette '1064'
$paletteList = Get-Edit $palette '1072'
$paletteHeight = [UIntPtr]::Zero
$ok = [VerifyWindow]::ReadListMetric([IntPtr]$paletteList.Current.NativeWindowHandle, 0x01A1, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 2000, [ref]$paletteHeight)
$largestLayout = $presetPoints[-1].list
Assert-That ($ok -ne [IntPtr]::Zero -and [int]$paletteHeight.ToUInt64() -ge $largestLayout.body_line_height -and [int]$paletteHeight.ToUInt64() -ge 2 * $largestLayout.preview_line_height + 4) 'Palette rows clip larger text'
Assert-That ($paletteEdit.Current.BoundingRectangle.Height -ge $largestLayout.body_line_height) 'Palette query clips larger text'
@{ row_height = $paletteHeight.ToUInt64(); edit_height = $paletteEdit.Current.BoundingRectangle.Height; body_line_height = $largestLayout.body_line_height; small_line_height = $largestLayout.preview_line_height } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'font-palette.json')
Save-Screen $session text-preset-palette
Send-Keys $session '{ESC}'
$old = Get-App $session
$oldPid = $session.pid
$oldTicks = $session.startTicks
Invoke-PaletteCommand $session 'Quit Postbox'
$null = Wait-Until { $old.Refresh(); $old.HasExited } 'font fixture closed for restart'
$app.StandardError.ReadToEnd() | Set-Content (Join-Path $Evidence 'font-before-restart.stderr.log')
$start.Environment['WAZIG_VERIFY_RESTART'] = $session.id
$app = [Diagnostics.Process]::Start($start)
$session.pid = $app.Id
$session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'session.json')
@{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $session.pid; new_start = $session.startTicks; root = $session.root; id = $session.id; sha256 = $session.sha256 } | ConvertTo-Json | Set-Content (Join-Path $Evidence 'font-restart.json')
$null = Wait-Until { $app.Refresh(); if ($app.HasExited) { throw 'font fixture exited after restart' }; $app.MainWindowHandle -ne [IntPtr]::Zero } 'font fixture restarted'
$null = Wait-Until { (Read-Control $session status).chat_count -eq 3 } 'font fixture chats restored'
Invoke-Doctor $session | Out-Null
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 9) | Out-Null
[LayoutCapture]::MoveWindow($app.MainWindowHandle, 0, 0, 1920, 1032, $true) | Out-Null
$null = Read-Control $session select -Arguments @('fixture-group@g.us', '--provider', 'whatsapp')
$null = Wait-Until { (Read-Control $session status).font_layout.scale -eq 150 -and (Read-Control $session messages).chat.id -eq 'fixture-group@g.us' } 'larger preset survives restart'
Invoke-PaletteCommand $session 'Compose message'
$compose = Get-Edit (Get-Window $session) '1032'
Send-Keys $session '^aScale probe'
$null = Wait-Until { (Read-Edit $compose) -eq 'Scale probe' } 'restart font probe'
$textPattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
$restartPoints = [double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute)
Assert-That ($restartPoints -eq $presetPoints[-1].points -and (Get-ItemProperty $preferences).FontScale -eq 150) 'Restart did not preserve the selected size'
Save-Screen $session text-preset-restart
Send-Keys $session '^0'
$null = Wait-Until { (Get-ItemProperty $preferences).FontScale -eq 100 -and (Read-Control $session status).font_layout.scale -eq 100 } 'preset reset'
Assert-That ([double]$textPattern.DocumentRange.GetAttributeValue([Windows.Automation.TextPattern]::FontSizeAttribute) -eq $baselinePoints) 'Ctrl+0 did not restore default font'
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

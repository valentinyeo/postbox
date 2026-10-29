. "$PSScriptRoot/menus.ps1"
Add-Type -Path "$PSScriptRoot/voice.cs"
Add-Type -Path "$PSScriptRoot/media-fit.cs"

function Set-MediaFitText($Session, [string]$Text) {
    $null = Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/media-fit-text" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body (@{ text = $Text } | ConvertTo-Json) -ContentType 'application/json'
    $null = Invoke-PaletteCommand $Session 'Refresh'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object { $_.id -eq 'fit-own' -and $_.text -ceq $Text }).Count -eq 1 } 'media-fit text refreshed through hub'
}

function Get-MediaFitTarget($Session, [string]$Id) {
    $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $bounds = [VerifyVoice]::Bounds($Session.pid, $canvas)
    $width = $bounds.Right - $bounds.Left
    $height = $bounds.Bottom - $bounds.Top
    $target = Wait-Until {
        $null = [VerifyVoice]::FullRepaint($Session.pid, $canvas)
        $rows = @((Read-Control $Session messages).messages | Where-Object id -eq $Id)
        $null = Assert-That ($rows.Count -eq 1) "media-fit: expected one message for $Id"
        $row = $rows[0]
        if ($row.bubble[2] -gt $row.bubble[0] -and $row.bubble[0] -ge 0 -and $row.bubble[2] -le $width -and $row.bubble[1] -ge 0 -and $row.bubble[3] -le $height) { return $row }
        $direction = if ($row.bubble[1] -lt 0) {
            [Math]::Min(120, -2 * $row.bubble[1])
        } elseif ($row.bubble[3] -gt $height) {
            -[Math]::Min(120, 2 * ($row.bubble[3] - $height))
        } elseif ($row.bubble[2] -eq $row.bubble[0] -and $Id -ne 'fit-own') { 120 } else { -120 }
        $null = [VerifyVoice]::Wheel($Session.pid, [int](($bounds.Left + $bounds.Right) / 2), [int](($bounds.Top + $bounds.Bottom) / 2), $direction)
        return $false
    } "media-fit $Id fully visible"
    return $target
}

function Invoke-MediaFitJourney($Session) {
    $null = Invoke-PaletteCommand $Session 'Verification Media'
    $fixture = Get-Content (Join-Path $Session.evidence 'media-fit-fixture.json') -Raw | ConvertFrom-Json
    $ids = @('landscape', 'portrait')
    if ($fixture.video) { $ids += 'video' }
    $null = Wait-Until {
        $shown = Read-Control $Session messages
        return ($shown.chat.id -eq 'fixture-media@g.us' -and @($shown.messages | Where-Object { $_.media_type -and $_.local }).Count -eq $ids.Count)
    } 'media-fit automatic hub downloads'
    $checks = [Collections.Generic.List[object]]::new()
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($size in @('wide', 'narrow')) {
        if ($size -eq 'narrow') {
            $app = Get-App $Session
            $window = $app.MainWindowHandle
            $null = [VerifyWindow]::ShowWindow($window, 9)
            $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
            $steps = [Collections.Generic.List[object]]::new()
            $dpi = [int][VerifyWindow]::GetDpiForWindow($window)
            $sidebarLimit = [int][Math]::Floor((300 * $dpi + 48) / 96)
            for ($attempt = 0; $attempt -lt 8; $attempt++) {
                $bounds = [VerifyVoice]::Bounds($Session.pid, $canvas)
                $canvasWidth = $bounds.Right - $bounds.Left
                if ($canvasWidth -eq 320) { break }
                $outer = [VerifyVoice]::Bounds($Session.pid, $window)
                $width = $outer.Right - $outer.Left
                $height = $outer.Bottom - $outer.Top
                $gain = if ($canvasWidth -lt $sidebarLimit) { 2 } else { 1 }
                $requestedWidth = $width + $gain * (320 - $canvasWidth)
                $null = Assert-That ([VerifyWindow]::SetWindowPos($window, [IntPtr]::Zero, 0, 0, $requestedWidth, $height, 6)) 'media-fit: native resize failed'
                $null = [VerifyVoice]::FullRepaint($Session.pid, $canvas)
                $after = [VerifyVoice]::Bounds($Session.pid, $canvas)
                $null = $steps.Add([ordered]@{ window_before = $width; canvas_before = $canvasWidth; gain = $gain; requested_window = $requestedWidth; canvas_after = ($after.Right - $after.Left) })
            }
            $bounds = [VerifyVoice]::Bounds($Session.pid, $canvas)
            $canvasWidth = $bounds.Right - $bounds.Left
            [ordered]@{ target = 320; dpi = $dpi; sidebar_limit = $sidebarLimit; canvas = $canvasWidth; steps = $steps.ToArray() } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Session.evidence 'media-fit-resize.json')
            Add-Content (Join-Path $Session.evidence 'actions.log') "resize: media-fit canvas=$canvasWidth target=320"
            $null = Assert-That ($canvasWidth -ge 300 -and $canvasWidth -le 340) "media-fit: native resize missed the 300-340 px canvas band (now $canvasWidth px)"
        }
        $null = Set-MediaFitText $Session 'M M M M M M M M'
        $own = Get-MediaFitTarget $Session 'fit-own'
        $null = Save-Screen $Session "$size-calibration"
        $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
        $bounds = [VerifyVoice]::Bounds($Session.pid, $canvas)
        $canvasWidth = $bounds.Right - $bounds.Left
        $canvasHeight = $bounds.Bottom - $bounds.Top
        $screen = [Windows.Forms.SystemInformation]::VirtualScreen
        $dpi = [int][VerifyWindow]::GetDpiForWindow($canvas)
        $ox = $bounds.Left - $screen.Left
        $oy = $bounds.Top - $screen.Top
        $image = Read-ScreenshotPixels (Join-Path $Session.evidence "$size-calibration.png")
        $step = [VerifyMediaFit]::WordStep($image.bytes, $image.stride, $ox, $oy, [int[]]$own.bubble, $dpi)
        $padding = [int][Math]::Floor((24 * $dpi + 48) / 96)
        $count = [int][Math]::Floor(($own.bubble[2] - $own.bubble[0] - $padding) / $step) - 1
        $null = Set-MediaFitText $Session ((@(1..$count | ForEach-Object { 'M' })) -join ' ')
        foreach ($id in @('fit-own') + $ids) {
            $row = Get-MediaFitTarget $Session $id
            $name = "$size-$id"
            $null = Save-Screen $Session $name
            $shown = Read-Control $Session messages
            $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$name.messages.json")
            $image = Read-ScreenshotPixels (Join-Path $Session.evidence "$name.png")
            $kind = if ($id -eq 'fit-own') { 'own' } else { $id }
            $result = [VerifyMediaFit]::Check($image.bytes, $image.width, $image.height, $image.stride, $ox, $oy, $canvasWidth, $canvasHeight, [int[]]$row.bubble, [int[]]$row.media, $kind, $dpi)
            $null = $checks.Add([ordered]@{ size = $size; id = $id; dpi = $dpi; bubble = $row.bubble; media = $row.media; screenshot = "$name.png"; canvas = @($ox, $oy, $canvasWidth, $canvasHeight); result = $result })
            foreach ($problem in $result.problems) { $null = $problems.Add("${name}: $problem") }
            $checks.ToArray() | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'media-fit-checks.json')
        }
    }
    Read-BridgeRequests $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'media-fit.requests.json')
    $wide = @($checks | Where-Object { $_.size -eq 'wide' -and $_.id -eq 'landscape' })[0]
    $narrow = @($checks | Where-Object { $_.size -eq 'narrow' -and $_.id -eq 'landscape' })[0]
    $null = Assert-That ($wide.bubble[2] - $wide.bubble[0] -gt $narrow.bubble[2] - $narrow.bubble[0]) 'media-fit: native resize did not narrow bubbles'
    $padding = [int][Math]::Floor((24 * $narrow.dpi + 48) / 96)
    $null = Assert-That ($narrow.bubble[2] - $narrow.bubble[0] - $padding -lt $wide.media[2] - $wide.media[0]) 'media-fit: narrow bubble must be smaller than the wide decoded landscape'
    $null = Assert-That ($problems.Count -eq 0) ($problems -join '; ')
    $null = Save-Screen $Session after
}

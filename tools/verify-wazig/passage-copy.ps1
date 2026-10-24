. "$PSScriptRoot/menus.ps1"
Add-Type -Path "$PSScriptRoot/passage-copy.cs"

function Get-PassageMessages($Rows) {
    $messages = @{}
    foreach ($row in $Rows) {
        Assert-That (-not $messages.ContainsKey($row.id)) "Duplicate passage message id: $($row.id)"
        $messages[$row.id] = $row
    }
    return $messages
}

function Get-PassageExpected($Rows, [int]$First, [int]$Last, [bool]$PartialLast) {
    $blocks = @()
    $day = ''
    foreach ($index in $First..$Last) {
        $matches = @($Rows | Where-Object { $_.MsgID -ceq "PASSAGE-$index" })
        Assert-That ($matches.Count -eq 1) "Expected one fixture row for PASSAGE-$index"
        $row = $matches[0]
        $text = $row.Text
        if ($index -eq $First) { $text = $text.Substring($text.IndexOf('MIDDLE')) }
        if ($index -eq $Last -and $PartialLast) { $text = $text.Substring(0, $text.IndexOf('MIDDLE') + 6) }
        $timestamp = if ($row.Timestamp -is [DateTime]) {
            $row.Timestamp.ToUniversalTime()
        } else {
            [DateTimeOffset]::Parse($row.Timestamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime
        }
        $local = $timestamp.ToLocalTime()
        $nextDay = $local.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        if ($day -ne '' -and $day -ne $nextDay) { $blocks += $nextDay }
        $day = $nextDay
        $time = $local.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        $sender = if ($row.FromMe) { 'You' } else { $row.SenderName }
        $blocks += "$sender, ${time}: $($text.Replace("`n", "`r`n"))"
    }
    return $blocks -join "`r`n"
}

function Get-PassageCanvas($Session) {
    $handle = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $rect = [VerifyWindow+Rect]::new()
    $origin = [VerifyWindow+Point]::new()
    Assert-That ([VerifyWindow]::GetClientRect($handle, [ref]$rect)) 'Cannot read passage canvas client bounds'
    Assert-That ([VerifyWindow]::ClientToScreen($handle, [ref]$origin)) 'Cannot map passage canvas to screen'
    $dpi = [int][VerifyWindow]::GetDpiForWindow($handle)
    Assert-That ($dpi -gt 0 -and $rect.Right -gt 0 -and $rect.Bottom -gt 0) 'Passage canvas must have valid DPI and client size'
    return @{ left = $origin.X; top = $origin.Y; width = $rect.Right; height = $rect.Bottom; dpi = $dpi }
}

function Test-PassageVisible($Message, $Canvas) {
    $b = $Message.bubble
    return $b[2] -gt $b[0] -and $b[3] -gt $b[1] -and $b[0] -ge 0 -and $b[1] -ge 0 -and $b[2] -le $Canvas.width -and $b[3] -le $Canvas.height
}

function Get-PassagePoint($Session, $Message, [string]$Shot) {
    $canvas = Get-PassageCanvas $Session
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $image = Read-ScreenshotPixels (Join-Path $Session.evidence "$Shot.png")
    $b = $Message.bubble
    Assert-That (Test-PassageVisible $Message $canvas) 'Target message must be fully visible'
    $point = [VerifyPassage]::Middle($image.bytes, $image.stride, ($canvas.left + $b[0] - $screen.Left), ($canvas.top + $b[1] - $screen.Top), ($canvas.left + $b[2] - $screen.Left), ($canvas.top + $b[3] - $screen.Top), $canvas.dpi)
    return @([int]($point[0] + $screen.Left), [int]($point[1] + $screen.Top))
}

function Assert-PassageHighlight($Session, $Messages, $Canvas, [string]$Name, [string]$Id) {
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $before = Read-ScreenshotPixels (Join-Path $Session.evidence "$Name-before.png")
    $after = Read-ScreenshotPixels (Join-Path $Session.evidence "$Name-after.png")
    Assert-That ($before.width -eq $after.width -and $before.height -eq $after.height -and $before.stride -eq $after.stride) "$Name passage screenshots must have matching dimensions"
    $message = $Messages[$Id]
    Assert-That (Test-PassageVisible $message $Canvas) "$Name $Id highlight must be fully visible"
    $painted = (Get-PassageMessages (Read-Control $Session messages).messages)[$Id]
    Assert-That (($message.bubble -join ',') -eq ($painted.bubble -join ',')) "$Name $Id must not move during the partial drag"
    $b = $message.bubble
    $metric = [VerifyPassage]::Highlight($before.bytes, $after.bytes, $before.stride, ($Canvas.left + $b[0] - $screen.Left), ($Canvas.top + $b[1] - $screen.Top), ($Canvas.left + $b[2] - $screen.Left), ($Canvas.top + $b[3] - $screen.Top), $Canvas.dpi)
    $metric | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Session.evidence "$Name-$Id-highlight.json")
    foreach ($phase in @('before', 'after')) {
        $image = [Drawing.Bitmap]::new((Join-Path $Session.evidence "$Name-$phase.png"))
        try {
            $rect = [Drawing.Rectangle]::new($metric.left, $metric.top, ($metric.right - $metric.left), ($metric.bottom - $metric.top))
            $crop = $image.Clone($rect, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try { $crop.Save((Join-Path $Session.evidence "$Name-$Id-$phase-row.png"), [Drawing.Imaging.ImageFormat]::Png) } finally { $crop.Dispose() }
        } finally { $image.Dispose() }
    }
    $direction = if ($message.from_me) { 'own' } else { 'incoming' }
    $diagnostic = '{0} {1} {2} message highlight not visible: bubble=#{3:X6} fill=#{4:X6} pixels={5} required={6} contrast={7:F3}:1' -f $Name, $Id, $direction, $metric.bubble, $metric.fill, $metric.pixels, $metric.required, $metric.contrast
    Assert-That ($metric.fill -ne $metric.bubble -and $metric.contrast -ge 1.3) "$diagnostic; requires at least 1.3:1 fill contrast"
    Assert-That ($metric.pixels -ge $metric.required) "$diagnostic; requires enough highlight-fill pixels changed from unselected bubble pixels"
}

function Invoke-PassageCopyJourney($Session) {
    $previousDpi = [VerifyPassage]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
    Assert-That ($previousDpi -ne [IntPtr]::Zero) 'Cannot use physical pixels for passage input and screenshots'
    try {
        $fixture = Invoke-RestMethod -Uri "$($Session.bridge_url)/fixture/passage" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' }
        $fixture | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'passage-fixture.json')
        $checks = @()
        $reactionLog = Join-Path $Session.evidence 'react-requests.jsonl'
        Send-Keys $Session '%0'
        foreach ($target in @(
            @{ provider = 'whatsapp'; chat = 'fixture-beta'; search = 'Verification Beta' },
            @{ provider = 'slack'; chat = 'fixture-alpha'; search = 'Verification Alpha' }
        )) {
            $name = $target.provider
            Send-Keys $Session '^f'
            Send-Keys $Session $target.search
            $null = Wait-Until {
                $shown = Read-Control $Session messages
                $messages = Get-PassageMessages $shown.messages
                $shown.chat.id -eq $target.chat -and $shown.chat.provider -eq $name -and $shown.messages.Count -eq 7 -and $messages.ContainsKey('PASSAGE-7') -and $messages['PASSAGE-7'].bubble[2] -gt $messages['PASSAGE-7'].bubble[0]
            } "$name passage history painted"
            Click-Control $Session '1024'
            $canvas = Get-PassageCanvas $Session
            $visible = $false
            for ($step = 0; $step -le 80; $step++) {
                $rows = (Read-Control $Session messages).messages
                $messages = Get-PassageMessages $rows
                $visible = @(2..5 | Where-Object { -not (Test-PassageVisible $messages["PASSAGE-$_"] $canvas) }).Count -eq 0
                if ($visible -or $step -eq 80) { break }
                $x = [int]($canvas.left + $canvas.width / 2)
                $y = [int]($canvas.top + $canvas.height / 2)
                [VerifyMenus]::Hover($Session.pid, $x, $y)
                [VerifyPassage]::Wheel($Session.pid, 120)
                Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: $name wheel up over canvas 1024 step=$($step + 1) x=$x y=$y"
                [System.Threading.Thread]::Sleep(150)
            }
            Assert-That $visible "$name messages 2 through 5 must fit fully inside canvas 1024 after at most 80 wheel steps; canvas=$($canvas.width)x$($canvas.height) message2=$($messages['PASSAGE-2'].bubble -join ',') message5=$($messages['PASSAGE-5'].bubble -join ',')"
            Save-Screen $Session "$name-before"
            $before = (Read-Control $Session messages).messages
            $messages = Get-PassageMessages $before
            Assert-That ($messages['PASSAGE-5'].bubble[3] - $messages['PASSAGE-2'].bubble[1] -le $canvas.height) "$name messages 2 through 5 must fit together in the canvas"
            Assert-That ($messages['PASSAGE-7'].bubble[2] -eq 0) "$name final fixture message must start below the fold"
            $start = Get-PassagePoint $Session $messages['PASSAGE-2'] "$name-before"
            $end = Get-PassagePoint $Session $messages['PASSAGE-5'] "$name-before"
            [VerifyMenus]::Hover($Session.pid, $start[0], $start[1])
            [VerifyPassage]::Button($Session.pid, $true)
            try { [VerifyMenus]::Hover($Session.pid, $end[0], $end[1]) } finally { [VerifyPassage]::Button($Session.pid, $false) }
            Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: $name passage message 2 middle to message 5 middle"
            Send-Keys $Session '^c'
            $actual = [Windows.Forms.Clipboard]::GetText()
            $expected = Get-PassageExpected $fixture.($target.chat) 2 5 $true
            $checks += @{ provider = $name; stage = 'partial'; actual = $actual; expected = $expected; start = $start; end = $end; canvas = $canvas; before = $before }
            ConvertTo-Json -InputObject $checks -Depth 12 | Set-Content (Join-Path $Session.evidence 'clipboard.json')
            Save-Screen $Session "$name-after"
            Assert-That ($actual -ceq $expected) "$name passage clipboard mismatch: expected stamped partial messages 2 through 5"
            Assert-That (@($fixture.($target.chat) | Where-Object { $_.MsgID -ceq 'PASSAGE-3' -and $_.FromMe }).Count -eq 1) "$name PASSAGE-3 must be the own-message highlight target"
            Assert-That (@($fixture.($target.chat) | Where-Object { $_.MsgID -ceq 'PASSAGE-4' -and -not $_.FromMe }).Count -eq 1) "$name PASSAGE-4 must be an incoming highlight target"
            Assert-PassageHighlight $Session $messages $canvas $name 'PASSAGE-4'
            Assert-PassageHighlight $Session $messages $canvas $name 'PASSAGE-3'
            $canvas = Get-PassageCanvas $Session
            $edgeBefore = (Read-Control $Session messages).messages
            $edgeMessages = Get-PassageMessages $edgeBefore
            Assert-That (Test-PassageVisible $edgeMessages['PASSAGE-2'] $canvas) "$name edge drag must start in visible message 2 before message 6"
            Assert-That ($edgeMessages['PASSAGE-7'].bubble[2] -eq 0) "$name message 7 must be below the fold at edge-drag start"
            Assert-That ($edgeMessages['PASSAGE-6'].bubble[2] -gt $edgeMessages['PASSAGE-6'].bubble[0]) "$name tall message 6 must be measurable before edge scrolling"
            $held = @{ messages = @(); scroll_before = $edgeMessages['PASSAGE-6'].bubble[1]; scroll_after = $edgeMessages['PASSAGE-6'].bubble[1] }
            $doubleClickDelay = [int][VerifyPassage]::GetDoubleClickTime() + 100
            [System.Threading.Thread]::Sleep($doubleClickDelay)
            Add-Content (Join-Path $Session.evidence 'actions.log') "Wait: $name edge drag double-click interval plus margin ${doubleClickDelay}ms"
            [VerifyMenus]::Hover($Session.pid, $start[0], $start[1])
            [VerifyPassage]::Button($Session.pid, $true)
            try {
                [VerifyMenus]::Hover($Session.pid, $start[0], ($canvas.top + $canvas.height + [Math]::Max(2, [int](2 * $canvas.dpi / 96))))
                $null = Wait-Until {
                    Assert-That (-not (Test-Path $reactionLog) -or (Get-Item $reactionLog).Length -eq 0) "$name passage-copy must not send reaction requests"
                    $held.messages = (Read-Control $Session messages).messages
                    $heldMessages = Get-PassageMessages $held.messages
                    $held.scroll_after = $heldMessages['PASSAGE-6'].bubble[1]
                    (Test-PassageVisible $heldMessages['PASSAGE-7'] $canvas) -and $heldMessages['PASSAGE-6'].bubble[2] -gt $heldMessages['PASSAGE-6'].bubble[0] -and $held.scroll_after -lt $held.scroll_before
                } "$name held edge drag must scroll canvas 1024 and fully reveal message 7"
                Assert-That ($held.scroll_after -lt $held.scroll_before) "$name read-only message 6 position must change during the held edge drag"
            } finally { [VerifyPassage]::Button($Session.pid, $false) }
            Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: $name held drag beyond canvas 1024 bottom"
            Send-Keys $Session '^c'
            $actual = [Windows.Forms.Clipboard]::GetText()
            $expected = Get-PassageExpected $fixture.($target.chat) 2 7 $false
            $after = (Read-Control $Session messages).messages
            $checks += @{ provider = $name; stage = 'edge'; actual = $actual; expected = $expected; before = $edgeBefore; after = $after; held = $held; canvas = $canvas }
            ConvertTo-Json -InputObject $checks -Depth 12 | Set-Content (Join-Path $Session.evidence 'clipboard.json')
            Save-Screen $Session "$name-edge-after"
            $afterMessages = Get-PassageMessages $after
            Assert-That ($afterMessages['PASSAGE-6'].bubble[2] -gt $afterMessages['PASSAGE-6'].bubble[0] -and $afterMessages['PASSAGE-6'].bubble[1] -lt $edgeMessages['PASSAGE-6'].bubble[1]) "$name held edge drag did not scroll"
            Assert-That ($actual -ceq $expected) "$name edge selection did not extend through final message"
            Assert-That (-not (Test-Path $reactionLog) -or (Get-Item $reactionLog).Length -eq 0) "$name passage-copy must not send reaction requests"
            Hub-Pass $Session "$name-passage"
            Send-Keys $Session '^f'
            Send-Keys $Session '^a{BACKSPACE}{ESC}'
        }
        Save-Screen $Session after
    } finally {
        $null = [VerifyPassage]::SetThreadDpiAwarenessContext($previousDpi)
    }
}

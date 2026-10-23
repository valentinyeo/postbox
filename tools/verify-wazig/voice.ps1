. "$PSScriptRoot/menus.ps1"
Add-Type -Path "$PSScriptRoot/voice.cs"

$script:voiceChecks = @()

function Get-VoiceCanvas($Session) {
    $canvas = Get-Edit (Get-Window $Session) '1024'
    return [IntPtr]$canvas.Current.NativeWindowHandle
}

function Read-VoiceMessages($Session) {
    $shown = Read-Control $Session messages
    if ($shown.chat.id -ne 'fixture-alpha') { return @() }
    return @($shown.messages)
}

function ConvertTo-VoiceRect($Values) {
    $rect = [VerifyVoice+Rect]::new()
    $rect.Left = [int]$Values[0]
    $rect.Top = [int]$Values[1]
    $rect.Right = [int]$Values[2]
    $rect.Bottom = [int]$Values[3]
    return $rect
}

function Get-VoiceLayout($Session) {
    $settled = @{ signature = $null; messages = @() }
    $null = Wait-Until {
        $rows = @(Read-VoiceMessages $Session)
        $signature = ($rows | ForEach-Object { "$($_.id)|$($_.bubble -join ',')|$($_.media -join ',')|$($_.toggle -join ',')|$($_.expanded)|$($_.transcript_chars)" }) -join ';'
        if ($rows.Count -gt 0 -and $signature -ceq $settled.signature) { return $true }
        $settled.signature = $signature
        $settled.messages = $rows
        [System.Threading.Thread]::Sleep(400)
        return $false
    } 'voice layout settled'
    return @{ signature = $settled.signature; messages = $settled.messages }
}

function Get-VoiceRows($Layout) {
    return @($Layout.messages | Where-Object { $_.media_type -eq 'audio' })
}

function Invoke-VoiceProbe($Session, [string]$Name) {
    $handle = Get-VoiceCanvas $Session
    $layout = $null
    foreach ($attempt in 1..3) {
        $layout = Get-VoiceLayout $Session
        [VerifyVoice]::FullRepaint($Session.pid, $handle)
        [System.Threading.Thread]::Sleep(500)
        Save-Screen $Session "$Name-full"
        $visible = @(Get-VoiceRows $layout | Where-Object { $_.bubble[2] -gt $_.bubble[0] -and $_.bubble[3] -gt $_.bubble[1] } | ForEach-Object { ConvertTo-VoiceRect $_.bubble })
        Assert-That ($visible.Count -ge 1) "voice: $Name shows no voice bubble"
        [VerifyVoice]::PlaybackRepaint($Session.pid, $handle, [VerifyVoice+Rect[]]$visible)
        [System.Threading.Thread]::Sleep(500)
        Save-Screen $Session $Name
        $after = Get-VoiceLayout $Session
        if ($after.signature -ceq $layout.signature) { break }
        Assert-That ($attempt -lt 3) "voice: $Name layout kept moving while probing"
    }
    $canvasRect = [VerifyVoice]::Bounds($Session.pid, $handle)
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $partial = Read-ScreenshotPixels (Join-Path $Session.evidence "$Name.png")
    $full = Read-ScreenshotPixels (Join-Path $Session.evidence "$Name-full.png")
    Assert-That ($partial.width -eq $full.width -and $partial.height -eq $full.height -and $partial.stride -eq $full.stride) 'voice: screenshots differ in size'
    $all = @($layout.messages | ForEach-Object { ConvertTo-VoiceRect $_.bubble })
    $items = @(Get-VoiceRows $layout | ForEach-Object {
        $item = [VerifyVoice+Item]::new()
        $item.id = $_.id
        $item.bubble = ConvertTo-VoiceRect $_.bubble
        $item.media = ConvertTo-VoiceRect $_.media
        $item
    })
    $dpi = [int][VerifyWindow]::GetDpiForWindow($handle)
    $result = [VerifyVoice]::Check($partial.bytes, $full.bytes, $partial.width, $partial.height, $partial.stride, $canvasRect, $screen.Left, $screen.Top, [VerifyVoice+Rect[]]$all, [VerifyVoice+Item[]]$items, $dpi)
    $record = [ordered]@{
        step = $Name; partial = "$Name.png"; full = "$Name-full.png"; dpi = $dpi
        canvas = @($canvasRect.Left, $canvasRect.Top, $canvasRect.Right, $canvasRect.Bottom)
        repainted = @($items | Where-Object { $_.bubble.Right -gt $_.bubble.Left } | ForEach-Object { $_.id })
        messages = $layout.messages
        differing = $result.differing; outside = $result.outside; problems = @($result.problems)
    }
    $script:voiceChecks += $record
    $script:voiceChecks | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'voice-checks.json')
    Add-Content (Join-Path $Session.evidence 'actions.log') "probe: $Name repainted $($record.repainted -join ',') differing=$($result.differing) problems=$($result.problems.Count)"
}

function Invoke-VoiceWheel($Session, [int]$Notches) {
    $handle = Get-VoiceCanvas $Session
    $canvasRect = [VerifyVoice]::Bounds($Session.pid, $handle)
    $before = (Get-VoiceLayout $Session).signature
    $x = [int](($canvasRect.Left + $canvasRect.Right) / 2)
    $y = [int](($canvasRect.Top + $canvasRect.Bottom) / 2)
    $step = if ($Notches -gt 0) { 120 } else { -120 }
    foreach ($notch in 1..([Math]::Abs($Notches))) {
        [VerifyVoice]::Wheel($Session.pid, $x, $y, $step)
        [System.Threading.Thread]::Sleep(120)
    }
    Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: wheel $Notches notches x=$x y=$y"
    $null = Wait-Until { (Get-VoiceLayout $Session).signature -cne $before } "voice canvas scrolled $Notches notches"
}

function Open-VoiceChatAgain($Session) {
    Send-Keys $Session '^{TAB}'
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq 'fixture-beta' -and (Read-Control $Session messages).chat.id -eq 'fixture-beta' } 'voice: other chat shown'
    Send-Keys $Session '^+{TAB}'
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq 'fixture-alpha' -and (Read-Control $Session messages).chat.id -eq 'fixture-alpha' } 'voice: voice chat shown again'
}

function Invoke-VoiceJourney($Session, [string]$Messages) {
    $media = Join-Path $Messages 'hub-media'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = @(Read-VoiceMessages $Session | Where-Object { $_.media_type -eq 'audio' })
        $state.selected.id -eq 'fixture-alpha' -and $rows.Count -eq 5
    } 'voice chat open with five voice notes'
    Save-Screen $Session opened
    $null = Wait-Until { @(Get-ChildItem $media -Filter '*.bin' -ErrorAction SilentlyContinue).Count -ge 5 } 'five voice notes downloaded automatically' -Seconds 90
    $null = Wait-Until {
        Open-VoiceChatAgain $Session
        $rows = @(Read-VoiceMessages $Session | Where-Object { $_.media_type -eq 'audio' })
        $rows.Count -eq 5 -and @($rows | Where-Object { -not $_.local }).Count -eq 0
    } 'five voice notes reopened from the local cache' -Seconds 60
    $sentence = 'This synthetic voice note transcript keeps talking about the weekend plan, the train times, the shopping list and the weather so that the cached text wraps across many lines inside the bubble.'
    $transcripts = @()
    $index = 0
    foreach ($file in @(Get-ChildItem $media -Filter '*.ogg' | Sort-Object Name)) {
        $index += 1
        $text = "Voice note $index. " + (@(1..(4 + $index) | ForEach-Object { $sentence }) -join ' ')
        Set-Content -LiteralPath "$($file.FullName).txt" -Value $text -NoNewline -Encoding utf8NoBOM
        $transcripts += [ordered]@{ file = $file.Name; chars = $text.Length }
    }
    Assert-That ($transcripts.Count -eq 5) "voice: expected five cached voice files, found $($transcripts.Count)"
    $transcripts | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Session.evidence 'transcripts.json')
    $null = Wait-Until {
        Open-VoiceChatAgain $Session
        $rows = @(Read-VoiceMessages $Session | Where-Object { $_.media_type -eq 'audio' })
        $rows.Count -eq 5 -and @($rows | Where-Object { $_.transcript_chars -lt 900 }).Count -eq 0
    } 'five cached long transcripts shown' -Seconds 60
    Invoke-VoiceProbe $Session 'voice-opened'
    Invoke-VoiceWheel $Session 4
    Invoke-VoiceProbe $Session 'voice-scrolled-up'
    Invoke-VoiceWheel $Session -2
    Invoke-VoiceProbe $Session 'voice-scrolled-down'
    $handle = Get-VoiceCanvas $Session
    $canvasRect = [VerifyVoice]::Bounds($Session.pid, $handle)
    $height = $canvasRect.Bottom - $canvasRect.Top
    $target = @(Get-VoiceRows (Get-VoiceLayout $Session) | Where-Object { -not $_.expanded -and $_.toggle[1] -ge 0 -and $_.toggle[3] -le $height -and $_.toggle[3] -gt $_.toggle[1] -and $_.bubble[1] -le $_.toggle[1] -and $_.bubble[3] -ge $_.toggle[3] }) | Select-Object -Last 1
    Assert-That ($null -ne $target) 'voice: no visible Show more link'
    $dpi = [int][VerifyWindow]::GetDpiForWindow($handle)
    $x = $canvasRect.Left + $target.toggle[0] + [int][Math]::Floor((20 * $dpi + 48) / 96)
    $y = $canvasRect.Top + [int](($target.toggle[1] + $target.toggle[3]) / 2)
    [VerifyMenus]::Click($Session.pid, $x, $y, $false)
    Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: Show more on $($target.id) x=$x y=$y"
    $null = Wait-Until { @(Read-VoiceMessages $Session | Where-Object { $_.id -eq $target.id -and $_.expanded }).Count -eq 1 } 'voice: transcript expanded with Show more'
    Invoke-VoiceProbe $Session 'voice-expanded'
    Invoke-VoiceWheel $Session 6
    Invoke-VoiceProbe $Session 'voice-expanded-up'
    Invoke-VoiceWheel $Session -3
    Invoke-VoiceProbe $Session 'voice-expanded-down'
    $problems = @($script:voiceChecks | ForEach-Object { $step = $_.step; $_.problems | ForEach-Object { "${step}: $_" } })
    $summary = @($problems | Select-Object -First 8) -join '; '
    Assert-That ($problems.Count -eq 0) $summary
}

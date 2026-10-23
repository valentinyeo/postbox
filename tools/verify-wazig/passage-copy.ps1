. "$PSScriptRoot/menus.ps1"
Add-Type -Path "$PSScriptRoot/passage-copy.cs"

function Get-PassageExpected($Rows, [int]$First, [int]$Last, [bool]$PartialLast) {
    $blocks = @()
    $day = ''
    foreach ($index in $First..$Last) {
        $row = $Rows[$index]
        $text = $row.Text
        if ($index -eq $First) { $text = $text.Substring($text.IndexOf('MIDDLE')) }
        if ($index -eq $Last -and $PartialLast) { $text = $text.Substring(0, $text.IndexOf('MIDDLE') + 6) }
        $nextDay = $row.Timestamp.Substring(0, 10)
        if ($day -ne '' -and $day -ne $nextDay) { $blocks += $nextDay }
        $day = $nextDay
        $sender = if ($row.FromMe) { 'You' } else { $row.SenderName }
        $blocks += "$sender, $($row.Timestamp.Substring(11, 5)): $($text.Replace("`n", "`r`n"))"
    }
    return $blocks -join "`r`n"
}

function Get-PassagePoint($Session, $Message, [string]$Shot) {
    $canvas = Get-Edit (Get-Window $Session) '1024'
    $rect = [VerifyMenus]::Bounds([IntPtr]$canvas.Current.NativeWindowHandle)
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $image = Read-ScreenshotPixels (Join-Path $Session.evidence "$Shot.png")
    $b = $Message.bubble
    Assert-That ($b[2] -gt $b[0] -and $b[1] -ge 0 -and $b[3] -le $rect.Bottom - $rect.Top) 'Target message must be fully visible'
    $dpi = [int][VerifyWindow]::GetDpiForWindow([IntPtr]$canvas.Current.NativeWindowHandle)
    $point = [VerifyPassage]::Middle($image.bytes, $image.stride, ($rect.Left + $b[0] - $screen.Left), ($rect.Top + $b[1] - $screen.Top), ($rect.Left + $b[2] - $screen.Left), ($rect.Top + $b[3] - $screen.Top), $dpi)
    return @([int]($point[0] + $screen.Left), [int]($point[1] + $screen.Top))
}

function Invoke-PassageCopyJourney($Session) {
    $fixture = Invoke-RestMethod -Uri "$($Session.bridge_url)/fixture/passage" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' }
    $fixture | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'passage-fixture.json')
    $checks = @()
    Send-Keys $Session '%0'
    foreach ($target in @(
        @{ provider = 'whatsapp'; chat = 'fixture-beta'; search = 'Verification Beta' },
        @{ provider = 'slack'; chat = 'fixture-alpha'; search = 'Verification Alpha' }
    )) {
        $name = $target.provider
        Send-Keys $Session '^f'
        Send-Keys $Session $target.search
        $null = Wait-Until { $shown = Read-Control $Session messages; $shown.chat.id -eq $target.chat -and $shown.messages.Count -eq 7 } "$name passage history"
        Click-Control $Session '1024'
        $null = Wait-Until {
            Send-Keys $Session '{PGUP}'
            $rows = (Read-Control $Session messages).messages
            $rows[0].bubble[2] -gt $rows[0].bubble[0] -and $rows[0].bubble[1] -ge 0
        } "$name first messages visible"
        Save-Screen $Session "$name-before"
        $before = (Read-Control $Session messages).messages
        Assert-That ($before[6].bubble[2] -eq 0) "$name final fixture message must start below the fold"
        $start = Get-PassagePoint $Session $before[1] "$name-before"
        $end = Get-PassagePoint $Session $before[4] "$name-before"
        [VerifyMenus]::Hover($Session.pid, $start[0], $start[1])
        [VerifyPassage]::Button($Session.pid, $true)
        try { [VerifyMenus]::Hover($Session.pid, $end[0], $end[1]) } finally { [VerifyPassage]::Button($Session.pid, $false) }
        Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: $name passage message 2 middle to message 5 middle"
        Send-Keys $Session '^c'
        $actual = [Windows.Forms.Clipboard]::GetText()
        $expected = Get-PassageExpected $fixture.($target.chat) 1 4 $true
        $checks += @{ provider = $name; stage = 'partial'; actual = $actual; expected = $expected; start = $start; end = $end }
        ConvertTo-Json -InputObject $checks -Depth 12 | Set-Content (Join-Path $Session.evidence 'clipboard.json')
        Save-Screen $Session "$name-after"
        Assert-That ($actual -ceq $expected) "$name passage clipboard mismatch: expected stamped partial messages 2 through 5"
        $canvas = [VerifyMenus]::Bounds([IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle)
        [VerifyMenus]::Hover($Session.pid, $start[0], $start[1])
        [VerifyPassage]::Button($Session.pid, $true)
        try {
            [VerifyMenus]::Hover($Session.pid, $start[0], ($canvas.Bottom + 2))
            $null = Wait-Until {
                $rows = (Read-Control $Session messages).messages
                $rows[6].bubble[2] -gt $rows[6].bubble[0] -and $rows[6].bubble[3] -le $canvas.Bottom - $canvas.Top
            } "$name held edge drag reaches final message"
        } finally { [VerifyPassage]::Button($Session.pid, $false) }
        Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: $name held drag beyond canvas 1024 bottom"
        Send-Keys $Session '^c'
        $actual = [Windows.Forms.Clipboard]::GetText()
        $expected = Get-PassageExpected $fixture.($target.chat) 1 6 $false
        $after = (Read-Control $Session messages).messages
        $checks += @{ provider = $name; stage = 'edge'; actual = $actual; expected = $expected; before = $before; after = $after }
        ConvertTo-Json -InputObject $checks -Depth 12 | Set-Content (Join-Path $Session.evidence 'clipboard.json')
        Save-Screen $Session "$name-edge-after"
        Assert-That ($after[1].bubble[1] -ne $before[1].bubble[1]) "$name held edge drag did not scroll"
        Assert-That ($actual -ceq $expected) "$name edge selection did not extend through final message"
        Hub-Pass $Session "$name-passage"
        Send-Keys $Session '^f'
        Send-Keys $Session '^a{BACKSPACE}{ESC}'
    }
    Save-Screen $Session after
}

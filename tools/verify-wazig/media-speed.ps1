. "$PSScriptRoot/menus.ps1"

function Invoke-MediaSpeedJourney($Session) {
    $ids = @(1..6 | ForEach-Object { "SPEED-IMG-$_" }) + @(1..4 | ForEach-Object { "SPEED-VOICE-$_" })
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-PaletteCommand $Session 'Verification Speed'
    $seen = [ordered]@{}
    $null = Wait-Until {
        $shown = Read-Control $Session messages
        if ($shown.chat.id -ne 'fixture-speed@g.us') { return $false }
        foreach ($row in @($shown.messages | Where-Object { $_.media_type -and $_.local })) {
            if (-not $seen.Contains($row.id)) { $seen[$row.id] = [Math]::Round($timer.Elapsed.TotalSeconds, 2) }
        }
        return (@($ids | Where-Object { $seen.Contains($_) }).Count -eq $ids.Count)
    } 'media-speed: ten images and voice notes downloaded' 40
    $total = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
    $shown = Read-Control $Session messages
    $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'media-speed.messages.json')
    [ordered]@{ ids = $ids; seen = $seen; total_seconds = $total } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Session.evidence 'media-speed.json')
    $null = Save-Screen $Session 'media-speed-done'
    $gone = @($shown.messages | Where-Object { $_.id -ceq 'SPEED-GONE-1' })
    $null = Assert-That ($gone.Count -eq 1 -and -not $gone[0].local) 'media-speed: the gone file must not show as downloaded'
    Read-BridgeRequests $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'media-speed.requests.json')
    $null = Assert-That ($total -lt 15) "media-speed: ten files took $total seconds, limit is 15"
}

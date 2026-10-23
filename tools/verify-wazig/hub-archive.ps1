function Wait-HubArchive($Session, [string]$Messages, [int]$Requests) {
    $null = Wait-Until {
        $writes = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/archive' -and $_.status -eq 200 -and $_.body.chat -eq 'personal:120363000000000001@g.us' -and $_.body.archived })
        $files = @(Get-ChildItem $Messages -Filter 'hub-*-archive-state.txt')
        if ($writes.Count -lt $Requests -or $files.Count -ne 1) { return $false }
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        $state.pending_archives -eq 0 -and -not $state.show_archived -and $state.chat_count -eq 1 -and
            $rows.Count -eq 1 -and $rows[0].id -eq 'personal:15550000003@s.whatsapp.net' -and
            (Get-Content $files[0].FullName -Raw).Contains("personal:120363000000000001@g.us`t1`t")
    } 'legacy kept group re-archived on hub and absent from inbox'
}

function Save-HubArchive($Session, [string]$Messages, [string]$Phase) {
    Save-Screen $Session "$Phase-inbox"
    $files = @(Get-ChildItem $Messages -Filter 'hub-*-archive-state.txt')
    Assert-That ($files.Count -eq 1) 'Hub archive state missing or ambiguous'
    Copy-Item $files[0].FullName (Join-Path $Session.evidence "$Phase-archive-state.txt")
    $markers = @(Get-ChildItem $Messages -Filter 'hub-*-archive-legacy-done.txt')
    Assert-That ($markers.Count -eq 1) 'Hub migration completion marker missing'
    Copy-Item $markers[0].FullName (Join-Path $Session.evidence "$Phase-archive-legacy-done.txt")
    Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats -Arguments @('--archived')).chats
        $state.show_archived -and $state.chat_count -eq 1 -and $rows.Count -eq 1 -and
            $rows[0].id -eq 'personal:120363000000000001@g.us' -and $rows[0].archived
    } 'migrated group visible and kept in Archive'
    Save-Screen $Session "$Phase-archived"
    Invoke-PaletteCommand $Session 'Show inbox chats'
    $null = Wait-Until { $state = Read-Control $Session status; -not $state.show_archived -and $state.chat_count -eq 1 } 'return to inbox'
    Assert-That ((Get-FileHash (Join-Path $Messages 'archive-state.txt')).Hash -eq (Get-FileHash (Join-Path $Session.evidence 'legacy-archive-state.txt')).Hash) 'Legacy archive file was modified'
    Read-BridgeRequests $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Phase.requests.json")
    Hub-Pass $Session $Phase | Out-Host
}

function Invoke-HubArchiveJourney($Session, [string]$Messages, $Start) {
    Save-HubArchive $Session $Messages first
    $old = Get-App $Session
    $oldPid = $Session.pid
    $oldTicks = $Session.startTicks
    Invoke-PaletteCommand $Session 'Quit Messages'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'fixture app closed for archive restart'
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/archive-incoming" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'restart-incoming.json')
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $app = [Diagnostics.Process]::Start($Start)
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    @{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $Session.pid; new_start = $Session.startTicks; root = $Session.root; id = $Session.id; sha256 = $Session.sha256 } |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'restart.json')
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted fixture window'
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    Wait-HubArchive $Session $Messages 2
    Invoke-Doctor $Session | Out-Null
    Save-HubArchive $Session $Messages restart
    Save-Screen $Session after
    return $app
}

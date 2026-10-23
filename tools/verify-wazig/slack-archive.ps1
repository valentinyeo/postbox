function Assert-SlackArchiveView($Session, [bool]$Archived, [int]$Unread, [string]$Capture) {
    $command = if ($Archived) { 'Show archived chats' } else { 'Show inbox chats' }
    if ((Read-Control $Session status).show_archived -ne $Archived) { Invoke-PaletteCommand $Session $command }
    $null = Wait-Until {
        $state = Read-Control $Session status
        $arguments = if ($Archived) { @('--archived') } else { @() }
        $rows = (Read-Control $Session chats -Arguments $arguments).chats
        $target = @($rows | Where-Object id -eq 'fixture-alpha')
        $state.show_archived -eq $Archived -and $state.pending_archives -eq 0 -and $rows.Count -eq 1 -and
            $(if ($Archived) { $target.Count -eq 1 -and $target[0].provider -eq 'slack' -and $target[0].archived -and $target[0].unread_count -eq $Unread } else { $target.Count -eq 0 -and $rows[0].id -eq 'fixture-beta' })
    } "Slack archive view $Capture"
    Save-Screen $Session $Capture
}

function Invoke-SlackArchiveJourney($Session, [string]$Messages, $Start) {
    $null = Send-Keys $Session '%1'
    $null = Send-Keys $Session '^1'
    $null = Wait-Until { $state = Read-Control $Session status; $state.selected.provider -eq 'slack' -and $state.selected.id -eq 'fixture-alpha' } 'Slack channel selected'
    $null = Save-Screen $Session before
    $null = Send-Keys $Session '^e'
    $null = Assert-SlackArchiveView $Session $false 0 archived-inbox
    $null = Assert-SlackArchiveView $Session $true 0 archived
    $null = Assert-SlackArchiveView $Session $false 0 before-incoming
    foreach ($number in 1..3) {
        Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/live" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' | Out-Null
        $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.method -eq 'SSE' -and $_.kind -eq 'msg' -and $_.incoming -eq $number }).Count -gt 0 } "Slack incoming delivery $number"
        $null = Invoke-PaletteCommand $Session 'Refresh'
        $null = Wait-Until { @(Read-BridgeRequests $Session | Where-Object { $_.method -eq 'GET' -and $_.path.StartsWith('/v1/wazig/chats?') -and $_.incoming -eq $number -and $_.archived -eq $false }).Count -gt 0 } "Slack incoming row $number refreshed"
        $null = Assert-SlackArchiveView $Session $false 0 "incoming-$number-inbox"
        $null = Assert-SlackArchiveView $Session $true $number "incoming-$number-archive"
        $null = Assert-SlackArchiveView $Session $false 0 "incoming-$number-hidden"
    }
    $null = Assert-SlackArchiveView $Session $true 3 incoming
    $archiveState = @(Get-ChildItem $Messages -Filter 'hub-*-archive-state.txt')
    $null = Assert-That ($archiveState.Count -eq 1) 'Isolated hub archive state missing'
    $null = Copy-Item $archiveState[0].FullName (Join-Path $Session.evidence 'slack-archive-state.txt')
    $old = Get-App $Session
    $oldPid = $Session.pid
    $oldTicks = $Session.startTicks
    $old.Kill()
    $null = Assert-That ($old.WaitForExit(10000)) 'Recorded fixture PID did not stop'
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $app = [Diagnostics.Process]::Start($Start)
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    @{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $Session.pid; new_start = $Session.startTicks; root = $Session.root; id = $Session.id; sha256 = $Session.sha256 } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'restart.json')
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted Slack archive fixture'
    $null = Get-App $Session
    $null = Assert-That ($app.MainWindowHandle -eq [IntPtr](Get-Window $Session).Current.NativeWindowHandle) 'Restarted process main window does not match owned app window'
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 1 } 'restarted Slack sidebar'
    $null = Assert-SlackArchiveView $Session $false 0 restart-inbox
    Invoke-Doctor $Session | Out-Null
    $null = Assert-SlackArchiveView $Session $true 3 restart
    $null = Send-Keys $Session '^e'
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 0 } 'Slack unarchived from Archive'
    $null = Invoke-PaletteCommand $Session 'Show inbox chats'
    $null = Wait-Until {
        $rows = (Read-Control $Session chats).chats
        $rows.Count -eq 2 -and @($rows | Where-Object { $_.id -eq 'fixture-alpha' -and $_.provider -eq 'slack' -and -not $_.archived }).Count -eq 1
    } 'Slack channel restored to inbox'
    $null = Save-Screen $Session unarchived
    $null = Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 0 } 'Slack Archive empty after unarchive'
    $null = Save-Screen $Session unarchived-archive
    $null = Invoke-PaletteCommand $Session 'Show inbox chats'
    $requests = Read-BridgeRequests $Session
    $null = Assert-That (@($requests | Where-Object { ([Uri]("http://fixture" + $_.path)).AbsolutePath.Contains('archive') }).Count -eq 0) 'Slack archive request reached the fake hub'
    $null = Hub-Pass $Session local-archive-incoming-restart-unarchive
    $null = Save-Screen $Session after
    return $app
}

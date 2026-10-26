function Get-AnyHubArchiveWrites($Session) {
    @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -in @('/v1/wazig/archive', '/v1/wazig/archive-batch') })
}

function Wait-HubArchive($Session, [string]$Messages) {
    $null = Wait-Until {
        $files = @(Get-ChildItem $Messages -Filter 'hub-*-archive-state.txt')
        if ($files.Count -ne 1) { return $false }
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        $state.pending_archives -eq 0 -and -not $state.show_archived -and $state.chat_count -eq 1 -and
            $rows.Count -eq 1 -and $rows[0].id -eq 'personal:15550000003@s.whatsapp.net' -and
            (Get-Content $files[0].FullName -Raw).Contains("personal:120363000000000001@g.us`t1`t")
    } 'legacy kept group stays archived in Wazig and absent from inbox'
    Assert-That ((Get-AnyHubArchiveWrites $Session).Count -eq 0) 'Wazig sent a WhatsApp archive request for the kept group'
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

$script:PlainReacted = 'personal:15550000005@s.whatsapp.net'
$script:PlainNewer = 'personal:15550000006@s.whatsapp.net'

function Select-HubChat($Session, [string]$Id) {
    foreach ($attempt in 1..([Math]::Max(1, (Read-Control $Session status).chat_count))) {
        if ((Read-Control $Session status).selected.id -eq $Id) { return }
        $null = Send-Keys $Session '^{TAB}'
        Start-Sleep -Milliseconds 1500
    }
    Assert-That ((Read-Control $Session status).selected.id -eq $Id) "Chat $Id was not selected"
}

function Read-ControlRefusal($Session, [string]$Command, [string[]]$Arguments, [int]$TimeoutMilliseconds = 15000) {
    $start = [Diagnostics.ProcessStartInfo]::new($Session.ctl)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add($Command)
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $start.Environment['USERNAME'] = $Session.username
    $child = [Diagnostics.Process]::Start($start)
    try {
        $output = $child.StandardOutput.ReadToEndAsync()
        $errorOutput = $child.StandardError.ReadToEndAsync()
        Assert-That ($child.WaitForExit($TimeoutMilliseconds)) "Control client timed out after $TimeoutMilliseconds ms: $Command"
        return $output.GetAwaiter().GetResult() + $errorOutput.GetAwaiter().GetResult()
    } finally {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
        $child.Dispose()
    }
}

function Invoke-HubUnknownIdJourney($Session, [string]$Messages) {
    $before = (Get-AnyHubArchiveWrites $Session).Count
    foreach ($id in @('telegram:user:99999', 'signal:ghost', '99999')) {
        foreach ($command in @('archive', 'unarchive')) {
            $reply = Read-ControlRefusal $Session $command @($id)
            Assert-That ($reply -match 'Unknown chat id') "Control $command of unknown id $id was not refused: $reply"
            Assert-That ($reply -notmatch '"ok"\s*:\s*true') "Control $command of unknown id $id reported success: $reply"
        }
    }
    $state = Read-Control $Session status
    Assert-That ($state.pending_archives -eq 0) 'Unknown ids left a pending archive'
    Assert-That ((Get-AnyHubArchiveWrites $Session).Count -eq $before) 'Unknown ids caused a WhatsApp archive request'
    $files = @(Get-ChildItem $Messages -Filter 'hub-*-archive-state.txt')
    Assert-That ($files.Count -eq 1) 'Hub archive state missing or ambiguous'
    Copy-Item $files[0].FullName (Join-Path $Session.evidence 'unknown-ids-archive-state.txt')
    Hub-Pass $Session unknown-ids | Out-Host
}

function Invoke-ArchiveFixture($Session, [string]$Name) {
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/$Name" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence "$Name.json")
    Invoke-PaletteCommand $Session 'Refresh'
}

function Wait-ArchiveRows($Session, [string[]]$Ids) {
    $null = Wait-Until {
        $state = Read-Control $Session status
        $args = if ($state.show_archived) { @('--archived') } else { @() }
        $rows = @((Read-Control $Session chats -Arguments $args).chats)
        $state.pending_archives -eq 0 -and $rows.Count -eq $Ids.Count -and
            -not (Compare-Object @($rows | ForEach-Object id | Sort-Object) @($Ids | Sort-Object))
    } "archive list matches $($Ids -join ', ')"
}

function Restart-ArchiveFixture($Session, $Start, [string]$Name) {
    $old = Get-App $Session
    $oldPid = $Session.pid
    $oldTicks = $Session.startTicks
    Invoke-PaletteCommand $Session 'Quit Messages'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'fixture app closed for archive restart'
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $app = [Diagnostics.Process]::Start($Start)
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    @{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $Session.pid; new_start = $Session.startTicks; root = $Session.root; id = $Session.id; sha256 = $Session.sha256 } |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence "$Name.json")
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted fixture window'
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    return $app
}

function Invoke-HubArchiveJourney($Session, [string]$Messages, $Start) {
    $other = 'personal:15550000003@s.whatsapp.net'
    $group = 'personal:120363000000000001@g.us'
    $telegram = 'telegram:user:7001'
    Wait-HubArchive $Session $Messages
    Save-HubArchive $Session $Messages first
    Invoke-ArchiveFixture $Session plain-dms
    Wait-ArchiveRows $Session @($other, $script:PlainReacted, $script:PlainNewer)
    Select-HubChat $Session $script:PlainReacted
    $null = Send-Keys $Session '^e'
    Wait-ArchiveRows $Session @($other, $script:PlainNewer)
    $writes = @(Get-AnyHubArchiveWrites $Session)
    Assert-That (@($writes | Where-Object { $_.status -eq 200 -and $_.body.chat -eq $script:PlainReacted -and $_.body.archived }).Count -eq 1) 'WhatsApp did not acknowledge archive'
    Invoke-PaletteCommand $Session 'Show archived chats'
    Wait-ArchiveRows $Session @($group, $script:PlainReacted)
    Save-Screen $Session provider-archived
    Select-HubChat $Session $script:PlainReacted
    $null = Send-Keys $Session '^e'
    Wait-ArchiveRows $Session @($group)
    Assert-That (@(Get-AnyHubArchiveWrites $Session | Where-Object { $_.status -eq 200 -and $_.body.chat -eq $script:PlainReacted -and -not $_.body.archived }).Count -eq 1) 'WhatsApp did not acknowledge unarchive'
    Invoke-PaletteCommand $Session 'Show inbox chats'
    Wait-ArchiveRows $Session @($other, $script:PlainReacted, $script:PlainNewer)
    Select-HubChat $Session $script:PlainReacted
    $null = Send-Keys $Session '^e'
    Wait-ArchiveRows $Session @($other, $script:PlainNewer)
    Invoke-ArchiveFixture $Session phone-unarchive
    Wait-ArchiveRows $Session @($other, $script:PlainReacted, $script:PlainNewer)
    Save-Screen $Session phone-unarchived
    Select-HubChat $Session $script:PlainNewer
    $null = Send-Keys $Session '^e'
    Wait-ArchiveRows $Session @($other, $script:PlainReacted)
    Invoke-ArchiveFixture $Session telegram-dm
    Wait-ArchiveRows $Session @($other, $script:PlainReacted, $telegram)
    $before = (Get-AnyHubArchiveWrites $Session).Count
    Invoke-ArchiveFixture $Session plain-incoming
    Invoke-ArchiveFixture $Session archive-incoming
    Wait-ArchiveRows $Session @($other, $script:PlainReacted, $script:PlainNewer, $telegram)
    Assert-That ((Get-AnyHubArchiveWrites $Session).Count -eq $before) 'Incoming messages caused a Wazig return write'
    Save-Screen $Session provider-incoming
    Invoke-PaletteCommand $Session 'Show archived chats'
    Wait-ArchiveRows $Session @($group)
    Save-Screen $Session kept-incoming
    Invoke-PaletteCommand $Session 'Show inbox chats'
    Select-HubChat $Session $telegram
    $null = Send-Keys $Session '^a'
    $null = Send-Keys $Session '^e'
    Wait-ArchiveRows $Session @()
    Invoke-PaletteCommand $Session 'Show archived chats'
    Wait-ArchiveRows $Session @($group, $other, $script:PlainReacted, $script:PlainNewer, $telegram)
    Select-HubChat $Session $script:PlainReacted
    $null = Send-Keys $Session '^e'
    Wait-ArchiveRows $Session @($group, $other, $script:PlainNewer, $telegram)
    Invoke-PaletteCommand $Session 'Show inbox chats'
    Wait-ArchiveRows $Session @($script:PlainReacted)
    $files = @(Get-ChildItem $Messages -Filter 'hub-*-archive-state.txt')
    Assert-That ($files.Count -eq 1) 'Hub archive state missing or ambiguous'
    $old = Get-App $Session
    Invoke-PaletteCommand $Session 'Quit Messages'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'close before seeding local archive migration'
    "$script:PlainReacted`t0`t2026-10-10T10:00:00Z" | Add-Content $files[0].FullName
    Copy-Item $files[0].FullName (Join-Path $Session.evidence 'migration-before.txt')
    $before = (Get-AnyHubArchiveWrites $Session).Count
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $app = [Diagnostics.Process]::Start($Start)
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'migration fixture window'
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    Wait-ArchiveRows $Session @()
    $null = Wait-Until { -not (Get-Content $files[0].FullName -Raw).Contains("$script:PlainReacted`t") } 'local archive removed only after provider acknowledgement'
    $writes = @(Get-AnyHubArchiveWrites $Session | Select-Object -Skip $before)
    Assert-That ($writes.Count -eq 1 -and $writes[0].status -eq 200 -and $writes[0].body.chat -eq $script:PlainReacted -and $writes[0].body.archived) 'Local archive migration not acknowledged exactly once'
    Copy-Item $files[0].FullName (Join-Path $Session.evidence 'migration-after.txt')
    Invoke-PaletteCommand $Session 'Show archived chats'
    Wait-ArchiveRows $Session @($group, $other, $script:PlainReacted, $script:PlainNewer, $telegram)
    Save-Screen $Session migrated-archived
    Invoke-PaletteCommand $Session 'Show inbox chats'
    $before = (Get-AnyHubArchiveWrites $Session).Count
    $app = Restart-ArchiveFixture $Session $Start restart
    Wait-ArchiveRows $Session @()
    Assert-That ((Get-AnyHubArchiveWrites $Session).Count -eq $before) 'Migration repeated after restart'
    Invoke-HubUnknownIdJourney $Session $Messages
    Save-Screen $Session after
    Read-BridgeRequests $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'provider.requests.json')
    Hub-Pass $Session provider-archive-phone-incoming-kept-migration | Out-Host
    return $app
}

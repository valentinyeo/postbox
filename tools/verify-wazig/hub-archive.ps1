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

$script:PlainReacted = 'personal:15550000005@s.whatsapp.net'
$script:PlainNewer = 'personal:15550000006@s.whatsapp.net'

function Get-HubArchiveWrites($Session, [string]$Chat, [bool]$Archived) {
    @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/archive' -and $_.status -eq 200 -and $_.body.chat -eq $Chat -and $_.body.archived -eq $Archived })
}

function Select-HubChat($Session, [string]$Id) {
    foreach ($attempt in 1..3) {
        if ((Read-Control $Session status).selected.id -eq $Id) { return }
        $null = Send-Keys $Session '^{TAB}'
        Start-Sleep -Milliseconds 1500
    }
    Assert-That ((Read-Control $Session status).selected.id -eq $Id) "Chat $Id was not selected"
}

function Invoke-HubPlainArchive($Session, [string]$Chat) {
    Select-HubChat $Session $Chat
    $null = Send-Keys $Session '^e'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        @(Get-HubArchiveWrites $Session $Chat $true).Count -eq 1 -and $state.pending_archives -eq 0 -and @($rows | Where-Object id -eq $Chat).Count -eq 0
    } "plain archive of $Chat"
}

function Test-HubProbe($Requests, [string]$Chat) {
    @($Requests | Where-Object {
        $_.method -eq 'GET' -and $_.wire_path.StartsWith('/v1/wazig/messages?') -and $_.wire_path.Contains('limit=3&') -and
            [Uri]::UnescapeDataString($_.wire_path).Contains("chat=$Chat&")
    }).Count -gt 0
}

function Invoke-HubPlainJourney($Session, [string]$Messages) {
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/plain-dms" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'plain-dms.json')
    Invoke-PaletteCommand $Session 'Refresh'
    $null = Wait-Until {
        $rows = (Read-Control $Session chats).chats
        $rows.Count -eq 3 -and @($rows | Where-Object { $_.id -eq $script:PlainReacted -or $_.id -eq $script:PlainNewer }).Count -eq 2
    } 'plain direct chats in inbox'
    Invoke-HubPlainArchive $Session $script:PlainReacted
    Invoke-HubPlainArchive $Session $script:PlainNewer
    $files = @(Get-ChildItem $Messages -Filter 'hub-*-archive-state.txt')
    Assert-That ($files.Count -eq 1) 'Hub archive state missing or ambiguous'
    Copy-Item $files[0].FullName (Join-Path $Session.evidence 'plain-archive-state.txt')
    $mark = @(Read-BridgeRequests $Session).Count
    $null = Wait-Until {
        $later = @(Read-BridgeRequests $Session | Select-Object -Skip $mark)
        (Test-HubProbe $later $script:PlainReacted) -and @(Get-HubArchiveWrites $Session $script:PlainNewer $false).Count -gt 0
    } 'archived scan probed the reacted chat and resurfaced the chat with a newer message' 360
    Start-Sleep -Seconds 3
    Assert-That (@(Get-HubArchiveWrites $Session $script:PlainReacted $false).Count -eq 0) 'Plain archived chat came back although only his own reaction followed the archive'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        $state.pending_archives -eq 0 -and -not $state.show_archived -and $rows.Count -eq 2 -and
            @($rows | Where-Object id -eq $script:PlainNewer).Count -eq 1 -and @($rows | Where-Object id -eq $script:PlainReacted).Count -eq 0
    } 'only the chat with a newer message back in the inbox'
    Save-Screen $Session plain-inbox
    Read-BridgeRequests $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'plain.requests.json')
    Hub-Pass $Session plain
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
    Invoke-HubPlainJourney $Session $Messages
    Save-Screen $Session after
    return $app
}

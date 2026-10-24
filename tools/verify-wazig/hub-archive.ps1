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
    foreach ($attempt in 1..([Math]::Max(1, (Read-Control $Session status).chat_count))) {
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
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 360
    $later = @(Read-BridgeRequests $Session | Select-Object -Skip $mark)
    Assert-That (@($later | Where-Object { $_.method -eq 'GET' -and $_.wire_path -like '/v1/wazig/chats?archived=true&*' }).Count -gt 0) 'Archived scan did not run during the plain archive wait'
    @{ elapsed_ms = $clock.ElapsedMilliseconds; requests_before = $mark } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'plain-scan.json')
    Start-Sleep -Seconds 3
    foreach ($chat in @($script:PlainReacted, $script:PlainNewer)) {
        Assert-That (@(Get-HubArchiveWrites $Session $chat $false).Count -eq 0) "Plain archived chat $chat was unarchived without a user action"
    }
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        $state.pending_archives -eq 0 -and -not $state.show_archived -and $rows.Count -eq 1 -and
            $rows[0].id -eq 'personal:15550000003@s.whatsapp.net'
    } 'both plain archived chats absent from the inbox'
    Save-Screen $Session plain-inbox
    Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats -Arguments @('--archived')).chats
        $state.show_archived -and $rows.Count -eq 3 -and
            @($rows | Where-Object { ($_.id -eq $script:PlainReacted -or $_.id -eq $script:PlainNewer) -and $_.archived }).Count -eq 2
    } 'both plain chats still listed in Archive'
    Save-Screen $Session plain-archived
    Invoke-PaletteCommand $Session 'Show inbox chats'
    $null = Wait-Until { $state = Read-Control $Session status; -not $state.show_archived -and $state.chat_count -eq 1 } 'return to inbox after plain archives'
    Read-BridgeRequests $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'plain.requests.json')
    Hub-Pass $Session plain | Out-Host
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
    $app = Invoke-HubTelegramArchiveJourney $Session $Messages $Start
    Save-Screen $Session after
    return $app
}

function Wait-HubEmptyInbox($Session) {
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        -not $state.show_archived -and $state.chat_count -eq 0 -and $rows.Count -eq 0 -and $state.pending_archives -eq 0
    } 'empty combined inbox after Telegram archive'
}

function Invoke-HubTelegramArchiveJourney($Session, [string]$Messages, $Start) {
    $telegram = 'telegram:user:7001'
    $other = 'personal:15550000003@s.whatsapp.net'
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/telegram-dm" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'telegram-dm.json')
    Invoke-PaletteCommand $Session 'Refresh'
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 2 } 'Telegram direct chat joins inbox'
    Invoke-HubPlainArchive $Session $other
    $null = Send-Keys $Session '%i'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        $state.view -eq 'all' -and $state.chat_count -eq 1 -and $state.selected.id -eq $telegram -and
            $rows.Count -eq 1 -and $rows[0].id -eq $telegram -and $rows[0].provider -eq 'telegram' -and $rows[0].account -eq 'telegram'
    } 'Telegram is the only Alt+I inbox row'
    Save-Screen $Session telegram-only
    $null = Send-Keys $Session '^e'
    Wait-HubEmptyInbox $Session
    Assert-That (@(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/archive' -and $_.body.chat -eq $telegram }).Count -eq 0) 'Single Telegram Ctrl+E must archive locally'
    Save-Screen $Session telegram-empty
    Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 5 } 'all five chats in Archive'
    Select-HubChat $Session $telegram
    $null = Send-Keys $Session '^e'
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 4 -and (Read-Control $Session status).pending_archives -eq 0 } 'explicit local Telegram unarchive'
    Invoke-PaletteCommand $Session 'Show inbox chats'
    $null = Wait-Until { $state = Read-Control $Session status; -not $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.id -eq $telegram } 'only Telegram returns after explicit unarchive'
    Save-Screen $Session telegram-unarchived
    $null = Send-Keys $Session '^a'
    $null = Send-Keys $Session '^e'
    Wait-HubEmptyInbox $Session
    Assert-That (@(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/archive' -and $_.body.chat -eq $telegram }).Count -eq 0) 'Telegram bulk archive and explicit unarchive must stay local'
    Save-Screen $Session telegram-bulk-empty
    $old = Get-App $Session
    $oldPid = $Session.pid
    $oldTicks = $Session.startTicks
    Invoke-PaletteCommand $Session 'Quit Messages'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'fixture closed for Telegram archive restart'
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $app = [Diagnostics.Process]::Start($Start)
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    @{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $Session.pid; new_start = $Session.startTicks; root = $Session.root; id = $Session.id; sha256 = $Session.sha256 } |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'telegram-restart.json')
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'Telegram restarted fixture window'
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    $null = Send-Keys $Session '%i'
    Wait-HubEmptyInbox $Session
    Save-Screen $Session telegram-restart-empty
    Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats -Arguments @('--archived')).chats
        $state.show_archived -and $state.chat_count -eq 5 -and @($rows | Where-Object { $_.id -eq $telegram -and $_.archived }).Count -eq 1
    } 'Telegram still archived after restart'
    Save-Screen $Session telegram-restart-archived
    Invoke-PaletteCommand $Session 'Show inbox chats'
    Wait-HubEmptyInbox $Session
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/plain-incoming" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' |
        ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'plain-incoming.json')
    Invoke-PaletteCommand $Session 'Refresh'
    $null = Wait-Until {
        $requests = @(Read-BridgeRequests $Session)
        $attempts = @($requests | Where-Object { $_.wire_path -eq '/v1/wazig/archive' -and $_.status -eq 409 -and $_.body.archived })
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        @($attempts | Where-Object { $_.body.chat -eq $script:PlainNewer }).Count -eq 0 -and
            @(Get-HubArchiveWrites $Session $script:PlainNewer $true).Count -eq 1 -and
            -not $state.show_archived -and $state.chat_count -eq 1 -and $rows.Count -eq 1 -and
            $rows[0].id -eq $script:PlainNewer -and -not $rows[0].archived -and $state.pending_archives -eq 0
    } 'plain WhatsApp returns to inbox without rearchive when the provider unarchives it'
    Save-Screen $Session plain-incoming-inbox
    Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats -Arguments @('--archived')).chats
        $state.show_archived -and $state.chat_count -eq 4 -and $rows.Count -eq 4 -and
            @($rows | Where-Object { $_.id -eq $telegram -and $_.archived }).Count -eq 1 -and
            @($rows | Where-Object id -eq $script:PlainNewer).Count -eq 0
    } 'provider-unarchived Telegram remains local while plain WhatsApp leaves Archive'
    Save-Screen $Session plain-incoming-archived
    Invoke-RestMethod -Method Post -Uri "$($Session.bridge_url)/fixture/rearchive-enable" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' | Out-Null
    Invoke-PaletteCommand $Session 'Show inbox chats'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $rows = (Read-Control $Session chats).chats
        -not $state.show_archived -and $state.chat_count -eq 1 -and $rows.Count -eq 1 -and
            $rows[0].id -eq $script:PlainNewer -and $state.pending_archives -eq 0 -and
            @(Get-HubArchiveWrites $Session $script:PlainNewer $true).Count -eq 1
    } 'plain WhatsApp stays in inbox until an explicit archive'
    Select-HubChat $Session $script:PlainNewer
    $null = Send-Keys $Session '^e'
    $null = Wait-Until {
        @(Get-HubArchiveWrites $Session $script:PlainNewer $true).Count -eq 2 -and
            @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/archive' -and $_.body.chat -eq $telegram }).Count -eq 0 -and (Read-Control $Session status).pending_archives -eq 0
    } 'WhatsApp explicitly archived again and Telegram remains locally archived without a hub write'
    Invoke-PaletteCommand $Session 'Refresh'
    Wait-HubEmptyInbox $Session
    Save-Screen $Session plain-rearchived-inbox
    Invoke-PaletteCommand $Session 'Show archived chats'
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 5 } 're-archived chats remain in Archive'
    Save-Screen $Session plain-rearchived-archived
    $files = @(Get-ChildItem $Messages -Filter 'hub-*-archive-state.txt')
    Assert-That ($files.Count -eq 1) 'Hub archive state missing or ambiguous'
    Copy-Item $files[0].FullName (Join-Path $Session.evidence 'telegram-archive-state.txt')
    Select-HubChat $Session $other
    $null = Send-Keys $Session '^e'
    $null = Wait-Until { @(Get-HubArchiveWrites $Session $other $false).Count -eq 1 -and (Read-Control $Session status).pending_archives -eq 0 } 'restore original inbox chat by explicit unarchive'
    Invoke-PaletteCommand $Session 'Show inbox chats'
    $null = Wait-Until { $state = Read-Control $Session status; -not $state.show_archived -and $state.chat_count -eq 1 -and $state.selected.id -eq $other } 'original inbox preserved'
    Read-BridgeRequests $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'telegram.requests.json')
    Hub-Pass $Session telegram-single-bulk-restart-incoming | Out-Host
    return $app
}

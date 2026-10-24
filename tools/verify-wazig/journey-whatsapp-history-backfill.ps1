Send-Keys $session '%0'
$rows = @((Read-Control $session chats -Arguments @('--json', '--messenger', 'whatsapp')).chats)
$target = @($rows | Where-Object name -eq 'Verification History')[0]
$others = @($rows | Where-Object name -ne 'Verification History')
Assert-That ($rows.Count -eq 3 -and $others.Count -eq 2) 'History fixture identities missing'
foreach ($row in $others) {
    $null = Read-Control $session select -Arguments @($row.id, '--provider', $row.provider, '--account', $row.account)
    $null = Wait-Until { $shown = Read-Control $session messages; $shown.chat.id -eq $row.id -and $shown.messages.Count -eq 1 } 'isolated baseline chat'
    Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$($row.name)-before.messages.json")
}
$null = Read-Control $session select -Arguments @($target.id, '--provider', $target.provider, '--account', $target.account)
$null = Wait-Until { $shown = Read-Control $session messages; $shown.chat.id -eq $target.id -and $shown.messages.Count -eq 65 } '65 stored conversation messages'
$null = Wait-Until {
    Send-Keys $session '{PGUP}'
    @(Read-BridgeRequests $session | Where-Object { $_.history_chat -eq $target.id -and $_.history_before -and $_.history_count -eq 0 }).Count -gt 0
} 'empty older page before phone recovery'
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'initial.messages.json')
Read-BridgeRequests $session | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $Evidence 'initial.requests.json')
Save-Screen $session initial
Hub-Pass $session stored-boundary
$statusHandle = [IntPtr](Get-Edit (Get-Window $session) '1048').Current.NativeWindowHandle
$failures = [ordered]@{
    'in-progress' = 'Older history fetch in progress; try again later'
    'timeout' = 'Older history timed out; not completed, retry Fetch older history'
    'unavailable' = 'Older history unavailable; not completed, retry Fetch older history'
}
foreach ($stage in $failures.Keys) {
    Invoke-PaletteCommand $session 'Fetch older history'
    $expected = $failures[$stage]
    $null = Wait-Until { (Read-EditText $statusHandle) -eq $expected } "$stage retry notice"
    Read-EditText $statusHandle | Set-Content (Join-Path $Evidence "$stage.status.txt")
    $olderCount = @(Read-BridgeRequests $session | Where-Object { $_.history_chat -eq $target.id -and $_.history_before }).Count
    Send-Keys $session '{PGUP}{PGUP}{PGUP}'
    $since = [DateTime]::UtcNow
    $null = Wait-Until {
        $now = @(Read-BridgeRequests $session | Where-Object { $_.history_chat -eq $target.id -and $_.history_before }).Count
        Assert-That ($now -eq $olderCount) "$stage cleared the exhausted flag"
        ([DateTime]::UtcNow - $since).TotalMilliseconds -ge 1000
    } "$stage exhausted flag stays set"
    $shown = Read-Control $session messages
    Assert-That ($shown.messages.Count -eq 65) "$stage claimed unavailable history"
    $shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$stage.messages.json")
    Read-BridgeRequests $session | ConvertTo-Json -Depth 12 -AsArray | Set-Content (Join-Path $Evidence "$stage.requests.json")
    Save-Screen $session $stage
    Hub-Pass $session "$stage-retryable"
}
Invoke-PaletteCommand $session 'Fetch older history' 'backfill-command'
$null = Wait-Until { @(Read-BridgeRequests $session | Where-Object history_phase -eq 'waiting-for-live').Count -eq 1 } 'correctly scoped POST waiting for live arrival'
Invoke-PaletteCommand $session 'Fetch older history'
$null = Wait-Until { (Read-EditText $statusHandle) -eq 'Older history fetch in progress; try again later' } 'local duplicate recovery guard'
Save-Screen $session recovering
Invoke-RestMethod "$($session.bridge_url)/fixture/live" -Method Post -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' | Out-Null
$null = Wait-Until {
    $shown = Read-Control $session messages
    $shown.chat.id -eq $target.id -and $shown.messages.Count -eq 134 -and @($shown.messages | Where-Object id -eq 'HB-LIVE').Count -eq 1
} '133 historical messages plus one live arrival' -Seconds 60
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.history_chat -eq $target.id -and $_.history_before -and $_.history_released -and $_.history_count -eq 0 }).Count -gt 0
} 'recovered pages reach their boundary'
$shown = Read-Control $session messages
$shown | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'recovered.messages.json')
$ids = @($shown.messages | ForEach-Object id)
$expected = @(1..68 | ForEach-Object { 'HB-OLD-{0:000}' -f $_ }) + @(1..65 | ForEach-Object { 'HB-{0:000}' -f $_ }) + @('HB-LIVE')
Assert-That (($ids -join ',') -eq ($expected -join ',')) 'Recovered IDs are missing, duplicated, polluted or out of order'
Assert-That (@($ids | Select-Object -Unique).Count -eq 134) 'History merge duplicated an ID'
Save-Screen $session recovered
Hub-Pass $session scoped-recovery-live-merge
foreach ($row in $others) {
    $null = Read-Control $session select -Arguments @($row.id, '--provider', $row.provider, '--account', $row.account)
    $null = Wait-Until { $shown = Read-Control $session messages; $shown.chat.id -eq $row.id -and $shown.messages.Count -eq 1 } 'other chat and account remain isolated'
    Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence "$($row.name)-after.messages.json")
    Save-Screen $session "$($row.name)-after"
}
Hub-Pass $session chat-account-isolation

. "$PSScriptRoot/paste-image.ps1"
$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$chats = (Read-Control $session chats).chats
$alpha = @($chats | Where-Object { $_.id -ceq 'fixture-alpha' -and $_.provider -ceq 'slack' })
$beta = @($chats | Where-Object { $_.id -ceq 'fixture-beta' -and $_.provider -ceq 'whatsapp' })
Assert-That ($alpha.Count -eq 1 -and $beta.Count -eq 1) 'Fixture identity ambiguous'
$checks = @()
foreach ($trial in @('text', 'file')) {
    Select-FixtureChat $session 'fixture-alpha'
    $null = Wait-Until { (Read-Control $session status).selected.id -ceq 'fixture-alpha' } 'fixture source selected'
    $status = Read-Control $session status
    Assert-That ($status.selected.provider -ceq $alpha[0].provider -and $status.selected.account -ceq $alpha[0].account -and $status.pending_sends -eq 0 -and $status.staged_attachment_count -eq 0 -and $status.reply.id -ceq '') 'Unsafe source state'
    $filename = Join-Path (Join-Path $session.root 'profile') 'independence-image.png'
    if ($trial -eq 'file') {
        [VerifyPasteImage]::Fixture($filename)
        Add-PickerImage $session $filename
        $null = Wait-Until { (Read-Control $session status).staged_attachment_count -eq 1 } 'fixture file staged'
    }
    $body = @{ trial = $trial } | ConvertTo-Json -Compress
    $null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/arm-send-independence" -Headers $headers -ContentType 'application/json' -Body $body
    Invoke-PaletteCommand $session 'Refresh'
    $null = Wait-Until { @(Read-BridgeRequests $session | Where-Object { $_.phase -ceq 'history-start' -and $_.trial -ceq $trial }).Count -eq 1 } 'held history began'
    $status = Read-Control $session status
    Assert-That ($status.selected.id -ceq $alpha[0].id -and $status.selected.provider -ceq $alpha[0].provider -and $status.selected.account -ceq $alpha[0].account) 'Source changed before send'
    $compose = Get-Edit (Get-Window $session) '1032'
    Assert-That ((Read-Edit $compose) -ceq '') 'Fixture composer not empty'
    $compose.SetFocus()
    $focused = [Windows.Automation.AutomationElement]::FocusedElement
    Assert-That ($focused.Current.ProcessId -eq $session.pid -and $focused.Current.AutomationId -ceq '1032' -and $focused.Current.HasKeyboardFocus) 'Composer focus missing'
    $label = if ($trial -eq 'text') { 'Independent fixture text' } else { 'Independent fixture file' }
    Send-Keys $session $label
    Assert-That ((Read-Edit $compose) -ceq $label) 'Fixture text mismatch'
    $marker = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/mark-send-independence" -Headers $headers -ContentType 'application/json' -Body '{}'
    Assert-That $marker.held 'History released before submission'
    Send-Keys $session '{ENTER}'
    $null = Wait-Until { @(Read-BridgeRequests $session | Where-Object { $_.phase -ceq 'send-arrived' -and $_.trial -ceq $trial }).Count -eq 1 } 'outgoing request arrived' 12
    if ($trial -eq 'file') {
        $arrived = @(Read-BridgeRequests $session | Where-Object { $_.phase -ceq 'send-arrived' -and $_.trial -ceq $trial })
        $indexPath = Join-Path $session.evidence 'identity-attempts/index.jsonl'
        $captured = @(Get-Content $indexPath | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.id -ceq $arrived[0].client_id })
        Assert-That ($captured.Count -eq 1 -and $captured[0].payload) 'Protected payload capture missing'
        $snap = Get-Content (Join-Path (Split-Path -Parent $indexPath) $captured[0].snapshot) -Raw | ConvertFrom-Json
        $record = @($snap.records | Where-Object { $_.id -ceq $arrived[0].client_id })
        Assert-That ($record.Count -eq 1 -and (Test-Path -LiteralPath $record[0].owned_file) -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $indexPath) $captured[0].payload))) 'Pending protected file missing'
    }
    Select-FixtureChat $session 'fixture-beta'
    $null = Wait-Until { (Read-Control $session status).selected.id -ceq 'fixture-beta' } 'fixture destination switched'
    $selected = (Read-Control $session status).selected
    Assert-That ($selected.provider -ceq $beta[0].provider -and $selected.account -ceq $beta[0].account) 'Wrong switched chat'
    $null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/switch-send-independence" -Headers $headers -ContentType 'application/json' -Body '{}'
    $null = Wait-Until { @(Read-BridgeRequests $session | Where-Object { $_.phase -ceq 'send-accepted' -and $_.trial -ceq $trial }).Count -eq 1 } 'outgoing accepted' 12
    $null = Wait-Until { @(Read-BridgeRequests $session | Where-Object { $_.phase -ceq 'history-release' -and $_.trial -ceq $trial }).Count -eq 1 } 'history released' 20
    $events = @(Read-BridgeRequests $session | Where-Object { $_.trial -ceq $trial })
    $start = @($events | Where-Object phase -CEQ 'history-start')
    $mark = @($events | Where-Object phase -CEQ 'submit-marker')
    $arrival = @($events | Where-Object phase -CEQ 'send-arrived')
    $switch = @($events | Where-Object phase -CEQ 'switch-marker')
    $accept = @($events | Where-Object phase -CEQ 'send-accepted')
    $release = @($events | Where-Object phase -CEQ 'history-release')
    Assert-That ($start.Count -eq 1 -and $mark.Count -eq 1 -and $arrival.Count -eq 1 -and $switch.Count -eq 1 -and $accept.Count -eq 1 -and $release.Count -eq 1) 'Fixture event count mismatch'
    Assert-That ($start[0].clock_monotonic -and -not $start[0].clock_adjustable -and $start[0].clock_resolution_seconds -gt 0) 'Fixture clock invalid'
    Assert-That ($mark[0].held -and -not $release[0].manual -and -not $accept[0].duplicate -and $mark[0].sequence -lt $arrival[0].sequence -and $arrival[0].sequence -lt $switch[0].sequence -and $switch[0].sequence -lt $accept[0].sequence -and $accept[0].sequence -lt $release[0].sequence) 'Send was not accepted during held history'
    Assert-That ($mark[0].perf_counter_ns -le $accept[0].perf_counter_ns -and $accept[0].perf_counter_ns -le $release[0].perf_counter_ns -and $arrival[0].client_id -ceq $accept[0].client_id) 'Fixture timing or send identity mismatch'
    $indexPath = Join-Path $session.evidence 'identity-attempts/index.jsonl'
    $identity = @(Get-Content $indexPath | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.id -ceq $accept[0].client_id })
    Assert-That ($identity.Count -eq 1 -and $identity[0].attempt -eq 1) 'Checkpoint attempt mismatch'
    $snapshotPath = Join-Path (Split-Path -Parent $indexPath) $identity[0].snapshot
    $snapshot = Get-Content $snapshotPath -Raw | ConvertFrom-Json
    $records = @($snapshot.records | Where-Object { $_.id -ceq $accept[0].client_id })
    Assert-That ($records.Count -eq 1 -and $records[0].phase -ceq 'uncertain' -and $records[0].attempt_serial -eq 1 -and $records[0].attempts -eq 0 -and $records[0].provider -ceq $alpha[0].provider -and $records[0].account -ceq $alpha[0].account -and $records[0].jid -ceq $alpha[0].id -and $records[0].text -ceq $label) 'Checkpoint identity mismatch'
    if ($trial -eq 'file') {
        Assert-That ($records[0].attachment_ready -and $records[0].wire_filename -ceq 'independence-image.png' -and $records[0].file_sha256 -ceq (Get-FileHash $filename).Hash.ToLowerInvariant() -and $records[0].file_bytes -eq (Get-Item $filename).Length) 'Checkpoint attachment mismatch'
    }
    $canonical = if ($trial -eq 'text') { 'INDEPENDENCE-SENT' } else { 'INDEPENDENCE-FILE' }
    Assert-That ($accept[0].canonical_id -ceq $canonical) 'Canonical acknowledgement mismatch'
    if ($trial -eq 'file') {
        Assert-That ($accept[0].filename -ceq 'independence-image.png' -and $accept[0].file_sha256 -ceq (Get-FileHash $filename).Hash.ToLowerInvariant() -and $accept[0].file_bytes -eq (Get-Item $filename).Length) 'Protected file changed'
    }
    $null = Wait-Until {
        $state = Read-Control $session status
        $state.pending_sends -eq 0 -and $state.unified_snapshot.loaded -and $state.unified_snapshot.inflight -eq 0 -and $state.unified_snapshot.hub_jobs -eq 0 -and $state.unified_snapshot.uncertain -eq 0 -and $state.unified_snapshot.held -eq 0 -and $state.unified_snapshot.unsaved_outcomes -eq 0
    } 'outbox acknowledged'
    Select-FixtureChat $session 'fixture-alpha'
    $null = Wait-Until {
        $rows = @((Read-Control $session messages).messages)
        $sent = @($rows | Where-Object { $_.id -ceq $canonical -and $_.text -ceq $label -and $_.send_state -ceq 'none' })
        @($rows | Where-Object id -CEQ 'INDEPENDENCE-HISTORY').Count -eq 1 -and $sent.Count -eq 1 -and @($rows | Where-Object { $_.text -like "$label*sending*" }).Count -eq 0
    } 'canonical message and complete history rendered' 30
    Save-Screen $session "send-independence-after-$trial"
    $checks += @{ trial = $trial; start = $start[0]; submit = $mark[0]; arrival = $arrival[0]; switched = $switch[0]; accepted = $accept[0]; release = $release[0] }
}
$checks | ConvertTo-Json -Depth 8 -AsArray | Set-Content (Join-Path $session.evidence 'send-independence-candidate.json')

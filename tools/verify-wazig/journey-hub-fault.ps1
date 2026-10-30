. "$PSScriptRoot/paste-image.ps1"

function Fault-Requests($Session, [string]$Label) {
    return @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.text -ceq $Label })
}

function Save-FaultEvidence($Session, [string]$Name, [string]$Label) {
    $app = Get-App $Session
    $paths = @(Get-ChildItem (Join-Path $messages 'unified-journal-v2') -Filter 'snapshot.v2' -Recurse -File)
    Assert-That ($paths.Count -eq 1) 'Fault journey needs one snapshot'
    $status = Read-Control $Session status
    $snapshot = Get-Content $paths[0].FullName -Raw | ConvertFrom-Json
    $record = @($snapshot.records | Where-Object { $_.text -ceq $Label })
    Assert-That ($record.Count -eq 1) "Fault record missing: $Name"
    Copy-Item $paths[0].FullName (Join-Path $Session.evidence "$Name.snapshot.json")
    $requests = @(Fault-Requests $Session $Label)
    ConvertTo-Json -InputObject $requests -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.requests.json")
    $status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.status.json")
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.messages.json")
    $bytesHash = (Get-FileHash $paths[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $payloadHash = ''
    if ($record[0].attachment_ready) {
        Assert-That (Test-Path $record[0].owned_file) 'Private payload missing'
        Copy-Item $record[0].owned_file (Join-Path $Session.evidence "$Name.payload")
        $payloadHash = (Get-FileHash $record[0].owned_file -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    @{ pid = $app.Id; start_ticks = $Session.startTicks; exe = $Session.exe; sha256 = $Session.sha256; commit = $Session.commit; root = $Session.root; backend = $Session.bridge_url; composer_text = (Read-Edit (Get-Edit (Get-Window $Session) '1032')); fault = $start.Environment['WAZIG_VERIFY_OUTBOX_FAULT']; transition = $start.Environment['WAZIG_VERIFY_OUTBOX_TRANSITION']; attempt = $start.Environment['WAZIG_VERIFY_OUTBOX_ATTEMPT']; snapshot_sha256 = $bytesHash; payload_sha256 = $payloadHash } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Session.evidence "$Name.meta.json")
    return $record[0]
}

function Restart-FaultApp($Session, [string]$Transition, [string]$Attempt) {
    $old = Get-App $Session
    Invoke-PaletteCommand $Session 'Quit Postbox'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'fault journey app stopped'
    foreach ($name in @('WAZIG_VERIFY_OUTBOX_FAULT', 'WAZIG_VERIFY_OUTBOX_TRANSITION', 'WAZIG_VERIFY_OUTBOX_ATTEMPT')) { $null = $start.Environment.Remove($name) }
    if ($Transition) {
        $start.Environment['WAZIG_VERIFY_OUTBOX_FAULT'] = 'replace'
        $start.Environment['WAZIG_VERIFY_OUTBOX_TRANSITION'] = $Transition
        $start.Environment['WAZIG_VERIFY_OUTBOX_ATTEMPT'] = $Attempt
    }
    $start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $new = [Diagnostics.Process]::Start($start)
    $Session.pid = $new.Id
    $Session.startTicks = $new.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    $null = Wait-Until { $new.Refresh(); $new.MainWindowHandle -ne [IntPtr]::Zero } 'fault journey restart window'
    [VerifyWindow]::ShowWindow($new.MainWindowHandle, 3) | Out-Null
    $null = Wait-Until { (Read-Control $Session status).chat_count -gt 0 } 'fault journey restart chats'
    $null = Read-Control $Session select -Arguments @('fixture-alpha', '--provider', 'slack')
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq 'fixture-alpha' } 'fault journey selected chat'
    Get-App $Session | Out-Null
}

function Start-FaultImage($Session, [string]$Label, [string]$Name) {
    Invoke-PaletteCommand $Session 'Compose message'
    Read-Control $Session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.source.json")
    $path = Join-Path (Join-Path $Session.root 'profile') "$Name.png"
    [VerifyPasteImage]::Fixture($path)
    Copy-Item $path (Join-Path $Session.evidence "$Name.original.png")
    Add-PickerImage $Session $path
    $null = Wait-Until { (Read-Control $Session status).staged_attachment_count -eq 1 } 'fault picker staged image'
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session $Label
    Send-Keys $Session '{ENTER}'
}

function Invoke-FaultManualRetry($Session, $Record, [string]$Name, [string]$Label, [int]$Before) {
    $bubble = Wait-Until {
        (Read-Control $Session messages).messages | Where-Object { $_.time -ceq $Record.id -and $_.text -ceq "$Label (unconfirmed)" -and $_.send_state -ceq 'failed' -and $_.bubble[2] -gt $_.bubble[0] }
    } 'fault restored unconfirmed bubble'
    $null = Save-FaultEvidence $Session "$Name-restart" $Label
    Save-Screen $Session "$Name-restart"
    $initial = @(Fault-Requests $Session $Label)
    Assert-That ($initial.Count -eq $Before) 'Restart sent uncertain record'
    $idleStart = [DateTime]::UtcNow
    Start-Sleep -Seconds 45
    $null = Save-FaultEvidence $Session "$Name-idle" $Label
    Assert-That (@(Fault-Requests $Session $Label).Count -eq $Before) 'Unconfirmed record automatically sent'
    $canvas = [IntPtr](Get-Edit (Get-Window $Session) '1024').Current.NativeWindowHandle
    $point = [VerifyWindow+Point]::new()
    $point.X = [int](($bubble.bubble[0] + $bubble.bubble[2]) / 2)
    $point.Y = [int](($bubble.bubble[1] + $bubble.bubble[3]) / 2)
    Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$point)) 'Fault retry origin missing'
    $null = Save-FaultEvidence $Session "$Name-preclick" $Label
    Assert-That (@(Fault-Requests $Session $Label).Count -eq $Before) 'Fault retry arrived before click'
    $click = [DateTime]::UtcNow
    [VerifyMenus]::Click($Session.pid, $point.X, $point.Y, $false)
    Add-Content (Join-Path $Session.evidence 'actions.log') "SendInput: fault retry $Name x=$($point.X) y=$($point.Y)"
    $null = Wait-Until {
        $s = (Read-Control $Session status).unified_snapshot
        @(Fault-Requests $Session $Label).Count -eq ($Before + 1) -and $s.hub_jobs -eq 0 -and $s.inflight -eq 0 -and $s.ready -eq 0 -and $s.uncertain -eq 0 -and $s.held -eq 0 -and -not $s.storage_blocked -and $s.unsaved_outcomes -eq 0
    } 'fault retry acknowledged' 45
    Read-Control $Session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.complete.status.json")
    @{ idle_start = $idleStart.ToString('o'); click = $click.ToString('o'); before = $Before; after = @(Fault-Requests $Session $Label).Count } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence "$Name.boundary.json")
}

$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$null = Wait-Until { (Read-Control $session status).selected.id -eq 'fixture-alpha' } 'fault chat selected'
Invoke-PaletteCommand $session 'Compose message'
Read-Control $session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'checkpoint.source.json')
Send-Keys $session 'Fault checkpoint'
Send-Keys $session '{ENTER}'
$null = Wait-Until {
    $s = (Read-Control $session status).unified_snapshot
    $s.fault_hits -gt 0 -and $s.storage_blocked -and $s.ready -eq 1 -and $s.uncertain -eq 0 -and $s.inflight -eq 0 -and $s.hub_jobs -eq 0
} 'checkpoint replacement blocked'
Assert-That ((Read-Edit (Get-Edit (Get-Window $session) '1032')) -ceq '') 'Accepted checkpoint input not cleared'
Assert-That (@(Fault-Requests $session 'Fault checkpoint').Count -eq 0) 'Checkpoint failure sent request'
$checkpoint = Save-FaultEvidence $session 'checkpoint-blocked' 'Fault checkpoint'
Start-Sleep -Seconds 3
$null = Save-FaultEvidence $session 'checkpoint-still-blocked' 'Fault checkpoint'
Assert-That (@(Fault-Requests $session 'Fault checkpoint').Count -eq 0) 'Blocked checkpoint sent request'
Restart-FaultApp $session '' ''
$null = Wait-Until {
    $s = (Read-Control $session status).unified_snapshot
    @(Fault-Requests $session 'Fault checkpoint').Count -eq 1 -and $s.hub_jobs -eq 0 -and $s.ready -eq 0 -and $s.uncertain -eq 0 -and $s.inflight -eq 0 -and -not $s.storage_blocked
} 'ready checkpoint resumed once' 45
Read-Control $session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'checkpoint.complete.status.json')
$checkpointApp = Get-App $session
@{ pid = $checkpointApp.Id; start_ticks = $session.startTicks; exe = $session.exe; sha256 = $session.sha256; commit = $session.commit; root = $session.root; backend = $session.bridge_url; fault = $start.Environment['WAZIG_VERIFY_OUTBOX_FAULT']; transition = $start.Environment['WAZIG_VERIFY_OUTBOX_TRANSITION']; attempt = $start.Environment['WAZIG_VERIFY_OUTBOX_ATTEMPT'] } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $session.evidence 'checkpoint-resumed.meta.json')
Hub-Pass $session checkpoint-ready-recovery

Restart-FaultApp $session 'held' '4'
Start-FaultImage $session 'Fault terminal file' terminal
$null = Wait-Until {
    $s = (Read-Control $session status).unified_snapshot
    @(Fault-Requests $session 'Fault terminal file').Count -eq 4 -and $s.fault_hits -gt 0 -and $s.storage_blocked -and $s.unsaved_outcomes -eq 1 -and $s.uncertain -eq 1 -and $s.inflight -eq 0 -and $s.hub_jobs -eq 0
} 'terminal replacement blocked' 100
$terminal = Save-FaultEvidence $session 'terminal-blocked' 'Fault terminal file'
Start-Sleep -Seconds 3
$null = Save-FaultEvidence $session 'terminal-still-blocked' 'Fault terminal file'
Restart-FaultApp $session '' ''
Invoke-FaultManualRetry $session $terminal terminal 'Fault terminal file' 4
Hub-Pass $session terminal-uncertain-recovery

Restart-FaultApp $session 'acknowledged' '1'
Start-FaultImage $session 'Fault ack file' ack
$null = Wait-Until {
    $s = (Read-Control $session status).unified_snapshot
    @(Fault-Requests $session 'Fault ack file').Count -eq 1 -and $s.fault_hits -gt 0 -and $s.storage_blocked -and $s.unsaved_outcomes -eq 1 -and $s.uncertain -eq 1 -and $s.inflight -eq 0 -and $s.hub_jobs -eq 0
} 'acknowledgement replacement blocked' 60
$ack = Save-FaultEvidence $session 'ack-blocked' 'Fault ack file'
Start-Sleep -Seconds 3
$null = Save-FaultEvidence $session 'ack-still-blocked' 'Fault ack file'
Restart-FaultApp $session '' ''
Invoke-FaultManualRetry $session $ack ack 'Fault ack file' 1
Hub-Pass $session acknowledgement-uncertain-recovery
Save-Screen $session after

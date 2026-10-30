. "$PSScriptRoot/rollback-common.ps1"

$beforeRename = $session.feature -ceq 'hub-migration-before-rename'
$oldProof = Get-Content (Join-Path $session.evidence 'historical-847/provenance.json') -Raw | ConvertFrom-Json
Assert-That ($oldProof.old_commit -ceq '84769d3edc2a927eab428bfdbc5e98a31fa0bfc0' -and $oldProof.checked_out_commit -ceq $oldProof.old_commit -and $oldProof.clean_before -and $oldProof.clean_after -and $oldProof.build_exit -eq 0) 'Historical provenance invalid'
$oldExe = (Resolve-Path (Join-Path $session.evidence 'historical-847/old-bin/bin/Messages.exe')).Path
$oldCtl = (Resolve-Path (Join-Path $session.evidence 'historical-847/old-bin/bin/wazigctl.exe')).Path
$oldHash = (Get-FileHash $oldExe -Algorithm SHA256).Hash
Assert-That ($oldHash.ToLowerInvariant() -ceq $oldProof.files.'Messages.exe'.sha256 -and (Get-FileHash $oldCtl).Hash.ToLowerInvariant() -ceq $oldProof.files.'wazigctl.exe'.sha256) 'Historical binary hash differs'
$newExe = $session.exe
$newCtl = $session.ctl
$newHash = $session.sha256
$runnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Assert-That ($oldHash -cne $newHash -and (Process-Sid $session.pid) -ceq $runnerSid) 'Initial process identity differs'
$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$initial = Wait-Until { $s = Read-Control $session status; if ($s.selected.id -ceq 'fixture-alpha' -and $s.selected.provider -ceq 'slack') { $s } } 'migration crash source chat'
$null = Wait-Until { @((Read-Control $session messages).messages | Where-Object id -CEQ 'BASELINE').Count -eq 1 } 'migration crash reply source'
$tag = (Get-Content (Join-Path $messages 'account-tag.txt') -Raw).Trim()
Assert-That ($tag -cmatch '^[0-9a-f]{16}$' -and $tag -ceq $initial.legacy_hub_tag) 'Migration source tag differs'
$initial | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'crash-source.status.json')
@{ root = $session.root; local = $local; profile = $profile; id = $session.id; runner_sid = $runnerSid; backend = $session.bridge_url; source_tag = $tag; new_exe = $newExe; new_sha256 = $newHash; old_exe = $oldExe; old_sha256 = $oldHash } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'crash-ownership.json')
Stop-RollbackApp $session
$cache = Join-Path $messages 'msg-cache-r'
New-Item $cache -ItemType Directory -ErrorAction Stop | Out-Null
Assert-That ([Text.Encoding]::UTF8.GetByteCount($cache + '\*') -le 80) 'Historical cleanup pattern exceeds buffer'
$original = Join-Path $cache 'interrupted-image.png'
[VerifyPasteImage]::Fixture($original)
(Get-Item $original).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-30)
$sourceFile = Get-Item $original
$sourceHash = (Get-FileHash $original -Algorithm SHA256).Hash.ToLowerInvariant()
$sourceLength = $sourceFile.Length
Assert-That ($sourceFile.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-14)) 'Original attachment not old enough'
Copy-Item $original (Join-Path $session.evidence 'crash-original.png')
@{ path = $original; bytes = $sourceFile.Length; sha256 = $sourceHash; written_utc = $sourceFile.LastWriteTimeUtc.ToString('o'); captured_utc = [DateTime]::UtcNow.ToString('o'); exists = $true; pattern_bytes = [Text.Encoding]::UTF8.GetByteCount($cache + '\*') } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'crash-original-before.json')
$id = 'dddddddddddddddddddddddddddddddd'
$row = @{ id = $id; provider = 'slack'; account = $initial.selected.account; jid = $initial.selected.id; text = 'Interrupted image'; file = $original; reply_to = 'BASELINE'; reply_sender = 'fixture-sender'; client_msg_id = ''; attempts = 0; ambiguous = $false; upload_file_id = ''; state = 'queued'; queued_unix = 101; ptt = $false; voice_seconds = 0 }
$legacy = Join-Path $messages "hub-$tag-outbox.jsonl"
Assert-That (-not (Test-Path $legacy)) 'Migration source journal already exists'
[IO.File]::WriteAllText($legacy, (($row | ConvertTo-Json -Compress -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
Copy-Item $legacy (Join-Path $session.evidence 'crash-seed.jsonl')
$start.Environment['WAZIG_VERIFY_RESTART'] = $session.id
$start.Environment['WAZIG_VERIFY_MIGRATION_CASE'] = $session.feature
$start.Environment['WAZIG_VERIFY_MIGRATION_STOP'] = $session.id
Assert-That ((Get-FileHash $newExe).Hash -ceq $newHash -and $start.Environment['LOCALAPPDATA'] -ceq $local) 'Crash launch ownership differs'
$crashed = [Diagnostics.Process]::Start($start)
$crashedTicks = $crashed.StartTime.ToUniversalTime().Ticks.ToString()
$session.pid = $crashed.Id
$session.startTicks = $crashedTicks
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'session.json')
try {
    Assert-That ($crashed.WaitForExit(30000)) 'Migration stop did not exit'
    @{ pid = $crashed.Id; start_ticks = $crashedTicks; sid = $runnerSid; exe = $newExe; sha256 = $newHash; exit_code = $crashed.ExitCode; root = $session.root; local = $local } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'crash-process.json')
    Assert-That ($crashed.ExitCode -eq $(if ($beforeRename) { 85 } else { 86 })) 'Migration stop exited at unexpected phase'
} finally {
    $null = $start.Environment.Remove('WAZIG_VERIFY_MIGRATION_STOP')
    $null = $start.Environment.Remove('WAZIG_VERIFY_MIGRATION_CASE')
    $crashed.Refresh()
    if (-not $crashed.HasExited) {
        Assert-That ($crashed.StartTime.ToUniversalTime().Ticks.ToString() -ceq $crashedTicks -and $crashed.Path -ceq $newExe -and (Get-FileHash $crashed.Path).Hash -ceq $newHash -and (Process-Sid $crashed.Id) -ceq $runnerSid) 'Crash process identity changed'
        $crashed.Kill(); $crashed.WaitForExit()
    }
}
$markerPath = Join-Path $messages 'verification-migration-stop.json'
Copy-Item $markerPath (Join-Path $session.evidence 'crash-marker.json')
$marker = Get-Content $markerPath -Raw | ConvertFrom-Json
$expectedPhase = if ($beforeRename) { 'after-protect-before-rename' } else { 'after-quarantine-before-import' }
Assert-That ($marker.phase -ceq $expectedPhase -and $marker.id -ceq $session.id -and $marker.root -ceq $session.root -and $marker.pid -eq $crashed.Id) 'Migration stop marker differs'
$private = Join-Path $messages 'unified-journal-v2'
$pending = @(Get-ChildItem (Join-Path $private 'imports') -Filter '*.pending' -File)
if ($beforeRename) {
    Assert-That ($pending.Count -eq 0 -and (Test-Path $legacy) -and $marker.source -ceq $legacy -and (Get-FileHash $legacy).Hash -ceq (Get-FileHash (Join-Path $session.evidence 'crash-seed.jsonl')).Hash) 'Pre-rename journal differs'
} else {
    Assert-That ($pending.Count -eq 1 -and -not (Test-Path $legacy) -and (Get-FileHash $pending[0].FullName).Hash -ceq (Get-FileHash (Join-Path $session.evidence 'crash-seed.jsonl')).Hash) 'Quarantined journal differs'
}
$boundary = Get-RollbackFiles $private
ConvertTo-Json -InputObject $boundary -Depth 8 | Set-Content (Join-Path $session.evidence 'crash-boundary.private.json')
Copy-Item $private (Join-Path $session.evidence 'crash-boundary-private') -Recurse
$null = Save-RollbackRequests $session 'crash-boundary'
. "$PSScriptRoot/rollback-offline-cleanup.ps1"
Assert-That (-not (Test-Path $original)) 'Historical cleanup did not delete original'
if ($beforeRename) {
    Assert-That ((Test-Path $legacy) -and (Get-FileHash $legacy).Hash -ceq (Get-FileHash (Join-Path $session.evidence 'crash-seed.jsonl')).Hash) 'Old app changed pre-rename journal'
    Copy-Item $legacy (Join-Path $session.evidence 'crash-source-after-old.jsonl')
}
$null = Start-RollbackApp $session $start $newExe $newCtl $newHash
$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$null = Wait-Until { (Read-Control $session status).selected.id -ceq 'fixture-alpha' } 'migration recovery chat'
$status = Read-Control $session status
$status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'crash-recovery.status.json')
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'crash-recovery.messages.json')
$recoveryFiles = Get-RollbackFiles $private
ConvertTo-Json -InputObject $recoveryFiles -Depth 8 | Set-Content (Join-Path $session.evidence 'crash-recovery.private.json')
Copy-Item $private (Join-Path $session.evidence 'crash-recovery-private') -Recurse
$snapshots = @(Get-ChildItem $private -Filter 'snapshot.v2' -Recurse -File)
$snapshot = $null
if ($snapshots.Count -eq 1) {
    Copy-Item $snapshots[0].FullName (Join-Path $session.evidence 'crash-recovery.snapshot.json')
    $snapshot = Get-Content $snapshots[0].FullName -Raw | ConvertFrom-Json
}
$null = Save-RollbackRequests $session 'crash-recovery'
@{ absent = (-not (Test-Path $original)); pid = $session.pid; start_ticks = $session.startTicks; exe = $session.exe; sha256 = $session.sha256; sid = (Process-Sid $session.pid); root = $session.root; backend = $session.bridge_url } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'crash-recovery.process.json')
Save-Screen $session crash-recovery
$records = if ($null -ne $snapshot) { @($snapshot.records | Where-Object id -CEQ $id) } else { @() }
if ($records.Count -ne 1 -or -not $records[0].attachment_ready -or -not (Test-Path $records[0].owned_file)) { throw 'Interrupted migration lost protected attachment' }
$record = $records[0]
Copy-Item $record.owned_file (Join-Path $session.evidence 'crash-recovery.payload')
Assert-That ($record.phase -ceq 'held' -and $record.ambiguous -and $record.attempt_serial -eq 0 -and $record.file_bytes -eq $sourceLength -and $record.file_sha256 -ceq $sourceHash -and $record.wire_filename -ceq [IO.Path]::GetFileName($original) -and (Get-FileHash $record.owned_file).Hash.ToLowerInvariant() -ceq $sourceHash) 'Recovered migration attachment differs'
foreach ($field in @('id', 'provider', 'account', 'jid', 'text', 'file', 'reply_to', 'reply_sender', 'client_msg_id', 'upload_file_id', 'queued_unix', 'ptt', 'voice_seconds', 'attempts')) {
    Assert-That ($record.$field -ceq $row[$field]) "Recovered migration field differs: $field"
}
Assert-That ($snapshot.backend -ceq $session.bridge_url -and $status.unified_snapshot.held -eq 1 -and $status.unified_snapshot.ready -eq 0 -and $status.unified_snapshot.hub_jobs -eq 0) 'Recovered migration is not held'
$before = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' })
Assert-That ($before.Count -eq 0) 'Interrupted migration automatically sent'
$idleStart = [DateTime]::UtcNow
Start-Sleep -Seconds 45
$null = Save-RollbackRequests $session 'crash-idle'
Assert-That (@(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' }).Count -eq 0) 'Interrupted migration sent during idle'
@{ idle_start = $idleStart.ToString('o'); idle_end = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'crash-idle.json')
$bubble = Wait-Until { (Read-Control $session messages).messages | Where-Object { $_.time -ceq $id -and $_.send_state -ceq 'failed' -and $_.bubble[2] -gt $_.bubble[0] } } 'recovered migration bubble'
$canvas = [IntPtr](Get-Edit (Get-Window $session) '1024').Current.NativeWindowHandle
$point = [VerifyWindow+Point]::new()
$point.X = [int](($bubble.bubble[0] + $bubble.bubble[2]) / 2)
$point.Y = [int](($bubble.bubble[1] + $bubble.bubble[3]) / 2)
Assert-That ([VerifyWindow]::ClientToScreen($canvas, [ref]$point)) 'Migration retry origin missing'
[VerifyMenus]::Click($session.pid, $point.X, $point.Y, $false)
Add-Content (Join-Path $session.evidence 'actions.log') "SendInput: migration retry x=$($point.X) y=$($point.Y)"
$null = Wait-Until { $s = (Read-Control $session status).unified_snapshot; @(Read-BridgeRequests $session | Where-Object { $_.wire_path -eq '/v1/wazig/send' -and $_.body.client_id -ceq $id -and $_.accepted }).Count -eq 1 -and $s.hub_jobs -eq 0 -and $s.inflight -eq 0 -and $s.ready -eq 0 -and $s.uncertain -eq 0 } 'migration retry acknowledged' -Seconds 45
$null = Save-RollbackRequests $session 'crash-retry'
Read-Control $session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'crash-retry.status.json')
Copy-Item (Join-Path $messages "verification-retry-$id-1.json") (Join-Path $session.evidence 'crash-retry.marker.json')
Copy-Item (Join-Path $messages "verification-dispatch-$id-1.json") (Join-Path $session.evidence 'crash-dispatch.marker.json')
Hub-Pass $session interrupted-migration-recovered
Save-Screen $session after

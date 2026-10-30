. "$PSScriptRoot/rollback-common.ps1"

$oldProof = Get-Content (Join-Path $session.evidence 'historical-847/provenance.json') -Raw | ConvertFrom-Json
Assert-That ($oldProof.old_commit -ceq '84769d3edc2a927eab428bfdbc5e98a31fa0bfc0' -and $oldProof.checked_out_commit -ceq $oldProof.old_commit -and $oldProof.clean_before -and $oldProof.clean_after -and $oldProof.build_exit -eq 0) 'Historical provenance invalid'
$oldExe = (Resolve-Path (Join-Path $session.evidence 'historical-847/old-bin/bin/Messages.exe')).Path
$oldCtl = (Resolve-Path (Join-Path $session.evidence 'historical-847/old-bin/bin/wazigctl.exe')).Path
$oldHash = (Get-FileHash $oldExe -Algorithm SHA256).Hash
Assert-That ($oldHash.ToLowerInvariant() -ceq $oldProof.files.'Messages.exe'.sha256 -and (Get-FileHash $oldCtl).Hash.ToLowerInvariant() -ceq $oldProof.files.'wazigctl.exe'.sha256) 'Historical binary hash differs'
$newExe = $session.exe
$newCtl = $session.ctl
$newHash = $session.sha256
Assert-That ($oldExe -cne $newExe -and $oldHash -cne $newHash) 'Historical executable is candidate binary'
$runnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Assert-That ((Process-Sid $session.pid) -ceq $runnerSid) 'Candidate runs as another user'
$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$initial = Wait-Until { $s = Read-Control $session status; if ($s.selected.id -ceq 'fixture-alpha' -and $s.selected.provider -ceq 'slack') { $s } } 'rollback source chat selected'
$null = Wait-Until { @((Read-Control $session messages).messages | Where-Object id -CEQ 'BASELINE').Count -eq 1 } 'rollback source history'
$initial | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'rollback-source.status.json')
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'rollback-source.messages.json')
$tag = (Get-Content (Join-Path $messages 'account-tag.txt') -Raw).Trim()
Assert-That ($tag -cmatch '^[0-9a-f]{16}$' -and $tag -ceq $initial.legacy_hub_tag) 'Backend tag missing or changed'
Copy-Item (Join-Path $messages 'account-tag.txt') (Join-Path $session.evidence 'rollback-account-tag.txt')
Stop-RollbackApp $session
$cache = Join-Path $messages 'msg-cache-r'
New-Item $cache -ItemType Directory -ErrorAction Stop | Out-Null
$pattern = $cache + '\*'
Assert-That ([Text.Encoding]::UTF8.GetByteCount($pattern) -le 80) 'Historical cleanup pattern exceeds buffer'
$original = Join-Path $cache 'rollback-source.png'
[VerifyPasteImage]::Fixture($original)
Copy-Item $original (Join-Path $session.evidence 'rollback-original.png')
$rows = @(
    @{ id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; provider = 'slack'; account = $initial.selected.account; jid = $initial.selected.id; text = 'Rollback text'; file = ''; reply_to = 'BASELINE'; reply_sender = 'fixture-sender'; client_msg_id = ''; attempts = 0; ambiguous = $false; upload_file_id = ''; state = 'queued'; queued_unix = 100; ptt = $false; voice_seconds = 0 },
    @{ id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; provider = 'slack'; account = $initial.selected.account; jid = $initial.selected.id; text = 'Rollback image'; file = $original; reply_to = 'BASELINE'; reply_sender = 'fixture-sender'; client_msg_id = ''; attempts = 0; ambiguous = $false; upload_file_id = ''; state = 'queued'; queued_unix = 101; ptt = $false; voice_seconds = 0 }
)
$legacy = Join-Path $messages "hub-$tag-outbox.jsonl"
Assert-That (-not (Test-Path $legacy)) 'Legacy migration journal already exists'
$lines = @($rows | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 })
[IO.File]::WriteAllText($legacy, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$direct = Join-Path $messages 'outbox.jsonl'
Assert-That (-not (Test-Path $direct)) 'Direct control journal already exists'
$directRow = @{ id = 'cccccccccccccccccccccccccccccccc'; provider = 'signal'; account = 'direct-control'; jid = 'signal:control'; text = 'Direct terminal control'; state = 'failed'; queued_unix = 1 }
[IO.File]::WriteAllText($direct, (($directRow | ConvertTo-Json -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
Copy-Item $legacy (Join-Path $session.evidence 'rollback-seed.jsonl')
Copy-Item $direct (Join-Path $session.evidence 'rollback-direct-before.jsonl')
@{ id = $session.id; root = $session.root; local = $local; profile = $profile; runner_sid = $runnerSid; source_tag = $tag; cleanup_pattern = $pattern; cleanup_pattern_bytes = [Text.Encoding]::UTF8.GetByteCount($pattern); new_exe = $newExe; new_sha256 = $newHash; old_exe = $oldExe; old_sha256 = $oldHash; backend = $session.bridge_url } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $session.evidence 'rollback-ownership.json')
$new = Start-RollbackApp $session $start $newExe $newCtl $newHash
$null = Wait-Until {
    $s = (Read-Control $session status).unified_snapshot
    $s.loaded -and $s.imports_clean -and $s.import_unresolved -eq 0 -and $s.import_overflow -eq 0 -and -not $s.storage_blocked -and $s.held -eq 2 -and $s.ready -eq 0 -and $s.uncertain -eq 0 -and $s.inflight -eq 0 -and $s.hub_jobs -eq 0
} 'complete rollback migration'
$migrated = Save-RollbackPrivate $session 'rollback-new'
Assert-That (@($migrated.records).Count -eq 2 -and @($migrated.records | Where-Object phase -CEQ 'held').Count -eq 2) 'Migration did not hold both records'
$payload = @($migrated.records | Where-Object id -CEQ 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
Assert-That ($payload.Count -eq 1 -and $payload[0].attachment_ready -and (Test-Path $payload[0].owned_file)) 'Migrated payload missing'
Copy-Item $payload[0].owned_file (Join-Path $session.evidence 'rollback-private.payload')
$imports = @(Get-ChildItem (Join-Path $messages 'unified-journal-v2/imports') -Filter '*.pending' -File)
Assert-That ($imports.Count -gt 0) 'Quarantined migration journal missing'
New-Item (Join-Path $session.evidence 'rollback-new-imports') -ItemType Directory | Out-Null
foreach ($import in $imports) { Copy-Item $import.FullName (Join-Path $session.evidence 'rollback-new-imports') }
Copy-Item $direct (Join-Path $session.evidence 'rollback-direct-after-new.jsonl')
Assert-That ((Get-FileHash $direct).Hash -ceq (Get-FileHash (Join-Path $session.evidence 'rollback-direct-before.jsonl')).Hash) 'New migration changed direct journal'
Read-Control $session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'rollback-new.status.json')
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'rollback-new.messages.json')
@{ pid = $session.pid; start_ticks = $session.startTicks; exe = $session.exe; sha256 = $session.sha256; sid = (Process-Sid $session.pid); root = $session.root; local = $local; backend = $session.bridge_url } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $session.evidence 'rollback-new.process.json')
$null = Save-RollbackRequests $session 'rollback-new'
$oldStart = [Diagnostics.ProcessStartInfo]::new($oldExe)
$oldStart.UseShellExecute = $false
$oldStart.ArgumentList.Add('--verify-fixture')
$oldStart.Environment.Clear()
foreach ($entry in $start.Environment.GetEnumerator()) { $oldStart.Environment[$entry.Key] = $entry.Value }
$oldStart.Environment['WAZIG_VERIFY_RESTART'] = $session.id
Assert-That ($oldStart.Environment['LOCALAPPDATA'] -ceq $local -and $oldStart.Environment['USERNAME'] -ceq $session.username) 'Mutex contender profile or identity differs'
$profileBefore = Get-MutexProtectedFiles
$requestsBefore = @(Read-BridgeRequests $session)
$contender = [Diagnostics.Process]::Start($oldStart)
$contenderTicks = $contender.StartTime.ToUniversalTime().Ticks.ToString()
try {
    Assert-That ((Process-Sid $contender.Id) -ceq $runnerSid -and $contender.Path -ceq $oldExe -and (Get-FileHash $contender.Path).Hash -ceq $oldHash) 'Contender ownership differs'
    $dialog = Wait-Until {
        $condition = [Windows.Automation.AndCondition]::new(
            [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty, $contender.Id),
            [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, '#32770'))
        [Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children, $condition)
    } 'historical mutex rejection dialog'
    $elements = $dialog.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
    $labels = @($elements | ForEach-Object { $_.Current.Name })
    $reasons = @($labels | Where-Object { $_ -like '*Postbox is already running*' })
    Assert-That ($reasons.Count -eq 1) 'Unexpected contender rejection'
    $profileAfter = Get-MutexProtectedFiles
    $requestsAfter = @(Read-BridgeRequests $session)
    ConvertTo-Json -InputObject $profileBefore -Depth 8 | Set-Content (Join-Path $session.evidence 'mutex-before.profile.json')
    ConvertTo-Json -InputObject $profileAfter -Depth 8 | Set-Content (Join-Path $session.evidence 'mutex-after.profile.json')
    ConvertTo-Json -InputObject $requestsBefore -Depth 12 | Set-Content (Join-Path $session.evidence 'mutex-before.requests.json')
    ConvertTo-Json -InputObject $requestsAfter -Depth 12 | Set-Content (Join-Path $session.evidence 'mutex-after.requests.json')
    Assert-That ((ConvertTo-Json -InputObject $profileBefore -Depth 8 -Compress) -ceq (ConvertTo-Json -InputObject $profileAfter -Depth 8 -Compress)) 'Protected files changed during mutex rejection'
    $writesBefore = @($requestsBefore | Where-Object { $_.method -cnotin @('GET', 'SSE') })
    $writesAfter = @($requestsAfter | Where-Object { $_.method -cnotin @('GET', 'SSE') })
    Assert-That ((ConvertTo-Json -InputObject $writesBefore -Depth 12 -Compress) -ceq (ConvertTo-Json -InputObject $writesAfter -Depth 12 -Compress)) 'Mutating requests changed during mutex rejection'
    $button = $dialog.FindFirst([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'OK'))
    Assert-That ($null -ne $button) 'Mutex dialog OK missing'
    $button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    Assert-That ($contender.WaitForExit(10000)) 'Mutex contender did not exit'
    @{ pid = $contender.Id; start_ticks = $contenderTicks; sid = $runnerSid; exe = $oldExe; sha256 = $oldHash; local = $local; root = $session.root; reason = $reasons[0]; exit_code = $contender.ExitCode; incumbent_pid = $session.pid; incumbent_start_ticks = $session.startTicks } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $session.evidence 'mutex.json')
} finally {
    $contender.Refresh()
    if (-not $contender.HasExited) {
        Assert-That ($contender.StartTime.ToUniversalTime().Ticks.ToString() -ceq $contenderTicks -and $contender.Path -ceq $oldExe -and (Get-FileHash $contender.Path).Hash -ceq $oldHash) 'Contender PID reused'
        $contender.Kill(); $contender.WaitForExit()
    }
}
Stop-RollbackApp $session
Copy-Item (Join-Path $messages 'launch-log.txt') (Join-Path $session.evidence 'rollback-before-old.launch.log')
$logBefore = Get-Content (Join-Path $session.evidence 'rollback-before-old.launch.log') -Raw
$old = Start-RollbackApp $session $oldStart $oldExe $oldCtl $oldHash
Assert-That ((Process-Sid $session.pid) -ceq $runnerSid) 'Historical app runs as another user'
$oldStatus = Read-Control $session status
$oldStatus | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'rollback-old.status.json')
$null = Save-RollbackRequests $session 'rollback-old-start'
@{ pid = $session.pid; start_ticks = $session.startTicks; exe = $session.exe; sha256 = $session.sha256; sid = (Process-Sid $session.pid); root = $session.root; local = $local; backend = $session.bridge_url } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $session.evidence 'rollback-old.process.json')
$null = Wait-Until {
    $logNow = Get-Content (Join-Path $messages 'launch-log.txt') -Raw
    $logNow.StartsWith($logBefore) -and $logNow.Substring($logBefore.Length).Contains('verification: hub fixture ready')
} 'historical fixture startup logged'
Start-Sleep -Seconds 3
$null = Save-RollbackPrivate $session 'rollback-old'
Copy-Item $payload[0].owned_file (Join-Path $session.evidence 'rollback-old.payload')
$null = Save-RollbackRequests $session 'rollback-old'
Copy-Item (Join-Path $messages 'launch-log.txt') (Join-Path $session.evidence 'rollback-old.launch.log')
$journals = @(Get-ChildItem $messages -Filter '*outbox.jsonl' -File)
New-Item (Join-Path $session.evidence 'rollback-old-journals') -ItemType Directory | Out-Null
foreach ($journal in $journals) { Copy-Item $journal.FullName (Join-Path $session.evidence 'rollback-old-journals') }
Hub-Pass $session complete-migration-old-loader
Hub-Pass $session same-user-profile-mutex
Save-Screen $session after

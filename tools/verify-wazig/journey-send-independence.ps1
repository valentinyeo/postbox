if ($session.expected_version -ceq '0.9.236') {
    Assert-That ($session.sha256 -ceq 'C28BF3C5125E9D6C28144108DFDEEEB603CB8684A23FEEFEA405334F90EE83C3') 'Published executable fingerprint mismatch'
}
$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'outbox idle'
$null = Read-Control $session select -Arguments @('fixture-beta', '--provider', 'whatsapp')
$null = Wait-Until { (Read-Control $session status).selected.id -ceq 'fixture-beta' } 'initial chat'
$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/arm-send-independence" -Headers $headers -ContentType 'application/json' -Body '{}'
$null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
$null = Wait-Until { @(Read-BridgeRequests $session | Where-Object phase -CEQ 'history-start').Count -eq 1 } 'held history began'
$state = Read-Control $session status
Assert-That ($state.selected.id -ceq 'fixture-alpha' -and $state.selected.provider -ceq 'slack') 'Wrong selected fixture chat'
$compose = Get-Edit (Get-Window $session) '1032'
Assert-That ((Read-Edit $compose) -ceq '') 'Fixture composer not empty'
$compose.SetFocus()
Send-Keys $session 'Independent fixture text'
Assert-That ((Read-Edit $compose) -ceq 'Independent fixture text') 'Fixture text mismatch'
Send-Keys $session '{ENTER}'
$submitted = [Diagnostics.Stopwatch]::GetTimestamp()
$trace = @(Read-BridgeRequests $session)
Assert-That (@($trace | Where-Object phase -CEQ 'history-start').Count -eq 1 -and @($trace | Where-Object phase -CEQ 'history-release').Count -eq 0) 'History was not held at submission'
$null = Wait-Until { @(Read-BridgeRequests $session | Where-Object phase -CEQ 'send-accepted').Count -ge 1 } 'synthetic send accepted' 30
$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'synthetic send acknowledged' 30
$null = Wait-Until { @((Read-Control $session messages).messages | Where-Object id -CEQ 'INDEPENDENCE-HISTORY').Count -eq 1 } 'complete history rendered' 30
$trace = @(Read-BridgeRequests $session)
$start = @($trace | Where-Object phase -CEQ 'history-start')
$release = @($trace | Where-Object phase -CEQ 'history-release')
$sends = @($trace | Where-Object phase -CEQ 'send-accepted')
Assert-That ($start.Count -eq 1 -and $release.Count -eq 1 -and $sends.Count -eq 1) 'Unexpected fixture event count'
Assert-That (-not $release[0].manual -and -not $sends[0].duplicate -and $sends[0].canonical_id -ceq 'INDEPENDENCE-SENT') 'Fixture delivery or barrier mismatch'
Assert-That ($start[0].monotonic_ns -lt $release[0].monotonic_ns -and $start[0].monotonic_ns -lt $sends[0].monotonic_ns) 'Fixture event ordering invalid'
if ($session.expected_version -ceq '0.9.236') {
    Assert-That ($release[0].monotonic_ns -lt $sends[0].monotonic_ns) 'Baseline did not block send behind history'
}
@{ version = $session.expected_version; executable_sha256 = $session.sha256; read_start_ns = $start[0].monotonic_ns; read_release_ns = $release[0].monotonic_ns; send_accepted_ns = $sends[0].monotonic_ns; submit_ticks = $submitted; submit_frequency = [Diagnostics.Stopwatch]::Frequency; deliveries = $sends.Count; duplicates = 0; canonical_id = 'INDEPENDENCE-SENT' } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'send-independence-baseline.json')

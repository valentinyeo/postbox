function Select-FixtureChat($Session, [string]$Id) {
    Send-Keys $Session '^k'
    $palette = Get-PaletteWindow $Session
    $edit = Get-Edit $palette '1064'
    $focused = [Windows.Automation.AutomationElement]::FocusedElement
    Assert-That ($focused.Current.ProcessId -eq $Session.pid -and $focused.Current.AutomationId -ceq '1064' -and $focused.Current.HasKeyboardFocus) 'Palette focus missing'
    Assert-That ((Read-Edit $edit) -ceq '') 'Palette query not empty'
    Send-Keys $Session $Id
    Assert-That ((Read-Edit $edit) -ceq $Id) 'Palette query mismatch'
    $focused = [Windows.Automation.AutomationElement]::FocusedElement
    Assert-That ($focused.Current.ProcessId -eq $Session.pid -and $focused.Current.AutomationId -ceq '1064' -and $focused.Current.HasKeyboardFocus) 'Palette focus changed'
    Send-Keys $Session '{ENTER}'
}

if ($session.expected_version -ceq '0.9.236') {
    Assert-That ($session.sha256 -ceq 'C28BF3C5125E9D6C28144108DFDEEEB603CB8684A23FEEFEA405334F90EE83C3') 'Published executable fingerprint mismatch'
}
$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'outbox idle'
$chats = (Read-Control $session chats).chats
$alpha = @($chats | Where-Object { $_.id -ceq 'fixture-alpha' -and $_.provider -ceq 'slack' })
$beta = @($chats | Where-Object { $_.id -ceq 'fixture-beta' -and $_.provider -ceq 'whatsapp' })
Assert-That ($alpha.Count -eq 1 -and $beta.Count -eq 1) 'Fixture identity ambiguous'
Select-FixtureChat $session 'fixture-beta'
$null = Wait-Until { (Read-Control $session status).selected.id -ceq 'fixture-beta' } 'initial chat'
$selected = (Read-Control $session status).selected
Assert-That ($selected.provider -ceq $beta[0].provider -and $selected.account -ceq $beta[0].account -and $selected.view_account -ceq $beta[0].view_account) 'Wrong initial fixture identity'
$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/arm-send-independence" -Headers $headers -ContentType 'application/json' -Body '{}'
Select-FixtureChat $session 'fixture-alpha'
$null = Wait-Until { @(Read-BridgeRequests $session | Where-Object phase -CEQ 'history-start').Count -eq 1 } 'held history began'
$state = Read-Control $session status
Assert-That ($state.selected.id -ceq $alpha[0].id -and $state.selected.provider -ceq $alpha[0].provider -and $state.selected.account -ceq $alpha[0].account -and $state.selected.view_account -ceq $alpha[0].view_account) 'Wrong selected fixture identity'
$compose = Get-Edit (Get-Window $session) '1032'
Assert-That ((Read-Edit $compose) -ceq '') 'Fixture composer not empty'
$compose.SetFocus()
$focused = [Windows.Automation.AutomationElement]::FocusedElement
Assert-That ($focused.Current.ProcessId -eq $session.pid -and $focused.Current.AutomationId -ceq '1032' -and $focused.Current.HasKeyboardFocus) 'Composer focus missing'
Send-Keys $session 'Independent fixture text'
Assert-That ((Read-Edit $compose) -ceq 'Independent fixture text') 'Fixture text mismatch'
$marker = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/mark-send-independence" -Headers $headers -ContentType 'application/json' -Body '{}'
Assert-That ($marker.held -eq $true) 'History released before submission marker'
$focused = [Windows.Automation.AutomationElement]::FocusedElement
Assert-That ($focused.Current.ProcessId -eq $session.pid -and $focused.Current.AutomationId -ceq '1032' -and $focused.Current.HasKeyboardFocus) 'Composer focus changed'
Assert-That ((Read-Edit $compose) -ceq 'Independent fixture text') 'Fixture text changed'
Send-Keys $session '{ENTER}'
$trace = @(Read-BridgeRequests $session)
Assert-That (@($trace | Where-Object phase -CEQ 'history-start').Count -eq 1 -and @($trace | Where-Object phase -CEQ 'history-release').Count -eq 0) 'History was not held through submission'
$null = Wait-Until { @(Read-BridgeRequests $session | Where-Object phase -CEQ 'send-accepted').Count -ge 1 } 'synthetic send accepted' 30
$null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'synthetic send acknowledged' 30
$null = Wait-Until {
    $rows = @((Read-Control $session messages).messages)
    @($rows | Where-Object id -CEQ 'INDEPENDENCE-HISTORY').Count -eq 1 -and @($rows | Where-Object id -CEQ 'INDEPENDENCE-SENT').Count -eq 1
} 'history and canonical send rendered' 30
$trace = @(Read-BridgeRequests $session)
$start = @($trace | Where-Object phase -CEQ 'history-start')
$markers = @($trace | Where-Object phase -CEQ 'submit-marker')
$release = @($trace | Where-Object phase -CEQ 'history-release')
$sends = @($trace | Where-Object phase -CEQ 'send-accepted')
Assert-That ($start.Count -eq 1 -and $markers.Count -eq 1 -and $release.Count -eq 1 -and $sends.Count -eq 1) 'Unexpected fixture event count'
Assert-That ($start[0].clock_monotonic -and -not $start[0].clock_adjustable -and $start[0].clock_resolution_seconds -gt 0) 'Fixture clock invalid'
Assert-That ($markers[0].held -and -not $release[0].manual -and -not $sends[0].duplicate -and $sends[0].canonical_id -ceq 'INDEPENDENCE-SENT') 'Fixture delivery or barrier mismatch'
Assert-That ($start[0].sequence -lt $markers[0].sequence -and $markers[0].sequence -lt $release[0].sequence -and $markers[0].sequence -lt $sends[0].sequence) 'Fixture event ordering invalid'
Assert-That ($start[0].perf_counter_ns -le $markers[0].perf_counter_ns -and $markers[0].perf_counter_ns -le $release[0].perf_counter_ns -and $markers[0].perf_counter_ns -le $sends[0].perf_counter_ns) 'Fixture clock ordering invalid'
if ($session.expected_version -ceq '0.9.236') {
    Assert-That ($release[0].sequence -lt $sends[0].sequence -and $release[0].perf_counter_ns -le $sends[0].perf_counter_ns) 'Baseline did not block send behind history'
}
@{ version = $session.expected_version; executable_sha256 = $session.sha256; read_start = $start[0]; submit_marker = $markers[0]; read_release = $release[0]; send_acceptance = $sends[0]; marker_to_acceptance_ns = ($sends[0].perf_counter_ns - $markers[0].perf_counter_ns); deliveries = 1; duplicates = 0; canonical_id = 'INDEPENDENCE-SENT' } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $session.evidence 'send-independence-baseline.json')

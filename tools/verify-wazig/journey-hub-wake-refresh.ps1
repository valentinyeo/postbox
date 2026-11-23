$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$null = Wait-Until {
    $shown = Read-Control $session messages
    (Read-Control $session status).chat_count -eq 2 -and @($shown.messages | Where-Object id -eq 'BASELINE').Count -eq 1
} 'hub wake baseline ready'
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/mute-sse" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/stale-row" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$resumeStart = [DateTime]::UtcNow
$resumeResult = [UIntPtr]::Zero
$sent = [VerifyWindow]::ReadListMetric((Get-App $session).MainWindowHandle, 0x218, [UIntPtr]0x12, [IntPtr]::Zero, 2, 3000, [ref]$resumeResult)
Assert-That ($sent -ne [IntPtr]::Zero) 'Windows resume notification delivered' -Harness
$null = Wait-Until {
    @((Read-Control $session messages).messages | Where-Object id -eq 'POLL-ROW').Count -eq 1
} 'resume refresh delivered poll row' 15
$resumeMs = ([DateTime]::UtcNow - $resumeStart).TotalMilliseconds
@{ resume_ms = $resumeMs; chat_pulls = @(Read-BridgeRequests $session | Where-Object { $_.path -eq '/v1/chats?' -and $_.status -eq 200 }).Count } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'wake-resume.json')
Assert-That ($resumeMs -lt 15000) 'Simulated resume refresh exceeded fifteen seconds'
Hub-Pass $session wake-resume
$beforeChats = @(Read-BridgeRequests $session | Where-Object { $_.path -eq '/v1/chats?' -and $_.status -eq 200 }).Count
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/stale-row" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$pollStart = [DateTime]::UtcNow
Start-Sleep -Seconds 65
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.path -eq '/v1/chats?' -and $_.status -eq 200 }).Count -gt $beforeChats
} 'safety poll refreshed inbox without SSE' 10
$pollMs = ([DateTime]::UtcNow - $pollStart).TotalMilliseconds
$chatPulls = @(Read-BridgeRequests $session | Where-Object { $_.path -eq '/v1/chats?' -and $_.status -eq 200 })
@{ poll_ms = $pollMs; chat_pulls = $chatPulls.Count } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'safety-poll.json')
Assert-That ($pollMs -le 75000) 'Safety poll exceeded seventy-five seconds'
$sseLive = @(Read-BridgeRequests $session | Where-Object { $_.path -eq '/v1/events' -and $_.id -eq '2' })
Assert-That ($sseLive.Count -eq 0) 'Muted SSE still delivered a live event'
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'poll.messages.json')
Hub-Pass $session safety-poll
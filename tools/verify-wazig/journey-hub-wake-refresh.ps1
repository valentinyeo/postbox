$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$null = Wait-Until {
    $shown = Read-Control $session messages
    (Read-Control $session status).chat_count -eq 2 -and @($shown.messages | Where-Object id -eq 'BASELINE').Count -eq 1
} 'hub wake baseline ready'
$canvasElement = Wait-Until {
    $element = (Get-Window $session).FindFirst([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty, 'WacliMessageCanvas'))
    if ($null -ne $element) { $element }
} 'chat canvas for the sync line'
$desktop = [Windows.Forms.SystemInformation]::VirtualScreen
$syncRect = {
    param($state)
    $bounds = $canvasElement.Current.BoundingRectangle
    @([int]($bounds.Left + $state.sync_rect[0] - $desktop.Left), [int]($bounds.Top + $state.sync_rect[1] - $desktop.Top), [int]($bounds.Left + $state.sync_rect[2] - $desktop.Left), [int]($bounds.Top + $state.sync_rect[3] - $desktop.Top))
}
$caughtUp = Wait-Until {
    $state = Read-Control $session status
    if ($state.sync_state -ceq 'caught_up' -and $state.sync_as_of -cmatch '^\d\d:\d\d$' -and $null -ne $state.sync_rect) { $state }
} 'the chat header shows the last sync time'
Assert-That ($caughtUp.sync_line -clike 'Up to date*' -and $caughtUp.sync_line.EndsWith($caughtUp.sync_as_of)) 'Caught-up line does not name the last sync time'
$caughtUpRect = & $syncRect $caughtUp
Save-Screen $session sync-caught-up
$launchLogPath = Join-Path $messages 'launch-log.txt'
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/drop-events" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$null = Wait-Until {
    $log = Get-Content $launchLogPath -Raw
    $log -match 'retry in 1000 ms' -and $log -match 'retry in 2000 ms' -and $log -match 'retry in 4000 ms'
} 'reconnect retries slow down after each failure' 60
$offline = Wait-Until {
    $state = Read-Control $session status
    if ($state.sync_state -ceq 'offline' -and $state.sync_line -clike 'Offline*') { $state }
} 'the chat header says the inbox is offline'
Assert-That ($offline.sync_line.Contains($caughtUp.sync_as_of) -or $offline.sync_as_of -match '^\d\d:\d\d$') 'Offline line lost the last sync time'
$offlineRect = & $syncRect $offline
Save-Screen $session sync-offline
$hubLines = @(Get-Content $launchLogPath | Where-Object { $_ -match 'hub events: ' })
$retries = @($hubLines | Where-Object { $_ -match 'retry in \d+ ms' } | ForEach-Object { [int]($_ -replace '.*retry in (\d+) ms.*', '$1') })
Assert-That ($retries.Count -ge 3 -and $retries[0] -eq 1000 -and $retries[1] -eq 2000 -and $retries[2] -eq 4000) 'Retry waits did not double then cap'
Assert-That (@($retries | Select-Object -Unique).Count -eq $retries.Count) 'Repeated retry waits were logged more than once'
$offlineConnected = @($hubLines | Where-Object { $_ -match 'hub events: connected' }).Count
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/restore-events" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$recovered = Wait-Until {
    $state = Read-Control $session status
    if ($state.sync_state -ceq 'caught_up' -and @(Get-Content $launchLogPath | Where-Object { $_ -match 'hub events: connected' }).Count -gt $offlineConnected) { $state }
} 'the sync line returns to up to date' 60
@{ caught_up = @{ state = $caughtUp.sync_state; line = $caughtUp.sync_line; rect = $caughtUpRect }; offline = @{ state = $offline.sync_state; line = $offline.sync_line; rect = $offlineRect }; retries = $retries; connected = @(Get-Content $launchLogPath | Where-Object { $_ -match 'hub events: connected' }).Count } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Evidence 'sync-line.json')
Hub-Pass $session retry-backoff
Assert-That ($recovered.sync_line -clike 'Up to date*') 'Reconnected line does not say up to date'
Hub-Pass $session sync-line
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
@{ resume_ms = $resumeMs; chat_pulls = @(Read-BridgeRequests $session | Where-Object { $_.path.StartsWith('/v1/chats?') -and $_.status -eq 200 }).Count } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'wake-resume.json')
Assert-That ($resumeMs -lt 15000) 'Simulated resume refresh exceeded fifteen seconds'
Hub-Pass $session wake-resume
$beforeChats = @(Read-BridgeRequests $session | Where-Object { $_.path.StartsWith('/v1/chats?') -and $_.status -eq 200 }).Count
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/stale-row" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$pollStart = [DateTime]::UtcNow
Start-Sleep -Seconds 65
$null = Wait-Until {
    @(Read-BridgeRequests $session | Where-Object { $_.path.StartsWith('/v1/chats?') -and $_.status -eq 200 }).Count -gt $beforeChats
} 'safety poll refreshed inbox without SSE' 10
$pollMs = ([DateTime]::UtcNow - $pollStart).TotalMilliseconds
$chatPulls = @(Read-BridgeRequests $session | Where-Object { $_.path.StartsWith('/v1/chats?') -and $_.status -eq 200 })
@{ poll_ms = $pollMs; chat_pulls = $chatPulls.Count } | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'safety-poll.json')
Assert-That ($pollMs -le 75000) 'Safety poll exceeded seventy-five seconds'
$sseLive = @(Read-BridgeRequests $session | Where-Object { $_.path -eq '/v1/events' -and $_.id -eq '2' })
Assert-That ($sseLive.Count -eq 0) 'Muted SSE still delivered a live event'
Read-Control $session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'poll.messages.json')
Hub-Pass $session safety-poll
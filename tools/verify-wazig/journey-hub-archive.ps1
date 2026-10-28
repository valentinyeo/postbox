$app = Invoke-HubArchiveJourney $session $messages $start

$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/notification-baseline" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json'
Invoke-PaletteCommand $session 'Refresh'
Wait-ArchiveRows $session @('business:notification-inbox@s.whatsapp.net')
$log = Join-Path $messages 'launch-log.txt'
$proof = @()
foreach ($phase in @('archived', 'inbox')) {
    $id = "NOTIFY-$phase"
    $before = @(Get-Content $log | Where-Object { $_ -match 'notification: accepted' }).Count
    $started = [Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/notification-$phase" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json'
    $null = Wait-Until { (Get-Content $log -Raw).Contains("notification: accepted chat=business:notification-$phase@s.whatsapp.net message=$id") } "incoming $phase desktop notification" 10
    $elapsed = $started.Elapsed.TotalSeconds
    Assert-That ($elapsed -le 10) 'Notification arrived after ten seconds'
    $null = Wait-Until { (Get-Content $log -Raw).Contains("notification: shown message=$id") } "visible $phase desktop notification" 10
    Save-Screen $session "notification-$phase"
    $null = Wait-Until { (Read-Control $session chats).chats.id -contains "business:notification-$phase@s.whatsapp.net" } "incoming $phase chat in inbox"
    $proof += @{ phase = $phase; id = $id; elapsed_seconds = $elapsed; accepted_before = $before }
    Add-Type -AssemblyName UIAutomationClient
    $desktop = [Windows.Automation.AutomationElement]::RootElement
    $desktop.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition) |
        ForEach-Object { "$($_.Current.ClassName) | $($_.Current.Name)" } | Set-Content (Join-Path $Evidence "notification-$phase.desktop.txt")
    Invoke-PaletteCommand $session 'Refresh'
    $null = Wait-Until { (Read-Control $session status).pending_archives -eq 0 } 'notification unarchive acknowledged'
    $after = @(Get-Content $log | Where-Object { $_ -match 'notification: accepted' }).Count
    Assert-That ($after -eq $before + 1) 'Duplicate incoming notification'
}
$proof | ConvertTo-Json | Set-Content (Join-Path $Evidence 'notifications.json')
Read-BridgeRequests $session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Evidence 'notification.requests.json')
$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/notification-clear" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json'
Invoke-PaletteCommand $session 'Refresh'
Wait-ArchiveRows $session @()

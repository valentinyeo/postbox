$app = Invoke-HubArchiveJourney $session $messages $start

Assert-That ($env:GITHUB_ACTIONS -eq 'true') 'Notification settings belong only to the hosted fixture'
$desktop = [Windows.Automation.AutomationElement]::RootElement
$all = [Windows.Automation.Condition]::TrueCondition
$notificationButton = @($desktop.FindAll([Windows.Automation.TreeScope]::Descendants, $all) | Where-Object { $_.Current.Name -like 'Notifications*' })[0]
if ($notificationButton.Current.Name -match 'Do not disturb on') {
    $notificationButton.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    $toggle = Wait-Until {
        foreach ($element in $desktop.FindAll([Windows.Automation.TreeScope]::Descendants, $all)) {
            if ($element.Current.Name -notmatch 'do not disturb') { continue }
            $pattern = $null
            if ($element.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) {
                if ($pattern.Current.ToggleState -eq [Windows.Automation.ToggleState]::On) { return $pattern }
            }
        }
    } 'hosted Windows Do not disturb toggle'
    $toggle.Toggle()
    $null = Wait-Until {
        $button = @($desktop.FindAll([Windows.Automation.TreeScope]::Descendants, $all) | Where-Object { $_.Current.Name -like 'Notifications*' })[0]
        $button.Current.Name -notmatch 'Do not disturb on'
    } 'hosted notifications enabled'
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
}
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
    $null = Wait-Until { (Get-Content $log -Raw).Contains("notification: shown message=$id") } "visible $phase desktop notification" 10
    $desktopText = Wait-Until {
        $text = ($desktop.FindAll([Windows.Automation.TreeScope]::Descendants, $all) | ForEach-Object { "$($_.Current.ClassName) | $($_.Current.Name)" }) -join "`n"
        if ($text.Contains('Notification Business') -and $text.Contains('New business message')) { return $text }
    } "readable $phase desktop notification" 10
    $elapsed = $started.Elapsed.TotalSeconds
    Assert-That ($elapsed -le 10) 'Visible notification arrived after ten seconds'
    Save-Screen $session "notification-$phase"
    $null = Wait-Until { (Read-Control $session chats).chats.id -contains "business:notification-$phase@s.whatsapp.net" } "incoming $phase chat in inbox"
    $proof += @{ phase = $phase; id = $id; elapsed_seconds = $elapsed; accepted_before = $before }
    $desktopText | Set-Content (Join-Path $Evidence "notification-$phase.desktop.txt")
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

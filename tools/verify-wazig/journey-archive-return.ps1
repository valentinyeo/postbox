$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/notification-baseline" -Headers $headers -Body '{}' -ContentType 'application/json'
Invoke-PaletteCommand $session 'Refresh'
$null = Wait-Until { try { (Read-Control $session chats).chats.id -contains 'business:notification-inbox@s.whatsapp.net' } catch { $false } } 'archive-return baseline chat' 60

$target = Wait-Until { try { @((Read-Control $session chats).chats | Where-Object { $_.id -eq 'business:notification-inbox@s.whatsapp.net' })[0] } catch { $null } } 'archive-return chat' 30
$null = Read-Control $session select -Arguments @($target.id, '--provider', $target.provider)
$null = Wait-Until { (Read-Control $session status).selected.id -eq $target.id } 'archive-return chat selected' 30

Send-Keys $session '^e'
$null = Wait-Until { (Read-Control $session status).pending_archives -eq 0 -and -not ((Read-Control $session chats).chats.id -contains $target.id) } 'archive-return chat archived' 60

$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/notification-inbox" -Headers $headers -Body '{}' -ContentType 'application/json'
$null = Wait-Until { (Read-Control $session chats).chats.id -contains $target.id } 'archive-return chat back in the inbox' 60
Invoke-PaletteCommand $session 'Refresh'
$null = Wait-Until { (Read-Control $session status).pending_archives -eq 0 } 'archive-return return acknowledged' 60
Hub-Pass $session whatsapp-return

$null = Wait-Until {
    try {
        $null = Read-Control $session select -Arguments @($target.id, '--provider', $target.provider)
        (Read-Control $session status).selected.id -eq $target.id
    } catch { $false }
} 'archive-return kept chat selected' 30
Send-Keys $session '^+e'
$null = Wait-Until { (Read-Control $session status).pending_archives -eq 0 -and -not ((Read-Control $session chats).chats.id -contains $target.id) } 'archive-return chat kept' 60
$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/notification-archived" -Headers $headers -Body '{}' -ContentType 'application/json'
Start-Sleep -Seconds 10
Invoke-PaletteCommand $session 'Refresh'
Assert-That (-not ((Read-Control $session chats).chats.id -contains $target.id)) 'archive-return kept chat came back'
Hub-Pass $session kept-stays
$null = Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/notification-clear" -Headers $headers -Body '{}' -ContentType 'application/json'

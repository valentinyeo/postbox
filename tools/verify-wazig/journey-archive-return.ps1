$headers = @{ Authorization = 'Bearer fixture-key-not-a-secret' }
$null = Wait-Until { try { (Read-Control $session status).chat_count -gt 0 } catch { $false } } 'archive-return control ready' 60
$null = Wait-Until {
    try {
        $null = Read-Control $session select -Arguments @('fixture-alpha', '--provider', 'slack')
        (Read-Control $session status).selected.id -eq 'fixture-alpha'
    } catch { $false }
} 'archive-return chat selected' 60
Send-Keys $session '^e'
$null = Wait-Until { (Read-Control $session status).selected.archived } 'archive-return: chat archived' 30
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/live" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
$null = Wait-Until { -not (Read-Control $session status).selected.archived } 'archive-return: chat returned on a new message' 60
Hub-Pass $session slack-return

Send-Keys $session '^+e'
$null = Wait-Until { (Read-Control $session status).selected.archived } 'archive-return: kept chat archived' 30
Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/live" -Headers $headers -Body '{}' -ContentType 'application/json' | Out-Null
Start-Sleep -Seconds 8
Assert-That ((Read-Control $session status).selected.archived) 'archive-return: kept chat returned'
Hub-Pass $session kept-stays

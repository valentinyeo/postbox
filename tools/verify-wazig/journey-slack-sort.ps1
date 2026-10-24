Send-Keys $session '%1'
$null = Wait-Until { (Read-Control $session status).view -eq 'slack' } 'Slack sidebar'
$orders = [ordered]@{
    before = @('fixture-beta', 'fixture-gamma', 'fixture-alpha', 'fixture-unknown')
    after = @('fixture-alpha', 'fixture-beta', 'fixture-gamma', 'fixture-unknown')
    sent = @('fixture-gamma', 'fixture-alpha', 'fixture-beta', 'fixture-unknown')
}
foreach ($stage in $orders.Keys) {
    if ($stage -eq 'after') {
        Invoke-RestMethod -Method Post -Uri "$($session.bridge_url)/fixture/live" -Headers @{ Authorization = 'Bearer fixture-key-not-a-secret' } -Body '{}' -ContentType 'application/json' | Out-Null
        Add-Content (Join-Path $Evidence 'actions.log') 'provider: new Slack last message to fixture-alpha'
    } elseif ($stage -eq 'sent') {
        Send-Keys $session '^{TAB}'
        $null = Wait-Until { (Read-Control $session status).selected.id -eq 'fixture-gamma' } 'select Slack send target'
        Invoke-PaletteCommand $session 'Compose message'
        Send-Keys $session 'Synthetic Slack outgoing'
        Send-Keys $session '{ENTER}'
        $null = Wait-Until { (Read-Control $session status).pending_sends -eq 0 } 'Slack send acknowledged'
    }
    $expected = $orders[$stage]
    $null = Wait-Until {
        $rows = (Read-Control $session chats).chats
        ($rows.id -join ',') -eq ($expected -join ',')
    } "Slack $stage last message order"
    $rows = (Read-Control $session chats).chats
    Assert-That ($rows.Count -eq 4 -and @($rows | Where-Object provider -ne 'slack').Count -eq 0) 'Slack list identity changed'
    Assert-That ($rows[3].last_message_time -eq '') 'Unknown Slack time did not stay last'
    Save-Screen $session $stage
    $walk = @()
    $first = (Read-Control $session status).selected.id
    foreach ($step in 1..4) {
        $selected = (Read-Control $session status).selected
        $walk += $selected.id
        if ($step -lt 4) { Send-Keys $session '^{TAB}' }
    }
    $offset = [Array]::IndexOf($expected, $first)
    Assert-That ($offset -ge 0) 'Selected chat is outside the Slack list'
    $visible = @(0..3 | ForEach-Object { $expected[($offset + $_) % 4] })
    Assert-That (($walk -join ',') -eq ($visible -join ',')) 'Keyboard navigation disagrees with visible Slack list order'
    $walk | ConvertTo-Json | Set-Content (Join-Path $Evidence "$stage.navigation.json")
    if ($stage -eq 'before') {
        Send-Keys $session '^+{TAB}'
        Send-Keys $session '^+{TAB}'
        $null = Wait-Until { (Read-Control $session status).selected.id -eq 'fixture-gamma' } 'retain selection during incoming reorder'
    } elseif ($stage -eq 'after') {
        Assert-That ($first -eq 'fixture-gamma') 'Incoming message changed selected Slack chat'
    }
    Hub-Pass $session "$stage-last-message-order"
}

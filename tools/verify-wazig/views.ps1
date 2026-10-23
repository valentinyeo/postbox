function Assert-AccountView($Session, [int]$Number, [string]$Account, [string]$Capture) {
    Send-Keys $Session "%$Number"
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.current_view.account -eq $Account -and -not $state.current_view.inbox -and $state.chat_count -eq 2
    } "account view $Account"
    $state = Read-Control $Session status
    $rows = Read-Control $Session chats
    Assert-That ($rows.total -eq 2 -and @($rows.chats | Where-Object view_account -ne $Account).Count -eq 0) 'Account view leaked another account'
    Assert-That ($state.current_view.label -eq $state.view_order[$Number - 1].label) 'View label does not match saved position'
    $rows | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Capture.chats.json")
    Save-Screen $Session $Capture
    return $rows.chats
}

function Invoke-ViewsJourney($Session, [string]$Messages, $Start) {
    $expected = @('personal', 'business', 'T0ABC123', 'T0DEF456')
    $null = Wait-Until { (Read-Control $Session status).view_order.Count -eq 5 } 'four populated account views and Signal'
    $baseline = Read-Control $Session status
    Assert-That ($baseline.current_view.inbox -and $baseline.chat_count -eq 8) 'Combined inbox baseline missing'
    $catalog = Read-Control $Session chats
    $catalog | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'views-catalog.json')
    for ($index = 0; $index -lt $expected.Count; $index++) {
        Assert-That ($baseline.view_order[$index].account -eq $expected[$index]) 'Default account order differs'
        $rows = @(Assert-AccountView $Session ($index + 1) $expected[$index] "view-$($index + 1)")
        Send-Keys $Session '^1'
        $null = Wait-Until { (Read-Control $Session status).selected.id -eq $rows[0].id } 'first chat in account'
        Send-Keys $Session '^{TAB}'
        $null = Wait-Until { (Read-Control $Session status).selected.id -eq $rows[1].id } 'next chat within account'
        Send-Keys $Session '^+{TAB}'
        $null = Wait-Until { (Read-Control $Session status).selected.id -eq $rows[0].id } 'previous chat within account'
        Send-Keys $Session '^f'
        Send-Keys $Session 'Shared'
        $null = Wait-Until { $state = Read-Control $Session status; $state.chat_count -eq 1 -and $state.selected.view_account -eq $expected[$index] -and $state.selected.name -eq 'Verification Shared' } 'account-scoped search'
        Save-Screen $Session "search-$($index + 1)"
        Send-Keys $Session '{ESC}'
        $null = Wait-Until { (Read-Control $Session status).chat_count -eq 2 } 'account search cleared'
    }
    $null = Assert-AccountView $Session 1 'personal' 'send-account'
    Send-Keys $Session '^2'
    $target = (Read-Control $Session status).selected
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session 'Verification account send'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' -and $_.accepted })
        $state.pending_sends -eq 0 -and $sends.Count -eq 1
    } 'one account-scoped send accepted'
    $sends = @(Read-BridgeRequests $Session | Where-Object { $_.path -eq '/v1/wazig/send' })
    Assert-That (@($sends | Where-Object { $_.source_account -ne 'personal' -or $_.body.chat -ne $target.id }).Count -eq 0) 'Send reached another account'
    $null = Wait-Until { @((Read-Control $Session messages).messages | Where-Object text -eq 'Verification account send').Count -eq 1 } 'sent message visible in source account'
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'sent.messages.json')
    Save-Screen $Session sent
    $null = Assert-AccountView $Session 2 'business' 'other-account'
    Send-Keys $Session '^2'
    $null = Wait-Until {
        $shown = Read-Control $Session messages
        $shown.chat.view_account -eq 'business' -and $shown.messages.Count -gt 0 -and @($shown.messages | Where-Object text -eq 'Verification account send').Count -eq 0
    } 'shared contact in other account has no sent message'
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'other.messages.json')
    Save-Screen $Session isolated
    Send-Keys $Session '%i'
    $null = Wait-Until { $state = Read-Control $Session status; $state.current_view.inbox -and $state.chat_count -eq 8 } 'combined inbox'
    $inbox = Read-Control $Session chats
    for ($index = 1; $index -lt $inbox.chats.Count; $index++) {
        Assert-That ($inbox.chats[$index - 1].last_message_time -ge $inbox.chats[$index].last_message_time) 'Combined inbox is not newest first'
    }
    $inbox | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'inbox.chats.json')
    Save-Screen $Session inbox
    Invoke-PaletteCommand $Session 'Sort views' sort-command
    Save-Screen $Session sort-before
    Send-Keys $Session '^{DOWN}'
    $null = Wait-Until { (Read-Control $Session status).view_order[0].account -eq 'business' } 'view move saved immediately'
    $preferences = "HKCU:\Software\MessagesVerification\$($Session.id)\Software\Messages"
    $savedOrder = (Get-ItemProperty $preferences).ViewOrder
    Assert-That ($savedOrder.StartsWith("whatsapp:business`nwhatsapp:personal`n")) 'ViewOrder not saved at move time'
    Set-Content (Join-Path $Session.evidence 'view-order.txt') $savedOrder -NoNewline
    Save-Screen $Session sort-moved
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { (Read-Control $Session status).current_view.account -eq 'personal' } 'Enter switches to moved selection'
    Save-Screen $Session sort-selected
    Invoke-PaletteCommand $Session 'Sort views'
    Send-Keys $Session '{ESC}'
    Save-Screen $Session sort-closed
    $old = Get-App $Session
    $oldPid = $Session.pid
    $oldTicks = $Session.startTicks
    Invoke-PaletteCommand $Session 'Quit Messages'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'fixture app closed for restart'
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $app = [Diagnostics.Process]::Start($Start)
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    @{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $Session.pid; new_start = $Session.startTicks; root = $Session.root; id = $Session.id; sha256 = $Session.sha256 } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'restart.json')
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted fixture window'
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    $null = Wait-Until { (Read-Control $Session status).chat_count -eq 2 } 'saved account view restored'
    Invoke-Doctor $Session | Out-Null
    $null = Assert-AccountView $Session 1 'business' 'restart-1'
    $null = Assert-AccountView $Session 2 'personal' 'restart-2'
    $null = Assert-AccountView $Session 3 'T0ABC123' 'restart-3'
    $null = Assert-AccountView $Session 4 'T0DEF456' 'restart-4'
    Save-Screen $Session after
    return $app
}

function Select-NotrapView($Session, $Order, [int]$Number) {
    Send-Keys $Session "%$($Number + 1)"
    $wanted = $Order[$Number - 1]
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.current_view.provider -eq $wanted.provider -and $state.current_view.account -eq $wanted.account -and $state.current_view.label -eq $wanted.label -and -not $state.current_view.inbox
    } "Alt+$($Number + 1) reaches saved view"
    return (Read-Control $Session status)
}

function Invoke-NotrapJourney($Session) {
    $startup = Read-Control $Session status
    Assert-That ($startup.view -notin @('signal', 'telegram') -and $startup.chat_count -gt 0) 'Saved unlinked view trapped startup'
    Assert-That $startup.current_view.inbox 'Empty saved provider did not fall back to the combined inbox'
    $order = @($startup.view_order)
    Assert-That ($order.Count -eq 6) 'Missing account views in no-trap fixture'
    Assert-That (@($order | Where-Object provider -eq 'signal').Count -eq 1 -and @($order | Where-Object provider -eq 'telegram').Count -eq 1) 'Missing empty provider views'
    $rows = (Read-Control $Session chats).chats
    Assert-That ($rows.Count -eq 8 -and @($rows | Where-Object { $_.provider -in @('signal', 'telegram') }).Count -eq 0) 'Unlinked providers returned chats'
    Save-Screen $Session startup
    Hub-Pass $Session startup-fallback
    $transitions = @()
    for ($source = 1; $source -le $order.Count; $source++) {
        $state = Select-NotrapView $Session $order $source
        $empty = $order[$source - 1].provider -in @('signal', 'telegram')
        Assert-That ($state.chat_count -eq $(if ($empty) { 0 } else { 2 })) 'Wrong provider chat count'
        Save-Screen $Session "view-$source"
        Send-Keys $Session '^f'
        Send-Keys $Session 'no-trap-search'
        $null = Wait-Until { $state = Read-Control $Session status; $state.search -eq 'no-trap-search' -and $state.chat_count -eq 0 } 'search accepts input in every view'
        Send-Keys $Session '{ESC}'
        $null = Wait-Until {
            $state = Read-Control $Session status
            $state.search -eq '' -and $state.chat_count -eq $(if ($empty) { 0 } else { 2 }) -and $state.current_view.account -eq $order[$source - 1].account
        } 'Esc clears search in every view'
        Send-Keys $Session '{ESC}'
        $null = Wait-Until {
            $state = Read-Control $Session status
            $state.chat_count -gt 0 -and ($state.current_view.inbox -or -not $empty)
        } 'Esc leaves an empty provider view and status still responds'
        $state = Read-Control $Session status
        $state | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "esc-$source.state.json")
        $null = Select-NotrapView $Session $order 1
        Read-Control $Session status | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "escape-to-first-$source.state.json")
        for ($target = 1; $target -le $order.Count; $target++) {
            $null = Select-NotrapView $Session $order $source
            $state = Select-NotrapView $Session $order $target
            $transitions += @{ source = $source; target = $target; current_view = $state.current_view }
        }
        foreach ($key in @('%1', '%i', 'gi')) {
            $null = Select-NotrapView $Session $order $source
            if ($key -eq 'gi') { (Get-Edit (Get-Window $Session) '1016').SetFocus() }
            Send-Keys $Session $key
            $null = Wait-Until { $state = Read-Control $Session status; $state.current_view.inbox -and $state.chat_count -eq 8 } 'Alt inbox shortcut from every view'
            $transitions += @{ source = $source; target = $key; current_view = (Read-Control $Session status).current_view }
        }
    }
    $null = Select-NotrapView $Session $order 1
    Send-Keys $Session '^1'
    $state = Read-Control $Session status
    Assert-That ($state.current_view.account -eq $order[0].account -and -not $state.current_view.inbox) 'Ctrl+1 must not switch views'
    Save-Screen $Session 'ctrl-one'
    Send-Keys $Session '^f'
    Send-Keys $Session 'gi'
    $null = Wait-Until { (Read-Control $Session status).search -eq 'gi' } 'search preserves typed gi'
    Save-Screen $Session 'typed-gi'
    Send-Keys $Session '{ESC}'
    (Get-Edit (Get-Window $Session) '1016').SetFocus()
    Send-Keys $Session 'g'
    Send-Keys $Session 'x'
    Send-Keys $Session 'i'
    $state = Read-Control $Session status
    Assert-That ($state.current_view.account -eq $order[0].account -and -not $state.current_view.inbox) 'intervening key cancels g prefix'
    Save-Screen $Session 'cancelled-gi'
    Send-Keys $Session '%1'
    $null = Wait-Until { (Read-Control $Session status).current_view.inbox } 'return to combined inbox'
    $transitions | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'transitions.json')
    Hub-Pass $Session every-view-escape-alt
    Save-Screen $Session after
}

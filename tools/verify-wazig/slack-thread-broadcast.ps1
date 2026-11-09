function Save-BroadcastState($Session, [string]$Name) {
    $thread = (Read-Control $Session status).slack_threads
    Assert-That ($null -ne $thread -and $null -ne $thread.broadcast_shown) 'Read-only broadcast checkbox state missing'
    $thread | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.json")
    Save-Screen $Session $Name
    return $thread
}

function Wait-ThreadSend($Session, [string]$Text) {
    return Wait-Until {
        $sent = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -like '*/send' -and $_.status -eq 200 -and $_.body.reply_to -eq '1740000000.000100' -and $_.body.text -eq $Text })
        if ($sent.Count -gt 0 -and (Read-Control $Session status).pending_sends -eq 0) { $sent[0] }
    } "thread send acknowledged: $Text"
}

function Invoke-SlackThreadBroadcastJourney($Session) {
    Send-Keys $Session '%2'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.selected.id -eq 'slack:fixture-threads:channel' -and $state.slack_threads.parent_reply_line -eq '30 replies'
    } 'thread parent replies line'
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session '^{UP}'
    Send-Keys $Session '^{UP}'
    Send-Keys $Session '^{UP}'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { $thread = (Read-Control $Session status).slack_threads; $thread.open -and $thread.replies -eq 30 -and $thread.broadcast_shown } 'thread panel with the broadcast checkbox'
    $unticked = Save-BroadcastState $Session broadcast-unticked
    Assert-That (-not $unticked.broadcast_checked) 'Broadcast checkbox must start unticked'
    Assert-That ($unticked.broadcast_label -ceq 'Also send to Verification Threads') 'Broadcast checkbox label does not name the chat'
    Send-Keys $Session 'Synthetic plain thread reply'
    Send-Keys $Session '{ENTER}'
    $plain = Wait-ThreadSend $Session 'Synthetic plain thread reply'
    Assert-That (-not $plain.body.PSObject.Properties['reply_broadcast']) 'Unticked reply must not carry reply_broadcast'
    Send-Keys $Session '{TAB}'
    Send-Keys $Session ' '
    $null = Wait-Until { (Read-Control $Session status).slack_threads.broadcast_checked } 'checkbox ticked from the keyboard'
    $ticked = Save-BroadcastState $Session broadcast-ticked
    Assert-That $ticked.broadcast_checked 'Broadcast checkbox did not tick'
    Send-Keys $Session '{TAB}'
    Send-Keys $Session 'Synthetic broadcast reply'
    Send-Keys $Session '{ENTER}'
    $broadcast = Wait-ThreadSend $Session 'Synthetic broadcast reply'
    Assert-That ($broadcast.body.reply_broadcast -eq $true) 'Ticked reply must carry reply_broadcast true'
    $null = Wait-Until { -not (Read-Control $Session status).slack_threads.broadcast_checked } 'checkbox back to unticked after the send'
    $null = Save-BroadcastState $Session broadcast-reset
    Invoke-PaletteCommand $Session 'Refresh'
    $rows = Wait-Until {
        $messages = @((Read-Control $Session messages).messages | Where-Object { $_.text -eq 'Synthetic broadcast reply' })
        if (@($messages | Where-Object { $_.quoted_msg_id -eq '1740000000.000100' }).Count -ge 1 -and @($messages | Where-Object { $_.quoted_msg_id -eq '' }).Count -ge 1) { $messages }
    } 'broadcast reply in the thread and in the chat'
    $rows | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Session.evidence 'broadcast-messages.json')
    Save-Screen $Session broadcast-thread-result
    Send-Keys $Session '{ESC}'
    $null = Wait-Until { -not (Read-Control $Session status).slack_threads.open } 'thread panel closed'
    Save-Screen $Session broadcast-chat-result
}

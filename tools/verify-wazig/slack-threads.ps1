. "$PSScriptRoot/menus.ps1"

function Save-ThreadsState($Session, [string]$Name) {
    $thread = (Read-Control $Session status).slack_threads
    Assert-That ($null -ne $thread) 'Read-only Slack thread state missing'
    $thread | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.json")
    Save-Screen $Session $Name
    return $thread
}

function Open-FixtureChat($Session, [string]$Search, [string]$Id) {
    Send-Keys $Session '^f'
    Send-Keys $Session $Search
    $null = Wait-Until { (Read-Control $Session status).selected.id -eq $Id } "$Id selected"
    Click-Control $Session '1032'
    Send-Keys $Session '^f'
    Send-Keys $Session '^a{BACKSPACE}{ESC}'
}

function Invoke-SlackThreadsJourney($Session, $Start) {
    Open-FixtureChat $Session 'Verification Threads' 'slack:fixture-threads:channel'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.selected.id -eq 'slack:fixture-threads:channel' -and $state.slack_threads.parent_reply_line -eq '30 replies' -and $state.slack_threads.inline_replies -eq 0 -and $state.slack_threads.loose_replies -eq 0
    } 'thread parent replies line without inline or loose replies'
    $on = Save-ThreadsState $Session threads-on
    Assert-That ($on.parent_id -eq '1740000000.000100') 'Wrong thread parent'
    Invoke-PaletteCommand $Session 'Compose message'
    Send-Keys $Session '^{UP}'
    Send-Keys $Session '^{UP}'
    Send-Keys $Session '^{UP}'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until { $thread = (Read-Control $Session status).slack_threads; $thread.open -and $thread.replies -eq 30 } 'thread panel with parent and all replies'
    $null = Save-ThreadsState $Session thread-panel
    Send-Keys $Session 'Synthetic thread reply'
    Send-Keys $Session '{ENTER}'
    $null = Wait-Until {
        $sent = @(Read-BridgeRequests $Session | Where-Object { $_.wire_path -like '*/send' -and $_.status -eq 200 -and $_.body.reply_to -eq '1740000000.000100' -and $_.body.text -eq 'Synthetic thread reply' })
        $sent.Count -gt 0 -and (Read-Control $Session status).pending_sends -eq 0
    } 'thread-scoped send acknowledged'
    Save-Screen $Session thread-reply
    Send-Keys $Session '{ESC}'
    $null = Wait-Until { -not (Read-Control $Session status).slack_threads.open } 'thread panel closed'
    Invoke-PaletteCommand $Session 'Slack threads like Slack for this account'
    $null = Wait-Until { $thread = (Read-Control $Session status).slack_threads; $thread.inline_replies -eq 32 -and $thread.loose_replies -eq 32 -and $thread.parent_reply_line -eq '' -and $thread.threads_option -eq 'off' } 'inline mode restored'
    $null = Save-ThreadsState $Session threads-off
    $old = Get-App $Session
    $oldPid = $Session.pid
    $oldTicks = $Session.startTicks
    Invoke-PaletteCommand $Session 'Quit Postbox'
    $null = Wait-Until { $old.Refresh(); $old.HasExited } 'fixture closed normally'
    $Start.Environment['WAZIG_VERIFY_RESTART'] = $Session.id
    $app = [Diagnostics.Process]::Start($Start)
    $Session.pid = $app.Id
    $Session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
    $Session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'session.json')
    @{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $Session.pid; new_start = $Session.startTicks; root = $Session.root; id = $Session.id; sha256 = $Session.sha256 } | ConvertTo-Json | Set-Content (Join-Path $Session.evidence 'restart.json')
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted fixture window' -Harness
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    Open-FixtureChat $Session 'Verification Threads' 'slack:fixture-threads:channel'
    $null = Wait-Until { $thread = (Read-Control $Session status).slack_threads; $thread.threads_option -eq 'off' -and $thread.inline_replies -eq 32 } 'account option applied to the chat survived same-profile restart'
    Invoke-Doctor $Session | Out-Null
    $thread = Save-ThreadsState $Session threads-restart
    $thread | Add-Member -NotePropertyName restarted -NotePropertyValue ($old.HasExited -and $Session.startTicks -ne $oldTicks)
    $thread | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'threads-restart.json')
    Invoke-PaletteCommand $Session 'Slack threads like Slack for this account'
    $null = Wait-Until { $thread = (Read-Control $Session status).slack_threads; $thread.threads_option -eq 'on' -and $thread.inline_replies -eq 0 -and $thread.parent_reply_line -eq '30 replies' } 'account option back on folds the replies again'
    Invoke-PaletteCommand $Session 'Replies: WhatsApp style'
    $null = Wait-Until {
        $thread = (Read-Control $Session status).slack_threads
        $thread.replies_style -eq 'whatsapp' -and $thread.inline_replies -eq 32 -and $thread.loose_replies -eq 32 -and $thread.parent_reply_line -eq '' -and $thread.threads_option -eq 'off'
    } 'this Slack chat follows its own WhatsApp style while the account keeps threads on'
    $null = Save-ThreadsState $Session chat-whatsapp-style
    Invoke-PaletteCommand $Session 'Replies: Slack style'
    $null = Wait-Until {
        $thread = (Read-Control $Session status).slack_threads
        $thread.replies_style -eq 'slack' -and $thread.inline_replies -eq 0 -and $thread.loose_replies -eq 0 -and $thread.parent_reply_line -eq '30 replies' -and $thread.threads_option -eq 'on'
    } 'this Slack chat folds the replies again in Slack style'
    $null = Save-ThreadsState $Session chat-slack-style
    Open-FixtureChat $Session 'Verification Fresh' 'fixture-fresh'
    $null = Wait-Until {
        $thread = (Read-Control $Session status).slack_threads
        $thread.replies_style -eq 'slack' -and $thread.threads_option -eq 'on' -and $thread.parent_id -eq '1750000000.000100' -and $thread.parent_reply_line -eq '2 replies' -and $thread.inline_replies -eq 0 -and $thread.loose_replies -eq 0
    } 'fresh Slack chat with no saved setting opens in Slack style'
    $null = Save-ThreadsState $Session fresh-slack-default
    Open-FixtureChat $Session 'Verification WhatsApp' 'fixture-whatsapp'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.selected.provider -eq 'whatsapp' -and $null -eq $state.slack_threads
    } 'whatsapp chat with no saved setting opens in WhatsApp style'
    $null = Wait-Until {
        (Read-Control $Session messages).messages | Where-Object { $_.id -ceq 'WA-REPLY' -and $_.quote_line[2] -gt $_.quote_line[0] }
    } 'whatsapp reply painted inline with its quote'
    Read-Control $Session messages | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'whatsapp-default.messages.json')
    Save-Screen $Session whatsapp-default
    return $app
}

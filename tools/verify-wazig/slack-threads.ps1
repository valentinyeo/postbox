function Save-ThreadsState($Session, [string]$Name) {
    $thread = (Read-Control $Session status).slack_threads
    Assert-That ($null -ne $thread) 'Read-only Slack thread state missing'
    $thread | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence "$Name.json")
    Save-Screen $Session $Name
    return $thread
}

function Invoke-SlackThreadsJourney($Session, $Start) {
    Send-Keys $Session '%2'
    $null = Wait-Until {
        $state = Read-Control $Session status
        $state.selected.id -eq 'slack:fixture-threads:channel' -and $state.slack_threads.parent_reply_line -eq '30 replies' -and $state.slack_threads.inline_replies -eq 0
    } 'thread parent replies line without inline replies'
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
    $null = Wait-Until { $thread = (Read-Control $Session status).slack_threads; $thread.inline_replies -eq 30 -and $thread.parent_reply_line -eq '' -and $thread.threads_option -eq 'off' } 'inline mode restored'
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
    $null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted fixture window'
    [VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
    Send-Keys $Session '%2'
    $null = Wait-Until { $thread = (Read-Control $Session status).slack_threads; $thread.threads_option -eq 'off' -and $thread.inline_replies -eq 30 } 'account option survived same-profile restart'
    Invoke-Doctor $Session | Out-Null
    $thread = Save-ThreadsState $Session threads-restart
    $thread | Add-Member -NotePropertyName restarted -NotePropertyValue ($old.HasExited -and $Session.startTicks -ne $oldTicks)
    $thread | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Session.evidence 'threads-restart.json')
    return $app
}

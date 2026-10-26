$workload = 264
$list = Get-Edit $window '1016'
$compose.SetFocus()
Send-Keys $session 'hello'
Send-Keys $session '^a'
$selection = @($compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern).GetSelection())
Assert-That ($selection.Count -eq 1 -and $selection[0].GetText(-1) -ceq 'hello') 'Ctrl+A must retain composer text selection'
Send-Keys $session '{BACKSPACE}'
$presses = @()
$targets = @($compose, $list)
foreach ($press in 1..10) {
    $cleared = $true
    if ($press -gt 1) {
        Send-Keys $session '{ESC}'
        $cleared = (Read-Control $session status).bulk_selected_count -eq 0
    }
    $target = $targets[($press - 1) % $targets.Count]
    $focused = $true
    try { $target.SetFocus() } catch { $focused = $false }
    try { $null = Wait-Until { $target.Current.HasKeyboardFocus } "focus $($target.Current.AutomationId)" 5 } catch { $focused = $false }
    Send-Keys $session '^a'
    $ok = $cleared -and (Read-Control $session status).bulk_selected_count -eq $workload
    $presses += @{ press = $press; ok = $ok; focused = $focused; target = $target.Current.AutomationId }
    Write-Output "ctrl_a_press=$press ok=$($ok.ToString().ToLowerInvariant())"
}
$okCount = @($presses | Where-Object ok).Count
Write-Output "ctrl_a_ok=$okCount"
$presses | ConvertTo-Json | Set-Content (Join-Path $session.evidence 'ctrl-a.json')
Assert-That ($okCount -eq 10) 'Ctrl+A did not select the complete workload on all ten presses'
Save-Screen $session selected
$clock = [Diagnostics.Stopwatch]::StartNew()
Send-Keys $session '^e'
$null = Wait-Until {
    $state = Read-Control $session status
    $state.pending_archives -eq 0 -and $state.chat_count -eq 0
} 'complete fixed 264-chat bulk archive held in Wazig'
$clock.Stop()
$total = $clock.ElapsedMilliseconds
$perChat = $total / $workload
Write-Output "bulk_archive_ms_total=$total bulk_archive_ms_per_chat=$($perChat.ToString('F3', [Globalization.CultureInfo]::InvariantCulture))"
$writes = @(Read-BridgeRequests $session | Where-Object { $_.wire_path -in @('/v1/wazig/archive', '/v1/wazig/archive-batch') })
$singles = @($writes | Where-Object wire_path -eq '/v1/wazig/archive')
$batches = @($writes | Where-Object wire_path -eq '/v1/wazig/archive-batch')
@{ chats = $workload; remote_chats = 261; total_ms = $total; per_chat_ms = $perChat; single_requests = $singles.Count; batch_requests = $batches.Count } |
    ConvertTo-Json | Set-Content (Join-Path $session.evidence 'bulk-timing.json')
Read-BridgeRequests $session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'archive.requests.json')
Assert-That ($singles.Count -eq 0 -and $batches.Count -eq 1 -and $batches[0].body.chats.Count -eq 261) 'Expected one batch for 261 WhatsApp chats; other providers remain local'
Save-Screen $session empty
Invoke-PaletteCommand $session 'Refresh'
$null = Wait-Until { (Read-Control $session status).chat_count -eq 0 } 'archive intent survives metadata-free refresh'
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until {
    $state = Read-Control $session status
    $rows = @((Read-Control $session chats -Arguments @('--archived')).chats)
    $state.show_archived -and $state.chat_count -eq $workload -and $rows.Count -eq $workload -and
        @($rows | Where-Object { $_.archived -and $_.archive_label -in @('Archived', 'Kept archived') }).Count -eq $workload
} 'every archived sidebar and control row retains its archive flag'
$archived = @((Read-Control $session chats -Arguments @('--archived')).chats | Where-Object archived).Count
Write-Output "archived_among_shown=$archived"
Save-Screen $session archived
$files = @(Get-ChildItem $messages -Filter 'hub-*-archive-state.txt')
Assert-That ($files.Count -eq 1) 'Archive state missing or ambiguous'
Copy-Item $files[0].FullName (Join-Path $session.evidence 'saved-archive-state.txt')
Invoke-PaletteCommand $session 'Show inbox chats'
Send-Keys $session '^2'
$null = Wait-Until { (Read-Control $session status).chat_count -eq 0 } 'Ctrl+2 does not restore archived sessions'
Save-Screen $session account-empty
$old = Get-App $session
$oldPid = $session.pid
$oldTicks = $session.startTicks
Invoke-PaletteCommand $session 'Quit Postbox'
$null = Wait-Until { $old.Refresh(); $old.HasExited } 'close for same-profile archive restart'
$start.Environment['WAZIG_VERIFY_RESTART'] = $session.id
$app = [Diagnostics.Process]::Start($start)
$session.pid = $app.Id
$session.startTicks = $app.StartTime.ToUniversalTime().Ticks.ToString()
$session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'session.json')
@{ old_pid = $oldPid; old_start = $oldTicks; new_pid = $session.pid; new_start = $session.startTicks; root = $session.root; id = $session.id; sha256 = $session.sha256 } |
    ConvertTo-Json | Set-Content (Join-Path $session.evidence 'restart.json')
$null = Wait-Until { $app.Refresh(); $app.MainWindowHandle -ne [IntPtr]::Zero } 'restarted archive fixture window'
[VerifyWindow]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
Send-Keys $session '%i'
$null = Wait-Until { $state = Read-Control $session status; $state.current_view.inbox -and $state.chat_count -eq 0 } 'restart preserves empty combined inbox'
Save-Screen $session restart-empty
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { $state = Read-Control $session status; $state.show_archived -and $state.chat_count -eq $workload } 'restart preserves all archived rows'
Save-Screen $session after
Read-BridgeRequests $session | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $session.evidence 'archive.requests.json')

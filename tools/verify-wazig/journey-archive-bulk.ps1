$compose.SetFocus()
Assert-That ($compose.Current.HasKeyboardFocus -and (Read-Edit $compose) -eq '') 'bulk: composer did not start focused and empty'
Save-Screen $session before
Send-Keys $session '^a'
$null = Wait-Until {
    (Read-Control $session status).bulk_selected_count -eq 2
} 'bulk: Ctrl+A in empty composer selected no chats'
Save-Screen $session selected
Assert-That $compose.Current.HasKeyboardFocus 'bulk: selection moved focus out of composer'
Send-Keys $session '^e'
$null = Wait-Until {
    $state = Read-Control $session status
    $rows = @((Get-Content $provider -Raw | ConvertFrom-Json).data)
    $inbox = @((Read-Control $session chats).chats)
    $state.pending_archives -eq 0 -and $rows.Count -eq 2 -and
        @($rows | Where-Object { $_.archived -eq $true }).Count -eq 2 -and
        $state.chat_count -eq 0 -and $inbox.Count -eq 0
} 'bulk: Ctrl+E did not archive every selected chat'
Save-Screen $session after
Invoke-PaletteCommand $session 'Show archived chats'
$null = Wait-Until { $compose.Current.IsEnabled } 'bulk: archived composer unavailable for text check'
$compose.SetFocus()
Send-Keys $session 'hello'
$null = Wait-Until { (Read-Edit $compose) -ceq 'hello' } 'bulk: composer did not receive text'
Send-Keys $session '^a'
$null = Wait-Until {
    $pattern = $compose.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern)
    $selection = @($pattern.GetSelection())
    $selection.Count -eq 1 -and $selection[0].GetText(-1) -ceq 'hello' -and
        (Read-Control $session status).bulk_selected_count -eq 0
} 'bulk: Ctrl+A with text did not keep text select-all'
Save-Screen $session text-selected
Send-Keys $session '{BACKSPACE}'
$null = Wait-Until { (Read-Edit $compose) -eq '' } 'bulk: composer did not clear'
